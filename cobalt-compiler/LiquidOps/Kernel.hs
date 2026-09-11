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

-- LiquidOps.Kernel â€” Educational pipeline: HExpr â†’ P4 â†’ LiquidOp IR
-- Simple standalone version for learning and prototyping.
-- For the full production pipeline (ISA integration, NandTree, Logic IR) see
-- LiquidOps.KernelFull.
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module LiquidOps.Kernel where

import Data.Int (Int64)

-- â”€â”€ Source expression (Haskell-side AST) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
data HExpr
  = HVar  String
  | HInt  Int64
  | HAdd  HExpr HExpr
  | HSub  HExpr HExpr
  | HMul  HExpr HExpr
  deriving (Eq, Show)

-- â”€â”€ P4 intermediate (finite, linear, no recursion after lowering) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
data P4
  = P4Var   String
  | P4Const Int64
  | P4Add   P4 P4
  | P4Sub   P4 P4
  | P4Mul   P4 P4
  deriving (Eq, Show)

-- â”€â”€ LiquidOps instruction set (register-based) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
data LiquidOp
  = LLoad   Int String   -- dst â† mem[sym]
  | LConst  Int Int64    -- dst â† imm
  | LAdd    Int Int Int  -- dst â† src1 + src2
  | LSub    Int Int Int  -- dst â† src1 - src2
  | LMul    Int Int Int  -- dst â† src1 * src2
  | LReturn Int          -- return src
  deriving (Eq, Show)

-- â”€â”€ Lowering state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
data LowerState = LowerState
  { nextReg :: Int
  , ops     :: [LiquidOp]
  } deriving (Eq, Show)

emptyLowerState :: LowerState
emptyLowerState = LowerState 0 []

fresh :: LowerState -> (Int, LowerState)
fresh s = (nextReg s, s { nextReg = nextReg s + 1 })

emitOp :: LiquidOp -> LowerState -> LowerState
emitOp op s = s { ops = ops s ++ [op] }

-- â”€â”€ Stage 1: HExpr â†’ P4 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
toP4 :: HExpr -> P4
toP4 (HVar  v)   = P4Var v
toP4 (HInt  n)   = P4Const n
toP4 (HAdd a b)  = P4Add (toP4 a) (toP4 b)
toP4 (HSub a b)  = P4Sub (toP4 a) (toP4 b)
toP4 (HMul a b)  = P4Mul (toP4 a) (toP4 b)

-- â”€â”€ Stage 2: P4 constant folding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
simplifyP4 :: P4 -> P4
simplifyP4 (P4Add (P4Const a) (P4Const b)) = P4Const (a + b)
simplifyP4 (P4Sub (P4Const a) (P4Const b)) = P4Const (a - b)
simplifyP4 (P4Mul (P4Const a) (P4Const b)) = P4Const (a * b)
simplifyP4 (P4Add e1 e2) = P4Add (simplifyP4 e1) (simplifyP4 e2)
simplifyP4 (P4Sub e1 e2) = P4Sub (simplifyP4 e1) (simplifyP4 e2)
simplifyP4 (P4Mul e1 e2) = P4Mul (simplifyP4 e1) (simplifyP4 e2)
simplifyP4 e = e

-- â”€â”€ Stage 3: P4 â†’ register-based LiquidOps â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
lower :: P4 -> LowerState -> (Int, LowerState)
lower (P4Var v) s =
  let (r, s1) = fresh s
  in  (r, emitOp (LLoad r v) s1)
lower (P4Const n) s =
  let (r, s1) = fresh s
  in  (r, emitOp (LConst r n) s1)
lower (P4Add a b) s =
  let (ra, s1) = lower a s
      (rb, s2) = lower b s1
      (rd, s3) = fresh s2
  in  (rd, emitOp (LAdd rd ra rb) s3)
lower (P4Sub a b) s =
  let (ra, s1) = lower a s
      (rb, s2) = lower b s1
      (rd, s3) = fresh s2
  in  (rd, emitOp (LSub rd ra rb) s3)
lower (P4Mul a b) s =
  let (ra, s1) = lower a s
      (rb, s2) = lower b s1
      (rd, s3) = fresh s2
  in  (rd, emitOp (LMul rd ra rb) s3)

-- â”€â”€ Full pipeline: HExpr â†’ [LiquidOp] â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Example: (a+b)*2 â†’
--   [LLoad 0 "a", LLoad 1 "b", LAdd 2 0 1, LConst 3 2, LMul 4 2 3, LReturn 4]
compileKernel :: HExpr -> [LiquidOp]
compileKernel expr =
  let p4          = simplifyP4 (toP4 expr)
      (r, finalS) = lower p4 emptyLowerState
      finalOps    = ops finalS ++ [LReturn r]
  in  finalOps
