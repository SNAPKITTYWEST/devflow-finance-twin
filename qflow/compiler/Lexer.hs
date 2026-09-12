-- Qflow.Lexer
-- Deterministic hand-written lexer for the Qflow quantum dataflow DSL.
-- No external lexer generator. Pure and total.

module Qflow.Lexer
  ( Token(..)
  , AlexPosn(..)
  , lexer
  , showToken
  ) where

import Data.Char (isAlpha, isAlphaNum, isDigit, isSpace)

--------------------------------------------------------------------------------
-- Position tracking
--------------------------------------------------------------------------------

data AlexPosn = AlexPn !Int !Int !Int   -- absolute, line, column
  deriving (Eq, Show)

startPos :: AlexPosn
startPos = AlexPn 0 1 1

movePos :: AlexPosn -> Char -> AlexPosn
movePos (AlexPn a l c) '\n' = AlexPn (a+1) (l+1) 1
movePos (AlexPn a l c) _    = AlexPn (a+1) l (c+1)

--------------------------------------------------------------------------------
-- Tokens
--------------------------------------------------------------------------------

data Token
  = TIdent   String AlexPosn
  | TInt     Integer AlexPosn
  | TFloat   Double AlexPosn
  | TKeyword String AlexPosn
  | TType    String AlexPosn
  | TGate    String AlexPosn
  | TOp      String AlexPosn
  | TLParen  AlexPosn
  | TRParen  AlexPosn
  | TLBracket AlexPosn
  | TRBracket AlexPosn
  | TLBrace  AlexPosn
  | TRBrace  AlexPosn
  | TColon   AlexPosn
  | TEq      AlexPosn
  | TArrow   AlexPosn
  | TSemi    AlexPosn
  | TPar     AlexPosn
  | TComma   AlexPosn
  | TDot     AlexPosn
  | TTrue    AlexPosn
  | TFalse   AlexPosn
  | TEOF     AlexPosn
  deriving (Eq, Show)

showToken :: Token -> String
showToken (TIdent s _)   = "ident(" ++ s ++ ")"
showToken (TInt n _)     = "int(" ++ show n ++ ")"
showToken (TFloat f _)   = "float(" ++ show f ++ ")"
showToken (TKeyword s _) = "kw(" ++ s ++ ")"
showToken (TType s _)    = "type(" ++ s ++ ")"
showToken (TGate s _)    = "gate(" ++ s ++ ")"
showToken (TOp s _)      = "op(" ++ s ++ ")"
showToken (TLParen _)    = "("
showToken (TRParen _)    = ")"
showToken (TLBracket _)  = "["
showToken (TRBracket _)  = "]"
showToken (TLBrace _)    = "{"
showToken (TRBrace _)    = "}"
showToken (TColon _)     = ":"
showToken (TEq _)        = "="
showToken (TArrow _)     = "->"
showToken (TSemi _)      = ";"
showToken (TPar _)       = "||"
showToken (TComma _)     = ","
showToken (TDot _)       = "."
showToken (TTrue _)      = "true"
showToken (TFalse _)     = "false"
showToken (TEOF _)       = "<EOF>"

--------------------------------------------------------------------------------
-- Keyword / type / gate tables
--------------------------------------------------------------------------------

keywords :: [String]
keywords =
  [ "circuit", "process", "channel", "if", "else", "return"
  , "allocate", "ancilla", "release", "measure", "measure_all"
  , "control", "adjoint", "repeat", "map", "parallel", "identity"
  , "run", "print", "width", "depth", "gate_count", "qubit_count"
  , "t_count", "measurement_count", "dump_ir", "serialize"
  ]

types :: [String]
types =
  [ "Int", "UInt", "Float", "Bool", "Bit", "Unit"
  , "Qubit", "Circuit", "Gate", "Array", "Tuple", "Function"
  ]

gates :: [String]
gates =
  [ "I", "X", "Y", "Z", "H", "S", "T"
  , "RX", "RY", "RZ", "CNOT", "CZ", "SWAP"
  ]

--------------------------------------------------------------------------------
-- Main lexer
--------------------------------------------------------------------------------

lexer :: String -> [Token]
lexer input = go startPos input
  where
    go pos [] = [TEOF pos]
    go pos (c:cs)
      | isSpace c = go (movePos pos c) cs

      | c == '/' && startsWith "//" (c:cs) =
          let rest = dropWhile (/= '\n') cs
          in  go (movePos pos c) rest

      | c == '/' && startsWith "/*" (c:cs) =
          skipBlock pos (drop 2 (c:cs))

      | isAlpha c || c == '_' =
          let (name, rest) = span (\x -> isAlphaNum x || x == '_') (c:cs)
              pos' = advance pos name
          in  classify pos name : go pos' rest

      | isDigit c =
          let (num, rest) = span (\x -> isDigit x || x == '.') (c:cs)
              pos' = advance pos num
          in  if '.' `elem` num
                then TFloat (read num) pos : go pos' rest
                else TInt   (read num) pos : go pos' rest

      | startsWith "->" (c:cs) = TArrow pos : go (advance pos "->") (drop 2 (c:cs))
      | startsWith "||" (c:cs) = TPar   pos : go (advance pos "||") (drop 2 (c:cs))

      | c == '(' = TLParen   pos : go (movePos pos c) cs
      | c == ')' = TRParen   pos : go (movePos pos c) cs
      | c == '[' = TLBracket pos : go (movePos pos c) cs
      | c == ']' = TRBracket pos : go (movePos pos c) cs
      | c == '{' = TLBrace   pos : go (movePos pos c) cs
      | c == '}' = TRBrace   pos : go (movePos pos c) cs
      | c == ':' = TColon    pos : go (movePos pos c) cs
      | c == '=' = TEq       pos : go (movePos pos c) cs
      | c == ';' = TSemi     pos : go (movePos pos c) cs
      | c == ',' = TComma    pos : go (movePos pos c) cs
      | c == '.' = TDot      pos : go (movePos pos c) cs

      | otherwise = TOp [c] pos : go (movePos pos c) cs

    classify pos name
      | name `elem` keywords = TKeyword name pos
      | name `elem` types    = TType    name pos
      | name `elem` gates    = TGate    name pos
      | name == "true"       = TTrue    pos
      | name == "false"      = TFalse   pos
      | otherwise            = TIdent   name pos

    startsWith pref s = take (length pref) s == pref

    advance :: AlexPosn -> String -> AlexPosn
    advance p s = foldl movePos p s

    skipBlock :: AlexPosn -> String -> [Token]
    skipBlock pos [] = [TEOF pos]
    skipBlock pos ('*':'/':cs) = go (advance pos "*/") cs
    skipBlock pos (c:cs) = skipBlock (movePos pos c) cs
