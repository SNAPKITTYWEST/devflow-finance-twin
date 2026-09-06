{-# LANGUAGE BangPatterns #-}

module Cobalt.Dense
  ( Cobalt(..)
  , compileBatch
  , compile
  ) where

import qualified Data.ByteString as B
import qualified Data.Map.Strict as M
import Data.Char
import Data.Int
import Data.Word

-- ============================================================
-- Dense syntax/functor representation
-- ============================================================

data Cobalt
  = A !String
  | V !String
  | F !String ![Cobalt]
  | R !String ![Cobalt]
  | S ![Cobalt]
  deriving (Eq,Show)

-- F = ordinary functor
-- R = recursive functor
-- S = folded sequence

data Rule = Rule !Cobalt !Cobalt
  deriving (Eq,Show)

data Settings = Settings
  { invert :: !Bool
  , width :: !Int
  } deriving (Eq,Show)

-- ============================================================
-- ISA
-- ============================================================

data ISA
  = NOP
  | RET
  | MOV !Word8 !Word64
  | ADD !Word8 !Int32
  | XOR !Word8 !Word8
  | JMP !Int32
  deriving (Eq,Show)

-- ============================================================
-- Dense lexer
-- ============================================================

lexDense :: String -> [String]
lexDense =
  words . map normalize
  where
    normalize c
      | c `elem` "(),.:-" = ' '
      | otherwise = c

-- ============================================================
-- Atom parser
-- ============================================================

atom :: String -> Cobalt
atom x
  | isUpper (headDef '_' x) = V x
  | otherwise = A x

headDef :: a -> [a] -> a
headDef d [] = d
headDef _ (x:_) = x

-- ============================================================
-- Dense term parser
-- ============================================================

parseTerm :: [String] -> (Cobalt,[String])
parseTerm [] = (A "",[])

parseTerm (x:xs) =
  case xs of
    y:rest
      | isFunctorToken y ->
          let (args,tail') = parseArgs rest
          in (F x args,tail')
    _ ->
      (atom x,xs)

isFunctorToken :: String -> Bool
isFunctorToken x =
  x `elem`
    [ "step"
    , "walk"
    , "add"
    , "sub"
    , "and"
    , "or"
    , "not"
    ]

parseArgs :: [String] -> ([Cobalt],[String])
parseArgs [] = ([],[])

parseArgs xs =
  let (x,rest) = parseTerm xs
  in case rest of
       [] -> ([x],[])
       _ ->
         let (ys,zs) = parseArgs rest
         in (x:ys,zs)

-- ============================================================
-- Syntax -> recursive functor
-- ============================================================

foldRecursive :: String -> [Cobalt] -> Cobalt
foldRecursive name body =
  if any (contains name) body
  then R name body
  else F name body

contains :: String -> Cobalt -> Bool
contains name x =
  case x of
    A _ -> False
    V _ -> False
    F n xs -> n == name || any (contains name) xs
    R n xs -> n == name || any (contains name) xs
    S xs -> any (contains name) xs

-- ============================================================
-- Dense rule parser
--
-- Example:
--
-- walk X :- step X Y, walk Y.
--
-- ============================================================

parseRule :: String -> Maybe Rule
parseRule source =
  let t = lexDense source
  in case t of
       name:args ->
         let headNode = F name (map atom args)
         in Just
              (Rule
                headNode
                (foldBody name args))
       _ -> Nothing

foldBody :: String -> [String] -> Cobalt
foldBody name vars =
  case vars of
    [] ->
      S []

    x:rest ->
      let current =
            F "step"
              [ atom x
              , atom (headDef "X" rest)
              ]

          recursive =
            R name
              [ F "ref" [atom (headDef "X" rest)] ]

      in S [current,recursive]

-- ============================================================
-- Vault transformation
-- ============================================================

vault :: Settings -> Cobalt -> Cobalt
vault s x
  | not (invert s) = x

vault s (A x) =
  A (reverse x)

vault s (V x) =
  V (reverse x)

vault s (F n xs) =
  F
    (reverse n)
    (map (vault s) (reverse xs))

vault s (R n xs) =
  R
    (reverse n)
    (map (vault s) xs)

vault s (S xs) =
  S
    (map (vault s) (reverse xs))

-- ============================================================
-- Functor folding
--
-- Recursive nodes are folded directly into syntax/ISA.
-- ============================================================

foldISA :: Cobalt -> [ISA]
foldISA x =
  case x of

    A _ ->
      [NOP]

    V _ ->
      [NOP]

    F name args ->
      case name of
        "mov" ->
          case args of
            [V r,A n] ->
              [MOV (register r) (readWord n)]
            _ ->
              concatMap foldISA args

        "add" ->
          case args of
            [V r,A n] ->
              [ADD (register r) (readInt32 n)]
            _ ->
              concatMap foldISA args

        "xor" ->
          case args of
            [V a,V b] ->
              [XOR (register a) (register b)]
            _ ->
              concatMap foldISA args

        "ret" ->
          [RET]

        _ ->
          concatMap foldISA args

    R _ body ->
      concatMap foldISA body

    S xs ->
      concatMap foldISA xs

-- ============================================================
-- Register mapping
-- ============================================================

register :: String -> Word8
register x =
  case map toLower x of
    "rax" -> 0
    "rcx" -> 1
    "rdx" -> 2
    "rbx" -> 3
    "rsp" -> 4
    "rbp" -> 5
    "rsi" -> 6
    "rdi" -> 7
    "r8"  -> 8
    "r9"  -> 9
    "r10" -> 10
    "r11" -> 11
    "r12" -> 12
    "r13" -> 13
    "r14" -> 14
    "r15" -> 15
    _     -> 0

readWord :: String -> Word64
readWord x =
  case reads x of
    [(n,"")] -> fromIntegral (n :: Integer)
    _ -> 0

readInt32 :: String -> Int32
readInt32 x =
  case reads x of
    [(n,"")] -> fromIntegral (n :: Integer)
    _ -> 0

-- ============================================================
-- x86-64 encoding
-- ============================================================

encode :: ISA -> B.ByteString
encode NOP =
  B.pack [0x90]

encode RET =
  B.pack [0xC3]

encode (MOV r imm) =
  B.pack
    [ rex r
    , 0xB8 + (r .&. 7)
    ]
  <> le64 imm

encode (ADD r imm) =
  B.pack
    [ 0x48
    , 0x81
    , 0xC0 + (r .&. 7)
    ]
  <> le32 (fromIntegral imm)

encode (XOR a b) =
  B.pack
    [ rex2 a b
    , 0x31
    , 0xC0 + ((a .&. 7) `shiftL` 3)
             + (b .&. 7)
    ]

encode (JMP d) =
  B.pack [0xE9] <> le32 (fromIntegral d)

-- ============================================================
-- Dense binary helpers
-- ============================================================

rex :: Word8 -> Word8
rex r
  | r >= 8    = 0x49
  | otherwise = 0x48

rex2 :: Word8 -> Word8 -> Word8
rex2 a b =
  0x48
  + if a >= 8 then 4 else 0
  + if b >= 8 then 1 else 0

le32 :: Word32 -> B.ByteString
le32 x =
  B.pack
    [ fromIntegral (x `shiftR` 0)
    , fromIntegral (x `shiftR` 8)
    , fromIntegral (x `shiftR` 16)
    , fromIntegral (x `shiftR` 24)
    ]

le64 :: Word64 -> B.ByteString
le64 x =
  B.pack
    [ fromIntegral (x `shiftR` (8*i))
    | i <- [0..7]
    ]

-- ============================================================
-- One-shot transformation
-- ============================================================

compile :: Settings -> String -> Maybe B.ByteString
compile settings source = do

  rule <- parseRule source

  let Rule _ body = rule

      transformed =
        vault settings body

      isa =
        foldISA transformed

  pure (B.concat (map encode isa))

-- ============================================================
-- Batch transformation
-- ============================================================

compileBatch
  :: Settings
  -> [(String,String)]
  -> [(String,Maybe B.ByteString)]

compileBatch settings =
  map
    (\(name,source) ->
      (name,compile settings source))
