module Cobalt.Trilock
  ( Trilock(..)
  , mkTrilock
  , trilockHash
  ) where

import           Cobalt.Dense (Functor'(..))
import           Data.Bits    (xor, shiftL, shiftR, (.&.))
import           Data.Char    (ord)
import           Data.List    (foldl')
import           Data.Word    (Word64)

-- ---------------------------------------------------------------------------
-- Trilock — 3-component structural identity triad
--   A : structural identity   (functor shape hash)
--   B : connectivity          (child-count Fibonacci mix)
--   C : emission constraint   (atom name hash)
-- ---------------------------------------------------------------------------

data Trilock = Trilock
  { tlA :: Word64   -- structural identity
  , tlB :: Word64   -- connectivity
  , tlC :: Word64   -- emission constraint
  } deriving (Eq, Show)

phi64 :: Word64
phi64 = 0x9E3779B97F4A7C15   -- 2^64 / φ (Fibonacci hash constant)

fibMix :: Word64 -> Word64
fibMix x = (x `xor` (x `shiftR` 30)) * 0xBF58476D1CE4E5B9
         `xor` ((x `xor` (x `shiftR` 27)) * 0x94D049BB133111EB)
         `xor`  (x `shiftR` 31)

nameHash :: String -> Word64
nameHash = foldl' step 0xcbf29ce484222325
  where
    step acc c = (acc `xor` fromIntegral (ord c)) * 0x00000100000001B3

mkTrilock :: Functor' -> Trilock
mkTrilock f = Trilock
  { tlA = fibMix (shapeHash f)
  , tlB = fibMix (fromIntegral (arity f) * phi64)
  , tlC = fibMix (atomHash f)
  }

shapeHash :: Functor' -> Word64
shapeHash (Atom _)            = 0x0000000000000001
shapeHash (Compound _ args)   = fibMix $ fromIntegral (length args) * phi64
shapeHash (Recursive name _)  = nameHash name `xor` 0xDEADBEEFCAFEBABE

arity :: Functor' -> Int
arity (Atom _)          = 0
arity (Compound _ args) = length args
arity (Recursive _ a)   = length a

atomHash :: Functor' -> Word64
atomHash (Atom name)          = nameHash name
atomHash (Compound name _)    = nameHash name
atomHash (Recursive name _)   = nameHash name `xor` phi64

-- Combined 192-bit hash as three Word64 hex fields.
trilockHash :: Trilock -> String
trilockHash (Trilock a b c) =
  hex a ++ "-" ++ hex b ++ "-" ++ hex c
  where
    hex w = pad16 (showHex w "")
    pad16 s = replicate (16 - length s) '0' ++ s

-- Minimal showHex without Data.Numeric.
showHex :: Word64 -> ShowS
showHex 0 acc = if null acc then "0" else acc
showHex n acc = showHex (n `shiftR` 4) (hexDigit (n .&. 0xF) : acc)
  where hexDigit d | d < 10    = toEnum (fromEnum '0' + fromIntegral d)
                   | otherwise = toEnum (fromEnum 'a' + fromIntegral d - 10)
