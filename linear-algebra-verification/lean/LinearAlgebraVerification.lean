/-
  LinearAlgebraVerification.lean
  Complete formal verification of outer-product update algebra
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Data.Real.Basic

/-!
# Linear Algebra Verification

Complete proofs of:
- Outer product action identity
- Linearity of matrix-vector multiplication
- Inner product expansion under update
- Exact change in projection
- Threshold conditions for projection crossing
- Existence of gains achieving arbitrary thresholds
-/

namespace LinearAlgebraVerification

/-! ## Vector Space Setup -/

variable {V : Type*} [InnerProductSpace ℝ V]

/-! ## Outer Product Definition -/

/-- The outer product of vectors v and x: (v ⊗ xᵀ)(y) = ⟨x,y⟩ · v -/
def outerProduct (v x : V) : V →ₗ[ℝ] V :=
  LinearMap.mk (fun y => inner x y • v)
    (fun a b y => by simp [smul_add, inner_add_left])
    (fun a x y => by simp [smul_comm])

/-! ## ALG-001: Outer Product Action -/

/-- (v ⊗ xᵀ)x = ‖x‖² · v -/
theorem outerProductAction (v x : V) :
    outerProduct v x x = inner x x • v := by
  simp [outerProduct]

/-! ## Update Operator -/

/-- ΔW = η · (v ⊗ xᵀ) -/
def updateOperator (η : ℝ) (v x : V) : V →ₗ[ℝ] V :=
  η • outerProduct v x

/-- Updated activation: (W + ΔW)x -/
def updatedActivation (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) : V :=
  (W + updateOperator η v x) x

/-! ## ALG-002: Linearity -/

/-- (W + ΔW)x = Wx + ΔWx -/
theorem linearity (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) :
    updatedActivation W η v x = W x + updateOperator η v x x := by
  simp [updatedActivation, LinearMap.add_apply]

/-! ## ALG-003: Inner Product Expansion -/

/-- ⟨(W + ΔW)x, v⟩ = ⟨Wx, v⟩ + ⟨ΔWx, v⟩ -/
theorem innerProductExpansion (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) :
    inner (updatedActivation W η v x) v =
    inner (W x) v + inner (updateOperator η v x x) v := by
  rw [linearity, inner_add_left]

/-! ## ALG-004: Exact Change in Projection -/

/-- ⟨(W + ΔW)x, v⟩ - ⟨Wx, v⟩ = η · ‖x‖² · ‖v‖² -/
theorem exactChangeInProjection (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) :
    inner (updatedActivation W η v x) v - inner (W x) v =
    η • inner x x • inner v v := by
  rw [innerProductExpansion, updateOperator, outerProductAction]
  simp [inner_smul_left, smul_smul]

/-! ## THR-001: Sufficient Condition -/

/-- η > (θ - ⟨Wx,v⟩)/(‖x‖²·‖v‖²) implies threshold crossing -/
theorem thresholdSufficient (W : V →ₗ[ℝ] V) (η : V →ₗ[ℝ] V → ℝ) (v x : V) (θ : ℝ)
    (hx : x ≠ 0) (hv : v ≠ 0)
    (hη : η W v x > (θ - inner (W x) v) / (inner x x * inner v v)) :
    inner (updatedActivation W (η W v x) v x) v > θ := by
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  rw [exactChangeInProjection]
  have : inner (updatedActivation W (η W v x) v x) v =
         inner (W x) v + (η W v x) • inner x x • inner v v := by
    simp [updatedActivation, updateOperator, LinearMap.add_apply,
          inner_add_left, outerProductAction, inner_smul_left, smul_smul]
  rw [this, sub_add_cancel]
  rw [← sub_lt_iff_lt_add']
  rw [← div_lt_iff hprod] at hη
  linarith

/-! ## THR-002: Existence of Valid Gain -/

/-- For any finite θ and nonzero x,v, there exists η > 0 achieving threshold -/
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
           inner (W x) v + ((θ - inner (W x) v + 1) / (inner x x * inner v v)) • inner x x • inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply,
            inner_add_left, outerProductAction, inner_smul_left, smul_smul]
    rw [this]
    field_simp
    linarith

/-! ## Arbitrary Margin -/

/-- For any ε > 0, there exists η > 0 achieving margin θ + ε -/
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
           inner (W x) v + ((θ + ε - inner (W x) v + 1) / (inner x x * inner v v)) • inner x x • inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply,
            inner_add_left, outerProductAction, inner_smul_left, smul_smul]
    rw [this]
    field_simp
    linarith

end LinearAlgebraVerification
