import Mathlib.LinearAlgebra.Matrix.Basic
import Mathlib.Data.Matrix.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

/-!
# Formalization of the Topological Quench and Information Erasure Proof
Proves that the Quench Trigger is a non-injective projection,
making state recovery mathematically impossible (Information Erasure).
-/

-- 1. Define the State Space (Density Matrices on Fin 2)
def StateSpace := Matrix (Fin 2) (Fin 2) ℂ

-- 2. Define the Vacuum State (Target of the Quench)
noncomputable def vacuum_state : StateSpace := 0

-- 3. Define the Quench Operator
noncomputable def quench_operator (s : StateSpace) : StateSpace := vacuum_state

-- 4. Explicit distinct states to demonstrate information loss
noncomputable def state_a : StateSpace := 1
noncomputable def state_b : StateSpace := 0

have states_distinct : state_a ≠ state_b := by
  intro h
  have h_elem := congr_fun (congr_fun h 0) 0
  norm_num at h_elem

-- 5. Information Erasure Theorem (Irreversibility)
theorem quench_information_erasure :
    quench_operator state_a = quench_operator state_b := by
  unfold quench_operator
  rfl

-- 6. Proof that State Recovery is Impossible (Non-Injectivity)
theorem quench_irreversible :
    ¬ Function.Injective quench_operator := by
  intro h_inj
  apply states_distinct
  apply h_inj
  exact quench_information_erasure
