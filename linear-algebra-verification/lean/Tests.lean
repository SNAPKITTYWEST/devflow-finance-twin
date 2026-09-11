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
  Tests.lean
  Unit tests for verified theorems
-/

import LinearAlgebraVerification
import ProjectionVerification

/-!
# Tests

Concrete instantiations of verified theorems.
-/

namespace Tests

open LinearAlgebraVerification
open ProjectionVerification

/-! ## Test: â„Â¹ case -/

/-- Test outer product action on â„ -/
theorem test_outer_product_â„ :
    outerProduct (1 : â„) 1 1 = (1 : â„) := by
  simp [outerProduct, inner, smul_eq_mul]
  norm_num

/-- Test exact change on â„ -/
theorem test_exact_change_â„ :
    inner (updatedActivation (LinearMap.mul 5) 2 1 1) (1 : â„) -
    inner ((LinearMap.mul 5) 1) (1 : â„) =
    2 * (1 : â„) := by
  simp [updatedActivation, updateOperator, outerProduct, LinearMap.add_apply,
        LinearMap.mul_apply, inner, smul_eq_mul, smul_smul]
  norm_num

/-- Test existence on â„ -/
theorem test_existence_â„ :
    âˆƒ Î· > 0, inner (updatedActivation (LinearMap.mul (-100)) Î· 1 1) (1 : â„) > 0 := by
  exact existenceOfValidGain (LinearMap.mul (-100)) 1 1 0 (by norm_num) (by norm_num)

end Tests
