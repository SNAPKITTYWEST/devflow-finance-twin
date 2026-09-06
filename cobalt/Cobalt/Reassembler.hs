module CobaltReassembler where

import qualified Data.Map.Strict as M
import Data.Word
import Data.Int

-- ============================================================
-- Logic layer
-- ============================================================

data Term
    = Atom String
    | Var String
    | Integer Integer
    | Compound String [Term]
    deriving (Eq, Show)

data Predicate = Predicate
    { predName :: String
    , predArgs :: [Term]
    }
    deriving (Eq, Show)

data Rule = Rule
    { ruleHead :: Predicate
    , ruleBody :: [Predicate]
    }
    deriving (Eq, Show)

-- ============================================================
-- Recursive functor layer
-- ============================================================

data Functor
    = FAtom String
    | FApply String [Functor]
    | FCompose [Functor]
    | FRecursive String [Functor]
    | FReference String
    deriving (Eq, Show)

data RecursiveFunctor = RecursiveFunctor
    { rfName :: String
    , rfArgs :: [String]
    , rfBody :: Functor
    }
    deriving (Eq, Show)

-- ============================================================
-- Cobalt vault
-- ============================================================

data VaultSettings = VaultSettings
    { vaultInvert :: Bool
    , vaultWidth  :: Int
    }
    deriving (Eq, Show)

data VaultNode
    = VaultFunctor  Functor
    | VaultRecursive RecursiveFunctor
    | VaultSequence [VaultNode]
    deriving (Eq, Show)

-- ============================================================
-- Binary ISA
-- ============================================================

data ISA
    = ISANop
    | ISARet

    | ISAMovImm
        { isaRegister  :: Word8
        , isaImmediate :: Word64
        }

    | ISAAddImm
        { isaRegister  :: Word8
        , isaImmediate :: Int32
        }

    | ISAXor
        { isaDst :: Word8
        , isaSrc :: Word8
        }

    | ISAJump
        { isaOffset :: Int32
        }

    | ISALogic
        { isaOpcode :: Word8
        }
    deriving (Eq, Show)

data BinaryProgram = BinaryProgram
    { binaryInstructions :: [ISA]
    }
    deriving (Eq, Show)

-- ============================================================
-- Batch logic
-- ============================================================

data CobaltUnit = CobaltUnit
    { cobaltName  :: String
    , cobaltRules :: [Rule]
    }
    deriving (Eq, Show)

data CobaltBatch = CobaltBatch
    { batchUnits :: [CobaltUnit]
    }
    deriving (Eq, Show)

-- ============================================================
-- Parse logic into recursive functors
-- ============================================================

predicateToFunctor :: Predicate -> Functor
predicateToFunctor (Predicate name args) =
    FApply name (map termToFunctor args)

termToFunctor :: Term -> Functor
termToFunctor (Atom x)          = FAtom x
termToFunctor (Var x)           = FReference x
termToFunctor (Integer n)       = FAtom (show n)
termToFunctor (Compound name args) =
    FApply name (map termToFunctor args)

ruleToRecursiveFunctor :: Rule -> RecursiveFunctor
ruleToRecursiveFunctor (Rule head body) =
    RecursiveFunctor
        { rfName = predName head
        , rfArgs = map showArg (predArgs head)
        , rfBody = FCompose (map predicateToFunctor body)
        }

showArg :: Term -> String
showArg (Var x) = x
showArg x       = show x

-- ============================================================
-- Detect recursion
-- ============================================================

containsReference :: String -> Functor -> Bool
containsReference name functor =
    case functor of
        FAtom _       -> False
        FReference x  -> x == name
        FApply _ xs   -> any (containsReference name) xs
        FCompose xs   -> any (containsReference name) xs
        FRecursive x xs ->
            x == name || any (containsReference name) xs

findRecursive :: RecursiveFunctor -> RecursiveFunctor
findRecursive rf
    | containsReference (rfName rf) (rfBody rf) = rf
    | otherwise = rf

-- ============================================================
-- Vault inversion
-- ============================================================

invertFunctor :: VaultSettings -> Functor -> Functor
invertFunctor settings f
    | not (vaultInvert settings) = f

invertFunctor settings (FAtom x) =
    FAtom (reverse x)

invertFunctor settings (FReference x) =
    FReference (reverse x)

invertFunctor settings (FApply name args) =
    FApply
        (reverse name)
        (map (invertFunctor settings) (reverse args))

invertFunctor settings (FCompose xs) =
    FCompose
        (map (invertFunctor settings) (reverse xs))

invertFunctor settings (FRecursive name xs) =
    FRecursive
        (reverse name)
        (map (invertFunctor settings) xs)

-- ============================================================
-- Lower functors into ISA
-- ============================================================

lowerFunctor :: Functor -> [ISA]
lowerFunctor functor =
    case functor of
        FAtom _       -> [ISANop]
        FReference _  -> [ISANop]
        FApply _ args -> concatMap lowerFunctor args
        FCompose xs   -> concatMap lowerFunctor xs
        FRecursive _ body -> lowerFunctor body

-- ============================================================
-- Vault -> ISA
-- ============================================================

vaultToISA :: VaultSettings -> RecursiveFunctor -> BinaryProgram
vaultToISA settings rf =
    let inverted     = invertFunctor settings (rfBody rf)
        instructions = lowerFunctor inverted
    in BinaryProgram instructions

-- ============================================================
-- Batch compilation
-- ============================================================

compileUnit
    :: VaultSettings
    -> CobaltUnit
    -> [(String, BinaryProgram)]
compileUnit settings unit =
    map compileRule (cobaltRules unit)
  where
    compileRule rule =
        let recursive = findRecursive (ruleToRecursiveFunctor rule)
            program   = vaultToISA settings recursive
        in (rfName recursive, program)

compileBatch
    :: VaultSettings
    -> CobaltBatch
    -> [(String, [(String, BinaryProgram)])]
compileBatch settings batch =
    map compileOne (batchUnits batch)
  where
    compileOne unit =
        (cobaltName unit, compileUnit settings unit)
