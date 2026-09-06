{-# LANGUAGE OverloadedStrings #-}

module X86BatchAssembler
  ( AssemblyUnit(..)
  , ObjectCode(..)
  , Diagnostic(..)
  , BatchResult(..)
  , assembleBatch
  , assemble
  ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as C8
import qualified Data.Map.Strict as Map
import Data.Int
import Data.Word
import Control.Monad
import Control.Monad.State.Strict
import Data.Char
import Numeric

--------------------------------------------------------------------------------
-- Public types
--------------------------------------------------------------------------------

data AssemblyUnit = AssemblyUnit
  { unitName   :: String
  , unitSource :: String
  } deriving (Show, Eq)

data ObjectCode = ObjectCode
  { objectName :: String
  , objectCode :: BS.ByteString
  } deriving (Show, Eq)

data Diagnostic = Diagnostic
  { diagnosticUnit :: String
  , diagnosticLine :: Int
  , diagnosticText :: String
  } deriving (Show, Eq)

data BatchResult = BatchResult
  { batchObjects     :: [ObjectCode]
  , batchDiagnostics :: [Diagnostic]
  } deriving (Show, Eq)

--------------------------------------------------------------------------------
-- Internal representation
--------------------------------------------------------------------------------

data Register
  = RAX | RCX | RDX | RBX
  | RSP | RBP | RSI | RDI
  | R8  | R9  | R10 | R11
  | R12 | R13 | R14 | R15
  deriving (Show, Eq, Ord, Enum)

data Operand
  = Reg Register
  | Imm Int64
  | LabelRef String
  deriving (Show, Eq)

data Instruction
  = INop
  | IRet
  | IInt3
  | IMov Register Int64
  | IAddRax Int32
  | ISubRax Int32
  | IJmp String
  deriving (Show, Eq)

data Statement
  = Label String
  | Instr Instruction
  deriving (Show, Eq)

--------------------------------------------------------------------------------
-- Batch API
--------------------------------------------------------------------------------

assembleBatch :: [AssemblyUnit] -> BatchResult
assembleBatch units =
    let results = map assembleUnit units
        objects = [ o | Right o <- results ]
        errors  = concat [ e | Left  e <- results ]
    in BatchResult objects errors

assemble :: String -> Either [Diagnostic] BS.ByteString
assemble source =
    case assembleUnit (AssemblyUnit "<anonymous>" source) of
      Left errors -> Left errors
      Right obj   -> Right (objectCode obj)

assembleUnit :: AssemblyUnit -> Either [Diagnostic] ObjectCode
assembleUnit unit =
    case parseSource (unitName unit) (unitSource unit) of
      Left errors -> Left errors
      Right stmts ->
        case buildSymbols stmts of
          Left errors -> Left
            [ Diagnostic (unitName unit) 0 e | e <- errors ]
          Right symbols ->
            case encodeProgram symbols stmts of
              Left errors -> Left
                [ Diagnostic (unitName unit) 0 e | e <- errors ]
              Right bytes ->
                Right $ ObjectCode
                  (unitName unit)
                  bytes

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------

parseSource :: String -> String -> Either [Diagnostic] [Statement]
parseSource name source =
    let ls     = zip [1..] (lines source)
        parsed = map (parseLine name) ls
        errors = [ e | Left  e       <- parsed ]
        stmts  = [ s | Right (Just s) <- parsed ]
    in if null errors
       then Right stmts
       else Left errors

parseLine
  :: String
  -> (Int, String)
  -> Either Diagnostic (Maybe Statement)

parseLine name (lineNo, raw) =
    let line    = stripComment raw
        trimmed = trim line
    in
      if null trimmed
      then Right Nothing
      else if last trimmed == ':'
      then
        let lbl = trim (init trimmed)
        in if validLabel lbl
           then Right (Just (Label lbl))
           else Left $
             Diagnostic name lineNo "invalid label"
      else
        case parseInstruction trimmed of
          Nothing ->
            Left $ Diagnostic name lineNo
              ("cannot parse instruction: " ++ trimmed)
          Just i ->
            Right (Just (Instr i))

parseInstruction :: String -> Maybe Instruction
parseInstruction s =
    case words s of

      ["nop"]  -> Just INop
      ["ret"]  -> Just IRet
      ["int3"] -> Just IInt3

      ["mov", dst, src] ->
        case (parseRegister dst, parseImmediate src) of
          (Just r, Just n) -> Just (IMov r n)
          _ -> Nothing

      ["add", "rax,", imm] ->
        IAddRax <$> parseInt32 imm

      ["sub", "rax,", imm] ->
        ISubRax <$> parseInt32 imm

      ["jmp", lbl] ->
        Just (IJmp lbl)

      _ -> Nothing

--------------------------------------------------------------------------------
-- Symbols
--------------------------------------------------------------------------------

type SymbolTable = Map.Map String Int

buildSymbols :: [Statement] -> Either [String] SymbolTable
buildSymbols statements =
    go statements 0 Map.empty []
  where
    go [] _ symbols errors =
      if null errors
      then Right symbols
      else Left (reverse errors)

    go (stmt:rest) offset symbols errors =
      case stmt of

        Label name ->
          if Map.member name symbols
          then go rest offset symbols
                 (("duplicate label: " ++ name) : errors)
          else
            go rest offset
              (Map.insert name offset symbols)
              errors

        Instr instruction ->
          let size = instructionSize instruction
          in go rest (offset + size) symbols errors

instructionSize :: Instruction -> Int
instructionSize INop      = 1
instructionSize IRet      = 1
instructionSize IInt3     = 1
instructionSize (IMov _ _) = 10  -- REX + opcode + 8-byte imm
instructionSize (IAddRax _) = 6  -- REX + 0x05 + 4-byte imm
instructionSize (ISubRax _) = 6
instructionSize (IJmp _)  = 5   -- 0xE9 + 4-byte rel32

--------------------------------------------------------------------------------
-- Encoder
--------------------------------------------------------------------------------

encodeProgram
  :: SymbolTable
  -> [Statement]
  -> Either [String] BS.ByteString

encodeProgram symbols statements =
    fmap BS.concat $
      evalStateT (mapM (encodeStatement symbols) statements) 0

encodeStatement
  :: SymbolTable
  -> Statement
  -> StateT Int (Either [String]) BS.ByteString

encodeStatement _ (Label _) =
    pure BS.empty

encodeStatement symbols (Instr instruction) = do
    offset <- get
    let result = encodeInstruction symbols offset instruction

    case result of
      Left err ->
        lift (Left [err])

      Right bytes -> do
        put (offset + BS.length bytes)
        pure bytes

encodeInstruction
  :: SymbolTable
  -> Int
  -> Instruction
  -> Either String BS.ByteString

encodeInstruction _ _ INop =
    pure (BS.pack [0x90])

encodeInstruction _ _ IRet =
    pure (BS.pack [0xC3])

encodeInstruction _ _ IInt3 =
    pure (BS.pack [0xCC])

-- mov r64, imm64
encodeInstruction _ _ (IMov reg value) =
    pure $
      BS.pack
        [ rexW reg
        , 0xB8 + regLowBits reg
        ]
      <> word64LE value

-- add rax, imm32
encodeInstruction _ _ (IAddRax value) =
    pure $
      BS.pack [0x48, 0x05]
      <> word32LE (fromIntegral value)

-- sub rax, imm32
encodeInstruction _ _ (ISubRax value) =
    pure $
      BS.pack [0x48, 0x2D]
      <> word32LE (fromIntegral value)

-- jmp rel32
encodeInstruction symbols offset (IJmp label) =
    case Map.lookup label symbols of
      Nothing ->
        Left ("undefined label: " ++ label)

      Just target ->
        let nextInstruction = offset + 5
            displacement =
              fromIntegral target - fromIntegral nextInstruction
        in
          if displacement < (-2147483648)
             || displacement > 2147483647
          then
            Left ("jump displacement out of range: " ++ label)
          else
            Right $
              BS.pack [0xE9]
              <> word32LE (fromIntegral displacement)

--------------------------------------------------------------------------------
-- Register encoding
--------------------------------------------------------------------------------

regLowBits :: Register -> Word8
regLowBits r =
    case r of
      RAX -> 0;  RCX -> 1;  RDX -> 2;  RBX -> 3
      RSP -> 4;  RBP -> 5;  RSI -> 6;  RDI -> 7
      R8  -> 0;  R9  -> 1;  R10 -> 2;  R11 -> 3
      R12 -> 4;  R13 -> 5;  R14 -> 6;  R15 -> 7

rexW :: Register -> Word8
rexW r
  | r >= R8   = 0x49
  | otherwise = 0x48

--------------------------------------------------------------------------------
-- Register parsing
--------------------------------------------------------------------------------

parseRegister :: String -> Maybe Register
parseRegister s =
    case map toLower (stripComma s) of
      "rax" -> Just RAX;  "rcx" -> Just RCX
      "rdx" -> Just RDX;  "rbx" -> Just RBX
      "rsp" -> Just RSP;  "rbp" -> Just RBP
      "rsi" -> Just RSI;  "rdi" -> Just RDI
      "r8"  -> Just R8;   "r9"  -> Just R9
      "r10" -> Just R10;  "r11" -> Just R11
      "r12" -> Just R12;  "r13" -> Just R13
      "r14" -> Just R14;  "r15" -> Just R15
      _ -> Nothing

--------------------------------------------------------------------------------
-- Integer parsing
--------------------------------------------------------------------------------

parseImmediate :: String -> Maybe Int64
parseImmediate s =
    let t = stripComma s
    in if "0x" `prefixOf` map toLower t
       then parseHex (drop 2 t)
       else readMaybe t

parseInt32 :: String -> Maybe Int32
parseInt32 s =
    fromIntegral <$> (parseImmediate s :: Maybe Int64)

parseHex :: String -> Maybe Int64
parseHex s =
    case readHex s of
      [(n, "")] -> Just n
      _ -> Nothing

readMaybe :: Read a => String -> Maybe a
readMaybe s =
    case reads s of
      [(x, "")] -> Just x
      _ -> Nothing

--------------------------------------------------------------------------------
-- Byte encoding
--------------------------------------------------------------------------------

word32LE :: Word32 -> BS.ByteString
word32LE x =
    BS.pack
      [ fromIntegral x
      , fromIntegral (x `shiftR` 8)
      , fromIntegral (x `shiftR` 16)
      , fromIntegral (x `shiftR` 24)
      ]

word64LE :: Int64 -> BS.ByteString
word64LE x =
    let w = fromIntegral x :: Word64
    in BS.pack
      [ fromIntegral (w `shiftR` (8 * i))
      | i <- [0..7]
      ]

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

stripComment :: String -> String
stripComment = takeWhile (/= ';')

stripComma :: String -> String
stripComma = filter (/= ',')

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

validLabel :: String -> Bool
validLabel [] = False
validLabel (x:xs) =
    (isAlpha x || x == '_') &&
    all (\c -> isAlphaNum c || c == '_') xs

prefixOf :: String -> String -> Bool
prefixOf prefix value =
    take (length prefix) value == prefix

shiftR :: Bits a => a -> Int -> a
shiftR = Data.Bits.shiftR
