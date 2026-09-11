{-# LANGUAGE OverloadedStrings #-}
module Main where

import KrausExtractor
import qualified Numeric.LinearAlgebra as LA
import Data.Complex (Complex((:+)), realPart)
import System.Exit (exitFailure)
import System.Directory (doesFileExist)
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson (eitherDecode)
import Control.Monad (when)
import System.FilePath ((</>))
import Data.List (foldl')

outdir :: FilePath
outdir = "kraus_out"

thetaSym :: String
thetaSym = "theta"

tol :: Double
tol = 1e-8

type ObjectRows = [[(Double, Double)]]

readKrausJSON :: FilePath -> IO (LA.Matrix (Complex Double))
readKrausJSON path = do
  exists <- doesFileExist path
  if not exists
    then error $ "Kraus JSON file not found: " ++ path
    else do
      bs <- BL.readFile path
      case eitherDecode bs :: Either String ObjectRows of
        Left  err -> error $ "Failed to parse " ++ path ++ ": " ++ err
        Right obj -> return $ LA.fromLists (map (map (\(re,im) -> re :+ im)) obj)

numericCompleteness :: [LA.Matrix (Complex Double)] -> Double
numericCompleteness ks =
  let sumMat = foldl1 (+) (map (\k -> LA.tr k LA.<> k) ks)
  in LA.norm_Inf (sumMat - LA.ident (LA.rows sumMat))

numericMinEigen :: LA.Matrix (Complex Double) -> Double
numericMinEigen k =
  let m   = LA.tr k LA.<> k
      evs = LA.eigenvaluesSH m
  in minimum (map realPart (LA.toList evs))

main :: IO ()
main = do
  putStrLn "=== Kraus extractor main/test harness ==="
  putStrLn "Step 1: Running extraction (1 system qubit, 1 ancilla qubit)..."
  runExtraction 1 1 simulateBasis outdir thetaSym

  let k0path = outdir </> "K_0.json"
      k1path = outdir </> "K_1.json"
  k0exists <- doesFileExist k0path
  k1exists <- doesFileExist k1path
  when (not k0exists || not k1exists) $ do
    putStrLn "ERROR: Expected Kraus JSON files not found."
    exitFailure

  putStrLn "Loading Kraus matrices..."
  k0 <- readKrausJSON k0path
  k1 <- readKrausJSON k1path

  let compDiff = numericCompleteness [k0, k1]
      minEv0   = numericMinEigen k0
      minEv1   = numericMinEigen k1

  putStrLn $ "Completeness norm = " ++ show compDiff
  putStrLn $ "Min eigenvalue K0 = " ++ show minEv0
  putStrLn $ "Min eigenvalue K1 = " ++ show minEv1

  if compDiff < tol && minEv0 >= (-tol) && minEv1 >= (-tol)
    then putStrLn "All tests passed."
    else do
      putStrLn "One or more tests failed."
      exitFailure
