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

-- Language.Fixpoint.Solver.Simplify â€” Recursive LiquidHaskell expression simplifier
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module Language.Fixpoint.Solver.Simplify where

-- â”€â”€ Fixpoint expression AST â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
data Expr
  = Lit  Int
  | BoolE Bool
  | Var  String
  | Add  Expr Expr
  | Sub  Expr Expr
  | Mul  Expr Expr
  | And  Expr Expr
  | Or   Expr Expr
  | Not  Expr
  | Set  [Int]
  | SetUnion [Int] [Int]
  | SetInter [Int] [Int]
  | Eq   Expr Expr
  | Lt   Expr Expr
  | Ite  Expr Expr Expr
  deriving (Eq, Show)

-- â”€â”€ Size measure â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
{-@ measure exprSize :: Expr -> Nat @-}
exprSize :: Expr -> Int
exprSize (Lit _)            = 1
exprSize (BoolE _)          = 1
exprSize (Var _)            = 1
exprSize (Add  e1 e2)       = 1 + exprSize e1 + exprSize e2
exprSize (Sub  e1 e2)       = 1 + exprSize e1 + exprSize e2
exprSize (Mul  e1 e2)       = 1 + exprSize e1 + exprSize e2
exprSize (And  e1 e2)       = 1 + exprSize e1 + exprSize e2
exprSize (Or   e1 e2)       = 1 + exprSize e1 + exprSize e2
exprSize (Not  e)           = 1 + exprSize e
exprSize (Set  _)           = 1
exprSize (SetUnion xs ys)   = 1 + length xs + length ys
exprSize (SetInter xs ys)   = 1 + length xs + length ys
exprSize (Eq   e1 e2)       = 1 + exprSize e1 + exprSize e2
exprSize (Lt   e1 e2)       = 1 + exprSize e1 + exprSize e2
exprSize (Ite  c t f)       = 1 + exprSize c + exprSize t + exprSize f

-- â”€â”€ Constant folding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
applyConstantFolding :: Expr -> Expr
applyConstantFolding (Add (Lit a) (Lit b)) = Lit (a + b)
applyConstantFolding (Sub (Lit a) (Lit b)) = Lit (a - b)
applyConstantFolding (Mul (Lit a) (Lit b)) = Lit (a * b)
applyConstantFolding (Mul (Lit 0) _)       = Lit 0
applyConstantFolding (Mul _ (Lit 0))       = Lit 0
applyConstantFolding (Add (Lit 0) e)       = e
applyConstantFolding (Add e (Lit 0))       = e
applyConstantFolding (Mul (Lit 1) e)       = e
applyConstantFolding (Mul e (Lit 1))       = e
applyConstantFolding (Eq (Lit a) (Lit b))  = BoolE (a == b)
applyConstantFolding (Lt (Lit a) (Lit b))  = BoolE (a <  b)
applyConstantFolding e                     = e

-- â”€â”€ Boolean folding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
applyBooleanFolding :: Expr -> Expr
applyBooleanFolding (And (BoolE True)  e)            = e
applyBooleanFolding (And (BoolE False) _)            = BoolE False
applyBooleanFolding (And e (BoolE True))             = e
applyBooleanFolding (And _ (BoolE False))            = BoolE False
applyBooleanFolding (Or  (BoolE True)  _)            = BoolE True
applyBooleanFolding (Or  (BoolE False) e)            = e
applyBooleanFolding (Or  _ (BoolE True))             = BoolE True
applyBooleanFolding (Or  e (BoolE False))            = e
applyBooleanFolding (Not (BoolE True))               = BoolE False
applyBooleanFolding (Not (BoolE False))              = BoolE True
applyBooleanFolding (Not (Not e))                    = e
applyBooleanFolding (Ite (BoolE True)  t _)          = t
applyBooleanFolding (Ite (BoolE False) _ f)          = f
applyBooleanFolding e                                = e

-- â”€â”€ Set folding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
applySetFolding :: Expr -> Expr
applySetFolding (SetUnion xs ys) = Set (foldr insert xs ys)
  where insert x acc = if x `elem` acc then acc else x : acc
applySetFolding (SetInter xs ys) = Set [ x | x <- xs, x `elem` ys ]
applySetFolding e                = e

-- â”€â”€ Descend: one-level simplification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
{-@ descend :: e:Expr -> {v:Expr | exprSize v <= exprSize e} @-}
descend :: Expr -> Expr
descend e =
  let e1 = applyConstantFolding e
      e2 = applyBooleanFolding  e1
      e3 = applySetFolding      e2
  in  e3

-- â”€â”€ Full recursive simplification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
{-@ simplifyRecursive :: e:Expr -> Expr / [exprSize e] @-}
simplifyRecursive :: Expr -> Expr
simplifyRecursive (Add e1 e2)     = descend (Add  (simplifyRecursive e1) (simplifyRecursive e2))
simplifyRecursive (Sub e1 e2)     = descend (Sub  (simplifyRecursive e1) (simplifyRecursive e2))
simplifyRecursive (Mul e1 e2)     = descend (Mul  (simplifyRecursive e1) (simplifyRecursive e2))
simplifyRecursive (And e1 e2)     = descend (And  (simplifyRecursive e1) (simplifyRecursive e2))
simplifyRecursive (Or  e1 e2)     = descend (Or   (simplifyRecursive e1) (simplifyRecursive e2))
simplifyRecursive (Not e)         = descend (Not  (simplifyRecursive e))
simplifyRecursive (Eq  e1 e2)     = descend (Eq   (simplifyRecursive e1) (simplifyRecursive e2))
simplifyRecursive (Lt  e1 e2)     = descend (Lt   (simplifyRecursive e1) (simplifyRecursive e2))
simplifyRecursive (Ite c t f)     = descend (Ite  (simplifyRecursive c)
                                                   (simplifyRecursive t)
                                                   (simplifyRecursive f))
simplifyRecursive (SetUnion xs ys) = descend (SetUnion xs ys)
simplifyRecursive (SetInter xs ys) = descend (SetInter xs ys)
simplifyRecursive e               = e

-- â”€â”€ Driver â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
simplify :: Expr -> Expr
simplify = simplifyRecursive
