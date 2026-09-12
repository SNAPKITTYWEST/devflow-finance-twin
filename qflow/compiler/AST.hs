-- Qflow.AST
-- Abstract Syntax Tree for the Qflow quantum dataflow DSL.
-- Deterministic, pure data types. No evaluation semantics here.

module Qflow.AST where

import Qflow.Lexer (AlexPosn(..))

--------------------------------------------------------------------------------
-- Source location
--------------------------------------------------------------------------------

type Loc = AlexPosn

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

data Type
  = TyInt
  | TyUInt
  | TyFloat
  | TyBool
  | TyBit
  | TyUnit
  | TyQubit
  | TyQubitN Int
  | TyCircuit
  | TyGate
  | TyArray Type
  | TyTuple [Type]
  | TyFun [Type] Type
  | TyNamed String
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- Top-level
--------------------------------------------------------------------------------

data Program = Program [TopLevel]
  deriving (Eq, Show)

data TopLevel
  = TLCircuit CircuitDef
  | TLProcess ProcessDef
  | TLStmt Stmt
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- Circuit & Process definitions
--------------------------------------------------------------------------------

data CircuitDef = CircuitDef
  { cdName :: String
  , cdParams :: [Param]
  , cdBody :: [Stmt]
  , cdLoc :: Loc
  } deriving (Eq, Show)

data ProcessDef = ProcessDef
  { pdName :: String
  , pdParams :: [Param]
  , pdBody :: [Stmt]
  , pdLoc :: Loc
  } deriving (Eq, Show)

data Param = Param
  { pName :: String
  , pType :: Type
  , pLoc :: Loc
  } deriving (Eq, Show)

--------------------------------------------------------------------------------
-- Statements (single-assignment)
--------------------------------------------------------------------------------

data Stmt
  = SDecl String Type Expr Loc
  | SAssign String Expr Loc
  | SGate String [Expr] Loc
  | SControl Expr [Stmt] Loc
  | SReturn Expr Loc
  | SIf Expr [Stmt] [Stmt] Loc
  | SRelease Expr Loc
  | SExpr Expr Loc
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- Expressions
--------------------------------------------------------------------------------

data Expr
  = EIdent String Loc
  | EInt Integer Loc
  | EFloat Double Loc
  | EBool Bool Loc
  | EBit Bool Loc
  | EUnit Loc
  | EIndex Expr Expr Loc
  | ECall String [Expr] Loc
  | ECircuit [Stmt] Loc
  | ESeq Expr Expr Loc
  | EPar Expr Expr Loc
  | EAdjoint Expr Loc
  | EControl Expr Expr Loc
  | ERepeat Expr Expr Loc
  | ETuple [Expr] Loc
  | EArray [Expr] Loc
  | ELambda [Param] Expr Loc
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- Helpers for pretty-printing (used by tests & dump)
--------------------------------------------------------------------------------

prettyType :: Type -> String
prettyType TyInt = "Int"
prettyType TyUInt = "UInt"
prettyType TyFloat = "Float"
prettyType TyBool = "Bool"
prettyType TyBit = "Bit"
prettyType TyUnit = "Unit"
prettyType TyQubit = "Qubit"
prettyType (TyQubitN n) = "Qubit[" ++ show n ++ "]"
prettyType TyCircuit = "Circuit"
prettyType TyGate = "Gate"
prettyType (TyArray t) = "Array[" ++ prettyType t ++ "]"
prettyType (TyTuple ts) = "Tuple[" ++ join ", " (map prettyType ts) ++ "]"
prettyType (TyFun as r) = "Function(" ++ join ", " (map prettyType as) ++ ") -> " ++ prettyType r
prettyType (TyNamed s) = s

join :: String -> [String] -> String
join _ [] = ""
join _ [x] = x
join sep (x:xs) = x ++ sep ++ join sep xs

prettyExpr :: Expr -> String
prettyExpr (EIdent s _) = s
prettyExpr (EInt n _) = show n
prettyExpr (EFloat f _) = show f
prettyExpr (EBool b _) = if b then "true" else "false"
prettyExpr (EBit b _) = if b then "1" else "0"
prettyExpr (EUnit _) = "()"
prettyExpr (EIndex e i _) = prettyExpr e ++ "[" ++ prettyExpr i ++ "]"
prettyExpr (ECall f args _) = f ++ "(" ++ join ", " (map prettyExpr args) ++ ")"
prettyExpr (ESeq a b _) = prettyExpr a ++ " ; " ++ prettyExpr b
prettyExpr (EPar a b _) = prettyExpr a ++ " || " ++ prettyExpr b
prettyExpr (EAdjoint e _) = "adjoint(" ++ prettyExpr e ++ ")"
prettyExpr (EControl c u _) = "control(" ++ prettyExpr c ++ ", " ++ prettyExpr u ++ ")"
prettyExpr (ERepeat u n _) = "repeat(" ++ prettyExpr u ++ ", " ++ prettyExpr n ++ ")"
prettyExpr (ETuple es _) = "(" ++ join ", " (map prettyExpr es) ++ ")"
prettyExpr (EArray es _) = "[" ++ join ", " (map prettyExpr es) ++ "]"
prettyExpr (ECircuit _ _) = "{...}"
prettyExpr (ELambda _ _ _) = "\\..."
