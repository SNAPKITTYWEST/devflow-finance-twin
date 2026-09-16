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

-- PhaseEstimationQuipper.hs
-- Quipper circuit: discrete phase estimation analogue (single-qubit phase via controlled-U powers)
-- Build: ghc with Quipper installed
-- Usage: runghc PhaseEstimationQuipper.hs

{-# LANGUAGE FlexibleContexts #-}
import Quipper
import Quipper.Libraries.Simulation (run_generic_io)
import Data.Bits (testBit)
import Control.Monad (replicateM_)

-- Controlled-U: here U = Rz(Ï†) on target; controlled by control qubit
controlled_Rz :: Double -> (Qubit, Qubit) -> Circ ()
controlled_Rz phi (ctrl, tgt) = do
  with_controls (ctrl .==. 1) $ do
    gate_Rz_at phi tgt
  return ()

-- Phase estimation with t ancilla qubits, one target qubit prepared in eigenstate of U
phase_estimation :: Int -> Double -> Circ ([Qubit], Qubit)
phase_estimation t phi = do
  anc <- qinit (replicate t False)
  tgt <- qinit True
  mapUnary hadamard anc
  let indices = [0..t-1]
  sequence_ [ do
      let power = 2^(t-1-k)
      replicateM_ power (controlled_Rz phi (anc !! k, tgt))
    | k <- indices ]
  inv_qft anc
  return (anc, tgt)

-- Inverse QFT
inv_qft :: [Qubit] -> Circ ()
inv_qft qs = do
  let n = length qs
  sequence_ [ do
      let k = i
      hadamard_at (qs !! k)
      sequence_ [ do
          let j = k + m
          if j < n
            then do
              let angle = - pi / fromIntegral (2^(m+1))
              controlled_Rz angle (qs !! j, qs !! k)
            else return ()
        | m <- [1..(n-k-1)] ]
    | i <- [0..(n-1)] ]
  mapM_ swap_qubits (zip qs (reverse qs))
  return ()

main :: IO ()
main = do
  let t   = 4
      phi = 0.3 * pi
  print_generic Preview (phase_estimation t phi)
  putStrLn "Note: measure ancilla qubits to obtain phase estimate bits; feed into classical controller."
