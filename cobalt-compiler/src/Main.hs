module Main where

import           MagicCobalt
import           Cobalt.Dense   (encodeISA, lowerFunctor, parsePrologRules,
                                  rulesToLibrary, expandUntilCrystal, crystalize)
import qualified Data.ByteString as BS

-- ---------------------------------------------------------------------------
-- Demo driver — shows every stage of the pipeline
-- ---------------------------------------------------------------------------

prologSrc :: String
prologSrc = unlines
  [ "walk(X) :- step(X,Y), walk(Y)."
  , "step(a,b)."
  , "step(b,c)."
  , "base(c)."
  ]

main :: IO ()
main = do
  putStrLn "=== localCobalt demo ==="
  putStrLn ""

  -- Stage 1: parse
  let rules = parsePrologRules prologSrc
  putStrLn $ "Parsed rules: " ++ show (length rules)
  mapM_ (putStrLn . ("  " ++) . show) rules
  putStrLn ""

  -- Stage 2: library
  let lib0 = rulesToLibrary rules
  putStrLn $ "Library size: " ++ show (length lib0)
  putStrLn ""

  -- Stage 3: crystal expansion
  let crystal = expandUntilCrystal lib0
  putStrLn $ "Crystal library size: " ++ show (length crystal)
  let flat = crystalize crystal
  putStrLn $ "Crystal functors: " ++ show (length flat)
  putStrLn ""

  -- Stage 4: full compile (default config)
  case compile defaultConfig prologSrc of
    Left err -> putStrLn $ "Compile error: " ++ err
    Right cr -> do
      putStrLn $ "Assembled bytes: " ++ show (BS.length (crBytes cr))
      putStrLn ""
      putStrLn "Trilock hashes:"
      mapM_ (\(lbl, h) -> putStrLn $ "  " ++ lbl ++ " => " ++ h)
            (crTrilocks cr)
      putStrLn ""

  -- Stage 5: vault-inverted compile
  let vaultCfg = defaultConfig { invertVault = True }
  case compile vaultCfg prologSrc of
    Left err -> putStrLn $ "Vault compile error: " ++ err
    Right cr -> do
      putStrLn $ "Vault-inverted bytes: " ++ show (BS.length (crBytes cr))
      putStrLn "Vault trilock hashes:"
      mapM_ (\(lbl, h) -> putStrLn $ "  " ++ lbl ++ " => " ++ h)
            (crTrilocks cr)

  putStrLn ""
  putStrLn "Done."
