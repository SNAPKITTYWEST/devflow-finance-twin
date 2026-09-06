{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE DeriveGeneric #-}

-- Language.Fixpoint.LiquidOps.Kernel
-- Production compilation pipeline:
--   Fixpoint Expr → Recursive Normalization → KernelIR → NAND canonicalization
--   → LiquidOps → OPExit
--
-- Production constraints:
--   • NAND is the only boolean primitive (AND/OR/NOT/IMP/IFF are eliminated)
--   • Arithmetic, loads, stores, comparisons, control flow remain explicit
--   • P4 consumes the finite LiquidOps stream (no runtime recursion)
--   • LH termination via exprSize / nandNodes measures
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module Language.Fixpoint.LiquidOps.Kernel
  ( Kernel(..)
  , KBool(..)
  , KArith(..)
  , KMem(..)
  , KCmp(..)
  , LiquidOp(..)
  , KernelState(..)
  , compile
  , compileValidated
  , normalize
  , lower
  , nandNot
  , nandAnd
  , nandOr
  , nandImp
  , walkNand
  , nandNodes
  , validate
  ) where

import Data.Int  (Int64)
import Data.List (foldl')
import Language.Fixpoint.Types  hiding (simplify)
import Language.Fixpoint.Smt.Theories

--------------------------------------------------------------------------------
-- REFINEMENTS
--------------------------------------------------------------------------------

{-@ type Nat = {v:Int | v >= 0} @-}
{-@ type RegId   = {v:Int | v >= 0} @-}
{-@ type LabelId = {v:Int | v >= 0} @-}

--------------------------------------------------------------------------------
-- REGISTERS
--------------------------------------------------------------------------------

data Reg = Reg { regId :: Int } deriving (Eq, Ord, Show)

{-@ mkReg :: Nat -> Reg @-}
mkReg :: Int -> Reg
mkReg = Reg

--------------------------------------------------------------------------------
-- LABELS
--------------------------------------------------------------------------------

newtype Label = Label Int deriving (Eq, Ord, Show)

--------------------------------------------------------------------------------
-- ARITHMETIC IR
--------------------------------------------------------------------------------

data KArith
  = KConst Int64
  | KVar   String
  | KAdd   KArith KArith
  | KSub   KArith KArith
  | KMul   KArith KArith
  | KDiv   KArith KArith
  | KMod   KArith KArith
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- MEMORY IR
--------------------------------------------------------------------------------

data KMem
  = KLoad  KArith
  | KStore KArith KArith
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- COMPARISON IR (produces boolean, consumed by NAND)
--------------------------------------------------------------------------------

data KCmp
  = KEq KArith KArith
  | KNe KArith KArith
  | KLt KArith KArith
  | KLe KArith KArith
  | KGt KArith KArith
  | KGe KArith KArith
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- NAND BOOLEAN IR  (only primitive: BNand; AND/OR/NOT/IMP are pre-eliminated)
--------------------------------------------------------------------------------

data KBool
  = BTrue
  | BFalse
  | BCompare KCmp
  | BNand    KBool KBool
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- HIGH-LEVEL KERNEL
--------------------------------------------------------------------------------

data Kernel
  = KArithmetic KArith
  | KMemory     KMem
  | KBoolean    KBool
  | KIf         KBool Kernel Kernel
  | KSeq        [Kernel]
  | KReturn     Kernel
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- LIQUIDOPS INSTRUCTION SET
--------------------------------------------------------------------------------

data LiquidOp
  = OPConst   Reg Int64
  | OPLoad    Reg String
  | OPAdd     Reg Reg Reg
  | OPSub     Reg Reg Reg
  | OPMul     Reg Reg Reg
  | OPDiv     Reg Reg Reg
  | OPMod     Reg Reg Reg
  | OPLoadMem Reg Reg
  | OPStoreMem Reg Reg
  | OPEq      Reg Reg Reg
  | OPNe      Reg Reg Reg
  | OPLt      Reg Reg Reg
  | OPLe      Reg Reg Reg
  | OPGt      Reg Reg Reg
  | OPGe      Reg Reg Reg
  | OPNand    Reg Reg Reg
  | OPBranch  Reg Label
  | OPLabel   Label
  | OPReturn  Reg
  | OPExit
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- LOWERING STATE
--------------------------------------------------------------------------------

data KernelState = KernelState
  { ksNextReg   :: !Int
  , ksNextLabel :: !Int
  , ksOps       :: [LiquidOp]
  } deriving (Eq, Show)

emptyState :: KernelState
emptyState = KernelState 0 0 []

freshReg :: KernelState -> (Reg, KernelState)
freshReg s = (Reg r, s { ksNextReg = r + 1 })
  where r = ksNextReg s

freshLabel :: KernelState -> (Label, KernelState)
freshLabel s = (Label l, s { ksNextLabel = l + 1 })
  where l = ksNextLabel s

emit :: LiquidOp -> KernelState -> KernelState
emit op s = s { ksOps = ksOps s ++ [op] }

--------------------------------------------------------------------------------
-- FIXPOINT EXPRESSION SIZE (termination measure)
--------------------------------------------------------------------------------

{-@ measure exprSize :: Expr -> Nat @-}
exprSize :: Expr -> Int
exprSize e = case e of
  EVar _       -> 1
  ECon _       -> 1
  EBot         -> 1
  PTrue        -> 1
  PFalse       -> 1
  EBin _ x y  -> 1 + exprSize x + exprSize y
  EApp x y    -> 1 + exprSize x + exprSize y
  PAtom _ x y -> 1 + exprSize x + exprSize y
  PAnd xs      -> 1 + sum (map exprSize xs)
  POr xs       -> 1 + sum (map exprSize xs)
  PNot x       -> 1 + exprSize x
  PImp x y     -> 1 + exprSize x + exprSize y
  PIff x y     -> 1 + exprSize x + exprSize y
  _            -> 1

--------------------------------------------------------------------------------
-- CONSTANT FOLDING HELPERS
--------------------------------------------------------------------------------

applyConstantFolding :: Bop -> Expr -> Expr -> Expr
applyConstantFolding bop (ECon (I a)) (ECon (I b)) = case bop of
  Plus  -> ECon (I (a + b))
  Minus -> ECon (I (a - b))
  Times -> ECon (I (a * b))
  Div   -> if b /= 0 then ECon (I (a `div` b)) else EBin bop (ECon (I a)) (ECon (I b))
  Mod   -> if b /= 0 then ECon (I (a `mod` b)) else EBin bop (ECon (I a)) (ECon (I b))
  _     -> EBin bop (ECon (I a)) (ECon (I b))
applyConstantFolding Plus  e (ECon (I 0)) = e
applyConstantFolding Plus  (ECon (I 0)) e = e
applyConstantFolding Times _ (ECon (I 0)) = ECon (I 0)
applyConstantFolding Times (ECon (I 0)) _ = ECon (I 0)
applyConstantFolding Times e (ECon (I 1)) = e
applyConstantFolding Times (ECon (I 1)) e = e
applyConstantFolding bop  x y              = EBin bop x y

applyBooleanFolding :: Brel -> Expr -> Expr -> Expr
applyBooleanFolding rel (ECon (I a)) (ECon (I b)) = case rel of
  Eq  -> if a == b then PTrue else PFalse
  Ne  -> if a /= b then PTrue else PFalse
  Lt  -> if a < b  then PTrue else PFalse
  Le  -> if a <= b then PTrue else PFalse
  Gt  -> if a > b  then PTrue else PFalse
  Ge  -> if a >= b then PTrue else PFalse
  _   -> PAtom rel (ECon (I a)) (ECon (I b))
applyBooleanFolding rel x y = PAtom rel x y

isSetPred :: Expr -> Bool
isSetPred (EVar s) = show s `elem` ["setEmp","setMem","setSub","setCup","setCap","setDif"]
isSetPred _        = False

applySetFolding :: Expr -> Expr -> Expr
applySetFolding f x = EApp f x

--------------------------------------------------------------------------------
-- RECURSIVE NORMALIZATION  (structurally decreasing on exprSize)
--------------------------------------------------------------------------------

{-@ normalize :: e:Expr -> {v:Expr | exprSize v <= exprSize e} / [exprSize e] @-}
normalize :: Expr -> Expr
normalize e = case e of
  EBin bop x y -> applyConstantFolding bop (normalize x) (normalize y)
  PAtom rel x y -> applyBooleanFolding rel (normalize x) (normalize y)
  PAnd xs       -> PAnd (map normalize xs)
  POr  xs       -> POr  (map normalize xs)
  PNot x        -> PNot (normalize x)
  PImp x y      -> PImp (normalize x) (normalize y)
  PIff x y      -> PIff (normalize x) (normalize y)
  EApp x y      ->
    let x' = normalize x; y' = normalize y
    in  if isSetPred x' then applySetFolding x' y' else EApp x' y'
  _             -> e

--------------------------------------------------------------------------------
-- FIXPOINT → ARITHMETIC
--------------------------------------------------------------------------------

exprToArith :: Expr -> Maybe KArith
exprToArith e = case e of
  ECon (I n) -> Just (KConst (fromIntegral n))
  EVar x     -> Just (KVar (show x))
  EBin Plus  x y -> KAdd <$> exprToArith x <*> exprToArith y
  EBin Minus x y -> KSub <$> exprToArith x <*> exprToArith y
  EBin Times x y -> KMul <$> exprToArith x <*> exprToArith y
  EBin Div   x y -> KDiv <$> exprToArith x <*> exprToArith y
  EBin Mod   x y -> KMod <$> exprToArith x <*> exprToArith y
  _              -> Nothing

--------------------------------------------------------------------------------
-- FIXPOINT → COMPARISON
--------------------------------------------------------------------------------

exprToCmp :: Brel -> Expr -> Expr -> Maybe KCmp
exprToCmp rel x y = do
  x' <- exprToArith x
  y' <- exprToArith y
  pure $ case rel of
    Eq  -> KEq x' y'; Ne -> KNe x' y'
    Lt  -> KLt x' y'; Le -> KLe x' y'
    Gt  -> KGt x' y'; Ge -> KGe x' y'
    Ueq -> KEq x' y'; Une -> KNe x' y'

--------------------------------------------------------------------------------
-- FIXPOINT → BOOLEAN (eliminates AND/OR/NOT/IMP/IFF into NAND)
--------------------------------------------------------------------------------

exprToBool :: Expr -> Maybe KBool
exprToBool e = case e of
  PTrue        -> Just BTrue
  PFalse       -> Just BFalse
  PAtom rel x y -> BCompare <$> exprToCmp rel x y
  PNot x       -> nandNot <$> exprToBool x
  PAnd []      -> Just BTrue
  PAnd [x]     -> exprToBool x
  PAnd (x:xs)  -> nandAnd <$> exprToBool x <*> exprToBool (PAnd xs)
  POr  []      -> Just BFalse
  POr  [x]     -> exprToBool x
  POr  (x:xs)  -> nandOr  <$> exprToBool x <*> exprToBool (POr xs)
  PImp x y     -> nandImp  <$> exprToBool x <*> exprToBool y
  PIff x y     -> do
    a <- exprToBool x; b <- exprToBool y
    let ab = BNand a b; aa = BNand a a; bb = BNand b b
        x1 = BNand aa bb;  x2 = BNand ab ab
    pure (BNand x1 x2)
  _            -> Nothing

--------------------------------------------------------------------------------
-- NAND IDENTITIES  (boolean completeness primitives)
--------------------------------------------------------------------------------

-- NOT a  = NAND(a,a)
nandNot :: KBool -> KBool
nandNot x = BNand x x

-- AND(a,b)  = NAND(NAND(a,b), NAND(a,b))
nandAnd :: KBool -> KBool -> KBool
nandAnd x y = let n = BNand x y in BNand n n

-- OR(a,b)   = NAND(NAND(a,a), NAND(b,b))
nandOr :: KBool -> KBool -> KBool
nandOr x y = BNand (BNand x x) (BNand y y)

-- IMP(a,b)  = NAND(NAND(a,a), b)
nandImp :: KBool -> KBool -> KBool
nandImp x y = BNand (BNand x x) y

--------------------------------------------------------------------------------
-- NAND SIZE / WALK  (LH termination measures)
--------------------------------------------------------------------------------

{-@ measure nandNodes :: KBool -> Nat @-}
nandNodes :: KBool -> Int
nandNodes BTrue         = 1
nandNodes BFalse        = 1
nandNodes (BCompare _)  = 1
nandNodes (BNand x y)   = 1 + nandNodes x + nandNodes y

{-@ walkNand :: b:KBool -> [KBool] / [nandNodes b] @-}
walkNand :: KBool -> [KBool]
walkNand b@BTrue         = [b]
walkNand b@BFalse        = [b]
walkNand b@(BCompare _)  = [b]
walkNand b@(BNand x y)   = b : walkNand x ++ walkNand y

--------------------------------------------------------------------------------
-- FIXPOINT → KERNEL
--------------------------------------------------------------------------------

lowerExpr :: Expr -> Either String Kernel
lowerExpr e = case exprToBool e of
  Just b  -> Right (KBoolean b)
  Nothing -> case exprToArith e of
    Just a  -> Right (KArithmetic a)
    Nothing -> Left ("LiquidOps: unsupported Fixpoint expression: " ++ show e)

--------------------------------------------------------------------------------
-- ARITHMETIC LOWERING
--------------------------------------------------------------------------------

lowerArith :: KArith -> KernelState -> (Reg, KernelState)
lowerArith (KConst n) s = let (r,s1) = freshReg s in (r, emit (OPConst r n) s1)
lowerArith (KVar x)   s = let (r,s1) = freshReg s in (r, emit (OPLoad r x) s1)
lowerArith (KAdd x y) s = lowerBinArith OPAdd x y s
lowerArith (KSub x y) s = lowerBinArith OPSub x y s
lowerArith (KMul x y) s = lowerBinArith OPMul x y s
lowerArith (KDiv x y) s = lowerBinArith OPDiv x y s
lowerArith (KMod x y) s = lowerBinArith OPMod x y s

lowerBinArith :: (Reg -> Reg -> Reg -> LiquidOp) -> KArith -> KArith -> KernelState -> (Reg, KernelState)
lowerBinArith op x y s =
  let (rx, s1) = lowerArith x s
      (ry, s2) = lowerArith y s1
      (rz, s3) = freshReg s2
  in  (rz, emit (op rz rx ry) s3)

--------------------------------------------------------------------------------
-- COMPARISON LOWERING
--------------------------------------------------------------------------------

lowerCmp :: KCmp -> KernelState -> (Reg, KernelState)
lowerCmp (KEq x y) s = lowerBinCmp OPEq x y s
lowerCmp (KNe x y) s = lowerBinCmp OPNe x y s
lowerCmp (KLt x y) s = lowerBinCmp OPLt x y s
lowerCmp (KLe x y) s = lowerBinCmp OPLe x y s
lowerCmp (KGt x y) s = lowerBinCmp OPGt x y s
lowerCmp (KGe x y) s = lowerBinCmp OPGe x y s

lowerBinCmp :: (Reg -> Reg -> Reg -> LiquidOp) -> KArith -> KArith -> KernelState -> (Reg, KernelState)
lowerBinCmp op x y s =
  let (rx, s1) = lowerArith x s
      (ry, s2) = lowerArith y s1
      (rz, s3) = freshReg s2
  in  (rz, emit (op rz rx ry) s3)

--------------------------------------------------------------------------------
-- NAND LOWERING  (only boolean primitive in LiquidOps)
--------------------------------------------------------------------------------

lowerBool :: KBool -> KernelState -> (Reg, KernelState)
lowerBool BTrue         s = let (r,s1) = freshReg s in (r, emit (OPConst r 1) s1)
lowerBool BFalse        s = let (r,s1) = freshReg s in (r, emit (OPConst r 0) s1)
lowerBool (BCompare c)  s = lowerCmp c s
lowerBool (BNand x y)   s =
  let (rx, s1) = lowerBool x s
      (ry, s2) = lowerBool y s1
      (rz, s3) = freshReg s2
  in  (rz, emit (OPNand rz rx ry) s3)

--------------------------------------------------------------------------------
-- MEMORY LOWERING
--------------------------------------------------------------------------------

lowerMem :: KMem -> KernelState -> (Reg, KernelState)
lowerMem (KLoad addr) s =
  let (ra, s1) = lowerArith addr s
      (rd, s2) = freshReg s1
  in  (rd, emit (OPLoadMem rd ra) s2)
lowerMem (KStore addr value) s =
  let (ra, s1) = lowerArith addr s
      (rv, s2) = lowerArith value s1
  in  (rv, emit (OPStoreMem ra rv) s2)

--------------------------------------------------------------------------------
-- KERNEL LOWERING
--------------------------------------------------------------------------------

lower :: Kernel -> KernelState -> (Reg, KernelState)
lower (KArithmetic a)     s = lowerArith a s
lower (KBoolean b)        s = lowerBool b s
lower (KMemory m)         s = lowerMem m s
lower (KReturn x)         s = let (r, s1) = lower x s in (r, emit (OPReturn r) s1)
lower (KSeq [])           s = freshReg s
lower (KSeq (x:xs))       s = let (_, s1) = lower x s in lower (KSeq xs) s1
lower (KIf cond yes no)   s =
  let (rc, s1) = lowerBool cond s
      (le, s2) = freshLabel s1
      (ln, s3) = freshLabel s2
      s4       = emit (OPBranch rc le) s3
      (_,  s5) = lower yes s4
      s6       = emit (OPBranch rc ln) s5
      s7       = emit (OPLabel le) s6
      (rn, s8) = lower no s7
      s9       = emit (OPLabel ln) s8
  in  (rn, s9)

--------------------------------------------------------------------------------
-- COMPILE  (Fixpoint Expr → LiquidOps)
--------------------------------------------------------------------------------

{-@ compile :: e:Expr -> Either String [LiquidOp] @-}
compile :: Expr -> Either String [LiquidOp]
compile source = do
  let normalized = normalize source
  kernel         <- lowerExpr normalized
  let (_, st)    =  lower (KReturn kernel) emptyState
  pure (ksOps st ++ [OPExit])

--------------------------------------------------------------------------------
-- VALIDATION
--------------------------------------------------------------------------------

validLiquidOp :: LiquidOp -> Bool
validLiquidOp (OPConst  (Reg r) _)         = r >= 0
validLiquidOp (OPLoad   (Reg r) _)         = r >= 0
validLiquidOp (OPAdd    (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPSub    (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPMul    (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPDiv    (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPMod    (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPLoadMem  (Reg a)(Reg b))   = a>=0&&b>=0
validLiquidOp (OPStoreMem (Reg a)(Reg b))   = a>=0&&b>=0
validLiquidOp (OPEq     (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPNe     (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPLt     (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPLe     (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPGt     (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPGe     (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPNand   (Reg a)(Reg b)(Reg c)) = a>=0&&b>=0&&c>=0
validLiquidOp (OPBranch (Reg r)(Label l))   = r>=0&&l>=0
validLiquidOp (OPLabel  (Label l))           = l>=0
validLiquidOp (OPReturn (Reg r))             = r>=0
validLiquidOp OPExit                         = True

validate :: [LiquidOp] -> Either String [LiquidOp]
validate ops
  | null ops              = Left "LiquidOps: empty kernel"
  | not (all validLiquidOp ops) = Left "LiquidOps: invalid register or label"
  | last ops /= OPExit    = Left "LiquidOps: missing OPExit"
  | otherwise             = Right ops

compileValidated :: Expr -> Either String [LiquidOp]
compileValidated source = compile source >>= validate
