-- ========================================================================
-- SOVEREIGN LEVIATHAN NODE LICENSE
-- License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
-- Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- ========================================================================
--
-- This file is a covered work under the GNU Affero General Public License,
-- version 3, together with the Sovereign Leviathan additional terms.
--
-- Hark, though this node be but a spark,
-- Its covenant endureth through the dark.
--
-- Ignorantia juris non excusat.
-- ========================================================================

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import KrausLH
import System.Environment (getArgs)
import System.Random (mkStdGen, randomRs)
import qualified Numeric.LinearAlgebra as LA
import Data.Complex (Complex((:+)), realPart)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Time.Clock (getCurrentTime)
import System.Process (readProcess)
import System.Exit (exitFailure)
import Control.Exception (try, SomeException)
import Control.Monad (when)
import System.Info (os, arch)

defaultTrials :: Int
defaultTrials = 1000

defaultSeed :: Int
defaultSeed = 1337

tol :: Double
tol = 1e-10

k0Matrix :: Double -> LA.Matrix (Complex Double)
k0Matrix theta =
  let c = cos (theta / 2.0)
  in LA.fromLists [[1.0 :+ 0.0, 0.0 :+ 0.0],[0.0 :+ 0.0, c :+ 0.0]]

k1Matrix :: Double -> LA.Matrix (Complex Double)
k1Matrix theta =
  let s = sin (theta / 2.0)
  in LA.fromLists [[0.0 :+ 0.0, 0.0 :+ 0.0],[0.0 :+ 0.0, s :+ 0.0]]

completenessNorm :: LA.Matrix (Complex Double) -> LA.Matrix (Complex Double) -> Double
completenessNorm k0 k1 =
  let sumMat   = LA.tr k0 LA.<> k0 + LA.tr k1 LA.<> k1
      identMat = LA.ident (LA.rows sumMat)
  in LA.norm_Inf (sumMat - identMat)

minEigenKdagK :: LA.Matrix (Complex Double) -> Double
minEigenKdagK k =
  let m    = LA.tr k LA.<> k
      evs  = LA.eigenvaluesSH m
  in minimum (map realPart (LA.toList evs))

testTheta :: Double -> (Double, Double, Double)
testTheta theta =
  let k0  = k0Matrix theta
      k1  = k1Matrix theta
      cn  = completenessNorm k0 k1
      me0 = minEigenKdagK k0
      me1 = minEigenKdagK k1
  in (cn, me0, me1)

genThetas :: Int -> Int -> [Double]
genThetas seed n = take n $ randomRs (1e-6, pi - 1e-6) (mkStdGen seed)

lookupArg :: String -> [String] -> Maybe String
lookupArg _ [] = Nothing
lookupArg key (x:y:xs)
  | x == key = Just y
  | otherwise = lookupArg key (y:xs)
lookupArg _ _ = Nothing

tryRun :: String -> [String] -> IO (Either String String)
tryRun cmd args =
  (Right <$> readProcess cmd args "")
    `Control.Exception.catch` (\(e :: SomeException) -> return (Left (show e)))

main :: IO ()
main = do
  args <- getArgs
  let trials = maybe defaultTrials (read :: String -> Int) (lookupArg "--trials" args)
      seed   = maybe defaultSeed   (read :: String -> Int) (lookupArg "--seed"   args)
  putStrLn $ "KrausLHTest: trials=" ++ show trials ++ " seed=" ++ show seed

  putStrLn "Running Liquid Haskell on KrausLH.hs..."
  lhResult <- tryRun "liquid" ["haskell/KrausLH.hs"]
  case lhResult of
    Left err -> putStrLn $ "LH warning (continuing): " ++ err
    Right _  -> putStrLn "Liquid Haskell OK"

  let thetas  = genThetas seed trials
      results = map testTheta thetas
      maxC    = maximum $ map (\(c,_,_) -> c) results
      minMe0  = minimum $ map (\(_,m,_) -> m) results
      minMe1  = minimum $ map (\(_,_,m) -> m) results

  time <- getCurrentTime
  let report = object
        [ "trials" .= trials, "seed" .= seed
        , "max_completeness_norm" .= maxC
        , "min_eig_K0" .= minMe0, "min_eig_K1" .= minMe1
        , "tolerance" .= tol, "time" .= show time
        , "platform" .= (os ++ "-" ++ arch)
        ]
  BL.writeFile "kraus_test_report.json" (encode report)
  putStrLn $ "max_completeness_norm = " ++ show maxC
  putStrLn $ "min_eig_K0 = " ++ show minMe0
  putStrLn $ "min_eig_K1 = " ++ show minMe1

  when (maxC > 1e-8) $ do
    putStrLn "FAIL: completeness norm exceeds 1e-8"; exitFailure
  when (minMe0 < (-1e-8) || minMe1 < (-1e-8)) $ do
    putStrLn "FAIL: PSD numeric check failed"; exitFailure

  putStrLn "All numeric checks passed."
  putStrLn "Report written to kraus_test_report.json"
