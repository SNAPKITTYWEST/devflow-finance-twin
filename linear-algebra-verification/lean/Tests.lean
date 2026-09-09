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

/-! ## Test: ℝ¹ case -/

/-- Test outer product action on ℝ -/
theorem test_outer_product_ℝ :
    outerProduct (1 : ℝ) 1 1 = (1 : ℝ) := by
  simp [outerProduct, inner, smul_eq_mul]
  norm_num

/-- Test exact change on ℝ -/
theorem test_exact_change_ℝ :
    inner (updatedActivation (LinearMap.mul 5) 2 1 1) (1 : ℝ) -
    inner ((LinearMap.mul 5) 1) (1 : ℝ) =
    2 * (1 : ℝ) := by
  simp [updatedActivation, updateOperator, outerProduct, LinearMap.add_apply,
        LinearMap.mul_apply, inner, smul_eq_mul, smul_smul]
  norm_num

/-- Test existence on ℝ -/
theorem test_existence_ℝ :
    ∃ η > 0, inner (updatedActivation (LinearMap.mul (-100)) η 1 1) (1 : ℝ) > 0 := by
  exact existenceOfValidGain (LinearMap.mul (-100)) 1 1 0 (by norm_num) (by norm_num)

end Tests
