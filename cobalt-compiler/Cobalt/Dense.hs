module Cobalt.Dense
  ( Functor'(..)
  , ISA(..)
  , Library
  , Rule(..)
  , parsePrologRules
  , rulesToLibrary
  , expandUntilCrystal
  , crystalize
  , crystalFold
  , lowerFunctor
  , encodeISA
  ) where

import qualified Data.Map.Strict as M
import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import           Data.Bits       (shiftL, shiftR, (.&.), (.|.))
import           Data.Word       (Word8, Word32)
import           Data.List       (nub)
import           Data.Char       (isAlphaNum, isSpace)

-- ---------------------------------------------------------------------------
-- Core types
-- ---------------------------------------------------------------------------

data Functor'
  = Atom      String
  | Compound  String [Functor']
  | Recursive String [Functor']   -- retained until lowerFunctor
  deriving (Eq, Ord, Show)

type Library = M.Map String Functor'

data ISA
  = NOP
  | RET
  | MovImm Int Int   -- reg, immediate
  | XorRR  Int Int   -- reg, reg
  | AddImm Int Int   -- reg, immediate
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Prolog tokeniser / parser  (single-clause subset)
-- ---------------------------------------------------------------------------

data Rule = Rule
  { rHead :: String
  , rBody :: [String]
  } deriving (Show)

tokenize :: String -> [String]
tokenize []     = []
tokenize (c:cs)
  | isSpace c                    = tokenize cs
  | isAlphaNum c || c == '_'     =
      let (tok, rest) = span (\x -> isAlphaNum x || x == '_') (c:cs)
      in  tok : tokenize rest
  | c `elem` (":-(),." :: String) = [c] : tokenize cs
  | otherwise                    = tokenize cs

parsePrologRules :: String -> [Rule]
parsePrologRules = concatMap parseClause . lines
  where
    parseClause ln =
      let toks = tokenize ln
      in  case toks of
            (h:":-":rest) -> [Rule h (filter (`notElem` [",","."]) rest)]
            [h,"."]       -> [Rule h []]
            [h]           -> [Rule h []]
            _             -> []

-- ---------------------------------------------------------------------------
-- Library construction
-- ---------------------------------------------------------------------------

rulesToLibrary :: [Rule] -> Library
rulesToLibrary = M.fromList . map (\r -> (rHead r, buildFunctor r))
  where
    buildFunctor r
      | null (rBody r) = Atom (rHead r)
      | otherwise      = Compound (rHead r) (map Atom (rBody r))

-- ---------------------------------------------------------------------------
-- Fixed-point crystal expansion  (max 64 rounds)
-- ---------------------------------------------------------------------------

maxRounds :: Int
maxRounds = 64

expandF :: Library -> Functor' -> Functor'
expandF lib (Atom name) = case M.lookup name lib of
  Nothing             -> Atom name
  Just (Atom n)
    | n == name       -> Recursive name []
  Just f              -> f
expandF lib (Compound name args) =
  let args' = map (expandF lib) args
  in  Compound name args'
expandF lib (Recursive name args) =
  Recursive name (map (expandF lib) args)

isStable :: Library -> Library -> Bool
isStable old new = M.toAscList old == M.toAscList new

expandUntilCrystal :: Library -> Library
expandUntilCrystal = go 0
  where
    go n lib
      | n >= maxRounds = lib
      | otherwise =
          let lib' = M.map (expandF lib) lib
          in  if isStable lib lib' then lib else go (n + 1) lib'

-- ---------------------------------------------------------------------------
-- Crystal: stable library → flat functor list
-- ---------------------------------------------------------------------------

crystalize :: Library -> [Functor']
crystalize = nub . M.elems

-- Depth-bounded fold caps infinite recursion before lowering.
crystalFold :: Int -> Functor' -> [Functor']
crystalFold 0 _                     = [Atom "_depth_cap"]
crystalFold _ f@(Atom _)            = [f]
crystalFold d f@(Compound _ args)   = f : concatMap (crystalFold (d-1)) args
crystalFold d   (Recursive name args) =
  Atom name : concatMap (crystalFold (d-1)) args

-- ---------------------------------------------------------------------------
-- Lowering: Functor' → ISA
-- ---------------------------------------------------------------------------

lowerFunctor :: Functor' -> [ISA]
lowerFunctor (Atom _)          = [NOP]
lowerFunctor (Recursive _ _)   = [MovImm 0 0, XorRR 0 0, RET]
lowerFunctor (Compound _ args) =
  zipWith (\i _ -> MovImm i i) [0..] args ++ [RET]

-- ---------------------------------------------------------------------------
-- x86-64 encoding
-- ---------------------------------------------------------------------------

encodeISA :: [ISA] -> ByteString
encodeISA = BS.pack . concatMap encodeOne
  where
    encodeOne :: ISA -> [Word8]
    encodeOne NOP = [0x90]
    encodeOne RET = [0xC3]
    encodeOne (MovImm r i) =
      let op = 0xB8 + fromIntegral (r `mod` 8) :: Word8
      in  [0x48, op] ++ imm32 i
    encodeOne (XorRR r1 r2) =
      let rm :: Word8
          rm = 0xC0
             .|. (fromIntegral (r2 `mod` 8) `shiftL` 3)
             .|.  fromIntegral (r1 `mod` 8)
      in  [0x48, 0x33, rm]
    encodeOne (AddImm r i) =
      let rm = 0xC0 .|. fromIntegral (r `mod` 8) :: Word8
      in  [0x48, 0x81, rm] ++ imm32 i

    imm32 :: Int -> [Word8]
    imm32 n =
      let w = fromIntegral n :: Word32
      in  map (\s -> fromIntegral ((w `shiftR` s) .&. 0xFF)) [0,8,16,24]
