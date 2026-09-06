{-# LANGUAGE GADTs, DataKinds, KindSignatures, TypeFamilies #-}
-- ISA.Core — Machine state, registers, memory, flags, instruction GADT
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module ISA.Core where

import Data.Word
import Data.Int
import Data.Bits
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M

{-@ type RegId  = {r:Int   | r >= 0 && r < 32} @-}
{-@ type MemAddr = Word64 @-}
{-@ type Imm     = Int64  @-}

-- ── Machine state ─────────────────────────────────────────────────────────────
-- رجل الآلة الحالة / machine state

data MachineState = MachineState
  { regs  :: Map Int Word64
  , mem   :: Map Word64 Word8
  , pc    :: Word64
  , flags :: Flags
  } deriving (Show, Eq)

data Flags = Flags
  { zeroFlag     :: Bool
  , signFlag     :: Bool
  , carryFlag    :: Bool
  , overflowFlag :: Bool
  } deriving (Show, Eq)

{-@ emptyState :: MachineState @-}
emptyState :: MachineState
emptyState = MachineState
  { regs  = M.fromList [(i, 0) | i <- [0..31]]
  , mem   = M.empty
  , pc    = 0
  , flags = Flags False False False False
  }

-- ── Register access ───────────────────────────────────────────────────────────
{-@ getReg :: r:RegId -> MachineState -> Word64 @-}
getReg :: Int -> MachineState -> Word64
getReg r s = M.findWithDefault 0 r (regs s)

{-@ setReg :: r:RegId -> Word64 -> MachineState -> MachineState @-}
setReg :: Int -> Word64 -> MachineState -> MachineState
setReg r v s = s { regs = M.insert r v (regs s) }

-- ── Memory access ─────────────────────────────────────────────────────────────
{-@ readMem  :: MemAddr -> MachineState -> Word8 @-}
readMem :: Word64 -> MachineState -> Word8
readMem a s = M.findWithDefault 0 a (mem s)

{-@ writeMem :: MemAddr -> Word8 -> MachineState -> MachineState @-}
writeMem :: Word64 -> Word8 -> MachineState -> MachineState
writeMem a v s = s { mem = M.insert a v (mem s) }

-- ── Flags ─────────────────────────────────────────────────────────────────────
{-@ updateFlags :: Word64 -> MachineState -> MachineState @-}
updateFlags :: Word64 -> MachineState -> MachineState
updateFlags result s = s
  { flags = (flags s)
      { zeroFlag = result == 0
      , signFlag = testBit result 63
      }
  }

-- ── Instruction GADT ─────────────────────────────────────────────────────────
data Instr where
  MovImm    :: Int -> Word64  -> Instr        -- rd = imm
  Add       :: Int -> Int -> Int -> Instr     -- rd = rs1 + rs2
  Sub       :: Int -> Int -> Int -> Instr     -- rd = rs1 - rs2
  Mul       :: Int -> Int -> Int -> Instr     -- rd = rs1 * rs2
  Div       :: Int -> Int -> Int -> Instr     -- rd = rs1 / rs2 (0 if div-by-zero)
  And       :: Int -> Int -> Int -> Instr     -- rd = rs1 & rs2
  Or        :: Int -> Int -> Int -> Instr     -- rd = rs1 | rs2
  Xor       :: Int -> Int -> Int -> Instr     -- rd = rs1 ^ rs2
  Nand      :: Int -> Int -> Int -> Instr     -- rd = ~(rs1 & rs2)
  Load      :: Int -> Int -> Word64 -> Instr  -- rd = mem[ra + offset]
  Store     :: Int -> Int -> Word64 -> Instr  -- mem[ra + offset] = rs
  Jump      :: Word64 -> Instr                -- pc = target
  JumpZero  :: Word64 -> Instr                -- if ZF then pc = target
  Nop       :: Instr
  deriving (Show, Eq)

-- ── Instruction execution ─────────────────────────────────────────────────────
{-@ exec :: Instr -> MachineState -> MachineState @-}
exec :: Instr -> MachineState -> MachineState
exec instr s = case instr of
  MovImm rd imm ->
    s { pc = pc s + 1, regs = M.insert rd imm (regs s) }
  Add rd rs1 rs2 ->
    let r = getReg rs1 s + getReg rs2 s
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  Sub rd rs1 rs2 ->
    let r = getReg rs1 s - getReg rs2 s
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  Mul rd rs1 rs2 ->
    let r = getReg rs1 s * getReg rs2 s
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  Div rd rs1 rs2 ->
    let v2 = getReg rs2 s
        r  = if v2 == 0 then 0 else getReg rs1 s `div` v2
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  And rd rs1 rs2 ->
    let r = getReg rs1 s .&. getReg rs2 s
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  Or rd rs1 rs2 ->
    let r = getReg rs1 s .|. getReg rs2 s
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  Xor rd rs1 rs2 ->
    let r = xor (getReg rs1 s) (getReg rs2 s)
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  Nand rd rs1 rs2 ->
    let r = complement (getReg rs1 s .&. getReg rs2 s)
    in updateFlags r $ s { pc = pc s + 1, regs = M.insert rd r (regs s) }
  Load rd ra offset ->
    let addr = getReg ra s + offset
        byte = fromIntegral (readMem addr s)
    in s { pc = pc s + 1, regs = M.insert rd byte (regs s) }
  Store rs ra offset ->
    let addr = getReg ra s + offset
        byte = fromIntegral (getReg rs s)
    in s { pc = pc s + 1, mem = M.insert addr byte (mem s) }
  Jump target   -> s { pc = target }
  JumpZero tgt  -> if zeroFlag (flags s) then s { pc = tgt } else s { pc = pc s + 1 }
  Nop           -> s { pc = pc s + 1 }
