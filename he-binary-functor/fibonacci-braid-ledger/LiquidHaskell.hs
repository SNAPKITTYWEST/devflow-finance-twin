{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

module FibonacciBraidLedger where

import Language.Haskell.Liquid.Prelude
import Data.Int (Int64)

{-@ type MaxFib = {v:Nat | v <= 90} @-}
{-@ type Gen = {v:Int | 1 <= abs v && abs v <= 4} @-}
{-@ type Word = {w:[Gen] | len w <= 64} @-}
{-@ type Idx = {v:Nat | v <= 90} @-}

maxFib, maxGen, maxWord, strands :: Int
maxFib = 90
maxGen = 4
maxWord = 64
strands = 5

{-@ fib :: n:MaxFib -> {v:Nat | v >= 0} @-}
fib :: Int -> Integer
fib 0 = 0
fib 1 = 1
fib n = fib (n-1) + fib (n-2)

{-@ fibArr :: n:MaxFib -> {v:[Integer] | len v == n+1} @-}
fibArr :: Int -> [Integer]
fibArr n = go 0 1 n
  where
    go a _ 0 = [a]
    go a b k = a : go b (a+b) (k-1)

{-@ validGen :: x:Int -> {v:Bool | v <=> (1 <= abs x && abs x <= 4)} @-}
validGen :: Int -> Bool
validGen x = let a = abs x in 1 <= a && a <= maxGen

{-@ validWord :: w:[Int] -> {v:Bool | v <=> (len w <= 64 && all validGen w)} @-}
validWord :: [Int] -> Bool
validWord w = length w <= maxWord && all validGen w

{-@ inv :: Word -> Word @-}
inv :: [Int] -> [Int]
inv = reverse . map negate

{-@ reduce' :: Word -> Word @-}
reduce' :: [Int] -> [Int]
reduce' = reverse . foldl step []
  where
    step [] x = [x]
    step acc@(y:ys) x
      | y == -x = ys
      | otherwise = x:acc

{-@ braidFromFib :: n:Idx -> Word @-}
braidFromFib :: Int -> [Int]
braidFromFib n =
  let f = fromIntegral (fib n)
      l = min f maxWord
      gs = [1 + (k `mod` maxGen) | k <- [0..l-1]]
      ss = [if even k then 1 else -1 | k <- [0..l-1]]
  in zipWith (*) ss gs

data State = State
  { idx :: Int
  , wlen :: Int
  , rlen :: Int
  , seal :: Int64
  , chk :: Int64
  } deriving (Eq, Show)

{-@ initState :: State @-}
initState :: State
initState = State 0 0 0 0 0

{-@ transition :: s:State -> w:Word -> State @-}
transition :: State -> [Int] -> State
transition s w =
  let newIdx = idx s + 1
      wl = length w
      rw = reduce' w
      rl = length rw
      ssum = sum (map abs w)
      newSeal = (seal s + fromIntegral (ssum * fromIntegral (fib (idx s)))) `mod` (2^32)
      newChk = chk s `xor` fromIntegral (sum rw)
  in State newIdx wl rl newSeal newChk

{-@ invariant {v:State | 0 <= idx v && idx v <= 90} @-}
{-@ invariant {v:State | 0 <= wlen v && wlen v <= 64} @-}
{-@ invariant {v:State | 0 <= rlen v && rlen v <= 64} @-}
