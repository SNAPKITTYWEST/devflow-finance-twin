-- Physics.Godel — Gödel universe with parameterized cyclic time indices
-- نموذج عالم جودل مع مؤشرات زمنية دائرية معلمية
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust
-- {-@ LIQUID "--reflection" @-}
-- {-@ LIQUID "--ple" @-}

module Physics.Godel where

import Core.Nat

-- ── GTime record ─────────────────────────────────────────────────────────────
-- الزمن كسجل بفترة صريحة / time as record with explicit period

{-@ type Period = {v:Nat | v > 0} @-}

{-@ data GTime = GTime
      { timeIndex  :: Nat
      , timePeriod :: Period
      } @-}
data GTime = GTime
  { timeIndex  :: Int
  , timePeriod :: Int
  } deriving (Eq, Show)

-- تطبيع مؤشر الزمن / normalize time index into [0, period)
{-@ normalizeTime :: p:Period -> x:Nat -> GTime @-}
normalizeTime :: Int -> Int -> GTime
normalizeTime p x = GTime (x `mod` p) p

-- استخراج المؤشر / index projection
{-@ unTime :: t:GTime -> {v:Nat | v < timePeriod t} @-}
unTime :: GTime -> Int
unTime = timeIndex

-- ── Step and iteration ───────────────────────────────────────────────────────
-- خطوة زمنية دورية / cyclic step (preserves period)
{-@ step :: t:GTime -> {v:GTime | timePeriod v == timePeriod t} @-}
step :: GTime -> GTime
step (GTime x p) = GTime ((x + 1) `mod` p) p

-- تكرار بعدد محدود / iterated step (structural recursion on n)
{-@ stepN :: n:Nat -> t:GTime -> GTime / [n] @-}
stepN :: Int -> GTime -> GTime
stepN 0 t = t
stepN n t = stepN (n - 1) (step t)

-- ── Closed curves ────────────────────────────────────────────────────────────
-- حافظ الدورة / same-period predicate
{-@ samePeriod :: a:GTime -> b:GTime -> {v:Bool | v <=> timePeriod a == timePeriod b} @-}
samePeriod :: GTime -> GTime -> Bool
samePeriod a b = timePeriod a == timePeriod b

-- منحنى زمني مغلق / closed timelike curve
{-@ isClosedCurve :: t:GTime
                  -> {v:Bool | v <=> timeIndex (stepN (timePeriod t) t) == timeIndex t} @-}
isClosedCurve :: GTime -> Bool
isClosedCurve t = timeIndex (stepN (timePeriod t) t) == timeIndex t

-- العودة بعد الدورة / period returns to origin
{-@ cycleInvariant :: t:GTime -> {v:Bool | v <=> isClosedCurve t} @-}
cycleInvariant :: GTime -> Bool
cycleInvariant = isClosedCurve

-- ثبات خاصية عبر الدورة / abstract invariant preserved under full cycle
{-@ invariantUnderCycle :: t:GTime -> p:(GTime -> Bool)
                        -> {v:Bool | v <=> p t == p (stepN (timePeriod t) t)} @-}
invariantUnderCycle :: GTime -> (GTime -> Bool) -> Bool
invariantUnderCycle t p = p t == p (stepN (timePeriod t) t)

-- المسافة الدورية / time distance
{-@ timeDistance :: a:GTime -> b:GTime -> Nat @-}
timeDistance :: GTime -> GTime -> Int
timeDistance a b = abs (timeIndex a - timeIndex b)

-- المسافة بعد الدورة الكاملة هي صفر / distance after full cycle is zero
{-@ distanceCycle :: t:GTime -> {v:Nat | v <= timePeriod t} @-}
distanceCycle :: GTime -> Int
distanceCycle t = timeDistance t (stepN (timePeriod t) t)

-- ── Convenience specialization (period = 7) ──────────────────────────────────
-- دورة مرجعية بطول 7 / reference cycle of length 7

{-@ period7 :: {v:Period | v == 7} @-}
period7 :: Int
period7 = 7

{-@ mkTime7 :: x:Nat -> GTime @-}
mkTime7 :: Int -> GTime
mkTime7 x = normalizeTime 7 x

-- انغلاق الدورة / check all 7 elements satisfy closed-curve
checkAllClosed :: Bool
checkAllClosed = all (isClosedCurve . mkTime7) [0..6]
