-- TokenModel.agda
-- Core definitions for formal verification of linear-algebraic transformation protocol
--
-- This file defines:
-- - Finite-dimensional real vector spaces
-- - Linear operators (matrices)
-- - Outer products
-- - Update operators
-- - Activation functions
-- - Threshold predicates

module TokenModel where

open import Data.Nat using (ℕ; zero; suc; _+_; _*_)
open import Data.Fin using (Fin; zero; suc)
open import Data.Vec using (Vec; []; _∷_; map₂; replicate)
open import Data.Real using (ℝ; _+_; _*_; _-_; _>_; _≤_; 0ℝ; 1ℝ)
open import Data.Real.Properties using (+-comm; *-comm; *-assoc)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

--! ## Vector Space Definitions

--! A finite-dimensional real vector space
Vector : ℕ → Set
Vector n = Vec ℝ n

--! Inner product
innerProduct : ∀ {n} → Vector n → Vector n → ℝ
innerProduct [] [] = 0ℝ
innerProduct (x ∷ xs) (y ∷ ys) = (x * y) + innerProduct xs ys

--! Norm squared
normSq : ∀ {n} → Vector n → ℝ
normSq v = innerProduct v v

--! ## Outer Product

--! Outer product of two vectors
outerProduct : ∀ {n} → Vector n → Vector n → Vec (Vector n) n
outerProduct [] ys = []
outerProduct (x ∷ xs) ys = map₂ (λ xi xj → xi * xj) (replicate x) ys ∷ outerProduct xs ys

--! ## Update Operator

--! Update operator: ΔW = η · (v ⊗ xᵀ)
updateOperator : ∀ {n} → ℝ → Vector n → Vector n → Vec (Vector n) n
updateOperator η v x = map₂ (λ row vi → vi * η) (outerProduct v x) v

--! ## Activation

--! Matrix-vector multiplication
matVecMul : ∀ {n} → Vec (Vector n) n → Vector n → Vector n
matVecMul [] [] = []
matVecMul (row ∷ rows) (x ∷ xs) = innerProduct row (x ∷ xs) ∷ matVecMul rows xs

--! Activation of input x under operator W
activation : ∀ {n} → Vec (Vector n) n → Vector n → Vector n
activation W x = matVecMul W x

--! Updated activation
updatedActivation : ∀ {n} → Vec (Vector n) n → ℝ → Vector n → Vector n → Vector n
updatedActivation W η v x = matVecMul (map₂ (map₂ _+_) W (updateOperator η v x)) x

--! ## Threshold Predicate

--! Threshold predicate: ThoughtFires(y, v, θ) ⟺ ⟨y, v⟩ > θ
thoughtFires : ∀ {n} → Vector n → Vector n → ℝ → Set
thoughtFires y v θ = innerProduct y v > θ

--! ## Core Theorems

--! AX-001: Outer product action
--! (v ⊗ xᵀ)x = ‖x‖² · v
postulate
  outerProductAction : ∀ {n} (v x : Vector n) →
    matVecMul (outerProduct v x) x ≡ map₂ _*_ (replicate (normSq x)) v

--! AX-002: Update action
--! ΔW · x = η · ‖x‖² · v
postulate
  updateAction : ∀ {n} (η : ℝ) (v x : Vector n) →
    matVecMul (updateOperator η v x) x ≡ map₂ _*_ (replicate (η * normSq x)) v

--! ALG-001: Linearity of updated activation
--! (W + ΔW)x = Wx + ΔWx
postulate
  linearityOfUpdatedActivation : ∀ {n} (W : Vec (Vector n) n) (η : ℝ) (v x : Vector n) →
    updatedActivation W η v x ≡ map₂ _+_ (activation W x) (matVecMul (updateOperator η v x) x

--! ALG-002: Projection expansion
--! ⟨(W + ΔW)x, v⟩ = ⟨Wx, v⟩ + ⟨ΔWx, v⟩
postulate
  projectionExpansion : ∀ {n} (W : Vec (Vector n) n) (η : ℝ) (v x : Vector n) →
    innerProduct (updatedActivation W η v x) v ≡
    innerProduct (activation W x) v + innerProduct (matVecMul (updateOperator η v x) x) v

--! ALG-003: Exact change in projection
--! ⟨(W + ΔW)x, v⟩ - ⟨Wx, v⟩ = η · ‖x‖² · ‖v‖²
postulate
  exactChangeInProjection : ∀ {n} (W : Vec (Vector n) n) (η : ℝ) (v x : Vector n) →
    innerProduct (updatedActivation W η v x) v - innerProduct (activation W x) v ≡
    η * normSq x * normSq v

--! THR-001: Sufficient condition for threshold crossing
postulate
  thresholdSufficientCondition : ∀ {n} {W : Vec (Vector n) n} {η θ : ℝ} {v x : Vector n} →
    normSq x > 0ℝ →
    normSq v > 0ℝ →
    η > (θ - innerProduct (activation W x) v) / (normSq x * normSq v) →
    thoughtFires (updatedActivation W η v x) v θ
