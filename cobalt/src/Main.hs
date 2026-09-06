module Main where

import qualified Data.ByteString as BS
import X86BatchAssembler
import MagicCobalt

-- ============================================================
-- X86BatchAssembler demo
-- ============================================================

batchUnits :: [AssemblyUnit]
batchUnits =
  [ AssemblyUnit "hello.asm"
      "mov rax, 42\n\
      \add rax, 8\n\
      \ret\n"

  , AssemblyUnit "jump.asm"
      "jmp done\n\
      \nop\n\
      \nop\n\
      \done:\n\
      \ret\n"
  ]

printObject :: ObjectCode -> IO ()
printObject obj = do
    putStrLn (objectName obj)
    putStrLn $ "  " ++ show (BS.length (objectCode obj)) ++ " bytes"

-- ============================================================
-- MagicCobalt demo
-- ============================================================

exampleProgram :: String
exampleProgram =
  "walk(X) :- step(X, Y), walk(Y).\n\
  \step(a, b).\n\
  \step(b, c).\n"

main :: IO ()
main = do
    putStrLn "=== X86BatchAssembler ==="
    let result = assembleBatch batchUnits
    mapM_ print (batchDiagnostics result)
    mapM_ printObject (batchObjects result)

    putStrLn ""
    putStrLn "=== MagicCobalt ==="
    case magicCobalt defaultConfig exampleProgram of
      Left err ->
        putStrLn $ "Error: " ++ show err

      Right build -> do
        putStrLn $ "Library nodes:  " ++
          show (librarySize (buildLibrary build))
        putStrLn $ "Matrix:         " ++
          show (matrixRows (buildMatrix build)) ++ "x" ++
          show (matrixCols (buildMatrix build))
        putStrLn $ "Triads:         " ++
          show (length (buildTriads build))
        putStrLn $ "ISA ops:        " ++
          show (length (buildISA build))
        putStrLn $ "Binary bytes:   " ++
          show (BS.length (buildBinary build))

librarySize :: Library -> Int
librarySize = length . libraryOrder
