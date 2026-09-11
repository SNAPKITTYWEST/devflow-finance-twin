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

-- Physics.WormholeBH â€” Einstein-Rosen bridge + black hole event horizon
-- Ø­ÙØ¸ Ø¬Ø³Ø± Ø£ÙŠÙ†Ø´ØªØ§ÙŠÙ†-Ø±ÙˆØ²Ù† ÙˆØ£ÙÙ‚ Ø­Ø¯Ø« Ø§Ù„Ø«Ù‚Ø¨ Ø§Ù„Ø£Ø³ÙˆØ¯
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust
-- {-@ LIQUID "--reflection" @-}
-- {-@ LIQUID "--ple" @-}

module Physics.WormholeBH where

import Core.Nat

-- â”€â”€ Wormhole regions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ù…Ù†Ø·Ù‚ØªØ§Ù† Ø®Ø§Ø±Ø¬ Ø§Ù„Ø£ÙÙ‚ / two external regions

newtype RegionL = RegionL { unRegionL :: Int } deriving (Eq, Show)
newtype RegionR = RegionR { unRegionR :: Int } deriving (Eq, Show)

-- Ø§Ù„ÙƒØªÙ„Ø© ÙÙŠ Ø§Ù„Ù…Ù†Ø·Ù‚Ø© Ø§Ù„ÙŠØ³Ø±Ù‰ / mass in left region
{-@ massL :: RegionL -> Nat @-}
massL :: RegionL -> Int
massL (RegionL n) = abs n

-- Ø§Ù„ÙƒØªÙ„Ø© ÙÙŠ Ø§Ù„Ù…Ù†Ø·Ù‚Ø© Ø§Ù„ÙŠÙ…Ù†Ù‰ / mass in right region
{-@ massR :: RegionR -> Nat @-}
massR :: RegionR -> Int
massR (RegionR n) = abs n

-- â”€â”€ Einstein-Rosen bridge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ø¬Ø³Ø± Ù…Ø­Ø§ÙØ¸ Ø¹Ù„Ù‰ Ø§Ù„ÙƒØªÙ„Ø© / mass-preserving bridge
{-@ bridge :: l:RegionL -> {r:RegionR | massR r == massL l} @-}
bridge :: RegionL -> RegionR
bridge (RegionL n) = RegionR n

-- Ø¹ÙƒØ³ Ø§Ù„Ø¬Ø³Ø± / inverse bridge
{-@ unbridge :: r:RegionR -> {l:RegionL | massL l == massR r} @-}
unbridge :: RegionR -> RegionL
unbridge (RegionR n) = RegionL n

-- Ø­ÙØ¸ Ø§Ù„ÙƒØªÙ„Ø© ÙÙŠ Ø§Ù„Ø§ØªØ¬Ø§Ù‡ÙŠÙ† / conservation in both directions
{-@ lemmaBridgeConservesMass :: l:RegionL
                             -> {v:Bool | v <=> massR (bridge l) == massL l} @-}
lemmaBridgeConservesMass :: RegionL -> Bool
lemmaBridgeConservesMass l = massR (bridge l) == massL l

{-@ lemmaUnbridgeConservesMass :: r:RegionR
                               -> {v:Bool | v <=> massL (unbridge r) == massR r} @-}
lemmaUnbridgeConservesMass :: RegionR -> Bool
lemmaUnbridgeConservesMass r = massL (unbridge r) == massR r

-- Ø¯ÙˆØ±Ø© Ø§Ù„Ø¬Ø³Ø± / bridge round-trips
{-@ bridgeRoundTrip  :: l:RegionL -> {v:Bool | v <=> unbridge (bridge l) == l} @-}
bridgeRoundTrip :: RegionL -> Bool
bridgeRoundTrip l = unbridge (bridge l) == l

{-@ unbridgeRoundTrip :: r:RegionR -> {v:Bool | v <=> bridge (unbridge r) == r} @-}
unbridgeRoundTrip :: RegionR -> Bool
unbridgeRoundTrip r = bridge (unbridge r) == r

-- â”€â”€ Black hole â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ø­Ø§Ù„Ø© Ø§Ù„Ø«Ù‚Ø¨ Ø§Ù„Ø£Ø³ÙˆØ¯ ÙƒØ³Ø¬Ù„ / black-hole state as record

{-@ data RegionBH = RegionBH { bhMass :: Nat } @-}
data RegionBH = RegionBH { bhMass :: Int } deriving (Eq, Show)

