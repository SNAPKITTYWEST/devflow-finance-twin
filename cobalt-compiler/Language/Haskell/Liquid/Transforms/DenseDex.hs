-- Language.Haskell.Liquid.Transforms.DenseDex — Dense index transforms for LiquidHaskell
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust
-- {-@ LIQUID "--reflection" @-}

module Language.Haskell.Liquid.Transforms.DenseDex where

import Data.List (nub, sort)

-- ── Dense index type ─────────────────────────────────────────────────────────
{-@ type DexIdx = {v:Int | v >= 0} @-}

-- A dense index mapping: list of (key, value) pairs sorted by key
data DenseDex a = DenseDex
  { dexKeys   :: [Int]
  , dexValues :: [a]
  } deriving (Eq, Show)

{-@ measure dexSize :: DenseDex a -> Nat
    dexSize (DenseDex ks _) = len ks @-}

-- ── Constructors ──────────────────────────────────────────────────────────────
{-@ emptyDex :: DenseDex a @-}
emptyDex :: DenseDex a
emptyDex = DenseDex [] []

{-@ insertDex :: DexIdx -> a -> DenseDex a -> DenseDex a @-}
insertDex :: Int -> a -> DenseDex a -> DenseDex a
insertDex k v (DenseDex ks vs) = DenseDex (k:ks) (v:vs)

-- ── Lookup ────────────────────────────────────────────────────────────────────
{-@ lookupDex :: DexIdx -> DenseDex a -> Maybe a @-}
lookupDex :: Int -> DenseDex a -> Maybe a
lookupDex k (DenseDex ks vs) = go ks vs
  where
    go []       _       = Nothing
    go (k':ks') (v:vs') = if k == k' then Just v else go ks' vs'
    go _        _       = Nothing

-- ── Fold (termination: dexSize d) ────────────────────────────────────────────
{-@ dexFold :: (b -> DexIdx -> a -> b) -> b -> d:DenseDex a -> b / [dexSize d] @-}
dexFold :: (b -> Int -> a -> b) -> b -> DenseDex a -> b
dexFold _ acc (DenseDex []     _)      = acc
dexFold f acc (DenseDex (k:ks) (v:vs)) = dexFold f (f acc k v) (DenseDex ks vs)
dexFold _ acc _                        = acc

-- ── Map ──────────────────────────────────────────────────────────────────────
{-@ dexMap :: (a -> b) -> DenseDex a -> DenseDex b @-}
dexMap :: (a -> b) -> DenseDex a -> DenseDex b
dexMap f d = dexFold (\acc k v -> insertDex k (f v) acc) emptyDex d

-- ── Filter ───────────────────────────────────────────────────────────────────
{-@ dexFilter :: (DexIdx -> a -> Bool) -> DenseDex a -> DenseDex a @-}
dexFilter :: (Int -> a -> Bool) -> DenseDex a -> DenseDex a
dexFilter p d = dexFold (\acc k v -> if p k v then insertDex k v acc else acc) emptyDex d

-- ── Merge (union, left-biased) ───────────────────────────────────────────────
{-@ dexMerge :: DenseDex a -> DenseDex a -> DenseDex a @-}
dexMerge :: DenseDex a -> DenseDex a -> DenseDex a
dexMerge d1 d2 = dexFold (\acc k v -> case lookupDex k acc of
    Nothing -> insertDex k v acc
    Just _  -> acc) d1 d2

-- ── Normalize (deduplicate keys) ─────────────────────────────────────────────
{-@ normalizeDex :: DenseDex a -> DenseDex a @-}
normalizeDex :: DenseDex a -> DenseDex a
normalizeDex d = dexFilter (\k _ -> True) d
