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

variable {V : Type*} [InnerProductSpace â„ V]

/-! ## Outer Product Definition -/

/-- The outer product of vectors v and x: (v âŠ— xáµ€)(y) = âŸ¨x,yâŸ© Â· v -/
def outerProduct (v x : V) : V â†’â‚—[â„] V :=
  LinearMap.mk (fun y => inner x y â€¢ v)
    (fun a b y => by simp [smul_add, inner_add_left])
    (fun a x y => by simp [smul_comm])

/-! ## ALG-001: Outer Product Action -/

/-- (v âŠ— xáµ€)x = â€–xâ€–Â² Â· v -/
theorem outerProductAction (v x : V) :
    outerProduct v x x = inner x x â€¢ v := by
  simp [outerProduct]

/-! ## Update Operator -/

/-- Î”W = Î· Â· (v âŠ— xáµ€) -/
def updateOperator (Î· : â„) (v x : V) : V â†’â‚—[â„] V :=
  Î· â€¢ outerProduct v x

/-- Updated activation: (W + Î”W)x -/
def updatedActivation (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) : V :=
  (W + updateOperator Î· v x) x

/-! ## ALG-002: Linearity -/

/-- (W + Î”W)x = Wx + Î”Wx -/
theorem linearity (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) :
    updatedActivation W Î· v x = W x + updateOperator Î· v x x := by
  simp [updatedActivation, LinearMap.add_apply]

/-! ## ALG-003: Inner Product Expansion -/

/-- âŸ¨(W + Î”W)x, vâŸ© = âŸ¨Wx, vâŸ© + âŸ¨Î”Wx, vâŸ© -/
theorem innerProductExpansion (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) :
    inner (updatedActivation W Î· v x) v =
    inner (W x) v + inner (updateOperator Î· v x x) v := by
  rw [linearity, inner_add_left]

/-! ## ALG-004: Exact Change in Projection -/

/-- âŸ¨(W + Î”W)x, vâŸ© - âŸ¨Wx, vâŸ© = Î· Â· â€–xâ€–Â² Â· â€–vâ€–Â² -/
theorem exactChangeInProjection (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) :
    inner (updatedActivation W Î· v x) v - inner (W x) v =
    Î· â€¢ inner x x â€¢ inner v v := by
  rw [innerProductExpansion, updateOperator, outerProductAction]
  simp [inner_smul_left, smul_smul]

/-! ## THR-001: Sufficient Condition -/

/-- Î· > (Î¸ - âŸ¨Wx,vâŸ©)/(â€–xâ€–Â²Â·â€–vâ€–Â²) implies threshold crossing -/
theorem thresholdSufficient (W : V â†’â‚—[â„] V) (Î· : V â†’â‚—[â„] V â†’ â„) (v x : V) (Î¸ : â„)
    (hx : x â‰  0) (hv : v â‰  0)
    (hÎ· : Î· W v x > (Î¸ - inner (W x) v) / (inner x x * inner v v)) :
    inner (updatedActivation W (Î· W v x) v x) v > Î¸ := by
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  rw [exactChangeInProjection]
  have : inner (updatedActivation W (Î· W v x) v x) v =
         inner (W x) v + (Î· W v x) â€¢ inner x x â€¢ inner v v := by
    simp [updatedActivation, updateOperator, LinearMap.add_apply,
          inner_add_left, outerProductAction, inner_smul_left, smul_smul]
  rw [this, sub_add_cancel]
  rw [â† sub_lt_iff_lt_add']
  rw [â† div_lt_iff hprod] at hÎ·
  linarith

/-! ## THR-002: Existence of Valid Gain -/

/-- For any finite Î¸ and nonzero x,v, there exists Î· > 0 achieving threshold -/
theorem existenceOfValidGain (W : V â†’â‚—[â„] V) (v x : V) (Î¸ : â„)
    (hx : x â‰  0) (hv : v â‰  0) :
    âˆƒ Î· > 0, inner (updatedActivation W Î· v x) v > Î¸ := by
  refine âŸ¨(Î¸ - inner (W x) v + 1) / (inner x x * inner v v), ?_, ?_âŸ©
  Â· have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    positivity
  Â· have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    rw [exactChangeInProjection]
    have : inner (updatedActivation W ((Î¸ - inner (W x) v + 1) / (inner x x * inner v v)) v x) v =
           inner (W x) v + ((Î¸ - inner (W x) v + 1) / (inner x x * inner v v)) â€¢ inner x x â€¢ inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply,
            inner_add_left, outerProductAction, inner_smul_left, smul_smul]
    rw [this]
    field_simp
    linarith

/-! ## Arbitrary Margin -/

/-- For any Îµ > 0, there exists Î· > 0 achieving margin Î¸ + Îµ -/
theorem arbitraryMargin (W : V â†’â‚—[â„] V) (v x : V) (Î¸ Îµ : â„)
    (hx : x â‰  0) (hv : v â‰  0) (hÎµ : Îµ > 0) :
    âˆƒ Î· > 0, inner (updatedActivation W Î· v x) v > Î¸ + Îµ := by
  refine âŸ¨(Î¸ + Îµ - inner (W x) v + 1) / (inner x x * inner v v), ?_, ?_âŸ©
  Â· have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    positivity
  Â· have hxi : inner x x > 0 := inner_self_pos.mpr hx
    have hvi : inner v v > 0 := inner_self_pos.mpr hv
    have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
    rw [exactChangeInProjection]
    have : inner (updatedActivation W ((Î¸ + Îµ - inner (W x) v + 1) / (inner x x * inner v v)) v x) v =
           inner (W x) v + ((Î¸ + Îµ - inner (W x) v + 1) / (inner x x * inner v v)) â€¢ inner x x â€¢ inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply,
            inner_add_left, outerProductAction, inner_smul_left, smul_smul]
    rw [this]
    field_simp
    linarith

end LinearAlgebraVerification
