module X86BatchAssembler
  ( AssemblerState(..)
  , newAssemblerState
  , emitUnit
  , resolveLabels
  , finalBytes
  ) where

import           Cobalt.Dense    (ISA(..), encodeISA)
import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import           Data.Bits       (shiftL, shiftR, (.&.))
import           Data.Word       (Word8, Word32)
import qualified Data.Map.Strict as M

-- ---------------------------------------------------------------------------
-- Per-unit assembler state (fully independent; no shared globals)
-- ---------------------------------------------------------------------------

data AssemblerState = AssemblerState
  { asmBytes    :: ByteString               -- emitted code so far
  , asmSymbols  :: M.Map String Int         -- symbol → byte offset
  , asmPatches  :: [(Int, String)]          -- (offset-of-rel32, target-label)
  , asmOffset   :: Int                      -- current byte offset
  } deriving (Show)

newAssemblerState :: AssemblerState
newAssemblerState = AssemblerState
  { asmBytes   = BS.empty
  , asmSymbols = M.empty
  , asmPatches = []
  , asmOffset  = 0
  }

-- Emit a labelled block of ISA instructions.
emitUnit :: String -> [ISA] -> AssemblerState -> AssemblerState
emitUnit label insns st =
  let encoded = encodeISA insns
      base    = asmOffset st
      st1     = st
        { asmSymbols = M.insert label base (asmSymbols st)
        , asmBytes   = asmBytes st <> encoded
        , asmOffset  = base + BS.length encoded
        }
  in  st1

-- Emit a relative JMP rel32 placeholder and record the patch site.
-- REX.W prefix + JMP rel32 = [0x48, 0xE9, 0x00, 0x00, 0x00, 0x00]
emitJmpLabel :: String -> AssemblerState -> AssemblerState
emitJmpLabel target st =
  let patchAt = asmOffset st + 2   -- rel32 starts after 0x48 0xE9
      insn    = BS.pack [0x48, 0xE9, 0x00, 0x00, 0x00, 0x00]
  in  st
        { asmBytes   = asmBytes st <> insn
        , asmOffset  = asmOffset st + 6
        , asmPatches = (patchAt, target) : asmPatches st
        }

-- Resolve all recorded rel32 patches.
resolveLabels :: AssemblerState -> Either String AssemblerState
resolveLabels st = foldl applyPatch (Right st) (asmPatches st)
  where
    applyPatch (Left e) _            = Left e
    applyPatch (Right s) (off, lbl) =
      case M.lookup lbl (asmSymbols s) of
        Nothing   -> Left ("Undefined label: " ++ lbl)
        Just dest ->
          let rel32 = dest - (off + 4)  -- rel32 is relative to next insn
              patch = encodeRel32 rel32
              (pre, rest) = BS.splitAt off (asmBytes s)
              (_,   post) = BS.splitAt 4   rest
          in  Right s { asmBytes = pre <> BS.pack patch <> post }

encodeRel32 :: Int -> [Word8]
encodeRel32 n =
  let w = fromIntegral n :: Word32
  in  map (\s -> fromIntegral ((w `shiftR` s) .&. 0xFF)) [0,8,16,24]

-- Final assembled bytes for the unit.
finalBytes :: AssemblerState -> ByteString
finalBytes = asmBytes
