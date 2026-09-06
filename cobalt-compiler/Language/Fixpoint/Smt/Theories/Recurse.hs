-- Language.Fixpoint.Smt.Theories.Recurse — SMT2 recursive function bridge
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module Language.Fixpoint.Smt.Theories.Recurse where

-- ── SMT2 token types ─────────────────────────────────────────────────────────
data SMT2Token
  = Smt2Sym  String
  | Smt2Num  Int
  | Smt2Bool Bool
  | Smt2App  [SMT2Token]
  deriving (Eq, Show)

-- ── Recursive function descriptor ────────────────────────────────────────────
data RecurseFunc = RecurseFunc
  { rfName     :: String
  , rfArgs     :: [String]
  , rfBody     :: SMT2Token
  , rfMaxDepth :: Int
  } deriving (Eq, Show)

-- ── Truncation + recursion ────────────────────────────────────────────────────
-- Unroll a recursive function to depth d, substituting base case at leaf
{-@ truncateAndRecurseFunc :: RecurseFunc -> {v:Int | v >= 0} -> [SMT2Token] @-}
truncateAndRecurseFunc :: RecurseFunc -> Int -> [SMT2Token]
truncateAndRecurseFunc rf depth
  | depth <= 0 = [Smt2Bool False]
  | otherwise  =
      let inner = truncateAndRecurseFunc rf (depth - 1)
          subst = substRecurse (rfName rf) inner (rfBody rf)
      in  [subst]

-- Substitute all recursive calls in a token tree
substRecurse :: String -> [SMT2Token] -> SMT2Token -> SMT2Token
substRecurse name replacement (Smt2App (Smt2Sym f : args))
  | f == name = case replacement of
      [r] -> r
      rs  -> Smt2App rs
  | otherwise = Smt2App (Smt2Sym f : map (substRecurse name replacement) args)
substRecurse name replacement (Smt2App ts) =
  Smt2App (map (substRecurse name replacement) ts)
substRecurse _ _ t = t

-- ── SMT2 serialization ────────────────────────────────────────────────────────
renderSMT2 :: SMT2Token -> String
renderSMT2 (Smt2Sym s)    = s
renderSMT2 (Smt2Num n)    = show n
renderSMT2 (Smt2Bool b)   = if b then "true" else "false"
renderSMT2 (Smt2App ts)   = "(" ++ unwords (map renderSMT2 ts) ++ ")"

-- ── Bridge: Haskell recursive function → SMT2 define-fun-rec ─────────────────
smt2FuncRecurseBridge :: RecurseFunc -> String
smt2FuncRecurseBridge rf =
  let args    = unwords [ "(" ++ a ++ " Int)" | a <- rfArgs rf ]
      bodyStr = renderSMT2 (rfBody rf)
  in  "(define-fun-rec " ++ rfName rf ++ " (" ++ args ++ ") Int\n  " ++ bodyStr ++ ")"

-- ── Example: factorial recursive descriptor ──────────────────────────────────
factFunc :: RecurseFunc
factFunc = RecurseFunc
  { rfName     = "fact"
  , rfArgs     = ["n"]
  , rfBody     = Smt2App [ Smt2Sym "ite"
                          , Smt2App [Smt2Sym "<=", Smt2Sym "n", Smt2Num 0]
                          , Smt2Num 1
                          , Smt2App [ Smt2Sym "*"
                                    , Smt2Sym "n"
                                    , Smt2App [Smt2Sym "fact", Smt2App [Smt2Sym "-", Smt2Sym "n", Smt2Num 1]]
                                    ]
                          ]
  , rfMaxDepth = 10
  }
