-- Language.Fixpoint.Solver.Eliminate — KV scope solver and constraint elimination
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module Language.Fixpoint.Solver.Eliminate where

import Language.Fixpoint.Solver.Simplify (Expr(..), simplify)

-- ── Constraint types ─────────────────────────────────────────────────────────
type KVar = String
type Subst = [(String, Expr)]

data Constraint = Constraint
  { cLhs  :: Expr
  , cRhs  :: Expr
  , cKVs  :: [KVar]
  } deriving (Eq, Show)

data SolverInfo = SolverInfo
  { siConstraints :: [Constraint]
  , siKVScopes    :: [(KVar, [String])]
  , siSimplified  :: [Constraint]
  } deriving (Show)

-- ── KV scope analysis ────────────────────────────────────────────────────────
-- Collect all KVars in an expression
collectKVs :: Expr -> [KVar]
collectKVs (Var s)      = [s]
collectKVs (Add  e1 e2) = collectKVs e1 ++ collectKVs e2
collectKVs (Sub  e1 e2) = collectKVs e1 ++ collectKVs e2
collectKVs (Mul  e1 e2) = collectKVs e1 ++ collectKVs e2
collectKVs (And  e1 e2) = collectKVs e1 ++ collectKVs e2
collectKVs (Or   e1 e2) = collectKVs e1 ++ collectKVs e2
collectKVs (Not  e)     = collectKVs e
collectKVs (Eq   e1 e2) = collectKVs e1 ++ collectKVs e2
collectKVs (Lt   e1 e2) = collectKVs e1 ++ collectKVs e2
collectKVs (Ite  c t f) = collectKVs c ++ collectKVs t ++ collectKVs f
collectKVs _            = []

-- Compute scope (free variables) for each KVar
kvScopes :: [Constraint] -> [(KVar, [String])]
kvScopes cs =
  [ (kv, concatMap collectKVs [cLhs c, cRhs c])
  | c <- cs, kv <- cKVs c ]

-- ── Substitution ─────────────────────────────────────────────────────────────
applySubst :: Subst -> Expr -> Expr
applySubst s (Var v) = case lookup v s of
  Just e  -> e
  Nothing -> Var v
applySubst s (Add  e1 e2) = Add  (applySubst s e1) (applySubst s e2)
applySubst s (Sub  e1 e2) = Sub  (applySubst s e1) (applySubst s e2)
applySubst s (Mul  e1 e2) = Mul  (applySubst s e1) (applySubst s e2)
applySubst s (And  e1 e2) = And  (applySubst s e1) (applySubst s e2)
applySubst s (Or   e1 e2) = Or   (applySubst s e1) (applySubst s e2)
applySubst s (Not  e)     = Not  (applySubst s e)
applySubst s (Eq   e1 e2) = Eq   (applySubst s e1) (applySubst s e2)
applySubst s (Lt   e1 e2) = Lt   (applySubst s e1) (applySubst s e2)
applySubst s (Ite  c t f) = Ite  (applySubst s c) (applySubst s t) (applySubst s f)
applySubst _ e            = e

-- ── Elimination ──────────────────────────────────────────────────────────────
-- Eliminate a KVar from constraints by substituting Lit 0 (conservative)
eliminateKV :: KVar -> [Constraint] -> [Constraint]
eliminateKV kv cs =
  map (\c -> c { cLhs = applySubst [(kv, Lit 0)] (cLhs c)
               , cRhs = applySubst [(kv, Lit 0)] (cRhs c) })
      cs

-- ── Main solver entry point ───────────────────────────────────────────────────
solverInfo :: [Constraint] -> SolverInfo
solverInfo cs = SolverInfo
  { siConstraints = cs
  , siKVScopes    = kvScopes cs
  , siSimplified  = map simplifyConstraint cs
  }

simplifyConstraint :: Constraint -> Constraint
simplifyConstraint c = c { cLhs = simplify (cLhs c), cRhs = simplify (cRhs c) }

-- Eliminate all KVars in a solve pass
eliminate :: [Constraint] -> [Constraint]
eliminate cs =
  let kvs = concatMap cKVs cs
  in  foldr eliminateKV cs kvs
