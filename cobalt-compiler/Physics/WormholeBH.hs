-- Physics.WormholeBH — Einstein-Rosen bridge + black hole event horizon
-- حفظ جسر أينشتاين-روزن وأفق حدث الثقب الأسود
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust
-- {-@ LIQUID "--reflection" @-}
-- {-@ LIQUID "--ple" @-}

module Physics.WormholeBH where

import Core.Nat

-- ── Wormhole regions ─────────────────────────────────────────────────────────
-- منطقتان خارج الأفق / two external regions

newtype RegionL = RegionL { unRegionL :: Int } deriving (Eq, Show)
newtype RegionR = RegionR { unRegionR :: Int } deriving (Eq, Show)

-- الكتلة في المنطقة اليسرى / mass in left region
{-@ massL :: RegionL -> Nat @-}
massL :: RegionL -> Int
massL (RegionL n) = abs n

-- الكتلة في المنطقة اليمنى / mass in right region
{-@ massR :: RegionR -> Nat @-}
massR :: RegionR -> Int
massR (RegionR n) = abs n

-- ── Einstein-Rosen bridge ────────────────────────────────────────────────────
-- جسر محافظ على الكتلة / mass-preserving bridge
{-@ bridge :: l:RegionL -> {r:RegionR | massR r == massL l} @-}
bridge :: RegionL -> RegionR
bridge (RegionL n) = RegionR n

-- عكس الجسر / inverse bridge
{-@ unbridge :: r:RegionR -> {l:RegionL | massL l == massR r} @-}
unbridge :: RegionR -> RegionL
unbridge (RegionR n) = RegionL n

-- حفظ الكتلة في الاتجاهين / conservation in both directions
{-@ lemmaBridgeConservesMass :: l:RegionL
                             -> {v:Bool | v <=> massR (bridge l) == massL l} @-}
lemmaBridgeConservesMass :: RegionL -> Bool
lemmaBridgeConservesMass l = massR (bridge l) == massL l

{-@ lemmaUnbridgeConservesMass :: r:RegionR
                               -> {v:Bool | v <=> massL (unbridge r) == massR r} @-}
lemmaUnbridgeConservesMass :: RegionR -> Bool
lemmaUnbridgeConservesMass r = massL (unbridge r) == massR r

-- دورة الجسر / bridge round-trips
{-@ bridgeRoundTrip  :: l:RegionL -> {v:Bool | v <=> unbridge (bridge l) == l} @-}
bridgeRoundTrip :: RegionL -> Bool
bridgeRoundTrip l = unbridge (bridge l) == l

{-@ unbridgeRoundTrip :: r:RegionR -> {v:Bool | v <=> bridge (unbridge r) == r} @-}
unbridgeRoundTrip :: RegionR -> Bool
unbridgeRoundTrip r = bridge (unbridge r) == r

-- ── Black hole ───────────────────────────────────────────────────────────────
-- حالة الثقب الأسود كسجل / black-hole state as record

{-@ data RegionBH = RegionBH { bhMass :: Nat } @-}
data RegionBH = RegionBH { bhMass :: Int } deriving (Eq, Show)

-- أفق الحدث / event horizon threshold
{-@ horizon :: Pos @-}
horizon :: Int
horizon = 100

-- ما إذا كانت كتلة عند الأفق أو بعده / at-horizon predicate
{-@ atHorizon :: x:Nat -> {v:Bool | v <=> x >= horizon} @-}
atHorizon :: Int -> Bool
atHorizon x = x >= horizon

-- السقوط عبر الأفق (بوابة أحادية الاتجاه) / one-way horizon crossing
{-@ fallIn :: x:Nat -> Maybe {r:RegionBH | bhMass r >= horizon} @-}
fallIn :: Int -> Maybe RegionBH
fallIn x
  | x >= horizon = Just (RegionBH x)
  | otherwise    = Nothing

-- امتصاص الأفق / forced entry at exact horizon
{-@ horizonAbsorption :: x:{Nat | x >= horizon} -> {v:RegionBH | bhMass v >= horizon} @-}
horizonAbsorption :: Int -> RegionBH
horizonAbsorption x = case fallIn x of
  Just r  -> r
  Nothing -> RegionBH horizon

-- انتقال أحادي الاتجاه (لا ينقص) / monotone state transition
{-@ bhTransition :: r:{RegionBH | bhMass r >= horizon}
                 -> delta:Nat
                 -> {v:RegionBH | bhMass v >= bhMass r} @-}
bhTransition :: RegionBH -> Int -> RegionBH
bhTransition (RegionBH m) delta = RegionBH (m + delta)

-- رتابة الكتلة / mass monotonicity
{-@ bhMassMonotone :: r:{RegionBH | bhMass r >= horizon}
                   -> d:Nat
                   -> {v:Bool | v <=> bhMass (bhTransition r d) >= bhMass r} @-}
bhMassMonotone :: RegionBH -> Int -> Bool
bhMassMonotone r d = bhMass (bhTransition r d) >= bhMass r

-- لا هروب من داخل الأفق / no escape below horizon (abstract axiom)
{-@ assume lemmaNoEscape :: before:RegionBH
                         -> after:{RegionBH | bhMass after >= bhMass before}
                         -> {v:Bool | v} @-}
lemmaNoEscape :: RegionBH -> RegionBH -> Bool
lemmaNoEscape _ _ = True

-- تكرار الانتقال / iterated transition (structural recursion on n)
{-@ bhIter :: n:Nat -> b:{RegionBH | bhMass b >= horizon}
           -> {v:RegionBH | bhMass v >= bhMass b} / [n] @-}
bhIter :: Int -> RegionBH -> RegionBH
bhIter 0 b = b
bhIter n b = bhIter (n - 1) (bhTransition b 1)

-- ── Bridge ↔ BH compatibility ────────────────────────────────────────────────
-- التوافق مع الجسر / bridge entry conservation
{-@ bridgeBHConservation :: l:RegionL
                         -> {v:Bool | v <=> massR (bridge l) == massL l} @-}
bridgeBHConservation :: RegionL -> Bool
bridgeBHConservation l = massR (bridge l) == massL l
