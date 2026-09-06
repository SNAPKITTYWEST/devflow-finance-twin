{-@ LIQUID "--reflection" @-}
module FibRaid where

{-@ type Idx = {v:Int | 0 <= v && v <= 20} @-}
{-@ type Gen = {v:Int | 1 <= v && v <= 7 || -7 <= v && v <= -1} @-}
{-@ type Len = {v:Int | 0 <= v && v <= 16} @-}

data Word = W {len :: Int, gens :: [Int]} deriving (Eq, Show)
data Entry = E {n :: Int, prev :: Int, op :: Int, word :: Word, state :: Int, seal :: Int} deriving (Eq, Show)

{-@ validGen :: Int -> Bool @-}
validGen :: Int -> Bool
validGen g = (1<=g && g<=7) || (-7<=g && g<= -1)

{-@ validWord :: Word -> Bool @-}
validWord :: Word -> Bool
validWord (W l gs) = l == length gs && all validGen gs && l <= 16

{-@ step :: Entry -> Entry -> Bool @-}
step :: Entry -> Entry -> Bool
step old new =
  validWord (word new) &&
  n new <= 20 &&
  (n old < n new || n old == 0)