-- Ø£ÙÙ‚ Ø§Ù„Ø­Ø¯Ø« / event horizon threshold
{-@ horizon :: Pos @-}
horizon :: Int
horizon = 100

-- Ù…Ø§ Ø¥Ø°Ø§ ÙƒØ§Ù†Øª ÙƒØªÙ„Ø© Ø¹Ù†Ø¯ Ø§Ù„Ø£ÙÙ‚ Ø£Ùˆ Ø¨Ø¹Ø¯Ù‡ / at-horizon predicate
{-@ atHorizon :: x:Nat -> {v:Bool | v <=> x >= horizon} @-}
atHorizon :: Int -> Bool
atHorizon x = x >= horizon

-- Ø§Ù„Ø³Ù‚ÙˆØ· Ø¹Ø¨Ø± Ø§Ù„Ø£ÙÙ‚ (Ø¨ÙˆØ§Ø¨Ø© Ø£Ø­Ø§Ø¯ÙŠØ© Ø§Ù„Ø§ØªØ¬Ø§Ù‡) / one-way horizon crossing
{-@ fallIn :: x:Nat -> Maybe {r:RegionBH | bhMass r >= horizon} @-}
fallIn :: Int -> Maybe RegionBH
fallIn x
  | x >= horizon = Just (RegionBH x)
  | otherwise    = Nothing

-- Ø§Ù…ØªØµØ§Øµ Ø§Ù„Ø£ÙÙ‚ / forced entry at exact horizon
{-@ horizonAbsorption :: x:{Nat | x >= horizon} -> {v:RegionBH | bhMass v >= horizon} @-}
horizonAbsorption :: Int -> RegionBH
horizonAbsorption x = case fallIn x of
  Just r  -> r
  Nothing -> RegionBH horizon

-- Ø§Ù†ØªÙ‚Ø§Ù„ Ø£Ø­Ø§Ø¯ÙŠ Ø§Ù„Ø§ØªØ¬Ø§Ù‡ (Ù„Ø§ ÙŠÙ†Ù‚Øµ) / monotone state transition
{-@ bhTransition :: r:{RegionBH | bhMass r >= horizon}
                 -> delta:Nat
                 -> {v:RegionBH | bhMass v >= bhMass r} @-}
bhTransition :: RegionBH -> Int -> RegionBH
bhTransition (RegionBH m) delta = RegionBH (m + delta)

-- Ø±ØªØ§Ø¨Ø© Ø§Ù„ÙƒØªÙ„Ø© / mass monotonicity
{-@ bhMassMonotone :: r:{RegionBH | bhMass r >= horizon}
                   -> d:Nat
                   -> {v:Bool | v <=> bhMass (bhTransition r d) >= bhMass r} @-}
bhMassMonotone :: RegionBH -> Int -> Bool
bhMassMonotone r d = bhMass (bhTransition r d) >= bhMass r

-- Ù„Ø§ Ù‡Ø±ÙˆØ¨ Ù…Ù† Ø¯Ø§Ø®Ù„ Ø§Ù„Ø£ÙÙ‚ / no escape below horizon (abstract axiom)
{-@ assume lemmaNoEscape :: before:RegionBH
                         -> after:{RegionBH | bhMass after >= bhMass before}
                         -> {v:Bool | v} @-}
lemmaNoEscape :: RegionBH -> RegionBH -> Bool
lemmaNoEscape _ _ = True

-- ØªÙƒØ±Ø§Ø± Ø§Ù„Ø§Ù†ØªÙ‚Ø§Ù„ / iterated transition (structural recursion on n)
{-@ bhIter :: n:Nat -> b:{RegionBH | bhMass b >= horizon}
           -> {v:RegionBH | bhMass v >= bhMass b} / [n] @-}
bhIter :: Int -> RegionBH -> RegionBH
bhIter 0 b = b
bhIter n b = bhIter (n - 1) (bhTransition b 1)

-- â”€â”€ Bridge â†” BH compatibility â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Ø§Ù„ØªÙˆØ§ÙÙ‚ Ù…Ø¹ Ø§Ù„Ø¬Ø³Ø± / bridge entry conservation
{-@ bridgeBHConservation :: l:RegionL
                         -> {v:Bool | v <=> massR (bridge l) == massL l} @-}
bridgeBHConservation :: RegionL -> Bool
bridgeBHConservation l = massR (bridge l) == massL l
