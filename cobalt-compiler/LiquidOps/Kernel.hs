-- LiquidOps.Kernel — Educational pipeline: HExpr → P4 → LiquidOp IR
-- Simple standalone version for learning and prototyping.
-- For the full production pipeline (ISA integration, NandTree, Logic IR) see
-- LiquidOps.KernelFull.
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module LiquidOps.Kernel where

import Data.Int (Int64)

-- ── Source expression (Haskell-side AST) ─────────────────────────────────────
data HExpr
  = HVar  String
  | HInt  Int64
  | HAdd  HExpr HExpr
  | HSub  HExpr HExpr
  | HMul  HExpr HExpr
  deriving (Eq, Show)

-- ── P4 intermediate (finite, linear, no recursion after lowering) ─────────────
data P4
  = P4Var   String
  | P4Const Int64
  | P4Add   P4 P4
  | P4Sub   P4 P4
  | P4Mul   P4 P4
  deriving (Eq, Show)

-- ── LiquidOps instruction set (register-based) ───────────────────────────────
data LiquidOp
  = LLoad   Int String   -- dst ← mem[sym]
  | LConst  Int Int64    -- dst ← imm
  | LAdd    Int Int Int  -- dst ← src1 + src2
  | LSub    Int Int Int  -- dst ← src1 - src2
  | LMul    Int Int Int  -- dst ← src1 * src2
  | LReturn Int          -- return src
  deriving (Eq, Show)

-- ── Lowering state ────────────────────────────────────────────────────────────
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

-- ── Stage 1: HExpr → P4 ──────────────────────────────────────────────────────
toP4 :: HExpr -> P4
toP4 (HVar  v)   = P4Var v
toP4 (HInt  n)   = P4Const n
toP4 (HAdd a b)  = P4Add (toP4 a) (toP4 b)
toP4 (HSub a b)  = P4Sub (toP4 a) (toP4 b)
toP4 (HMul a b)  = P4Mul (toP4 a) (toP4 b)

-- ── Stage 2: P4 constant folding ─────────────────────────────────────────────
simplifyP4 :: P4 -> P4
simplifyP4 (P4Add (P4Const a) (P4Const b)) = P4Const (a + b)
simplifyP4 (P4Sub (P4Const a) (P4Const b)) = P4Const (a - b)
simplifyP4 (P4Mul (P4Const a) (P4Const b)) = P4Const (a * b)
simplifyP4 (P4Add e1 e2) = P4Add (simplifyP4 e1) (simplifyP4 e2)
simplifyP4 (P4Sub e1 e2) = P4Sub (simplifyP4 e1) (simplifyP4 e2)
simplifyP4 (P4Mul e1 e2) = P4Mul (simplifyP4 e1) (simplifyP4 e2)
simplifyP4 e = e

-- ── Stage 3: P4 → register-based LiquidOps ───────────────────────────────────
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

-- ── Full pipeline: HExpr → [LiquidOp] ────────────────────────────────────────
-- Example: (a+b)*2 →
--   [LLoad 0 "a", LLoad 1 "b", LAdd 2 0 1, LConst 3 2, LMul 4 2 3, LReturn 4]
compileKernel :: HExpr -> [LiquidOp]
compileKernel expr =
  let p4          = simplifyP4 (toP4 expr)
      (r, finalS) = lower p4 emptyLowerState
      finalOps    = ops finalS ++ [LReturn r]
  in  finalOps
