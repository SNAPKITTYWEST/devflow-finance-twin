{-# LANGUAGE GADTs #-}
-- ISA.Macro — Macro library for common instruction idioms
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

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

-- نسخ قيمة السجل / copy register (Xor-self clears, then Add)
{-@ macroCopy :: rd:RegId -> rs:RegId -> [Instr] @-}
macroCopy :: Int -> Int -> [Instr]
macroCopy rd rs = [Xor rd rd rd, Add rd rd rs]

-- تنظيف السجل / clear register
{-@ macroClear :: r:RegId -> [Instr] @-}
macroClear :: Int -> [Instr]
macroClear r = [Xor r r r]

-- الجمع الفوري / add immediate (uses temp register)
{-@ macroAddImm :: rd:RegId -> rs:RegId -> Word64 -> temp:RegId -> [Instr] @-}
macroAddImm :: Int -> Int -> Word64 -> Int -> [Instr]
macroAddImm rd rs imm temp =
  [ MovImm temp imm
  , Add rd rs temp
  ]

-- حمل كبير فوري / load large immediate via high/low halves
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

-- مقارنة ثم قفز / compare-and-branch (r0 used as scratch)
{-@ macroCompareJump :: rs1:RegId -> rs2:RegId -> Word64 -> [Instr] @-}
macroCompareJump :: Int -> Int -> Word64 -> [Instr]
macroCompareJump rs1 rs2 target =
  [ Sub 0 rs1 rs2
  , JumpZero target
  ]

-- حلقة عد / count loop (r30=limit r31=step scratch)
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

-- ضرب فوري (حلقة) / multiply immediate via repeated add
{-@ macroMulImm :: rd:RegId -> rs:RegId -> {i:Word64 | i <= 1024} -> [Instr] @-}
macroMulImm :: Int -> Int -> Word64 -> [Instr]
macroMulImm rd rs imm =
  [ MovImm rd 0 ]
  ++ replicate (fromIntegral imm) (Add rd rd rs)

-- ── NAND boolean macros ───────────────────────────────────────────────────────
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
