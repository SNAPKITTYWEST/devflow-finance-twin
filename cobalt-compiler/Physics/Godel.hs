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

-- Physics.Godel â€” GÃ¶del universe with parameterized cyclic time indices
-- Ù†Ù…ÙˆØ°Ø¬ Ø¹Ø§Ù„Ù… Ø¬ÙˆØ¯Ù„ Ù…Ø¹ Ù…Ø¤Ø´Ø±Ø§Øª Ø²Ù…Ù†ÙŠØ© Ø¯Ø§Ø¦Ø±ÙŠØ© Ù…Ø¹Ù„Ù…ÙŠØ©
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust
-- {-@ LIQUID "--reflection" @-}
-- {-@ LIQUID "--ple" @-}

module Physics.Godel where

import Core.Nat

-- â”€â”€ GTime record â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ø§Ù„Ø²Ù…Ù† ÙƒØ³Ø¬Ù„ Ø¨ÙØªØ±Ø© ØµØ±ÙŠØ­Ø© / time as record with explicit period

{-@ type Period = {v:Nat | v > 0} @-}

{-@ data GTime = GTime
      { timeIndex  :: Nat
      , timePeriod :: Period
      } @-}
data GTime = GTime
  { timeIndex  :: Int
  , timePeriod :: Int
  } deriving (Eq, Show)

-- ØªØ·Ø¨ÙŠØ¹ Ù…Ø¤Ø´Ø± Ø§Ù„Ø²Ù…Ù† / normalize time index into [0, period)
{-@ normalizeTime :: p:Period -> x:Nat -> GTime @-}
normalizeTime :: Int -> Int -> GTime
normalizeTime p x = GTime (x `mod` p) p

-- Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ø§Ù„Ù…Ø¤Ø´Ø± / index projection
{-@ unTime :: t:GTime -> {v:Nat | v < timePeriod t} @-}
unTime :: GTime -> Int
unTime = timeIndex

-- â”€â”€ Step and iteration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ø®Ø·ÙˆØ© Ø²Ù…Ù†ÙŠØ© Ø¯ÙˆØ±ÙŠØ© / cyclic step (preserves period)
{-@ step :: t:GTime -> {v:GTime | timePeriod v == timePeriod t} @-}
step :: GTime -> GTime
step (GTime x p) = GTime ((x + 1) `mod` p) p

-- ØªÙƒØ±Ø§Ø± Ø¨Ø¹Ø¯Ø¯ Ù…Ø­Ø¯ÙˆØ¯ / iterated step (structural recursion on n)
{-@ stepN :: n:Nat -> t:GTime -> GTime / [n] @-}
stepN :: Int -> GTime -> GTime
stepN 0 t = t
stepN n t = stepN (n - 1) (step t)

-- â”€â”€ Closed curves â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ø­Ø§ÙØ¸ Ø§Ù„Ø¯ÙˆØ±Ø© / same-period predicate
{-@ samePeriod :: a:GTime -> b:GTime -> {v:Bool | v <=> timePeriod a == timePeriod b} @-}
samePeriod :: GTime -> GTime -> Bool
samePeriod a b = timePeriod a == timePeriod b

-- Ù…Ù†Ø­Ù†Ù‰ Ø²Ù…Ù†ÙŠ Ù…ØºÙ„Ù‚ / closed timelike curve
{-@ isClosedCurve :: t:GTime
                  -> {v:Bool | v <=> timeIndex (stepN (timePeriod t) t) == timeIndex t} @-}
isClosedCurve :: GTime -> Bool
isClosedCurve t = timeIndex (stepN (timePeriod t) t) == timeIndex t

-- Ø§Ù„Ø¹ÙˆØ¯Ø© Ø¨Ø¹Ø¯ Ø§Ù„Ø¯ÙˆØ±Ø© / period returns to origin
{-@ cycleInvariant :: t:GTime -> {v:Bool | v <=> isClosedCurve t} @-}
cycleInvariant :: GTime -> Bool
cycleInvariant = isClosedCurve

-- Ø«Ø¨Ø§Øª Ø®Ø§ØµÙŠØ© Ø¹Ø¨Ø± Ø§Ù„Ø¯ÙˆØ±Ø© / abstract invariant preserved under full cycle
{-@ invariantUnderCycle :: t:GTime -> p:(GTime -> Bool)
                        -> {v:Bool | v <=> p t == p (stepN (timePeriod t) t)} @-}
invariantUnderCycle :: GTime -> (GTime -> Bool) -> Bool
invariantUnderCycle t p = p t == p (stepN (timePeriod t) t)

-- Ø§Ù„Ù…Ø³Ø§ÙØ© Ø§Ù„Ø¯ÙˆØ±ÙŠØ© / time distance
{-@ timeDistance :: a:GTime -> b:GTime -> Nat @-}
timeDistance :: GTime -> GTime -> Int
timeDistance a b = abs (timeIndex a - timeIndex b)

-- Ø§Ù„Ù…Ø³Ø§ÙØ© Ø¨Ø¹Ø¯ Ø§Ù„Ø¯ÙˆØ±Ø© Ø§Ù„ÙƒØ§Ù…Ù„Ø© Ù‡ÙŠ ØµÙØ± / distance after full cycle is zero
{-@ distanceCycle :: t:GTime -> {v:Nat | v <= timePeriod t} @-}
distanceCycle :: GTime -> Int
distanceCycle t = timeDistance t (stepN (timePeriod t) t)

-- â”€â”€ Convenience specialization (period = 7) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ø¯ÙˆØ±Ø© Ù…Ø±Ø¬Ø¹ÙŠØ© Ø¨Ø·ÙˆÙ„ 7 / reference cycle of length 7

{-@ period7 :: {v:Period | v == 7} @-}
period7 :: Int
period7 = 7

{-@ mkTime7 :: x:Nat -> GTime @-}
mkTime7 :: Int -> GTime
mkTime7 x = normalizeTime 7 x

-- Ø§Ù†ØºÙ„Ø§Ù‚ Ø§Ù„Ø¯ÙˆØ±Ø© / check all 7 elements satisfy closed-curve
checkAllClosed :: Bool
checkAllClosed = all (isClosedCurve . mkTime7) [0..6]
