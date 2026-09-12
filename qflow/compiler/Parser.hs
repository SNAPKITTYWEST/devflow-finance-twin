-- Qflow.Parser
-- Deterministic recursive-descent parser for Qflow.
-- No parser generator. Explicit error messages with source locations.

module Qflow.Parser
  ( parse
  , parseFile
  , ParserError(..)
  ) where

import Qflow.Lexer
import Qflow.AST

import Control.Monad (void)
import Data.List (intercalate)

--------------------------------------------------------------------------------
-- Parser monad
--------------------------------------------------------------------------------

newtype Parser a = Parser { runParser :: [Token] -> Either ParserError (a, [Token]) }

data ParserError = ParserError
  { peMsg :: String
  , peLoc :: AlexPosn
  } deriving (Eq, Show)

instance Functor Parser where
  fmap f (Parser p) = Parser $ \ts -> case p ts of
    Left e -> Left e
    Right (x, ts') -> Right (f x, ts')

instance Applicative Parser where
  pure x = Parser $ \ts -> Right (x, ts)
  Parser pf <*> Parser px = Parser $ \ts -> case pf ts of
    Left e -> Left e
    Right (f, ts') -> case px ts' of
      Left e -> Left e
      Right (x, ts'') -> Right (f x, ts'')

instance Monad Parser where
  return = pure
  Parser p >>= f = Parser $ \ts -> case p ts of
    Left e -> Left e
    Right (x, ts') -> runParser (f x) ts'

--------------------------------------------------------------------------------
-- Primitive combinators
--------------------------------------------------------------------------------

failP :: String -> AlexPosn -> Parser a
failP msg loc = Parser $ \_ -> Left (ParserError msg loc)

peek :: Parser Token
peek = Parser $ \ts -> case ts of
  [] -> Left (ParserError "unexpected end of input" (AlexPn 0 0 0))
  (t:_) -> Right (t, ts)

consume :: Parser Token
consume = Parser $ \ts -> case ts of
  [] -> Left (ParserError "unexpected end of input" (AlexPn 0 0 0))
  (t:ts') -> Right (t, ts')

satisfy :: (Token -> Bool) -> String -> Parser Token
satisfy pred msg = do
  t <- peek
  if pred t
    then consume
    else failP msg (tokenPos t)

token :: Token -> Parser Token
token expected = satisfy (== expected) ("expected " ++ showToken expected)

tokenPos :: Token -> AlexPosn
tokenPos (TIdent _ p) = p
tokenPos (TInt _ p) = p
tokenPos (TFloat _ p) = p
tokenPos (TKeyword _ p) = p
tokenPos (TType _ p) = p
tokenPos (TGate _ p) = p
tokenPos (TOp _ p) = p
tokenPos (TLParen p) = p
tokenPos (TRParen p) = p
tokenPos (TLBracket p) = p
tokenPos (TRBracket p) = p
tokenPos (TLBrace p) = p
tokenPos (TRBrace p) = p
tokenPos (TColon p) = p
tokenPos (TEq p) = p
tokenPos (TArrow p) = p
tokenPos (TSemi p) = p
tokenPos (TPar p) = p
tokenPos (TComma p) = p
tokenPos (TDot p) = p
tokenPos (TTrue p) = p
tokenPos (TFalse p) = p
tokenPos (TEOF p) = p

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

parse :: String -> Either ParserError Program
parse src = case runParser program (lexer src) of
  Left e -> Left e
  Right (p, [TEOF _]) -> Right p
  Right (_, t:_) -> Left (ParserError ("leftover tokens starting with " ++ showToken t) (tokenPos t))
  Right (_, []) -> Left (ParserError "internal error: empty leftover" (AlexPn 0 0 0))

parseFile :: FilePath -> IO (Either ParserError Program)
parseFile path = do
  src <- readFile path
  pure (parse src)

--------------------------------------------------------------------------------
-- Grammar
--------------------------------------------------------------------------------

program :: Parser Program
program = Program <$> many topLevel <* token (TEOF (AlexPn 0 0 0))

topLevel :: Parser TopLevel
topLevel = do
  t <- peek
  case t of
    TKeyword "circuit" _ -> TLCircuit <$> circuitDef
    TKeyword "process" _ -> TLProcess <$> processDef
    _ -> TLStmt <$> statement

circuitDef :: Parser CircuitDef
circuitDef = do
  TKeyword "circuit" loc <- satisfy isCircuit "expected 'circuit'"
  name <- ident
  token (TLParen loc)
  params <- paramList
  token (TRParen loc)
  token (TArrow loc)
  _ <- typeName
  token (TLBrace loc)
  body <- many statement
  token (TRBrace loc)
  pure $ CircuitDef name params body loc
  where
    isCircuit (TKeyword "circuit" _) = True
    isCircuit _ = False

processDef :: Parser ProcessDef
processDef = do
  TKeyword "process" loc <- satisfy isProcess "expected 'process'"
  name <- ident
  token (TLParen loc)
  params <- paramList
  token (TRParen loc)
  token (TLBrace loc)
  body <- many statement
  token (TRBrace loc)
  pure $ ProcessDef name params body loc
  where
    isProcess (TKeyword "process" _) = True
    isProcess _ = False

paramList :: Parser [Param]
paramList = do
  t <- peek
  case t of
    TRParen _ -> pure []
    _ -> do
      p <- param
      rest <- many (token (TComma (AlexPn 0 0 0)) *> param)
      pure (p:rest)

param :: Parser Param
param = do
  name <- ident
  token (TColon (AlexPn 0 0 0))
  ty <- typeName
  loc <- tokenPos <$> peek
  pure $ Param name ty loc

typeName :: Parser Type
typeName = do
  t <- peek
  case t of
    TType "Int" _ -> consume >> pure TyInt
    TType "UInt" _ -> consume >> pure TyUInt
    TType "Float" _ -> consume >> pure TyFloat
    TType "Bool" _ -> consume >> pure TyBool
    TType "Bit" _ -> consume >> pure TyBit
    TType "Unit" _ -> consume >> pure TyUnit
    TType "Qubit" _ -> do
      consume
      t2 <- peek
      case t2 of
        TLBracket _ -> do
          consume
          TInt n _ <- satisfy isInt "expected integer size"
          token (TRBracket (AlexPn 0 0 0))
          pure (TyQubitN (fromIntegral n))
        _ -> pure TyQubit
    TType "Circuit" _ -> consume >> pure TyCircuit
    TType "Gate" _ -> consume >> pure TyGate
    TType "Array" _ -> do
      consume
      token (TLBracket (AlexPn 0 0 0))
      inner <- typeName
      token (TRBracket (AlexPn 0 0 0))
      pure (TyArray inner)
    TIdent s _ -> consume >> pure (TyNamed s)
    _ -> failP "expected type name" (tokenPos t)
  where
    isInt (TInt _ _) = True
    isInt _ = False

statement :: Parser Stmt
statement = do
  t <- peek
  case t of
    TKeyword "return" loc -> do
      consume
      e <- expression
      pure $ SReturn e loc

    TKeyword "control" loc -> do
      consume
      token (TLParen loc)
      ctrl <- expression
      token (TRParen loc)
      token (TLBrace loc)
      body <- many statement
      token (TRBrace loc)
      pure $ SControl ctrl body loc

    TKeyword "if" loc -> do
      consume
      cond <- expression
      token (TLBrace loc)
      thenB <- many statement
      token (TRBrace loc)
      elseB <- do
        t2 <- peek
        case t2 of
          TKeyword "else" _ -> do
            consume
            token (TLBrace loc)
            b <- many statement
            token (TRBrace loc)
            pure b
          _ -> pure []
      pure $ SIf cond thenB elseB loc

    TKeyword "release" loc -> do
      consume
      e <- expression
      pure $ SRelease e loc

    _ -> do
      t1 <- peek
      case t1 of
        TIdent name loc -> do
          consume
          t2 <- peek
          case t2 of
            TColon _ -> do
              consume
              ty <- typeName
              token (TEq loc)
              e <- expression
              pure $ SDecl name ty e loc
            TEq _ -> do
              consume
              e <- expression
              pure $ SAssign name e loc
            TLParen _ -> do
              args <- parenArgs
              pure $ SGate name args loc
            TLBracket _ -> do
              idx <- bracketIndex
              t3 <- peek
              case t3 of
                TEq _ -> do
                  consume
                  e <- expression
                  pure $ SAssign (name ++ "[" ++ show idx ++ "]") e loc
                _ -> pure $ SExpr (EIndex (EIdent name loc) (EInt (fromIntegral idx) loc) loc) loc
            _ -> pure $ SExpr (EIdent name loc) loc

        TGate g loc -> do
          consume
          args <- parenArgs
          pure $ SGate g args loc

        _ -> do
          e <- expression
          pure $ SExpr e (exprLoc e)

parenArgs :: Parser [Expr]
parenArgs = do
  loc <- tokenPos <$> peek
  token (TLParen loc)
  args <- do
    t <- peek
    case t of
      TRParen _ -> pure []
      _ -> do
        e <- expression
        rest <- many (token (TComma loc) *> expression)
        pure (e:rest)
  token (TRParen loc)
  pure args

bracketIndex :: Parser Integer
bracketIndex = do
  loc <- tokenPos <$> peek
  token (TLBracket loc)
  TInt n _ <- satisfy isInt "expected integer index"
  token (TRBracket loc)
  pure n
  where isInt (TInt _ _) = True; isInt _ = False

expression :: Parser Expr
expression = seqExpr

seqExpr :: Parser Expr
seqExpr = do
  left <- parExpr
  rest <- many $ do
    token (TSemi (AlexPn 0 0 0))
    parExpr
  pure $ foldl (\a b -> ESeq a b (exprLoc a)) left rest

parExpr :: Parser Expr
parExpr = do
  left <- primary
  rest <- many $ do
    token (TPar (AlexPn 0 0 0))
    primary
  pure $ foldl (\a b -> EPar a b (exprLoc a)) left rest

primary :: Parser Expr
primary = do
  t <- peek
  case t of
    TIdent name loc -> do
      consume
      t2 <- peek
      case t2 of
        TLParen _ -> do
          args <- parenArgs
          pure $ ECall name args loc
        TLBracket _ -> do
          idx <- bracketExpr
          pure $ EIndex (EIdent name loc) idx loc
        _ -> pure $ EIdent name loc

    TInt n loc -> consume >> pure (EInt n loc)
    TFloat f loc -> consume >> pure (EFloat f loc)
    TTrue loc -> consume >> pure (EBool True loc)
    TFalse loc -> consume >> pure (EBool False loc)

    TGate g loc -> do
      consume
      args <- parenArgs
      pure $ ECall g args loc

    TKeyword "allocate" loc -> do
      consume
      args <- parenArgs
      pure $ ECall "allocate" args loc

    TKeyword "ancilla" loc -> do
      consume
      args <- parenArgs
      pure $ ECall "ancilla" args loc

    TKeyword "measure" loc -> do
      consume
      args <- parenArgs
      pure $ ECall "measure" args loc

    TKeyword "measure_all" loc -> do
      consume
      args <- parenArgs
      pure $ ECall "measure_all" args loc

    TKeyword "adjoint" loc -> do
      consume
      token (TLParen loc)
      e <- expression
      token (TRParen loc)
      pure $ EAdjoint e loc

    TKeyword "control" loc -> do
      consume
      token (TLParen loc)
      c <- expression
      token (TComma loc)
      u <- expression
      token (TRParen loc)
      pure $ EControl c u loc

    TKeyword "repeat" loc -> do
      consume
      token (TLParen loc)
      u <- expression
      token (TComma loc)
      n <- expression
      token (TRParen loc)
      pure $ ERepeat u n loc

    TKeyword "map" loc -> do
      consume
      args <- parenArgs
      pure $ ECall "map" args loc

    TKeyword "parallel" loc -> do
      consume
      args <- parenArgs
      pure $ ECall "parallel" args loc

    TKeyword "identity" loc -> do
      consume
      args <- parenArgs
      pure $ ECall "identity" args loc

    TLParen loc -> do
      consume
      t2 <- peek
      case t2 of
        TRParen _ -> consume >> pure (EUnit loc)
        _ -> do
          e <- expression
          t3 <- peek
          case t3 of
            TComma _ -> do
              rest <- many (token (TComma loc) *> expression)
              token (TRParen loc)
              pure $ ETuple (e:rest) loc
            _ -> do
              token (TRParen loc)
              pure e

    TLBracket loc -> do
      consume
      elems <- do
        t2 <- peek
        case t2 of
          TRBracket _ -> pure []
          _ -> do
            e <- expression
            rest <- many (token (TComma loc) *> expression)
            pure (e:rest)
      token (TRBracket loc)
      pure $ EArray elems loc

    TLBrace loc -> do
      consume
      body <- many statement
      token (TRBrace loc)
      pure $ ECircuit body loc

    _ -> failP ("unexpected token in expression: " ++ showToken t) (tokenPos t)

bracketExpr :: Parser Expr
bracketExpr = do
  loc <- tokenPos <$> peek
  token (TLBracket loc)
  e <- expression
  token (TRBracket loc)
  pure e

ident :: Parser String
ident = do
  t <- satisfy isIdent "expected identifier"
  case t of
    TIdent s _ -> pure s
    _ -> failP "internal error" (tokenPos t)
  where
    isIdent (TIdent _ _) = True
    isIdent _ = False

many :: Parser a -> Parser [a]
many p = do
  t <- peek
  case t of
    TEOF _ -> pure []
    TRBrace _ -> pure []
    TRParen _ -> pure []
    _ -> do
      x <- p
      xs <- many p
      pure (x:xs)

exprLoc :: Expr -> Loc
exprLoc (EIdent _ l) = l
exprLoc (EInt _ l) = l
exprLoc (EFloat _ l) = l
exprLoc (EBool _ l) = l
exprLoc (EBit _ l) = l
exprLoc (EUnit l) = l
exprLoc (EIndex _ _ l) = l
exprLoc (ECall _ _ l) = l
exprLoc (ECircuit _ l) = l
exprLoc (ESeq _ _ l) = l
exprLoc (EPar _ _ l) = l
exprLoc (EAdjoint _ l) = l
exprLoc (EControl _ _ l) = l
exprLoc (ERepeat _ _ l) = l
exprLoc (ETuple _ l) = l
exprLoc (EArray _ l) = l
exprLoc (ELambda _ _ l) = l
