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

-- ISA.Program â€” Program assembly, validation, execution, tracing
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module ISA.Program where

import ISA.Core
import ISA.Macro
import Data.Word

type Program = [Instr]

-- ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„ØªØ¹Ù„ÙŠÙ…Ø§Øª / validate instruction registers
{-@ instrValid :: Instr -> Bool @-}
instrValid :: Instr -> Bool
instrValid instr = case instr of
  MovImm rd _          -> rd >= 0 && rd < 32
  Add  rd rs1 rs2      -> all validR [rd, rs1, rs2]
  Sub  rd rs1 rs2      -> all validR [rd, rs1, rs2]
  Mul  rd rs1 rs2      -> all validR [rd, rs1, rs2]
  Div  rd rs1 rs2      -> all validR [rd, rs1, rs2]
  And  rd rs1 rs2      -> all validR [rd, rs1, rs2]
  Or   rd rs1 rs2      -> all validR [rd, rs1, rs2]
  Xor  rd rs1 rs2      -> all validR [rd, rs1, rs2]
  Nand rd rs1 rs2      -> all validR [rd, rs1, rs2]
  Load  rd ra _        -> all validR [rd, ra]
  Store rs ra _        -> all validR [rs, ra]
  Jump  _              -> True
  JumpZero _           -> True
  Nop                  -> True
  where validR r = r >= 0 && r < 32

-- ØªØ¬Ù…ÙŠØ¹ Ø§Ù„Ø¨Ø±Ù†Ø§Ù…Ø¬ / assemble and validate program
{-@ assembleProgram :: Program -> Either String Program @-}
assembleProgram :: Program -> Either String Program
assembleProgram prog
  | all instrValid prog = Right prog
  | otherwise           = Left "invalid instruction sequence"

-- ØªÙ†ÙÙŠØ° Ø§Ù„Ø¨Ø±Ù†Ø§Ù…Ø¬ / run program (step-bounded, terminates)
{-@ runProgram :: Program -> MachineState -> {n:Int | n >= 0} -> MachineState @-}
runProgram :: Program -> MachineState -> Int -> MachineState
runProgram _ s 0 = s
runProgram prog s steps
  | pc s >= fromIntegral (length prog) = s
  | otherwise =
      let instr = prog !! fromIntegral (pc s)
      in  runProgram prog (exec instr s) (steps - 1)

-- ØªØªØ¨Ø¹ Ø§Ù„ØªÙ†ÙÙŠØ° / execution trace with state snapshots
{-@ traceProgram :: Program -> MachineState -> {n:Int | n >= 0} -> [(Word64, MachineState)] @-}
traceProgram :: Program -> MachineState -> Int -> [(Word64, MachineState)]
traceProgram _ s 0 = [(pc s, s)]
traceProgram prog s steps
  | pc s >= fromIntegral (length prog) = [(pc s, s)]
  | otherwise =
      let instr = prog !! fromIntegral (pc s)
      in  (pc s, s) : traceProgram prog (exec instr s) (steps - 1)
