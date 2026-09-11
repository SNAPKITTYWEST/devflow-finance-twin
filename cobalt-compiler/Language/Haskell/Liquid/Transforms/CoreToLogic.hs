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

-- Language.Haskell.Liquid.Transforms.CoreToLogic â€” GHC Core â†’ Fixpoint logic translation
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module Language.Haskell.Liquid.Transforms.CoreToLogic where

import Language.Fixpoint.Solver.Simplify (Expr(..))

-- â”€â”€ GHC Core subset â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
data CoreExpr
  = CVar   String
  | CLit   Int
  | CBool  Bool
  | CApp   CoreExpr CoreExpr
  | CLam   String CoreExpr
  | CLet   String CoreExpr CoreExpr
  | CCase  CoreExpr [(CorePat, CoreExpr)]
  | CAdd   CoreExpr CoreExpr
  | CSub   CoreExpr CoreExpr
  | CMul   CoreExpr CoreExpr
  | CEq    CoreExpr CoreExpr
  | CLt    CoreExpr CoreExpr
  | CAnd   CoreExpr CoreExpr
  | COr    CoreExpr CoreExpr
  | CNot   CoreExpr
  | CIte   CoreExpr CoreExpr CoreExpr
  deriving (Eq, Show)

data CorePat
  = PLit Int
  | PBool Bool
  | PWild
  deriving (Eq, Show)

-- â”€â”€ Translation to Fixpoint Expr â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
{-@ measure coreSizeC :: CoreExpr -> Nat @-}
coreSizeC :: CoreExpr -> Int
coreSizeC (CVar _)       = 1
coreSizeC (CLit _)       = 1
coreSizeC (CBool _)      = 1
coreSizeC (CApp f a)     = 1 + coreSizeC f + coreSizeC a
coreSizeC (CLam _ b)     = 1 + coreSizeC b
coreSizeC (CLet _ e b)   = 1 + coreSizeC e + coreSizeC b
coreSizeC (CCase e alts) = 1 + coreSizeC e + sum (map (coreSizeC . snd) alts)
coreSizeC (CAdd a b)     = 1 + coreSizeC a + coreSizeC b
coreSizeC (CSub a b)     = 1 + coreSizeC a + coreSizeC b
coreSizeC (CMul a b)     = 1 + coreSizeC a + coreSizeC b
coreSizeC (CEq  a b)     = 1 + coreSizeC a + coreSizeC b
coreSizeC (CLt  a b)     = 1 + coreSizeC a + coreSizeC b
coreSizeC (CAnd a b)     = 1 + coreSizeC a + coreSizeC b
coreSizeC (COr  a b)     = 1 + coreSizeC a + coreSizeC b
coreSizeC (CNot e)       = 1 + coreSizeC e
coreSizeC (CIte c t f)   = 1 + coreSizeC c + coreSizeC t + coreSizeC f

-- Main translation: GHC Core â†’ Fixpoint Expr (structural recursion on coreSizeC)
{-@ coreToLg :: e:CoreExpr -> Expr / [coreSizeC e] @-}
coreToLg :: CoreExpr -> Expr
coreToLg (CVar v)     = Var v
coreToLg (CLit n)     = Lit n
coreToLg (CBool b)    = BoolE b
coreToLg (CAdd a b)   = Add (coreToLg a) (coreToLg b)
coreToLg (CSub a b)   = Sub (coreToLg a) (coreToLg b)
coreToLg (CMul a b)   = Mul (coreToLg a) (coreToLg b)
coreToLg (CEq  a b)   = Eq  (coreToLg a) (coreToLg b)
coreToLg (CLt  a b)   = Lt  (coreToLg a) (coreToLg b)
coreToLg (CAnd a b)   = And (coreToLg a) (coreToLg b)
coreToLg (COr  a b)   = Or  (coreToLg a) (coreToLg b)
coreToLg (CNot e)     = Not (coreToLg e)
coreToLg (CIte c t f) = Ite (coreToLg c) (coreToLg t) (coreToLg f)
coreToLg (CLam _ b)   = coreToLg b
coreToLg (CLet v e b) = Ite (Eq (Var v) (coreToLg e)) (coreToLg b) (Var v)
coreToLg (CApp f _)   = coreToLg f
coreToLg (CCase e alts) = foldr (caseAlt e) (BoolE False) alts

-- Convert one case alternative
caseAlt :: CoreExpr -> (CorePat, CoreExpr) -> Expr -> Expr
caseAlt scrut (PLit n,  body) rest = Ite (Eq (coreToLg scrut) (Lit n))  (coreToLg body) rest
caseAlt scrut (PBool b, body) rest = Ite (Eq (coreToLg scrut) (BoolE b))(coreToLg body) rest
caseAlt _     (PWild,   body) _    = coreToLg body

-- â”€â”€ Predicate application helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Apply a predicate expression to an argument (function application)
{-@ toPredApp :: CoreExpr -> [CoreExpr] -> Expr @-}
toPredApp :: CoreExpr -> [CoreExpr] -> Expr
toPredApp f []     = coreToLg f
toPredApp f (x:xs) =
  let f' = case coreToLg f of
              Var name -> Var (name ++ "_app")
              e        -> e
  in  Ite (Eq (coreToLg x) (Lit 0)) f' (toPredApp (CApp f x) xs)
