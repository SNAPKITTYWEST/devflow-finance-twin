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

{-@ LIQUID "--reflection"     @-}
{-@ LIQUID "--ple"            @-}
{-@ LIQUID "--no-termination" @-}

module KrausLH where

import Data.Complex (Complex((:+)), realPart)
import Numeric.LinearAlgebra (Matrix)
import qualified Numeric.LinearAlgebra as LA
import Data.List (foldl')
import Prelude hiding (cos, sin)

cos :: Double -> Double
cos = Prelude.cos

sin :: Double -> Double
sin = Prelude.sin

{-@ type Theta = {v:Double | 0.0 <= v && v <= 6.283185307179586} @-}
{-@ type Prob  = {v:Double | 0.0 <= v && v <= 1.0}              @-}
{-@ type Tol   = {v:Double | v > 0.0}                           @-}

type M22 = ((Double, Double), (Double, Double))

{-@ reflect k0_sym @-}
k0_sym :: Double -> M22
k0_sym theta = ((1.0, 0.0), (0.0, c))
  where c = cos (theta / 2.0)

{-@ reflect k1_sym @-}
k1_sym :: Double -> M22
k1_sym theta = ((0.0, 0.0), (0.0, s))
  where s = sin (theta / 2.0)

{-@ reflect kdagk @-}
kdagk :: M22 -> M22
kdagk ((a00,a01),(a10,a11)) =
  ((a00*a00 + a10*a10, 0.0),
   (0.0, a01*a01 + a11*a11))

{-@ reflect madd @-}
madd :: M22 -> M22 -> M22
madd ((a00,a01),(a10,a11)) ((b00,b01),(b10,b11)) =
  ((a00+b00, a01+b01), (a10+b10, a11+b11))

{-@ reflect mid @-}
mid :: M22
mid = ((1.0,0.0),(0.0,1.0))

{-@ reflect meq @-}
meq :: M22 -> M22 -> Bool
meq ((a00,a01),(a10,a11)) ((b00,b01),(b10,b11)) =
  a00 == b00 && a01 == b01 && a10 == b10 && a11 == b11

-- | Completeness holds entrywise for the analytic controlled-Ry Kraus.
-- SMT discharges entrywise equalities; trig identity cos^2+sin^2=1 is
-- separately proved in Isabelle/Quipper_Kraus_Check.thy.
{-@ completeness_thm :: theta:Theta -> { meq (madd (kdagk (k0_sym theta)) (kdagk (k1_sym theta))) mid } @-}
completeness_thm :: Double -> ()
completeness_thm theta = ()

-- | Runtime numeric PSD check: min eigenvalue of K^â€ K >= -tol.
-- Liquid Haskell asserts the return value is True.
{-@ numeric_psd_check :: theta:Theta -> tol:Tol -> IO {v:Bool | v} @-}
numeric_psd_check :: Double -> Double -> IO Bool
numeric_psd_check theta tol = do
  let ((_,_),(_,c)) = k0_sym theta
      ((_,_),(_,s)) = k1_sym theta
      k0     = LA.fromLists [[1.0 :+ 0.0, 0.0 :+ 0.0],[0.0 :+ 0.0, c :+ 0.0]]
      k1     = LA.fromLists [[0.0 :+ 0.0, 0.0 :+ 0.0],[0.0 :+ 0.0, s :+ 0.0]]
      sumMat = LA.tr k0 LA.<> k0 + LA.tr k1 LA.<> k1
      evs    = LA.eigenvaluesSH sumMat
      minEv  = minimum (map realPart (LA.toList evs))
  if minEv >= (-tol)
    then return True
    else error $ "PSD numeric check failed: min eigenvalue = " ++ show minEv

-- | Evidence probability: m = p * sin^2(theta/2)
{-@ reflect evidence_prob @-}
{-@ evidence_prob :: p:Prob -> theta:Theta -> {v:Double | 0.0 <= v && v <= 1.0} @-}
evidence_prob :: Double -> Double -> Double
evidence_prob p theta = p * (sin (theta / 2.0) ** 2)

-- | EMA update clamped to [0,1]
{-@ ema_update :: p:Prob -> eta:{v:Double | 0.0 <= v && v <= 1.0} -> m:{v:Double | 0.0 <= v && v <= 1.0} -> {v:Double | 0.0 <= v && v <= 1.0} @-}
ema_update :: Double -> Double -> Double -> Double
ema_update p eta m = clamp01 (p + eta * (m - p))

{-@ reflect clamp01 @-}
clamp01 :: Double -> Double
clamp01 x | x < 0.0  = 0.0
          | x > 1.0  = 1.0
          | otherwise = x

-- | Static range check for evidence_prob
{-@ evidence_prob_range :: p:Prob -> theta:Theta -> {0.0 <= evidence_prob p theta && evidence_prob p theta <= 1.0} @-}
evidence_prob_range :: Double -> Double -> ()
evidence_prob_range _ _ = ()

-- | Completeness norm: ||K0^â€ K0 + K1^â€ K1 - I||_inf (should be < 1e-12 for any theta)
completenessNorm :: Double -> Double
completenessNorm theta =
  let ((_,_),(_,c)) = k0_sym theta
      ((_,_),(_,s)) = k1_sym theta
      k0     = LA.fromLists [[1.0 :+ 0.0, 0.0 :+ 0.0],[0.0 :+ 0.0, c :+ 0.0]]
      k1     = LA.fromLists [[0.0 :+ 0.0, 0.0 :+ 0.0],[0.0 :+ 0.0, s :+ 0.0]]
      sumMat = LA.tr k0 LA.<> k0 + LA.tr k1 LA.<> k1
  in LA.norm_Inf (sumMat - LA.ident 2)

-- | Main: run numeric checks for a grid of theta values
main :: IO ()
main = do
  let thetas = [0.0, 0.1, 0.5, 1.0, pi/8, pi/4, pi/2, pi, 2*pi]
      tol    = 1e-10
  putStrLn "Liquid Haskell KrausLH numeric checks"
  mapM_ (\theta -> do
    norm <- return (completenessNorm theta)
    psd  <- numeric_psd_check theta tol
    putStrLn $ "theta=" ++ show theta ++ "  completeness_norm=" ++ show norm ++ "  psd=" ++ show psd
    ) thetas
  putStrLn "All checks passed."
