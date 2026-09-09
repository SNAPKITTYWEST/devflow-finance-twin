/-
  TokenModel.lean
  Core definitions for formal verification of linear-algebraic transformation protocol
  
  This file defines:
  - Finite-dimensional real inner product spaces
  - Linear operators (matrices)
  - Outer products
  - Update operators
  - Activation functions
  - Threshold predicates
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Data.Matrix.Basic
import Mathlib.Data.Real.Basic

namespace TokenModel

/-! ## Vector Space Definitions -/

/-- A finite-dimensional real inner product space -/
variable {V : Type*} [InnerProductSpace ℝ V] [FiniteDimensional ℝ V]

/-- The dimension of the vector space -/
noncomputable def dim (V : Type*) [InnerProductSpace ℝ V] [FiniteDimensional ℝ V] : ℕ :=
  FiniteDimensional.finrank ℝ V

/-! ## Outer Product -/

/-- The outer product of two vectors: v ⊗ xᵀ -/
def outerProduct {V : Type*} [InnerProductSpace ℝ V] (v x : V) : V →ₗ[ℝ] V :=
  LinearMap.mk (fun y => inner x y • v) (by
    intro a b y
    simp [smul_add, inner_add_left]
  ) (by
    intro a x y
    simp [smul_comm]
  )

/-- Matrix representation of outer product -/
def outerProductMatrix {n : ℕ} (v x : Fin n → ℝ) : Matrix (Fin n) (Fin n) ℝ :=
  Matrix.of (fun i j => v i * x j)

/-! ## Update Operator -/

/-- The update operator: ΔW = η · (v ⊗ xᵀ) -/
def updateOperator {V : Type*} [InnerProductSpace ℝ V]
    (η : ℝ) (v x : V) : V →ₗ[ℝ] V :=
  η • outerProduct v x

/-- Matrix representation of update operator -/
def updateMatrix {n : ℕ} (η : ℝ) (v x : Fin n → ℝ) : Matrix (Fin n) (Fin n) ℝ :=
  η • outerProductMatrix v x

/-! ## Activation -/

/-- The activation of input x under operator W -/
def activation {V : Type*} [InnerProductSpace ℝ V]
    (W : V →ₗ[ℝ] V) (x : V) : V :=
  W x

/-- The updated activation -/
def updatedActivation {V : Type*} [InnerProductSpace ℝ V]
    (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) : V :=
  (W + updateOperator η v x) x

/-! ## Threshold Predicate -/

/-- The threshold predicate: ThoughtFires(y, v, θ) ⟺ ⟨y, v⟩ > θ -/
def thoughtFires {V : Type*} [InnerProductSpace ℝ V]
    (y v : V) (θ : ℝ) : Prop :=
  inner y v > θ

/-! ## Core Theorems -/

/-- AX-001: Outer product action -/
theorem outerProductAction {V : Type*} [InnerProductSpace ℝ V]
    (v x : V) :
    (outerProduct v x) x = (inner x x) • v := by
  simp [outerProduct]

/-- AX-002: Update action -/
theorem updateAction {V : Type*} [InnerProductSpace ℝ V]
    (η : ℝ) (v x : V) :
    (updateOperator η v x) x = η • (inner x x) • v := by
  simp [updateOperator, outerProductAction]
  rw [← smul_assoc]

/-- ALG-001: Linearity of updated activation -/
theorem linearityOfUpdatedActivation {V : Type*} [InnerProductSpace ℝ V]
    (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) :
    (W + updateOperator η v x) x = W x + (updateOperator η v x) x := by
  simp [LinearMap.add_apply]

/-- ALG-002: Projection expansion -/
theorem projectionExpansion {V : Type*} [InnerProductSpace ℝ V]
    (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) :
    inner ((W + updateOperator η v x) x) v =
    inner (W x) v + inner ((updateOperator η v x) x) v := by
  rw [linearityOfUpdatedActivation, inner_add_left]

/-- ALG-003: Exact change in projection -/
theorem exactChangeInProjection {V : Type*} [InnerProductSpace ℝ V]
    (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) :
    inner ((W + updateOperator η v x) x) v - inner (W x) v =
    η • (inner x x) • inner v v := by
  rw [projectionExpansion, sub_add_cancel]
  simp [updateAction, inner_smul_left, smul_eq_mul]

/-- THR-001: Sufficient condition for threshold crossing -/
theorem thresholdSufficientCondition {V : Type*} [InnerProductSpace ℝ V]
    (W : V →ₗ[ℝ] V) (η : ℝ) (v x : V) (θ : ℝ)
    (hx : x ≠ 0) (hv : v ≠ 0)
    (hη : η > (θ - inner (W x) v) / (inner x x * inner v v)) :
    thoughtFires ((W + updateOperator η v x) x) v θ := by
  simp [thoughtFires, projectionExpansion]
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  calc
    inner (W x) v + inner ((updateOperator η v x) x) v
      = inner (W x) v + η • (inner x x) • inner v v := by simp [updateAction, inner_smul_left]
    _ > inner (W x) v + (θ - inner (W x) v) := by
      rw [← sub_lt_iff_lt_add']
      rw [sub_self]
      rw [zero_lt_iff_ne_zero] at hprod
      rw [smul_smul]
      exact div_lt_self_of_pos_of_pos (sub_lt_comm.mp (sub_pos.mpr (lt_of_le_of_lt (le_refl _) (by linarith)))) hprod
    _ = θ := by ring

end TokenModel
