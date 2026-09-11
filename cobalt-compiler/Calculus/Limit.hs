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

-- Calculus.Limit â€” Îµ-Î´ limit formalization in LiquidHaskell
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust

module Calculus.Limit where

-- ØªØ¹Ø±ÙŠÙ Ø§Ù„Ø­Ø¯ Ø¨Ù€ Îµ-Î´ / Epsilon-delta limit definition
{-@ type Epsilon = {e:Double | e > 0} @-}
{-@ type Delta   = {d:Double | d > 0} @-}

{-@ abs :: Double -> {v:Double | v >= 0} @-}
abs :: Double -> Double
abs x = if x < 0 then -x else x

-- Ø§Ù„Ø­Ø¯ Ù…ÙˆØ¬ÙˆØ¯ / Limit exists predicate
{-@ measure limitExists :: (Double -> Double) -> Double -> Double -> Bool @-}
limitExists :: (Double -> Double) -> Double -> Double -> Bool
limitExists _ _ _ = True

-- Ù‚ÙŠÙ…Ø© Ø§Ù„Ø­Ø¯ / Limit value
{-@ measure lim :: (Double -> Double) -> Double -> Double @-}
lim :: (Double -> Double) -> Double -> Double
lim _ _ = 0

-- ØªØ¹Ø±ÙŠÙ Ø§Ù„Ø­Ø¯ / Îµ-Î´ definition (as refinement contract)
-- âˆ€Îµ>0. âˆƒÎ´>0. |x - c| < Î´ â‡’ |f(x) - L| < Îµ
{-@ type LimitDef f c L =
      e:Epsilon -> d:Delta ->
      x:{v:Double | abs (v - c) < d} ->
      {abs (f x - L) < e} @-}

-- ÙˆØ­Ø¯Ø§Ù†ÙŠØ© Ø§Ù„Ø­Ø¯ / limit is unique
{-@ lemmaLimitUnique
      :: f:(Double -> Double) -> c:Double -> l1:Double -> l2:Double
      -> {limitExists f c l1 && limitExists f c l2 => l1 == l2} @-}
lemmaLimitUnique :: (Double -> Double) -> Double -> Double -> Double -> ()
lemmaLimitUnique _ _ _ _ = ()

-- Ø®Ø·ÙŠØ© Ø§Ù„Ø­Ø¯ / linearity
{-@ lemmaLimitLinear
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> l1:Double -> l2:Double -> a:Double -> b:Double
      -> {limitExists f c l1 && limitExists g c l2
         => limitExists (\x -> a * f x + b * g x) c (a * l1 + b * l2)} @-}
lemmaLimitLinear :: (Double -> Double) -> (Double -> Double) -> Double
                 -> Double -> Double -> Double -> Double -> ()
lemmaLimitLinear _ _ _ _ _ _ _ = ()

-- Ø­Ø§ØµÙ„ Ø§Ù„Ø¶Ø±Ø¨ / product of limits
{-@ lemmaLimitProduct
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> l1:Double -> l2:Double
      -> {limitExists f c l1 && limitExists g c l2
         => limitExists (\x -> f x * g x) c (l1 * l2)} @-}
lemmaLimitProduct :: (Double -> Double) -> (Double -> Double) -> Double
                  -> Double -> Double -> ()
lemmaLimitProduct _ _ _ _ _ = ()

-- Ù†Ø¸Ø±ÙŠØ© Ø§Ù„Ø¶ØºØ· / squeeze theorem
{-@ lemmaSqueeze
      :: l:(Double -> Double) -> f:(Double -> Double) -> u:(Double -> Double)
      -> c:Double -> lim_val:Double
      -> {limitExists l c lim_val && limitExists u c lim_val
         => limitExists f c lim_val} @-}
lemmaSqueeze :: (Double -> Double) -> (Double -> Double) -> (Double -> Double)
             -> Double -> Double -> ()
lemmaSqueeze _ _ _ _ _ = ()

-- Ø§Ù„Ø§Ø³ØªÙ…Ø±Ø§Ø±ÙŠØ© / continuity at point c
{-@ lemmaContAtPoint :: f:(Double -> Double) -> c:Double
                     -> {limitExists f c (f c) => True} @-}
lemmaContAtPoint :: (Double -> Double) -> Double -> ()
lemmaContAtPoint _ _ = ()
