/-
 ========================================================================
 SOVEREIGN LEVIATHAN NODE LICENSE
 License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
 Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
 ========================================================================

 This file is a covered work under the GNU Affero General Public License,
 version 3, together with the Sovereign Leviathan additional terms.

 Hark, though this node be but a spark,
 Its covenant endureth through the dark.

 Ignorantia juris non excusat.
 ========================================================================
-/

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
variable {V : Type*} [InnerProductSpace â„ V] [FiniteDimensional â„ V]

/-- The dimension of the vector space -/
noncomputable def dim (V : Type*) [InnerProductSpace â„ V] [FiniteDimensional â„ V] : â„• :=
  FiniteDimensional.finrank â„ V

/-! ## Outer Product -/

/-- The outer product of two vectors: v âŠ— xáµ€ -/
def outerProduct {V : Type*} [InnerProductSpace â„ V] (v x : V) : V â†’â‚—[â„] V :=
  LinearMap.mk (fun y => inner x y â€¢ v) (by
    intro a b y
    simp [smul_add, inner_add_left]
  ) (by
    intro a x y
    simp [smul_comm]
  )

/-- Matrix representation of outer product -/
def outerProductMatrix {n : â„•} (v x : Fin n â†’ â„) : Matrix (Fin n) (Fin n) â„ :=
  Matrix.of (fun i j => v i * x j)

/-! ## Update Operator -/

/-- The update operator: Î”W = Î· Â· (v âŠ— xáµ€) -/
def updateOperator {V : Type*} [InnerProductSpace â„ V]
    (Î· : â„) (v x : V) : V â†’â‚—[â„] V :=
  Î· â€¢ outerProduct v x

/-- Matrix representation of update operator -/
def updateMatrix {n : â„•} (Î· : â„) (v x : Fin n â†’ â„) : Matrix (Fin n) (Fin n) â„ :=
  Î· â€¢ outerProductMatrix v x

/-! ## Activation -/

/-- The activation of input x under operator W -/
def activation {V : Type*} [InnerProductSpace â„ V]
    (W : V â†’â‚—[â„] V) (x : V) : V :=
  W x

/-- The updated activation -/
def updatedActivation {V : Type*} [InnerProductSpace â„ V]
    (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) : V :=
  (W + updateOperator Î· v x) x

/-! ## Threshold Predicate -/

/-- The threshold predicate: ThoughtFires(y, v, Î¸) âŸº âŸ¨y, vâŸ© > Î¸ -/
def thoughtFires {V : Type*} [InnerProductSpace â„ V]
    (y v : V) (Î¸ : â„) : Prop :=
  inner y v > Î¸

/-! ## Core Theorems -/

/-- AX-001: Outer product action -/
theorem outerProductAction {V : Type*} [InnerProductSpace â„ V]
    (v x : V) :
    (outerProduct v x) x = (inner x x) â€¢ v := by
  simp [outerProduct]

/-- AX-002: Update action -/
theorem updateAction {V : Type*} [InnerProductSpace â„ V]
    (Î· : â„) (v x : V) :
    (updateOperator Î· v x) x = Î· â€¢ (inner x x) â€¢ v := by
  simp [updateOperator, outerProductAction]
  rw [â† smul_assoc]

/-- ALG-001: Linearity of updated activation -/
theorem linearityOfUpdatedActivation {V : Type*} [InnerProductSpace â„ V]
    (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) :
    (W + updateOperator Î· v x) x = W x + (updateOperator Î· v x) x := by
  simp [LinearMap.add_apply]

/-- ALG-002: Projection expansion -/
theorem projectionExpansion {V : Type*} [InnerProductSpace â„ V]
    (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) :
    inner ((W + updateOperator Î· v x) x) v =
    inner (W x) v + inner ((updateOperator Î· v x) x) v := by
  rw [linearityOfUpdatedActivation, inner_add_left]

/-- ALG-003: Exact change in projection -/
theorem exactChangeInProjection {V : Type*} [InnerProductSpace â„ V]
    (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) :
    inner ((W + updateOperator Î· v x) x) v - inner (W x) v =
    Î· â€¢ (inner x x) â€¢ inner v v := by
  rw [projectionExpansion, sub_add_cancel]
  simp [updateAction, inner_smul_left, smul_eq_mul]

/-- THR-001: Sufficient condition for threshold crossing -/
theorem thresholdSufficientCondition {V : Type*} [InnerProductSpace â„ V]
    (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) (Î¸ : â„)
    (hx : x â‰  0) (hv : v â‰  0)
    (hÎ· : Î· > (Î¸ - inner (W x) v) / (inner x x * inner v v)) :
    thoughtFires ((W + updateOperator Î· v x) x) v Î¸ := by
  simp [thoughtFires, projectionExpansion]
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  calc
    inner (W x) v + inner ((updateOperator Î· v x) x) v
      = inner (W x) v + Î· â€¢ (inner x x) â€¢ inner v v := by simp [updateAction, inner_smul_left]
    _ > inner (W x) v + (Î¸ - inner (W x) v) := by
      rw [â† sub_lt_iff_lt_add']
      rw [sub_self]
      rw [zero_lt_iff_ne_zero] at hprod
      rw [smul_smul]
      exact div_lt_self_of_pos_of_pos (sub_lt_comm.mp (sub_pos.mpr (lt_of_le_of_lt (le_refl _) (by linarith)))) hprod
    _ = Î¸ := by ring

end TokenModel
