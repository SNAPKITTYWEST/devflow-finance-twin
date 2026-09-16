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
module StateMachineKernel where

data MachineState = Run | Fault | Recover deriving (Eq, Show)
data Message = ValidTick | CorruptMsg deriving (Eq, Show)

{-@ type SInt = {v:Int | v >= 0 && v <= 2} @-}
{-@ type MInt = {v:Int | v == 1 || v == 255} @-}

{-@ stateToInt :: MachineState -> SInt @-}
stateToInt :: MachineState -> Int
stateToInt Run = 0
stateToInt Fault = 1
stateToInt Recover = 2

{-@ transition :: current:SInt -> msg:MInt -> SInt @-}
transition :: Int -> Int -> Int
transition 0 1   = 0   -- RUN + Valid -> RUN
transition 0 255 = 1   -- RUN + Corrupt -> FAULT
transition 1 _   = 2   -- FAULT + Any -> RECOVER
transition 2 1   = 0   -- RECOVER + Valid -> RUN
transition _ _   = 1   -- Fallback -> FAULT
