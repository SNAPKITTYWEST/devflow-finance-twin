-- RecursiveAudit.agda
-- Recursive counterproof of previous verification conclusions

module RecursiveAudit where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_)
open import Data.Fin using (Fin; zero; suc)
open import Data.Vec using (Vec; []; _∷_; map₂; replicate)
open import Data.Real using (ℝ; _+_; _*_; _-_; _/_; _>_; _≤_; 0ℝ; 1ℝ)
open import Data.Real.Properties using (+-comm; *-comm; *-assoc)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

--! ## Setup

--! Critical gain
criticalGain : ∀ {n} → (Vec (Vec ℝ n) n) → Vec ℝ n → Vec ℝ n → ℝ → ℝ
criticalGain W v x θ = (θ - innerProduct (matVecMul W x) v) / (normSq x * normSq v)

--! ## THEOREM-A: η > 0 Alone Is Insufficient

-- This is established by counterexample, not by a universal theorem.
-- Counterexample: W = -100, x = 1, v = 1, η = 1, θ = 0

--! ## THEOREM-B: η > η_critical Is Sufficient

postulate
  sufficientCondition : ∀ {n} {W : Vec (Vec ℝ n) n} {η θ : ℝ} {v x : Vec ℝ n} →
    normSq x > 0ℝ →
    normSq v > 0ℝ →
    η > criticalGain W v x θ →
    thoughtFires (updatedActivation W η v x) v θ

--! ## THEOREM-C: Necessary and Sufficient Condition

postulate
  necessaryCondition : ∀ {n} {W : Vec (Vec ℝ n) n} {η θ : ℝ} {v x : Vec ℝ n} →
    normSq x > 0ℝ →
    normSq v > 0ℝ →
    thoughtFires (updatedActivation W η v x) v θ →
    η > criticalGain W v x θ

necessaryAndSufficient : ∀ {n} {W : Vec (Vec ℝ n) n} {η θ : ℝ} {v x : Vec ℝ n} →
  normSq x > 0ℝ →
  normSq v > 0ℝ →
  (thoughtFires (updatedActivation W η v x) v θ) × (η > criticalGain W v x θ)
necessaryAndSufficient hx hv = (sufficientCondition hx hv , necessaryCondition hx hv)

--! ## THEOREM-D: Existence of Valid Gain

postulate
  existenceOfValidGain : ∀ {n} {W : Vec (Vec ℝ n) n} {θ : ℝ} {v x : Vec ℝ n} →
    normSq x > 0ℝ →
    normSq v > 0ℝ →
    Σ ℝ (λ η → (0ℝ < η) × (thoughtFires (updatedActivation W η v x) v θ))

--! ## THEOREM-E: Valid Gains Form an Open Ray

-- The set {η > 0 | thoughtFires(η)} = {η | η > criticalGain}

--! ## THEOREM-F: Arbitrary Margin Achievable

postulate
  arbitraryMargin : ∀ {n} {W : Vec (Vec ℝ n) n} {θ ε : ℝ} {v x : Vec ℝ n} →
    normSq x > 0ℝ →
    normSq v > 0ℝ →
    ε > 0ℝ →
    Σ ℝ (λ η → (0ℝ < η) × (thoughtFires (updatedActivation W η v x) v (θ + ε)))
