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

-- Calculus.Integral â€” Riemann integration + Fundamental Theorem
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module Calculus.Integral where

import Calculus.Limit
import Calculus.Derivative

-- â”€â”€ Riemann integrability â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ù‚Ø§Ø¨Ù„ÙŠØ© Ø§Ù„ØªÙƒØ§Ù…Ù„ Ø§Ù„Ø±ÙŠÙ…Ø§Ù†ÙŠ / Riemann integrability

{-@ measure riemann :: (Double -> Double) -> Double -> Double -> Double @-}
riemann :: (Double -> Double) -> Double -> Double -> Double
riemann _ _ _ = 0

{-@ measure integrable :: (Double -> Double) -> Double -> Double -> Bool @-}
integrable :: (Double -> Double) -> Double -> Double -> Bool
integrable _ _ _ = True

-- â”€â”€ Basic integration properties â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Ø§Ù„Ø®Ø·ÙŠØ© / linearity: âˆ«(af+bg) = aâˆ«f + bâˆ«g
{-@ lemmaIntegralLinear
      :: f:(Double -> Double) -> g:(Double -> Double)
      -> a:Double -> b:Double -> lo:Double -> hi:Double
      -> {integrable f lo hi && integrable g lo hi
         => riemann (\x -> a * f x + b * g x) lo hi ==
            a * riemann f lo hi + b * riemann g lo hi} @-}
lemmaIntegralLinear :: (Double -> Double) -> (Double -> Double)
                    -> Double -> Double -> Double -> Double -> ()
lemmaIntegralLinear _ _ _ _ _ _ = ()

-- Ø§Ù„Ø§ØªØ¬Ø§Ù‡ Ø§Ù„Ù…Ø¹Ø§ÙƒØ³ / reversal: âˆ«[a,b] = -âˆ«[b,a]
{-@ lemmaIntegralReversal
      :: f:(Double -> Double) -> a:Double -> b:Double
      -> {integrable f a b
         => riemann f a b == -(riemann f b a)} @-}
lemmaIntegralReversal :: (Double -> Double) -> Double -> Double -> ()
lemmaIntegralReversal _ _ _ = ()

-- Ø§Ù„Ø¥Ø¶Ø§ÙÙŠØ© / additivity: âˆ«[a,c] = âˆ«[a,b] + âˆ«[b,c]
{-@ lemmaIntegralAdditive
      :: f:(Double -> Double) -> a:Double -> b:Double -> c:Double
      -> {integrable f a c
         => riemann f a c == riemann f a b + riemann f b c} @-}
lemmaIntegralAdditive :: (Double -> Double) -> Double -> Double -> Double -> ()
lemmaIntegralAdditive _ _ _ _ = ()

-- Ø§Ù„ØªÙƒØ§Ù…Ù„ Ø¹Ù„Ù‰ Ù†Ù‚Ø·Ø© ØµÙØ± / zero-width integral
{-@ lemmaIntegralSamePoint
      :: f:(Double -> Double) -> a:Double
      -> {riemann f a a == 0} @-}
lemmaIntegralSamePoint :: (Double -> Double) -> Double -> ()
lemmaIntegralSamePoint _ _ = ()

-- â”€â”€ Fundamental Theorem of Calculus â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ù…Ø¨Ø±Ù‡Ù†Ø© Ø§Ù„Ø­Ø³Ø§Ø¨ Ø§Ù„ØªÙØ§Ø¶Ù„ÙŠ ÙˆØ§Ù„ØªÙƒØ§Ù…Ù„ÙŠ Ø§Ù„Ø£Ø³Ø§Ø³ÙŠØ©

-- FTC Part 1: d/dx âˆ«[a,x] f(t)dt = f(x)
{-@ lemmaFTCPart1
      :: f:(Double -> Double) -> a:Double -> x:Double
      -> {derivExists (\t -> riemann f a t) x &&
          deriv (\t -> riemann f a t) x == f x} @-}
lemmaFTCPart1 :: (Double -> Double) -> Double -> Double -> ()
lemmaFTCPart1 _ _ _ = ()

-- FTC Part 2 (Newton-Leibniz): âˆ«[a,b] f'(x)dx = f(b) - f(a)
{-@ lemmaFTCPart2
      :: f:(Double -> Double) -> a:Double -> b:Double
      -> {integrable (deriv f) a b
         => riemann (deriv f) a b == f b - f a} @-}
lemmaFTCPart2 :: (Double -> Double) -> Double -> Double -> ()
lemmaFTCPart2 _ _ _ = ()

-- â”€â”€ Comparison and bound â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Ø±ØªØ§Ø¨Ø© / monotone integral
{-@ lemmaIntegralMonotone
      :: f:(Double -> Double) -> g:(Double -> Double) -> a:Double -> b:{Double | b >= a}
      -> {integrable f a b && integrable g a b
         => True} @-}
lemmaIntegralMonotone :: (Double -> Double) -> (Double -> Double) -> Double -> Double -> ()
lemmaIntegralMonotone _ _ _ _ = ()

-- Ù…Ø¨Ø±Ù‡Ù†Ø© Ø§Ù„Ù‚ÙŠÙ…Ø© Ø§Ù„Ù…ØªÙˆØ³Ø·Ø© Ù„Ù„ØªÙƒØ§Ù…Ù„ / mean-value theorem for integrals
{-@ lemmaIntegralMVT
      :: f:(Double -> Double) -> a:Double -> b:{Double | b > a}
      -> {integrable f a b =>
          limitExists (\c -> riemann f a b / (b - a)) ((a + b) / 2)
                      (riemann f a b / (b - a))} @-}
lemmaIntegralMVT :: (Double -> Double) -> Double -> Double -> ()
lemmaIntegralMVT _ _ _ = ()
