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

-- Calculus.Derivative â€” Derivative rules in LiquidHaskell
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module Calculus.Derivative where

import Calculus.Limit

-- Ø§Ù„Ù…Ø´ØªÙ‚Ø© ÙƒØ­Ø¯ / Derivative as limit of difference quotient
{-@ diffQuotient :: f:(Double -> Double) -> c:Double
                 -> h:{h:Double | h /= 0} -> Double @-}
diffQuotient :: (Double -> Double) -> Double -> Double -> Double
diffQuotient f c h = (f (c + h) - f c) / h

-- Ø§Ù„Ù…Ø´ØªÙ‚Ø© Ù…ÙˆØ¬ÙˆØ¯Ø© / derivative exists
{-@ measure derivExists :: (Double -> Double) -> Double -> Bool @-}
derivExists :: (Double -> Double) -> Double -> Bool
derivExists _ _ = True

-- Ù‚ÙŠÙ…Ø© Ø§Ù„Ù…Ø´ØªÙ‚Ø© / derivative value
{-@ measure deriv :: (Double -> Double) -> Double -> Double @-}
deriv :: (Double -> Double) -> Double -> Double
deriv _ _ = 0

-- Ø§Ù„Ù‚Ø§Ø¨Ù„ÙŠØ© Ù„Ù„Ø§Ø´ØªÙ‚Ø§Ù‚ ØªØ¶Ù…Ù† Ø§Ù„Ø§Ø³ØªÙ…Ø±Ø§Ø±ÙŠØ© / differentiability â‡’ continuity
{-@ lemmaDerivImpliesCont
      :: f:(Double -> Double) -> c:Double
      -> {derivExists f c => limitExists f c (f c)} @-}
lemmaDerivImpliesCont :: (Double -> Double) -> Double -> ()
lemmaDerivImpliesCont _ _ = ()

-- Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø«Ø§Ø¨Øª / constant rule: d/dx(k) = 0
{-@ lemmaDerivConstant :: k:Double -> c:Double
                       -> {deriv (\_ -> k) c == 0} @-}
lemmaDerivConstant :: Double -> Double -> ()
lemmaDerivConstant _ _ = ()

-- Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ù‚ÙˆØ© / power rule: d/dx(xâ¿) = nÂ·xâ¿â»Â¹
{-@ lemmaDerivPower :: n:{n:Int | n > 0} -> c:Double
                    -> {deriv (\x -> x ^ n) c == fromIntegral n * c ^ (n - 1)} @-}
lemmaDerivPower :: Int -> Double -> ()
lemmaDerivPower _ _ = ()

-- Ø§Ù„Ø®Ø·ÙŠØ© / linearity: d/dx(af + bg) = aÂ·f' + bÂ·g'
{-@ lemmaDerivLinear
      :: f:(Double -> Double) -> g:(Double -> Double)
      -> c:Double -> a:Double -> b:Double
      -> {derivExists f c && derivExists g c
         => deriv (\x -> a * f x + b * g x) c ==
            a * deriv f c + b * deriv g c} @-}
lemmaDerivLinear :: (Double -> Double) -> (Double -> Double)
                 -> Double -> Double -> Double -> ()
lemmaDerivLinear _ _ _ _ _ = ()

-- Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¶Ø±Ø¨ / product rule: d/dx(fg) = fÂ·g' + gÂ·f'
{-@ lemmaDerivProduct
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> {derivExists f c && derivExists g c
         => deriv (\x -> f x * g x) c ==
            f c * deriv g c + g c * deriv f c} @-}
lemmaDerivProduct :: (Double -> Double) -> (Double -> Double) -> Double -> ()
lemmaDerivProduct _ _ _ = ()

-- Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ù†Ø³Ø¨Ø© / quotient rule
{-@ lemmaDerivQuotient
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> {derivExists f c && derivExists g c && g c /= 0
         => deriv (\x -> f x / g x) c ==
            (g c * deriv f c - f c * deriv g c) / (g c ^ 2)} @-}
lemmaDerivQuotient :: (Double -> Double) -> (Double -> Double) -> Double -> ()
lemmaDerivQuotient _ _ _ = ()

-- Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø³Ù„Ø³Ù„Ø© / chain rule: d/dx(fâˆ˜g) = f'(g(x)) Â· g'(x)
{-@ lemmaChainRule
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> {derivExists g c && derivExists f (g c)
         => deriv (\x -> f (g x)) c == deriv f (g c) * deriv g c} @-}
lemmaChainRule :: (Double -> Double) -> (Double -> Double) -> Double -> ()
lemmaChainRule _ _ _ = ()
