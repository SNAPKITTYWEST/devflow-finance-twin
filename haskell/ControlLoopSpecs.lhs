{-@ LIQUID "--no-termination" @-}
{-@ LIQUID "--ple" @-}

module ControlLoopSpecs where

import Data.List (foldl')

type Prob = Double

{-@ type ProbVec N = {v:[Prob] | len v == N && (Sum v) >= 0.0 } @-}

{-@ measure Sum :: [Double] -> Double
    Sum([]) = 0.0
    Sum(x:xs) = x + Sum(xs)
  @-}

{-@ normalize :: xs: [Prob] -> {v:[Prob] | len v == len xs && (Sum v) >= 0.0 } @-}
normalize :: [Prob] -> [Prob]
normalize xs =
  let s = foldl' (+) 0.0 xs
  in if s <= 0 then replicate (length xs) (1.0 / fromIntegral (length xs))
     else map (/ s) xs

{-@ assume normalize_spec :: xs:[Prob] -> { v:[Prob] | len v == len xs && (Sum v) >= 0.0 } @-}
normalize_spec :: [Prob] -> [Prob]
normalize_spec = normalize

{-@ update_weights :: ws:[Prob] -> likes:[Prob] -> {v:[Prob] | len v == len ws } @-}
update_weights :: [Prob] -> [Prob] -> [Prob]
update_weights ws likes =
  let prod = zipWith (*) ws likes
  in normalize prod

{-@ all_nonneg :: xs:[Prob] -> {v:Bool | v <=> (Sum xs >= 0.0)} @-}
all_nonneg :: [Prob] -> Bool
all_nonneg xs = all (>= 0.0) xs
