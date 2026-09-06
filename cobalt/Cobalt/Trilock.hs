{-# LANGUAGE BangPatterns #-}

module Cobalt.Trilock
  ( Functor(..)
  , Matrix(..)
  , Triad(..)
  , Library(..)
  , expand
  , expandBatch
  , matrix
  , trilock
  , lower
  , encode
  ) where

import qualified Data.ByteString as BS
import qualified Data.Map.Strict as M
import Data.Bits
import Data.Int
import Data.Word

-- ============================================================
-- FUNCTOR SYNTAX
-- ============================================================

data Functor
    = Atom !String
    | Var !String
    | Apply !String ![Functor]
    | Recursive !String ![Functor]
    | Fold ![Functor]
    deriving (Eq, Show)

-- ============================================================
-- EXPANSION LIBRARY
--
-- Every discovered functor is retained here.
-- The expansion process therefore feeds the library rather
-- than destroying the structure after lowering.
-- ============================================================

data Library = Library
    { libFunctors :: !(M.Map String Functor)
    , libOrder :: ![String]
    }
    deriving (Eq, Show)

emptyLibrary :: Library
emptyLibrary = Library M.empty []

insertFunctor :: String -> Functor -> Library -> Library
insertFunctor !name !f lib =
    case M.member name (libFunctors lib) of
        True -> lib
        False ->
            lib
              { libFunctors = M.insert name f (libFunctors lib)
              , libOrder = libOrder lib ++ [name]
              }

-- ============================================================
-- RECURSIVE EXPANSION
-- ============================================================

expand :: Library -> Functor -> (Functor, Library)
expand !lib f =
    case f of

        Atom _ ->
            (f, lib)

        Var _ ->
            (f, lib)

        Apply !name xs ->
            let (!ys,!lib') = expandList lib xs
                !node = Apply name ys
                !lib'' = insertFunctor name node lib'
            in
                (node, lib'')

        Recursive !name xs ->
            let (!ys,!lib') = expandList lib xs
                !node = Recursive name ys
                !lib'' = insertFunctor name node lib'
            in
                (node, lib'')

        Fold xs ->
            let (!ys,!lib') = expandList lib xs
            in
                (Fold ys, lib')

expandList
    :: Library
    -> [Functor]
    -> ([Functor], Library)
expandList !lib [] =
    ([], lib)

expandList !lib (x:xs) =
    let (!x', !lib1) = expand lib x
        (!xs',!lib2) = expandList lib1 xs
    in
        (x' : xs', lib2)

expandBatch
    :: [Functor]
    -> Library
expandBatch =
    snd . foldl step ((), emptyLibrary)
  where
    step (_, !lib) !f =
        let (_, !lib') = expand lib f
        in ((),lib')

-- ============================================================
-- DENSE MATRIX
--
-- Finite representation passed to the constraint layer.
-- Describes connectivity, not cryptographic security.
-- ============================================================

data Matrix = Matrix
    { rows :: !Int
    , cols :: !Int
    , cells :: !(M.Map (Int,Int) Int)
    }
    deriving (Eq, Show)

emptyMatrix :: Int -> Int -> Matrix
emptyMatrix r c =
    Matrix r c M.empty

setCell :: Int -> Int -> Int -> Matrix -> Matrix
setCell r c v m =
    m { cells = M.insert (r,c) v (cells m) }

matrix :: Functor -> Matrix
matrix f =
    let nodes = flatten f
        n = length nodes
        base = emptyMatrix n n
    in
        foldl connect base (zip [0..] nodes)
  where
    connect !m (i,node) =
        case node of
            Apply _ xs ->
                foldl
                    (\acc child ->
                        case lookupIndex child of
                            Just j -> setCell i j 1 acc
                            Nothing -> acc)
                    m
                    xs

            Recursive _ xs ->
                foldl
                    (\acc child ->
                        case lookupIndex child of
                            Just j -> setCell i j 2 acc
                            Nothing -> acc)
                    m
                    xs

            _ ->
                m

    allNodes = flatten f

    lookupIndex x =
        findIndexEq x allNodes

findIndexEq :: Eq a => a -> [a] -> Maybe Int
findIndexEq x =
    go 0
  where
    go !_ [] = Nothing
    go !n (y:ys)
        | x == y    = Just n
        | otherwise = go (n+1) ys

flatten :: Functor -> [Functor]
flatten x =
    x : case x of
        Atom _ ->
            []

        Var _ ->
            []

        Apply _ xs ->
            concatMap flatten xs

        Recursive _ xs ->
            concatMap flatten xs

        Fold xs ->
            concatMap flatten xs

-- ============================================================
-- TRILOCK TRIAD
--
-- Three independently represented components:
--
--   A = structural identity
--   B = transition/connectivity
--   C = binary emission constraint
--
-- Compiler IR construct. Not a claim of homomorphic
-- encryption by itself.
-- ============================================================

data Triad = Triad
    { triA :: !Word64
    , triB :: !Word64
    , triC :: !Word64
    }
    deriving (Eq, Show)

mix :: Word64 -> Word64 -> Word64
mix x y =
    let z = x `xor` y
        a = z * 0x9E3779B185EBCA87
    in rotateL a 17

trilock :: Matrix -> [Triad]
trilock m =
    map make [0 .. rows m - 1]
  where
    make !r =
        let !a = rowHash r
            !b = colHash r
            !c = mix a b
        in
            Triad a b c

    rowHash r =
        foldl
            (\h c ->
                mix h
                     (fromIntegral
                        (M.findWithDefault 0 (r,c) (cells m))))
            0
            [0 .. cols m - 1]

    colHash c =
        foldl
            (\h r ->
                mix h
                     (fromIntegral
                        (M.findWithDefault 0 (r,c) (cells m))))
            0
            [0 .. rows m - 1]

-- ============================================================
-- TRIAD -> ISA
-- ============================================================

data ISA
    = Nop
    | Ret
    | XorRR !Word8 !Word8
    | MovImm !Word8 !Word64
    | AddImm !Word8 !Int32
    deriving (Eq, Show)

lower :: [Triad] -> [ISA]
lower =
    concatMap lowerOne
  where
    lowerOne (Triad a b c) =
        [ MovImm 0 a
        , XorRR 0 1
        , AddImm 0 (fromIntegral (c .&. 0x7fffffff))
        ]

-- ============================================================
-- x86-64 BINARY ENCODER
-- ============================================================

encode :: ISA -> BS.ByteString
encode Nop =
    BS.pack [0x90]

encode Ret =
    BS.pack [0xC3]

encode (XorRR dst src) =
    BS.pack
        [ rex dst src
        , 0x31
        , 0xC0
            + ((dst .&. 7) `shiftL` 3)
            + (src .&. 7)
        ]

encode (MovImm r x) =
    BS.pack
        [ rexSingle r
        , 0xB8 + (r .&. 7)
        ]
    <> le64 x

encode (AddImm r x) =
    BS.pack
        [ rexSingle r
        , 0x81
        , 0xC0 + (r .&. 7)
        ]
    <> le32 (fromIntegral x)

rexSingle :: Word8 -> Word8
rexSingle r
    | r >= 8    = 0x49
    | otherwise = 0x48

rex :: Word8 -> Word8 -> Word8
rex dst src =
    0x48
      + if dst >= 8 then 4 else 0
      + if src >= 8 then 1 else 0

le32 :: Word32 -> BS.ByteString
le32 x =
    BS.pack
        [ fromIntegral (x `shiftR` 0)
        , fromIntegral (x `shiftR` 8)
        , fromIntegral (x `shiftR` 16)
        , fromIntegral (x `shiftR` 24)
        ]

le64 :: Word64 -> BS.ByteString
le64 x =
    BS.pack
        [ fromIntegral (x `shiftR` (8*i))
        | i <- [0..7]
        ]

-- ============================================================
-- COMPLETE ONE-SHOT PIPELINE
-- ============================================================

compileFunctor :: Functor -> (Library, Matrix, [Triad], BS.ByteString)
compileFunctor source =
    let !lib = expandBatch [source]
        !expanded =
            case libOrder lib of
                [] -> source
                name:_ ->
                    M.findWithDefault source name (libFunctors lib)

        !m = matrix expanded
        !triads = trilock m
        !isa = lower triads
        !binary = BS.concat (map encode isa)

    in
        (lib,m,triads,binary)
