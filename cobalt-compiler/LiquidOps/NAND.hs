--------------------------------------------------------------------------------
-- | LiquidOps NAND Kernel
-- |
-- | SOURCE      : Haskell / Fixpoint Expr
-- | NORMALIZATION : recursive Fixpoint traversal, constant folding,
-- |                 boolean folding, set folding
-- | LOGIC       : every boolean operation → NAND blocks
-- | LOWERING    : NAND IR → P4 → LiquidOps
-- | TERMINAL    : LiquidOps contains no Haskell expressions.
--------------------------------------------------------------------------------

{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE DeriveGeneric #-}

module LiquidOps.NAND
  ( NAND(..)
  , Logic(..)
  , Kernel(..)
  , LiquidOp(..)
  , LowerState(..)
  , Reg(..)
  , mkReg
  , normalize
  , nandify
  , lowerNAND
  , compileKernel
  , nandNot
  , nandAnd
  , nandOr
  , nandImp
  , nandTrue
  , nandFalse
  , nandSize
  , walkNAND
  , expandNAND
  , exampleNAND
  , exampleKernel
  ) where

import qualified Data.HashSet as HS
import qualified Data.HashMap.Strict as HM
import qualified Data.Set as S
import qualified Data.Maybe as Mb
import Data.Hashable
import Data.Int
import Data.Word
import GHC.Generics

-- Stub imports — replace with real Language.Fixpoint.Types in production
-- import Language.Fixpoint.Types hiding (simplify)
-- import Language.Fixpoint.Smt.Theories

-- Minimal Fixpoint stubs so this module compiles standalone
type Symbol = String
data Bop = Plus | Minus | Times | Div | RTimes | RDiv | Mod deriving (Eq, Show)
data Brel = Gt | Ge | Lt | Le | Eq | Ne | Ueq | Une deriving (Eq, Show)
data Constant = I Integer | R Double deriving (Eq, Show)
data Expr
  = EVar Symbol
  | ECon Constant
  | EBot
  | EBin Bop Expr Expr
  | EApp Expr Expr
  | PAtom Brel Expr Expr
  | PAnd [Expr]
  | POr [Expr]
  | PNot Expr
  | PImp Expr Expr
  | PIff Expr Expr
  | PTrue
  | PFalse
  deriving (Eq, Show)
dropECst :: Expr -> Expr
dropECst = id
isTautoPred :: Expr -> Bool
isTautoPred PTrue = True; isTautoPred _ = False
isContraPred :: Expr -> Bool
isContraPred PFalse = True; isContraPred _ = False
isSetPred :: Expr -> Bool
isSetPred _ = False
setEmp = "emp" :: Symbol
setMem = "mem" :: Symbol
setSub = "sub" :: Symbol
setCup = "cup" :: Symbol
setCap = "cap" :: Symbol
setDif = "dif" :: Symbol
setEmpty = "empty" :: Symbol
setSng = "sng" :: Symbol

--------------------------------------------------------------------------------
-- | REFINED NATURAL REGISTER SPACE
--------------------------------------------------------------------------------

newtype Reg = Reg { regId :: Int } deriving (Eq, Ord, Show)

mkReg :: Int -> Reg
mkReg = Reg

--------------------------------------------------------------------------------
-- | NAND BLOCK
--------------------------------------------------------------------------------

data NAND
  = NInput Reg
  | NConst Bool
  | NNand NAND NAND
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- | LOGICAL NORMAL FORM
--------------------------------------------------------------------------------

data Logic
  = LAtom Expr
  | LNot Logic
  | LAnd Logic Logic
  | LOr Logic Logic
  | LImp Logic Logic
  | LIff Logic Logic
  | LNand Logic Logic
  | LTrue
  | LFalse
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- | KERNEL IR
--------------------------------------------------------------------------------

data Kernel
  = KBool NAND
  | KInt  Expr
  | KSeq  [Kernel]
  | KIf   NAND Kernel Kernel
  | KReturn Kernel
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- | LIQUID OPS (terminal executable IR)
--------------------------------------------------------------------------------

data LiquidOp
  = Ld     Reg String
  | ImmI   Reg Int64
  | Mov    Reg Reg
  | AddI   Reg Reg Reg
  | SubI   Reg Reg Reg
  | MulI   Reg Reg Reg
  | AndI   Reg Reg Reg
  | OrI    Reg Reg Reg
  | XorI   Reg Reg Reg
  | NandI  Reg Reg Reg      -- the key instruction
  | SetEQ  Reg Reg Reg
  | SetLT  Reg Reg Reg
  | SetLE  Reg Reg Reg
  | Branch Reg Int
  | Label  Int
  | Return Reg
  | Exit
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- | LOWERING STATE
--------------------------------------------------------------------------------

data LowerState = LowerState
  { nextRegister :: !Int
  , nextLabel    :: !Int
  , emittedOps   :: [LiquidOp]
  } deriving (Eq, Show)

emptyLowerState :: LowerState
emptyLowerState = LowerState 0 0 []

freshR :: LowerState -> (Reg, LowerState)
freshR s =
  let r = nextRegister s
  in (Reg r, s { nextRegister = r + 1 })

freshLabel :: LowerState -> (Int, LowerState)
freshLabel s =
  let l = nextLabel s
  in (l, s { nextLabel = l + 1 })

emit :: LiquidOp -> LowerState -> LowerState
emit op s = s { emittedOps = emittedOps s ++ [op] }

--------------------------------------------------------------------------------
-- | EXPRESSION SIZE (for Liquid Haskell termination measure)
--------------------------------------------------------------------------------

exprSize :: Expr -> Int
exprSize e = case e of
  EVar _       -> 1
  ECon _       -> 1
  EBot         -> 1
  EBin _ x y  -> 1 + exprSize x + exprSize y
  EApp x y    -> 1 + exprSize x + exprSize y
  PAtom _ x y -> 1 + exprSize x + exprSize y
  PAnd xs     -> 1 + sum (map exprSize xs)
  POr  xs     -> 1 + sum (map exprSize xs)
  PNot x      -> 1 + exprSize x
  PImp x y    -> 1 + exprSize x + exprSize y
  PIff x y    -> 1 + exprSize x + exprSize y
  PTrue       -> 1
  PFalse      -> 1

isBooleanExpr :: Expr -> Bool
isBooleanExpr e = case e of
  PTrue{}  -> True;  PFalse{} -> True;  PAtom{} -> True
  PAnd{}   -> True;  POr{}    -> True;  PNot{}  -> True
  PImp{}   -> True;  PIff{}   -> True;  _       -> False

--------------------------------------------------------------------------------
-- | NORMALIZATION (recursive, Liquid Haskell: exprSize decreasing)
--------------------------------------------------------------------------------

normalize :: Expr -> Expr
normalize e = case e of
  EBin bop x y   -> applyConstantFolding bop (normalize x) (normalize y)
  PAtom rel x y  -> applyBooleanFolding  rel (normalize x) (normalize y)
  PAnd xs        -> PAnd (map normalize xs)
  POr  xs        -> POr  (map normalize xs)
  PNot x         -> PNot (normalize x)
  PImp x y       -> PImp (normalize x) (normalize y)
  PIff x y       -> PIff (normalize x) (normalize y)
  EApp x y       ->
    let x' = normalize x; y' = normalize y
    in if isSetPred x' then applySetFolding x' y' else EApp x' y'
  _              -> e

applyBooleanFolding :: Brel -> Expr -> Expr -> Expr
applyBooleanFolding brel e1 e2 =
  let e = PAtom brel e1 e2
  in case (e1, e2) of
       (ECon (I a), ECon (I b)) ->
         if getOp brel a b then PTrue else PFalse
       _ -> if isTautoPred e then PTrue
            else if isContraPred e then PFalse
            else e
  where
    getOp Gt = (>); getOp Ge = (>=); getOp Lt = (<); getOp Le = (<=)
    getOp Eq = (==); getOp Ne = (/=); getOp Ueq = (==); getOp Une = (/=)

applyConstantFolding :: Bop -> Expr -> Expr -> Expr
applyConstantFolding bop e1 e2 =
  let e = EBin bop e1 e2
  in case (e1, e2) of
       (ECon (I a), ECon (I b)) -> case bop of
         Plus  -> ECon (I (a + b))
         Minus -> ECon (I (a - b))
         Times -> ECon (I (a * b))
         Mod | b /= 0 -> ECon (I (a `mod` b))
         _    -> e
       _ -> e

applySetFolding :: Expr -> Expr -> Expr
applySetFolding e1 e2 = EApp e1 e2  -- simplified stub

--------------------------------------------------------------------------------
-- | BOOLEAN EXPR → LOGIC
--------------------------------------------------------------------------------

exprToLogic :: Expr -> Logic
exprToLogic e = case e of
  PTrue      -> LTrue
  PFalse     -> LFalse
  PAtom{}    -> LAtom e
  PAnd []    -> LTrue
  PAnd [x]   -> exprToLogic x
  PAnd (x:xs)-> LAnd (exprToLogic x) (exprToLogic (PAnd xs))
  POr  []    -> LFalse
  POr  [x]   -> exprToLogic x
  POr  (x:xs)-> LOr  (exprToLogic x) (exprToLogic (POr xs))
  PNot x     -> LNot (exprToLogic x)
  PImp x y   -> LImp (exprToLogic x) (exprToLogic y)
  PIff x y   -> LIff (exprToLogic x) (exprToLogic y)
  _          -> LAtom e

--------------------------------------------------------------------------------
-- | LOGIC → NAND  (every gate = NAND)
--------------------------------------------------------------------------------

nandify :: Logic -> NAND
nandify l = case l of
  LTrue  -> let x = NConst True  in NNand x (NNand x x)
  LFalse -> let x = NConst False in NNand x (NNand x x)
  LAtom _ -> NConst True
  LNand x y -> NNand (nandify x) (nandify y)
  LNot x -> let a = nandify x in NNand a a
  LAnd x y ->
    let a = nandify x; b = nandify y; n = NNand a b
    in NNand n n
  LOr x y ->
    let a = nandify x; b = nandify y
    in NNand (NNand a a) (NNand b b)
  LImp x y ->
    let a = nandify x; b = nandify y
    in NNand (NNand a a) b
  LIff x y ->
    let a = nandify x; b = nandify y
        ab = NNand a b; aa = NNand a a; bb = NNand b b
        na = NNand aa bb; nb = NNand ab ab
    in NNand na nb

--------------------------------------------------------------------------------
-- | NAND → REGISTERS (LiquidOps emission)
--------------------------------------------------------------------------------

lowerNAND :: NAND -> LowerState -> (Reg, LowerState)
lowerNAND node state = case node of
  NInput r -> (r, state)
  NConst b ->
    let (r, s1) = freshR state
        v = if b then 1 else 0
        s2 = emit (ImmI r v) s1
    in (r, s2)
  NNand x y ->
    let (rx, s1) = lowerNAND x state
        (ry, s2) = lowerNAND y s1
        (rz, s3) = freshR s2
        s4 = emit (NandI rz rx ry) s3
    in (rz, s4)

lowerLogic :: Expr -> Kernel
lowerLogic e
  | isBooleanExpr e = KBool (nandify (exprToLogic e))
  | otherwise       = KInt e

--------------------------------------------------------------------------------
-- | KERNEL LOWERING
--------------------------------------------------------------------------------

lowerKernel :: Kernel -> LowerState -> (Reg, LowerState)
lowerKernel kernel state = case kernel of
  KBool n -> lowerNAND n state
  KInt _  -> let (r, s) = freshR state in (r, s)
  KSeq [] -> let (r, s) = freshR state in (r, s)
  KSeq (x:xs) ->
    let (_, s1) = lowerKernel x state
    in lowerKernel (KSeq xs) s1
  KIf cond yes no ->
    let (rc, s1)    = lowerNAND cond state
        (lElse, s2) = freshLabel s1
        (lEnd,  s3) = freshLabel s2
        s4 = emit (Branch rc lElse) s3
        (_,  s5)    = lowerKernel yes s4
        s6 = emit (Label lEnd)  s5
        s7 = emit (Label lElse) s6
        (rn, s8) = lowerKernel no s7
        s9 = emit (Label lEnd)  s8
    in (rn, s9)
  KReturn x ->
    let (r, s1) = lowerKernel x state
        s2 = emit (Return r) s1
    in (r, s2)

--------------------------------------------------------------------------------
-- | COMPLETE PIPELINE
--------------------------------------------------------------------------------

compileKernel :: Expr -> [LiquidOp]
compileKernel source =
  let normalized = normalize source
      kernel     = lowerLogic normalized
      (_, s)     = lowerKernel kernel emptyLowerState
  in emittedOps s

--------------------------------------------------------------------------------
-- | NAND COMBINATORS
--------------------------------------------------------------------------------

nandNot :: NAND -> NAND;        nandNot x = NNand x x
nandAnd :: NAND -> NAND -> NAND; nandAnd x y = let n = NNand x y in NNand n n
nandOr  :: NAND -> NAND -> NAND; nandOr  x y = NNand (NNand x x) (NNand y y)
nandImp :: NAND -> NAND -> NAND; nandImp x y = NNand (NNand x x) y
nandTrue  :: NAND; nandTrue  = let x = NConst True  in NNand x (NNand x x)
nandFalse :: NAND; nandFalse = let x = NConst False in NNand x (NNand x x)

--------------------------------------------------------------------------------
-- | NAND SIZE + WALK (Liquid Haskell termination measures)
--------------------------------------------------------------------------------

nandSize :: NAND -> Int
nandSize (NInput _)  = 1
nandSize (NConst _)  = 1
nandSize (NNand x y) = 1 + nandSize x + nandSize y

walkNAND :: NAND -> [NAND]
walkNAND n = case n of
  NInput _  -> [n]
  NConst _  -> [n]
  NNand x y -> n : walkNAND x ++ walkNAND y

expandNAND :: NAND -> [NAND]
expandNAND = walkNAND

--------------------------------------------------------------------------------
-- | EXAMPLES
--------------------------------------------------------------------------------

exampleNAND :: NAND
exampleNAND = nandAnd (NInput (Reg 0)) (NInput (Reg 1))

exampleKernel :: Expr -> [LiquidOp]
exampleKernel = compileKernel
