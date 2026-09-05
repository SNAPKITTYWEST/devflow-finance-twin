{-# LANGUAGE ScopedTypeVariables #-}
{-@ LIQUID "--higherorder" @-}
{-@ LIQUID "--exact-data-con" @-}
module FibonacciBraidLedger where

{-@ measure maxIdx :: Int
    maxIdx = 92 @-}
{-@ measure maxWord :: Int
    maxWord = 256 @-}
{-@ measure strands :: Int
    strands = 8 @-}
{-@ measure intMax :: Int
    intMax = 9223372036854775807 @-}
{-@ measure intMin :: Int
    intMin = -9223372036854775808 @-}

MAX_IDX :: Int
MAX_IDX = 92
MAX_WORD :: Int
MAX_WORD = 256
STRANDS :: Int
STRANDS = 8
INT_MAX :: Int
INT_MAX = 9223372036854775807

{-@ type Nat = {v:Int | 0 <= v} @-}
{-@ type FibIdx = {v:Int | 0 <= v && v <= 92} @-}
{-@ type FibVal = {v:Int | 0 <= v && v <= 9223372036854775807} @-}
{-@ type Gen = {v:Int | v != 0 && -8 < v && v < 8} @-}
{-@ type BraidWord = {v:[Gen] | len v <= 256} @-}
{-@ type StateVec = {v:[Int] | len v == 8} @-}

{-@ measure fib :: Int -> Int
    fib 0 = 0
    fib 1 = 1
    fib n = fib (n-1) + fib (n-2) @-}

{-@ fibArray :: n:FibIdx -> {a:[FibVal] | len a == n+1 && hd a == 0} / [n] @-}
fibArray :: Int -> [Int]
fibArray n
  | n == 0 = [0]
  | n == 1 = [0,1]
  | n < 0  = error "negative index"
  | n > MAX_IDX = error "max index"
  | otherwise = go [0,1] 1
  where
    go acc i
      | i == n = acc'
      | otherwise = go acc' (i+1)
      where
        acc' = let v = last acc + last (init acc)
               in if v > INT_MAX then error "overflow" else acc ++ [v]

{-@ fibVal :: n:FibIdx -> FibVal @-}
fibVal :: Int -> Int
fibVal n = last (fibArray n)

{-@ validGen :: Gen -> Bool @-}
validGen :: Int -> Bool
validGen g = g /= 0 && abs g < STRANDS

{-@ validWord :: [Int] -> Bool @-}
validWord :: [Int] -> Bool
validWord w = length w <= MAX_WORD && all validGen w

{-@ inverse :: w:BraidWord -> {v:BraidWord | len v == len w} @-}
inverse :: [Int] -> [Int]
inverse = map negate . reverse

{-@ concatW :: a:BraidWord -> b:BraidWord -> {v:BraidWord | len v == len a + len b} @-}
concatW :: [Int] -> [Int] -> [Int]
concatW = (++)

{-@ append :: w:BraidWord -> g:Gen -> {v:BraidWord | len v == len w + 1} @-}
append :: [Int] -> Int -> [Int]
append w g = w ++ [g]

{-@ reduce :: w:BraidWord -> BraidWord @-}
reduce :: [Int] -> [Int]
reduce = foldl step []
  where
    step [] c = [c]
    step s c
      | last s == -c = init s
      | otherwise    = s ++ [c]

{-@ isReduced :: BraidWord -> Bool @-}
isReduced :: [Int] -> Bool
isReduced w = w == reduce w

{-@ braidLen :: FibIdx -> {v:Int | 1 <= v && v <= 8} @-}
braidLen :: Int -> Int
braidLen n = 1 + (n `mod` 8)

{-@ braidFromFib :: n:FibIdx -> BraidWord @-}
braidFromFib :: Int -> [Int]
braidFromFib n =
  let v = fibVal n
      l = braidLen n
      js = [0..l-1]
      mags j = 1 + ((v + j*13 + n*7) `mod` 7)
      signs j = if ((v + j + n) `mod` 2 == 0) then 1 else -1
  in [ signs j * mags j | j <- js ]

{-@ type BoundedInt = {v:Int | -9223372036854775808 <= v && v <= 9223372036854775807} @-}
{-@ initState :: StateVec @-}
initState :: [Int]
initState = replicate STRANDS 0

{-@ wordContrib :: BraidWord -> StateVec @-}
wordContrib :: [Int] -> [Int]
wordContrib w =
  let base = replicate (STRANDS-1) 0
      upd c g = let i = abs g -1
                    (l, x:r) = splitAt i c
                in l ++ (x + signum g) : r
      contrib = foldl upd base w
  in contrib ++ [0]

{-@ transition :: s:StateVec -> w:BraidWord -> StateVec @-}
transition :: [Int] -> [Int] -> [Int]
transition s w = zipWith (+) s (wordContrib w)

{-@ seal :: n:FibIdx -> (FibVal, BraidWord, StateVec) -> Int @-}
seal :: Int -> (Int, [Int], [Int]) -> Int
seal idx (val, word, state) =
  let h0 = idx * 1000003
      h1 = h0 + val
      h2 = h1 + sum (zipWith (*) word [0..])
      h3 = h2 + sum (zipWith (*) state [1..])
  in h3

data Ledger = Ledger {
  lIdxs   :: [Int],
  lVals   :: [Int],
  lWords  :: [[Int]],
  lRed    :: [[Int]],
  lStates :: [[Int]],
  lSeals  :: [Int]
}

{-@ invariant ledgerInv :: Ledger -> Bool @-}
ledgerInv :: Ledger -> Bool
ledgerInv l =
  length (lIdxs l) == length (lWords l)
  && all validWord (lWords l)
  && all (\n -> n <= MAX_IDX) (lIdxs l)
  && all (\w -> length w <= MAX_WORD) (lWords l)

{-@ buildEntry :: n:FibIdx -> (FibIdx, FibVal, BraidWord, BraidWord, StateVec, Int) @-}
buildEntry :: Int -> (Int, Int, [Int], [Int], [Int], Int)
buildEntry n =
  let v = fibVal n
      w = braidFromFib n
      r = reduce w
      s = transition initState w
      se = seal n (v,w,s)
  in (n,v,w,r,s,se)
