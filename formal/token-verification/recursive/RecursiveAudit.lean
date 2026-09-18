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
  RecursiveAudit.lean
  Recursive counterproof of previous verification conclusions
  
  This file establishes:
  - THEOREM-A: Î· > 0 alone is insufficient (counterexample)
  - THEOREM-B: Î· > Î·_critical is sufficient
  - THEOREM-C: Î· > Î·_critical is necessary and sufficient
  - THEOREM-D: Existence of valid gain
  - THEOREM-E: Valid gains form an open ray
  - THEOREM-F: Arbitrary margin achievable
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Data.Real.Basic

namespace RecursiveAudit

/-! ## Setup -/

variable {V : Type*} [InnerProductSpace â„ V] [FiniteDimensional â„ V]

/-- The update operator: Î”W = Î· Â· (v âŠ— xáµ€) -/
def updateOperator (Î· : â„) (v x : V) : V â†’â‚—[â„] V :=
  Î· â€¢ (LinearMap.mk (fun y => inner x y â€¢ v) (by simp [smul_add, inner_add_left]) (by simp [smul_comm]))

/-- The updated activation -/
def updatedActivation (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) : V :=
  (W + updateOperator Î· v x) x

/-- Critical gain -/
def criticalGain (W : V â†’â‚—[â„] V) (v x : V) (Î¸ : â„) : â„ :=
  (Î¸ - inner (W x) v) / (inner x x * inner v v)

/-! ## Core Identity: ALG-003 -/

/-- Exact change in projection -/
theorem exactChangeInProjection (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) :
    inner (updatedActivation W Î· v x) v - inner (W x) v =
    Î· â€¢ (inner x x) â€¢ inner v v := by
  simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left]
  rw [inner_smul_left, inner_smul_left, smul_smul]

/-! ## THEOREM-A: Î· > 0 Alone Is Insufficient -/

/-- THEOREM-A: There exist W, x, v, Î¸ where Î· > 0 but threshold not crossed -/
theorem etaPositiveInsufficient :
    âˆƒ (W : â„ â†’â‚—[â„] â„) (x v : â„) (Î¸ Î· : â„),
      Î· > 0 âˆ§ inner (updatedActivation W Î· v x) v â‰¤ Î¸ := by
  -- W = -100, x = 1, v = 1, Î¸ = 0, Î· = 1
  refine âŸ¨LinearMap.mul (-100), 1, 1, 0, 1, by norm_num, ?_âŸ©
  simp [updatedActivation, updateOperator, inner, LinearMap.mul_apply]
  norm_num

/-! ## THEOREM-B: Î· > Î·_critical Is Sufficient -/

/-- THEOREM-B: When Î· > Î·_critical, threshold is crossed -/
theorem sufficientCondition (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) (Î¸ : â„)
    (hx : x â‰  0) (hv : v â‰  0)
    (hÎ· : Î· > criticalGain W v x Î¸) :
    inner (updatedActivation W Î· v x) v > Î¸ := by
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  simp only [criticalGain] at hÎ·
  rw [exactChangeInProjection]
  have : inner (updatedActivation W Î· v x) v = inner (W x) v + Î· â€¢ (inner x x) â€¢ inner v v := by
    simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul]
  rw [this]
  rw [â† sub_lt_iff_lt_add']
  have : Î· â€¢ (inner x x) â€¢ inner v v = Î· * inner x x * inner v v := by ring
  rw [this]
  rw [â† div_lt_iff hprod] at hÎ·
  linarith

/-! ## THEOREM-C: Necessary and Sufficient Condition -/

/-- THEOREM-C (â‡’): If threshold crossed, then Î· > Î·_critical -/
theorem necessaryCondition (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) (Î¸ : â„)
    (hx : x â‰  0) (hv : v â‰  0)
    (hcross : inner (updatedActivation W Î· v x) v > Î¸) :
    Î· > criticalGain W v x Î¸ := by
  have hxi : inner x x > 0 := inner_self_pos.mpr hx
  have hvi : inner v v > 0 := inner_self_pos.mpr hv
  have hprod : inner x x * inner v v > 0 := mul_pos hxi hvi
  simp only [criticalGain]
  rw [exactChangeInProjection] at hcross
  have : inner (updatedActivation W Î· v x) v = inner (W x) v + Î· * inner x x * inner v v := by
    simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul, smul_eq_mul]
  rw [this] at hcross
  rw [â† div_lt_iff hprod]
  linarith

/-! ## THEOREM-D: Existence of Valid Gain -/

/-- THEOREM-D: For every finite Î¸ and nonzero x,v, a positive Î· exists -/
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
           inner (W x) v + ((Î¸ - inner (W x) v + 1) / (inner x x * inner v v)) * inner x x * inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul, smul_eq_mul]
    rw [this]
    field_simp
    linarith

/-! ## THEOREM-E: Valid Gains Form an Open Ray -/

/-- THEOREM-E: The set of valid gains is (Î·_critical, âˆž) -/
theorem validGainsOpenRay (W : V â†’â‚—[â„] V) (Î· : â„) (v x : V) (Î¸ : â„)
    (hx : x â‰  0) (hv : v â‰  0) :
    (inner (updatedActivation W Î· v x) v > Î¸) â†” (Î· > criticalGain W v x Î¸) := by
  constructor
  Â· intro h
    exact necessaryCondition W Î· v x Î¸ hx hv h
  Â· intro h
    exact sufficientCondition W Î· v x Î¸ hx hv h

/-! ## THEOREM-F: Arbitrary Margin Achievable -/

/-- THEOREM-F: For any Îµ > 0, there exists Î· achieving margin Îµ -/
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
           inner (W x) v + ((Î¸ + Îµ - inner (W x) v + 1) / (inner x x * inner v v)) * inner x x * inner v v := by
      simp [updatedActivation, updateOperator, LinearMap.add_apply, inner_add_left, inner_smul_left, smul_smul, smul_eq_mul]
    rw [this]
    field_simp
    linarith

end RecursiveAudit
