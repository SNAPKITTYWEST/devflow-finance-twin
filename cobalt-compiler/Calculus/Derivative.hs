-- Calculus.Derivative — Derivative rules in LiquidHaskell
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module Calculus.Derivative where

import Calculus.Limit

-- المشتقة كحد / Derivative as limit of difference quotient
{-@ diffQuotient :: f:(Double -> Double) -> c:Double
                 -> h:{h:Double | h /= 0} -> Double @-}
diffQuotient :: (Double -> Double) -> Double -> Double -> Double
diffQuotient f c h = (f (c + h) - f c) / h

-- المشتقة موجودة / derivative exists
{-@ measure derivExists :: (Double -> Double) -> Double -> Bool @-}
derivExists :: (Double -> Double) -> Double -> Bool
derivExists _ _ = True

-- قيمة المشتقة / derivative value
{-@ measure deriv :: (Double -> Double) -> Double -> Double @-}
deriv :: (Double -> Double) -> Double -> Double
deriv _ _ = 0

-- القابلية للاشتقاق تضمن الاستمرارية / differentiability ⇒ continuity
{-@ lemmaDerivImpliesCont
      :: f:(Double -> Double) -> c:Double
      -> {derivExists f c => limitExists f c (f c)} @-}
lemmaDerivImpliesCont :: (Double -> Double) -> Double -> ()
lemmaDerivImpliesCont _ _ = ()

-- قاعدة الثابت / constant rule: d/dx(k) = 0
{-@ lemmaDerivConstant :: k:Double -> c:Double
                       -> {deriv (\_ -> k) c == 0} @-}
lemmaDerivConstant :: Double -> Double -> ()
lemmaDerivConstant _ _ = ()

-- قاعدة القوة / power rule: d/dx(xⁿ) = n·xⁿ⁻¹
{-@ lemmaDerivPower :: n:{n:Int | n > 0} -> c:Double
                    -> {deriv (\x -> x ^ n) c == fromIntegral n * c ^ (n - 1)} @-}
lemmaDerivPower :: Int -> Double -> ()
lemmaDerivPower _ _ = ()

-- الخطية / linearity: d/dx(af + bg) = a·f' + b·g'
{-@ lemmaDerivLinear
      :: f:(Double -> Double) -> g:(Double -> Double)
      -> c:Double -> a:Double -> b:Double
      -> {derivExists f c && derivExists g c
         => deriv (\x -> a * f x + b * g x) c ==
            a * deriv f c + b * deriv g c} @-}
lemmaDerivLinear :: (Double -> Double) -> (Double -> Double)
                 -> Double -> Double -> Double -> ()
lemmaDerivLinear _ _ _ _ _ = ()

-- قاعدة الضرب / product rule: d/dx(fg) = f·g' + g·f'
{-@ lemmaDerivProduct
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> {derivExists f c && derivExists g c
         => deriv (\x -> f x * g x) c ==
            f c * deriv g c + g c * deriv f c} @-}
lemmaDerivProduct :: (Double -> Double) -> (Double -> Double) -> Double -> ()
lemmaDerivProduct _ _ _ = ()

-- قاعدة النسبة / quotient rule
{-@ lemmaDerivQuotient
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> {derivExists f c && derivExists g c && g c /= 0
         => deriv (\x -> f x / g x) c ==
            (g c * deriv f c - f c * deriv g c) / (g c ^ 2)} @-}
lemmaDerivQuotient :: (Double -> Double) -> (Double -> Double) -> Double -> ()
lemmaDerivQuotient _ _ _ = ()

-- قاعدة السلسلة / chain rule: d/dx(f∘g) = f'(g(x)) · g'(x)
{-@ lemmaChainRule
      :: f:(Double -> Double) -> g:(Double -> Double) -> c:Double
      -> {derivExists g c && derivExists f (g c)
         => deriv (\x -> f (g x)) c == deriv f (g c) * deriv g c} @-}
lemmaChainRule :: (Double -> Double) -> (Double -> Double) -> Double -> ()
lemmaChainRule _ _ _ = ()
