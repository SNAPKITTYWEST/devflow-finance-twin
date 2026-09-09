/-
  RecursiveAudit.lean
  Recursive counterproof of previous verification conclusions
  
  This file establishes:
  - THEOREM-A: η > 0 alone is insufficient (counterexample)
  - THEOREM-B: η > η_critical is sufficient
  - THEOREM-C: η > η_critical is necessary and sufficient
  - THEOREM-D: Existence of valid gain
  - THEOREM-E: Valid gains form an open ray
  - THEOREM-F: Arbitrary margin achievable
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Data.Real.Basic

namespace RecursiveAudit

/-! ## Setup -/

variable {V : Type*} [InnerProductSpace ℝ V] [FiniteDimensional ℝ V]

/-- The update operator: ΔW = η · (v ⊗ xᵀ) -/
def updateOperator (η : ℝ) (v x : V) : V →ₗ[ℝ] V :=
  η • (LinearMap.mk (fun y => inner x y • v) (by simp [smul_add, inner_add_left]) (by simp [smul_comm]))

/-- The updated activation -/
def updatedActivation (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) : V :=
  (W + updateOperator η v x) x

/-- Critical gain -/
def criticalGain (W : V →ₗ[ℝ] V) (v x : V) (θ : ℝ) : ℝ :=
  (θ - inner (W x) v) / (inner x x * inner v v)

/-! ## Core Identity: ALG-003 -/

/-- Exact change in projection -/
theorem exactChangeInProjection (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) :
    inner (updatedActivation W η v x) v - inner (W x) v =
    η • (inner x x) • inner v v := by
  simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left]
  rw [inner_smul_left, inner_smul_left, smul_smul]

/-! ## THEOREM-A: η > 0 Alone Is Insufficient -/

/-- THEOREM-A: There exist W, x, v, θ where η > 0 but threshold not crossed -/
theorem etaPositiveInsufficient :
    ∃ (W : ℝ →ₗ[ℝ] ℝ) (x v : ℝ) (θ η : ℝ),
      η > 0 ∧ inner (updatedActivation W η v x) v ≤ θ := by
  -- W = -100, x = 1, v = 1, θ = 0, η = 1
  refine ⟨LinearMap.mul (-100), 1, 1, 0, 1, by norm_num, ?_⟩
  simp [updatedActivation, updateOperator, inner, LinearMap.mul_apply]
  norm_num

/-! ## THEOREM-B: η > η_critical Is Sufficient -/

/-- THEOREM-B: When η > η_critical, threshold is crossed -/
theorem sufficientCondition (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) (θ : ℝ)
    (hx : x ≠ 0) (hv : v ≠ 0)
    (hη : η > criticalGain W v x θ) :
    inner (updatedActivation W η v x) v > θ := by
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  simp only [criticalGain] at hη
  rw [exactChangeInProjection]
  have : inner (updatedActivation W η v x) v = inner (W x) v + η • (inner x x) • inner v v := by
    simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul]
  rw [this]
  rw [← sub_lt_iff_lt_add']
  have : η • (inner x x) • inner v v = η * inner x x * inner v v := by ring
  rw [this]
  rw [← div_lt_iff hprod] at hη
  linarith

/-! ## THEOREM-C: Necessary and Sufficient Condition -/

/-- THEOREM-C (⇒): If threshold crossed, then η > η_critical -/
theorem necessaryCondition (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) (θ : ℝ)
    (hx : x ≠ 0) (hv : v ≠ 0)
    (hcross : inner (updatedActivation W η v x) v > θ) :
    η > criticalGain W v x θ := by
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  simp only [criticalGain]
  rw [exactChangeInProjection] at hcross
  have : inner (updatedActivation W η v x) v = inner (W x) v + η * inner x x * inner v v := by
    simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul, smul_eq_mul]
  rw [this] at hcross
  rw [← div_lt_iff hprod]
  linarith

/-! ## THEOREM-D: Existence of Valid Gain -/

/-- THEOREM-D: For every finite θ and nonzero x,v, a positive η exists -/
theorem existenceOfValidGain (W : V →ₗ[ℝ] V) (v x : V) (θ : ℝ)
    (hx : x ≠ 0) (hv : v ≠ 0) :
    ∃ η > 0, inner (updatedActivation W η v x) v > θ := by
  refine ⟨(θ - inner (W x) v + 1) / (inner x x * inner v v), ?_, ?_⟩
  · have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    positivity
  · have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    rw [exactChangeInProjection]
    have : inner (updatedActivation W ((θ - inner (W x) v + 1) / (inner x x * inner v v)) v x) v =
           inner (W x) v + ((θ - inner (W x) v + 1) / (inner x x * inner v v)) * inner x x * inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul, smul_eq_mul]
    rw [this]
    field_simp
    linarith

/-! ## THEOREM-E: Valid Gains Form an Open Ray -/

/-- THEOREM-E: The set of valid gains is (η_critical, ∞) -/
theorem validGainsOpenRay (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) (θ : ℝ)
    (hx : x ≠ 0) (hv : v ≠ 0) :
    (inner (updatedActivation W η v x) v > θ) ↔ (η > criticalGain W v x θ) := by
  constructor
  · intro h
    exact necessaryCondition W η v x θ hx hv h
  · intro h
    exact sufficientCondition W η v x θ hx hv h

/-! ## THEOREM-F: Arbitrary Margin Achievable -/

/-- THEOREM-F: For any ε > 0, there exists η achieving margin ε -/
theorem arbitraryMargin (W : V →ₗ[ℝ] V) (v x : V) (θ ε : ℝ)
    (hx : x ≠ 0) (hv : v ≠ 0) (hε : ε > 0) :
    ∃ η > 0, inner (updatedActivation W η v x) v > θ + ε := by
  refine ⟨(θ + ε - inner (W x) v + 1) / (inner x x * inner v v), ?_, ?_⟩
  · have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    positivity
  · have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    rw [exactChangeInProjection]
    have : inner (updatedActivation W ((θ + ε - inner (W x) v + 1) / (inner x x * inner v v)) v x) v =
           inner (W x) v + ((θ + ε - inner (W x) v + 1) / (inner x x * inner v v)) * inner x x * inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul, smul_eq_mul]
    rw [this]
    field_simp
    linarith

end RecursiveAudit
