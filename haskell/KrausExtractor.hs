{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE RecordWildCards #-}

-- KrausExtractor.hs
-- Build unitary from Quipper circuit by simulating basis states,
-- extract Kraus operators K_m = <m|_A U |0>_A, export JSON and Isabelle .thy.

module KrausExtractor
  ( buildUnitaryFromCircuit
  , extractKrausOperators
  , writeKrausJSON
  , writeKrausIsabelle
  , runExtraction
  , simulateBasis
  , circuitForBasis
  , writeGateListForBasis
  , indexToBits
  ) where

import Quipper
import Quipper.Libraries.Simulation (run_generic_io)
import Numeric.LinearAlgebra (Matrix, (><), fromList, toLists, cmap, ident, trans, conj)
import qualified Numeric.LinearAlgebra as LA
import Data.Complex (Complex((:+)), magnitude, realPart)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BL
import System.FilePath ((</>))
import System.Directory (createDirectoryIfMissing)
import System.Process (readProcess)
import System.IO (openFile, IOMode(..), hClose, hPutStrLn, writeFile)
import Control.Exception (bracket, try, SomeException)
import Control.Monad (forM, forM_, when)
import Data.List (foldl', intercalate)
import Text.Printf (printf)
import Data.Bits ((.&.), shiftR)
import System.Random (randomRIO)

{-@ LIQUID "--no-termination" @-}
{-@ LIQUID "--ple" @-}

type C = Complex Double

matrixFromLists :: [[C]] -> Matrix C
matrixFromLists rows =
  let r    = length rows
      c    = if r == 0 then 0 else length (head rows)
      flat = concat rows
  in (r LA.>< c) flat

matrixToLists :: Matrix C -> [[C]]
matrixToLists = toLists

-- | Build the full unitary U by simulating each basis input.
buildUnitaryFromCircuit :: Int -> (Int -> IO [C]) -> IO (Matrix C)
buildUnitaryFromCircuit n_total simulateBasisFn = do
  let dim = 2 ^ n_total
  cols <- forM [0 .. dim - 1] $ \i -> do
    amps <- simulateBasisFn i
    when (length amps /= dim) $
      error $ "simulateBasis: wrong vector length for index " ++ show i
    return amps
  return $ LA.fromColumns (map LA.fromList cols)

-- | Extract K_m = <m|_A U |0>_A for all ancilla outcomes.
extractKrausOperators :: Int -> Int -> Matrix C -> [Matrix C]
extractKrausOperators d_s d_a u =
  let idxRow s' m = s' * d_a + m
      idxCol s  a = s  * d_a + a
      buildK m   = LA.fromLists
        [ [ u LA.@> (idxRow s' m, idxCol s 0) | s <- [0..d_s-1] ] | s' <- [0..d_s-1] ]
  in [ buildK m | m <- [0..d_a-1] ]

-- | Completeness check: ||sum K^†K - I||_inf < tol
checkCompleteness :: [Matrix C] -> Double -> Bool
checkCompleteness ks tol =
  let z       = LA.konst 0 (LA.rows (head ks), LA.cols (head ks))
      sumMat  = foldl' (\acc k -> acc + (LA.tr k LA.<> k)) z ks
      diff    = LA.norm_Inf (sumMat - LA.ident (LA.rows sumMat))
  in diff < tol

checkPSD :: Matrix C -> Double -> Bool
checkPSD k tol =
  let m   = LA.tr k LA.<> k
      evs = LA.eigenvaluesSH m
  in minimum (map realPart (LA.toList evs)) >= (-tol)

-- | Write numeric Kraus JSON files.
writeKrausJSON :: FilePath -> [Matrix C] -> IO ()
writeKrausJSON outdir ks = do
  createDirectoryIfMissing True outdir
  forM_ (zip [0..] ks) $ \(m, k) -> do
    let rows      = matrixToLists k
        rowsPairs = map (map (\(x :+ y) -> object ["re" .= x, "im" .= y])) rows
        json      = encode $ object ["rows" .= rowsPairs]
        fname     = outdir </> ("K_" ++ show m ++ ".json")
    BL.writeFile fname json
    putStrLn $ "Wrote " ++ fname

-- | Write Isabelle .thy fragment with K definitions.
writeKrausIsabelle :: FilePath -> String -> [Matrix C] -> IO ()
writeKrausIsabelle outdir thetaSym ks = do
  createDirectoryIfMissing True outdir
  let thyPath = outdir </> "kraus_defs.thy"
  withFile thyPath WriteMode $ \h -> do
    hPutStrLn h "(* Auto-generated Kraus definitions *)"
    hPutStrLn h "theory kraus_defs"
    hPutStrLn h "imports Complex_Main \"HOL-Algebra.Matrix\""
    hPutStrLn h "begin\n"
    forM_ (zip [0..] ks) $ \(m, k) -> do
      let rows = matrixToLists k
          n    = length rows
          nc   = if null rows then 0 else length (head rows)
      hPutStrLn h $ "definition K" ++ show m ++ " :: \"complex matrix\" where"
      hPutStrLn h $ "  \"K" ++ show m ++ " = mat " ++ show n ++ " " ++ show nc ++ " (\\<lambda>(i,j)."
      forM_ (zip [0..] rows) $ \(i, row) ->
        forM_ (zip [0..] row) $ \(j, (x :+ y)) -> do
          let entry = if abs y < 1e-12
                        then printf "of_real %.15g" x
                        else printf "(of_real %.15g + %g * ii)" x y
          hPutStrLn h $ "    (if i = " ++ show i ++ " ∧ j = " ++ show (j::Int) ++ " then " ++ entry ++ " else"
      hPutStrLn h "    0))\""
      hPutStrLn h ""
    hPutStrLn h "end"
  putStrLn $ "Wrote Isabelle fragment to " ++ thyPath

withFile :: FilePath -> IOMode -> (System.IO.Handle -> IO a) -> IO a
withFile path mode = bracket (openFile path mode) hClose

-- | Top-level extraction runner.
runExtraction :: Int -> Int -> (Int -> IO [C]) -> FilePath -> String -> IO ()
runExtraction n_sys n_anc simulateBasisFn outdir thetaSym = do
  let n_total = n_sys + n_anc
  putStrLn $ "Building unitary for n_total = " ++ show n_total
  u  <- buildUnitaryFromCircuit n_total simulateBasisFn
  let ks = extractKrausOperators (2^n_sys) (2^n_anc) u
  putStrLn $ "Extracted " ++ show (length ks) ++ " Kraus operators."
  let completenessOk = checkCompleteness ks 1e-8
  putStrLn $ "Completeness: " ++ show completenessOk
  forM_ (zip [0..] ks) $ \(m, k) ->
    putStrLn $ "K_" ++ show m ++ " PSD: " ++ show (checkPSD k 1e-8)
  writeKrausJSON outdir ks
  writeKrausIsabelle outdir thetaSym ks
  putStrLn "Extraction complete."

-- | Convert basis index to bit list (MSB first).
indexToBits :: Int -> Int -> [Int]
indexToBits totalQubits idx =
  map (\i -> (idx `shiftR` i) .&. 1) [totalQubits-1, totalQubits-2 .. 0]

-- | Build weak-measurement circuit for a given basis input.
circuitForBasis :: [Int] -> Double -> Circ ()
circuitForBasis basisBits theta = do
  let sbit = head basisBits == 1
      abit = basisBits !! 1 == 1
  sys <- qinit sbit
  anc <- qinit abit
  with_controls sys $ gate_RY theta anc
  return ()

-- | Write gate list for the Python fallback simulator.
writeGateListForBasis :: FilePath -> [Int] -> Double -> IO ()
writeGateListForBasis path basisBits theta = do
  let header   = ["# gate list for weak-measurement circuit", "# qubit indices: 0=system,1=ancilla"]
      initLines = [ "INIT 0 " ++ show (head basisBits)
                  , "INIT 1 " ++ show (basisBits !! 1)
                  ]
      gateLine  = "C_RY 0 1 " ++ show theta
      content   = unlines $ header ++ initLines ++ [gateLine]
  System.IO.writeFile path content

-- | Simulate a basis input: try Quipper first, fallback to Python.
simulateBasis :: Int -> IO [C]
simulateBasis basisIndex = do
  let n_sys    = 1; n_anc = 1; n_total = n_sys + n_anc
      basisBits = indexToBits n_total basisIndex
      theta     = pi / 8
  tryQ <- try (do
      let circ = circuitForBasis basisBits theta
      amps <- run_generic_io circ
      return (amps :: [C])
    ) :: IO (Either SomeException [C])
  case tryQ of
    Right amps -> return amps
    Left _ -> do
      let gatefile = "gate_list_" ++ show basisIndex ++ ".txt"
      writeGateListForBasis gatefile basisBits theta
      out <- readProcess "python3" ["simulate_gate_list.py", gatefile] ""
      case eitherDecode (BL.pack out) of
        Right ampsPairs -> return $ map (\(re, im) -> re :+ im) (ampsPairs :: [(Double,Double)])
        Left err -> error $ "simulateBasis: python failed: " ++ err
  where
    eitherDecode bs = case Data.Aeson.eitherDecode bs of
      Right x -> Right x
      Left e  -> Left e
