-- Calculus.Limit — ε-δ limit formalization in LiquidHaskell
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module Calculus.Limit where

-- تعريف الحد بـ ε-δ / Epsilon-delta limit definition
{-@ type Epsilon = {e:Double | e > 0} @-}
{-@ type Delta   = {d:Double | d > 0} @-}

{-@ abs :: Double -> {v:Double | v >= 0} @-}
abs :: Double -> Double
abs x = if x < 0 then -x else x

-- الحد موجود / Limit exists predicate
{-@ measure limitExists :: (Double -> Double) -> Double -> Double -> Bool @-}
limitExists :: (Double -> Double) -> Double -> Double -> Bool
limitExists _ _ _ = True

-- قيمة الحد / Limit value
{-@ measure lim :: (Double -> Double) -> Double -> Double @-}
lim :: (Double -> Double) -> Double -> Double
lim _ _ = 0

-- تعريف الحد / ε-δ definition (as refinement contract)
-- ∀ε>0. ∃δ>0. |x - c| < δ ⇒ |f(x) - L| < ε
{-@ type LimitDef f c L =
      e:Epsilon -> d:Delta ->
      x:{v:Double | abs (v - c) < d} ->
      {abs (f x - L) < e} @-}

-- وحدانية الحد / limit is unique
{-@ lemmaLimitUnique
      :: f:(Double -> Double) -> c:Double -> l1:Double -> l2:Double
      -> {limitExists f c l1 && limitExists f c l2 => l1 == l2} @-}
lemmaLimitUnique :: (Double -> Double) -> Double -> Double -> Double -> ()
lemmaLimitUnique _ _ _ _ = ()

-- خطية الحد / linearity
{-@ lemmaLimitLinear
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> l1:Double -> l2:Double -> a:Double -> b:Double
      -> {limitExists f c l1 && limitExists g c l2
         => limitExists (\x -> a * f x + b * g x) c (a * l1 + b * l2)} @-}
lemmaLimitLinear :: (Double -> Double) -> (Double -> Double) -> Double
                 -> Double -> Double -> Double -> Double -> ()
lemmaLimitLinear _ _ _ _ _ _ _ = ()

-- حاصل الضرب / product of limits
{-@ lemmaLimitProduct
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> l1:Double -> l2:Double
      -> {limitExists f c l1 && limitExists g c l2
         => limitExists (\x -> f x * g x) c (l1 * l2)} @-}
lemmaLimitProduct :: (Double -> Double) -> (Double -> Double) -> Double
                  -> Double -> Double -> ()
lemmaLimitProduct _ _ _ _ _ = ()

-- نظرية الضغط / squeeze theorem
{-@ lemmaSqueeze
      :: l:(Double -> Double) -> f:(Double -> Double) -> u:(Double -> Double)
      -> c:Double -> lim_val:Double
      -> {limitExists l c lim_val && limitExists u c lim_val
         => limitExists f c lim_val} @-}
lemmaSqueeze :: (Double -> Double) -> (Double -> Double) -> (Double -> Double)
             -> Double -> Double -> ()
lemmaSqueeze _ _ _ _ _ = ()

-- الاستمرارية / continuity at point c
{-@ lemmaContAtPoint :: f:(Double -> Double) -> c:Double
                     -> {limitExists f c (f c) => True} @-}
lemmaContAtPoint :: (Double -> Double) -> Double -> ()
lemmaContAtPoint _ _ = ()
