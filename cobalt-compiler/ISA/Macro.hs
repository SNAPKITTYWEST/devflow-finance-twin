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

{-# LANGUAGE GADTs #-}
-- ISA.Macro â€” Macro library for common instruction idioms
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module ISA.Macro where

import ISA.Core
import Data.Word
import Data.Bits (shiftR)

type MacroLib = [(String, [Instr])]

{-@ registerMacro :: String -> [Instr] -> MacroLib -> MacroLib @-}
registerMacro :: String -> [Instr] -> MacroLib -> MacroLib
registerMacro name body lib = (name, body) : lib

{-@ lookupMacro :: String -> MacroLib -> Maybe [Instr] @-}
lookupMacro :: String -> MacroLib -> Maybe [Instr]
lookupMacro = lookup

-- Ù†Ø³Ø® Ù‚ÙŠÙ…Ø© Ø§Ù„Ø³Ø¬Ù„ / copy register (Xor-self clears, then Add)
{-@ macroCopy :: rd:RegId -> rs:RegId -> [Instr] @-}
macroCopy :: Int -> Int -> [Instr]
macroCopy rd rs = [Xor rd rd rd, Add rd rd rs]

-- ØªÙ†Ø¸ÙŠÙ Ø§Ù„Ø³Ø¬Ù„ / clear register
{-@ macroClear :: r:RegId -> [Instr] @-}
macroClear :: Int -> [Instr]
macroClear r = [Xor r r r]

-- Ø§Ù„Ø¬Ù…Ø¹ Ø§Ù„ÙÙˆØ±ÙŠ / add immediate (uses temp register)
{-@ macroAddImm :: rd:RegId -> rs:RegId -> Word64 -> temp:RegId -> [Instr] @-}
macroAddImm :: Int -> Int -> Word64 -> Int -> [Instr]
macroAddImm rd rs imm temp =
  [ MovImm temp imm
  , Add rd rs temp
  ]

-- Ø­Ù…Ù„ ÙƒØ¨ÙŠØ± ÙÙˆØ±ÙŠ / load large immediate via high/low halves
{-@ macroLoadLarge :: rd:RegId -> temp:RegId -> Word64 -> [Instr] @-}
macroLoadLarge :: Int -> Int -> Word64 -> [Instr]
macroLoadLarge rd temp imm =
  let high = fromIntegral (imm `shiftR` 32) :: Word64
      low  = imm .&. 0xFFFFFFFF
  in [ MovImm rd high
     , MovImm temp 32
     , Add rd rd temp
     , MovImm temp low
     , Or rd rd temp
     ]

-- Ù…Ù‚Ø§Ø±Ù†Ø© Ø«Ù… Ù‚ÙØ² / compare-and-branch (r0 used as scratch)
{-@ macroCompareJump :: rs1:RegId -> rs2:RegId -> Word64 -> [Instr] @-}
macroCompareJump :: Int -> Int -> Word64 -> [Instr]
macroCompareJump rs1 rs2 target =
  [ Sub 0 rs1 rs2
  , JumpZero target
  ]

-- Ø­Ù„Ù‚Ø© Ø¹Ø¯ / count loop (r30=limit r31=step scratch)
{-@ macroCountLoop :: counter:RegId -> Word64 -> [Instr] -> Word64 -> [Instr] @-}
macroCountLoop :: Int -> Word64 -> [Instr] -> Word64 -> [Instr]
macroCountLoop counter limit body target =
  [ MovImm counter 0 ]
  ++ body
  ++ [ MovImm 31 1
     , Add counter counter 31
     , MovImm 30 limit
     , Sub 29 counter 30
     , JumpZero target
     ]

-- Ø¶Ø±Ø¨ ÙÙˆØ±ÙŠ (Ø­Ù„Ù‚Ø©) / multiply immediate via repeated add
{-@ macroMulImm :: rd:RegId -> rs:RegId -> {i:Word64 | i <= 1024} -> [Instr] @-}
macroMulImm :: Int -> Int -> Word64 -> [Instr]
macroMulImm rd rs imm =
  [ MovImm rd 0 ]
  ++ replicate (fromIntegral imm) (Add rd rd rs)

-- â”€â”€ NAND boolean macros â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
{-@ macroNand :: rd:RegId -> rs1:RegId -> rs2:RegId -> [Instr] @-}
macroNand :: Int -> Int -> Int -> [Instr]
macroNand rd rs1 rs2 = [Nand rd rs1 rs2]

-- NOT x = NAND(x,x)
{-@ macroNot :: rd:RegId -> rs:RegId -> [Instr] @-}
macroNot :: Int -> Int -> [Instr]
macroNot rd rs = [Nand rd rs rs]

-- AND(x,y) = NAND(NAND(x,y), NAND(x,y))
{-@ macroAnd :: rd:RegId -> rs1:RegId -> rs2:RegId -> temp:RegId -> [Instr] @-}
macroAnd :: Int -> Int -> Int -> Int -> [Instr]
macroAnd rd rs1 rs2 temp =
  [ Nand temp rs1 rs2
  , Nand rd temp temp
  ]

-- OR(x,y) = NAND(NAND(x,x), NAND(y,y))
{-@ macroOr :: rd:RegId -> rs1:RegId -> rs2:RegId -> t1:RegId -> t2:RegId -> [Instr] @-}
macroOr :: Int -> Int -> Int -> Int -> Int -> [Instr]
macroOr rd rs1 rs2 t1 t2 =
  [ Nand t1 rs1 rs1
  , Nand t2 rs2 rs2
  , Nand rd t1 t2
  ]
