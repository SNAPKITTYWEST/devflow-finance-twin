-- ========================================================================
-- SOVEREIGN LEVIATHAN NODE LICENSE
-- License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
-- Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- ========================================================================
--
-- This file is a covered work under the GNU Affero General Public License,
-- version 3, together with the Sovereign Leviathan additional terms.
--
-- Hark, though this node be but a spark,
-- Its covenant endureth through the dark.
--
-- Ignorantia juris non excusat.
-- ========================================================================

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
