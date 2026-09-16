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

{-@ LIQUID "--ple" @-}
module BlocklaceRefinements where

{-@ type ParentCount = {v:Int | v >= 1 && v <= 4} @-}
{-@ type BraidLen = {v:Int | v >= 0 && v <= 16} @-}

data BlocklaceEntry = BlocklaceEntry {
    height :: Int,
    pCount :: Int,
    parents :: [Int],
    stateId :: Int,
    bLen :: Int,
    bWord :: [Int],
    selfSeal :: Int
}

{-@ validBlocklaceEntry :: e:BlocklaceEntry -> {v:Bool | v <=> (pCount e >= 1 && pCount e <= 4 && len (parents e) == pCount e && bLen e <= 16)} @-}
validBlocklaceEntry :: BlocklaceEntry -> Bool
validBlocklaceEntry e =
    pCount e >= 1 &&
    pCount e <= 4 &&
    length (parents e) == pCount e &&
    bLen e <= 16
