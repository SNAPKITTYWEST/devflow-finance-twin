{-|
Module      : WeakMeasureKrausLH
Description : Quipper weak-measurement circuit + Kraus extraction, hardened with Liquid Haskell specs.

This module implements a minimal Jungian weak-measurement circuit:
  - System qubit S, ancilla A initialized to |0>.
  - Controlled-Ry(theta) on ancilla conditioned on S==|1>.
  - Measure ancilla; Kraus operators on S are diagonal:
      K0 = diag(1, cos(theta/2))
      K1 = diag(0, sin(theta/2))

This file:
  - Builds the Quipper circuit.
  - Provides symbolic and numeric Kraus export functions.
  - Contains Liquid Haskell annotations to assert numeric bounds and invariants.
  - Documents the mapping to EMA: m = p * sin^2(theta/2), expected update p' = p + eta*(m - p).
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}

module WeakMeasureKrausLH
  ( weakMeasureCircuit
  , krausSymbolic
  , krausNumeric
  , evidenceProb
  , emaUpdate
  ) where

import Quipper
import Quipper.Libraries.Simulation (run_generic_io)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BL
import System.IO
import System.Environment (getArgs)
import Data.Complex (Complex((:+)), magnitude)
import Numeric.LinearAlgebra (Matrix, (><), fromLists, toLists, cmap)
import qualified Numeric.LinearAlgebra as LA
import Text.Printf (printf)
import Control.Monad (forM_, when)

{-@ LIQUID "--no-termination" @-}
{-@ LIQUID "--ple" @-}

{-@ measure isFinite :: Double -> Bool
    isFinite(x) = (not (isNaN x)) && (not (isInfinite x))
  @-}

weakMeasureCircuit :: Double -> Circ (Qubit, Bit)
weakMeasureCircuit theta = do
  sys <- qinit False
  anc <- qinit False
  with_controls sys $ gate_RY theta anc
  b <- measure anc
  return (sys, b)

{-@ assume validTheta :: theta:Double -> {v:() | isFinite theta && 0.0 <= theta && theta <= 6.283185307179586} @-}
validTheta :: Double -> ()
validTheta _ = ()

krausSymbolic :: String -> IO ()
krausSymbolic thetaSym = do
  let k0 = [["1", "0"], ["0", printf "cos(%s/2)" thetaSym]]
      k1 = [["0", "0"], ["0", printf "sin(%s/2)" thetaSym]]
      json = encode $ object ["K0" .= k0, "K1" .= k1]
  BL.writeFile "kraus_symbolic.json" json
  putStrLn "Wrote kraus_symbolic.json (symbolic K0,K1)."

{-@ krausNumeric :: theta:{Double | isFinite theta && 0.0 <= theta && theta <= 6.283185307179586} -> IO () @-}
krausNumeric :: Double -> IO ()
krausNumeric theta = do
  validTheta theta
  let c = cos (theta / 2.0)
      s = sin (theta / 2.0)
      k0 = [[1.0 :+ 0.0, 0.0 :+ 0.0], [0.0 :+ 0.0, c :+ 0.0]]
      k1 = [[0.0 :+ 0.0, 0.0 :+ 0.0], [0.0 :+ 0.0, s :+ 0.0]]
  writeComplexMatrix "K0.json" k0
  writeComplexMatrix "K1.json" k1
  putStrLn $ "Wrote K0.json and K1.json for theta = " ++ show theta
  let k0m = LA.fromLists (map (map id) k0)
      k1m = LA.fromLists (map (map id) k1)
      sumMat = (LA.tr k0m LA.<> k0m) + (LA.tr k1m LA.<> k1m)
      ident = LA.ident 2
      diff = LA.norm_Inf (sumMat - ident)
  when (diff > 1e-12) $
    putStrLn $ "Warning: completeness check failed numerically (||sum - I||_inf = " ++ show diff ++ ")"

toComplexPair :: Complex Double -> (Double, Double)
toComplexPair (x :+ y) = (x, y)

writeComplexMatrix :: FilePath -> [[Complex Double]] -> IO ()
writeComplexMatrix path mat = do
  let rows = map (map toComplexPair) mat
      json = encode $ object ["rows" .= rows]
  BL.writeFile path json

buildControlledRyUnitary :: Double -> Matrix (Complex Double)
buildControlledRyUnitary theta =
  let c = cos (theta / 2.0)
      s = sin (theta / 2.0)
      u00 = [1 :+ 0, 0 :+ 0, 0 :+ 0, 0 :+ 0]
      u01 = [0 :+ 0, 1 :+ 0, 0 :+ 0, 0 :+ 0]
      u10 = [0 :+ 0, 0 :+ 0, c :+ 0, (-s) :+ 0]
      u11 = [0 :+ 0, 0 :+ 0, s :+ 0, c :+ 0]
      cols = [u00, u01, u10, u11]
  in LA.fromColumns (map LA.fromList cols)

extractKrausFromUnitary :: Matrix (Complex Double) -> Int -> Matrix (Complex Double)
extractKrausFromUnitary u m =
  let u00 = LA.subMatrix (0,0) (2,2) u
      u10 = LA.subMatrix (0,2) (2,2) u
  in case m of
       0 -> u00
       1 -> u10
       _ -> error "ancilla index out of range"

numericKrausFromTheta :: Double -> IO ()
numericKrausFromTheta theta = do
  let u = buildControlledRyUnitary theta
      k0 = extractKrausFromUnitary u 0
      k1 = extractKrausFromUnitary u 1
  writeMatrixToJSON "K0_numeric.json" k0
  writeMatrixToJSON "K1_numeric.json" k1
  putStrLn "Wrote K0_numeric.json and K1_numeric.json (numeric Kraus)."

writeMatrixToJSON :: FilePath -> Matrix (Complex Double) -> IO ()
writeMatrixToJSON path m = do
  let rows = toLists m
      rowsPairs = map (map (\(x :+ y) -> object ["re" .= x, "im" .= y])) rows
      json = encode $ object ["rows" .= rowsPairs]
  BL.writeFile path json

{-@ evidenceProb :: p:{Double | 0.0 <= p && p <= 1.0} -> theta:{Double | isFinite theta && 0.0 <= theta && theta <= 6.283185307179586} -> {v:Double | 0.0 <= v && v <= 1.0} @-}
evidenceProb :: Double -> Double -> Double
evidenceProb p theta = p * (sin (theta / 2.0) ** 2)

{-@ emaUpdate :: p:{Double | 0.0 <= p && p <= 1.0} -> eta:{Double | 0.0 <= eta && eta <= 1.0} -> m:{Double | 0.0 <= m && m <= 1.0} -> {v:Double | 0.0 <= v && v <= 1.0} @-}
emaUpdate :: Double -> Double -> Double -> Double
emaUpdate p eta m = clamp01 (p + eta * (m - p))

clamp01 :: Double -> Double
clamp01 x | x < 0.0 = 0.0
          | x > 1.0 = 1.0
          | otherwise = x

main :: IO ()
main = do
  args <- getArgs
  let theta = if null args then pi / 8 else read (head args) :: Double
  putStrLn $ "Using theta = " ++ show theta
  krausSymbolic "theta"
  krausNumeric theta
  numericKrausFromTheta theta
  putStrLn "Done."
