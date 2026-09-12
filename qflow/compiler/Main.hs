-- Qflow compiler driver (Phase 1: lexer + parser only)
module Main where

import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import Qflow.Lexer
import Qflow.Parser
import Qflow.AST

main :: IO ()
main = do
  args <- getArgs
  case args of
    [path] -> do
      src <- readFile path
      putStrLn "=== Tokens ==="
      mapM_ (putStrLn . showToken) (lexer src)
      putStrLn "\n=== Parse ==="
      case parse src of
        Left err -> do
          putStrLn $ "Parse error: " ++ peMsg err
          putStrLn $ " at " ++ show (peLoc err)
          exitFailure
        Right prog -> do
          putStrLn "OK - AST constructed successfully"
          putStrLn (show prog)
          exitSuccess
    _ -> do
      putStrLn "Usage: qflow <file.qflow>"
      exitFailure
