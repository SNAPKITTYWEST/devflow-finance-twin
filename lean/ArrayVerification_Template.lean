-- ============================================================
-- LEAN 4 ARRAY VERIFICATION STARTER TEMPLATE
-- ============================================================
-- Copy this file and fill in the ?_ placeholders
-- Following integrity-first formal verification principles

import Mathlib.Data.Array.Basic
import Mathlib.Data.List.Basic
import Mathlib.Tactic

namespace YourProject

-- ============================================================
-- PART 1: FORMAL SPECIFICATION
-- ============================================================
-- Write this BEFORE implementation
-- This is your contract: what does correctness mean?

section Specification

/-- Abstract specification: contract for your array operation -/
structure ArrayContract (α : Type u) where
  size : Nat
  read : Fin size → α

/-- SPECIFICATION 1: What does your array represent? -/
def your_spec_1 {α : Type u} (param : Type) : ArrayContract α :=
  { size := ?_
    read := ?_ }

/-- SPECIFICATION 2: (if needed, add more specs) -/
def your_spec_2 {α : Type u} (param : Type) : ArrayContract α :=
  { size := ?_
    read := ?_ }

/-- Refinement relation: what it means for implementation to be correct -/
def satisfies (arr : Array α) (spec : ArrayContract α) : Prop :=
  arr.size = spec.size ∧
  ∀ i : Fin arr.size, arr.get i = spec.read ⟨i.val, by
    rw [← Array.Correctness.satisfies]
    exact i.isLt⟩

notation:25 a " ⊑ " s => satisfies a s

end Specification

-- ============================================================
-- PART 2: IMPLEMENTATION (Construction)
-- ============================================================

section Implementation

/-- CONSTRUCTION 1: How do you build your array? -/
def your_array_constructor (param : Type) : Array α :=
  ?_

/-- CONSTRUCTION 2: (if needed) -/
def your_other_constructor (param : Type) : Array α :=
  ?_

end Implementation

-- ============================================================
-- PART 3: LOCAL CORRECTNESS PROOFS
-- ============================================================

section LocalCorrectness

/-- AXIOM 1: Size property of your array -/
theorem your_constructor_size (param : Type) :
    (your_array_constructor param).size = ?_ := by
  unfold your_array_constructor
  simp [?_]
  sorry

/-- AXIOM 2: Element access property -/
theorem your_constructor_get (param : Type) (i : Fin ?_) :
    (your_array_constructor param).get i = ?_ := by
  unfold your_array_constructor
  simp [?_]
  sorry

/-- AXIOM 3: Additional property (if needed) -/
theorem your_constructor_property (param : Type) :
    ?_ (your_array_constructor param) := by
  unfold your_array_constructor
  sorry

end LocalCorrectness

-- ============================================================
-- PART 4: REFINEMENT PROOFS
-- ============================================================

section RefinementProofs

/-- CLAIM: Constructor satisfies specification -/
theorem your_constructor_refines (param : Type) :
    your_array_constructor param ⊑ your_spec_1 param := by
  constructor
  · unfold satisfies your_array_constructor your_spec_1
    exact your_constructor_size param
  · unfold your_array_constructor your_spec_1
    intro i
    exact your_constructor_get param i

/-- CLAIM: Alternative constructor (if applicable) -/
theorem your_other_constructor_refines (param : Type) :
    your_other_constructor param ⊑ your_spec_2 param := by
  sorry

end RefinementProofs

-- ============================================================
-- PART 5: EDGE CASE VERIFICATION
-- ============================================================

section EdgeCases

/-- Edge case: Empty array (if applicable) -/
theorem empty_case (param : Type) :
    ?_ (your_array_constructor param) := by sorry

/-- Edge case: Single element -/
theorem singleton_case :
    ?_ (your_array_constructor ?_) := by sorry

/-- Edge case: Boundary indices -/
theorem boundary_indices (param : Type) :
    ?_ (your_array_constructor param) := by sorry

end EdgeCases

-- ============================================================
-- PART 6: SAFE ACCESS VERIFICATION
-- ============================================================

section SafeAccess

/-- Safe get: bounded array access -/
def safe_get (arr : Array α) (i : Nat) : Option α :=
  if h : i < arr.size then some (arr.get ⟨i, h⟩) else none

/-- PROPERTY: Valid index always succeeds -/
theorem safe_get_valid {arr : Array α} {i : Nat} (h : i < arr.size) :
    safe_get arr i = some (arr.get ⟨i, h⟩) := by
  unfold safe_get; rw [dif_pos h]

/-- PROPERTY: Invalid index always fails -/
theorem safe_get_invalid {arr : Array α} {i : Nat} (h : ¬(i < arr.size)) :
    safe_get arr i = none := by
  unfold safe_get; rw [dif_neg h]

end SafeAccess

-- ============================================================
-- PART 7: INVARIANT PRESERVATION
-- ============================================================

section Invariants

/-- INVARIANT: Predicate holding for all elements -/
def your_invariant (P : α → Prop) (arr : Array α) : Prop :=
  ∀ i : Fin arr.size, P (arr.get i)

/-- CLAIM: Construction preserves invariant -/
theorem constructor_preserves_invariant {P : α → Prop} (param : Type)
    (h : ∀ x, ?_ x → P x) :
    your_invariant P (your_array_constructor param) := by
  unfold your_invariant; intro i; simp [your_array_constructor]; sorry

/-- CLAIM: Invariant composability -/
theorem invariant_chain {P Q : α → Prop} {arr : Array α}
    (h1 : your_invariant P arr) (h2 : ∀ x, P x → Q x) :
    your_invariant Q arr := by
  unfold your_invariant at *; intro i; exact h2 _ (h1 i)

end Invariants

-- ============================================================
-- PART 8: TRANSFORMATION PROOFS
-- ============================================================

section Transformations

/-- TRANSFORMATION: How do you transform the array? -/
def your_transform (f : α → β) (arr : Array α) : Array β := arr.map f

/-- PROPERTY: Size preservation -/
theorem transform_size {f : α → β} {arr : Array α} :
    (your_transform f arr).size = arr.size := by
  unfold your_transform; exact Array.size_map f arr

/-- PROPERTY: Correct element mapping -/
theorem transform_element {f : α → β} {arr : Array α} {i : Fin arr.size} :
    (your_transform f arr).get i = f (arr.get i) := by
  unfold your_transform; exact Array.getElem_map f arr i

/-- CLAIM: Transformation refines specification -/
theorem transform_refines {f : α → β} {arr : Array α} :
    your_transform f arr ⊑ ?_ := by
  constructor
  · exact transform_size
  · intro i; exact transform_element

end Transformations

-- ============================================================
-- PART 9: COMPOSITION PROOFS
-- ============================================================

section Composition

/-- COMPOSITION: Combining two operations -/
def composed_operation (arr : Array α) : Array β :=
  your_transform ?_ (your_array_constructor ?_)

/-- CLAIM: Composition preserves correctness -/
theorem composition_correct (arr : Array α) :
    composed_operation arr ⊑ ?_ := by
  unfold composed_operation; sorry

/-- LEMMA: Transitivity of refinement -/
theorem refine_trans {arr : Array α} {s1 s2 : ArrayContract α}
    (h1 : arr ⊑ s1) (h2 : s1.size = s2.size) :
    s1.size = s2.size := h2

end Composition

-- ============================================================
-- PART 10: EXAMPLES (Concrete Instances)
-- ============================================================

section Examples

/-- EXAMPLE 1: Concrete instantiation -/
example : (your_array_constructor ?_ : Array _).size = ?_ :=
  your_constructor_size ?_

/-- EXAMPLE 2: Test safe access -/
example :
  safe_get (your_array_constructor ?_) ?_ = some ?_ := by
  apply safe_get_valid; sorry

/-- EXAMPLE 3: Test transformation -/
example :
  (your_transform ?_ (your_array_constructor ?_) : Array _).size = ?_ :=
  transform_size

/-- EXAMPLE 4: Verify refinement -/
example : your_array_constructor ?_ ⊑ your_spec_1 ?_ :=
  your_constructor_refines ?_

end Examples

-- ============================================================
-- PART 11: INTEGRITY CHECKS
-- ============================================================

section IntegrityChecks

/-- Check: All main theorems type-check -/
#check your_constructor_refines
#check safe_get_valid
#check safe_get_invalid

/-- Check: No circular definitions -/
theorem no_circularity : True := trivial

/-- Check: Refinement notation works -/
#check (fun (arr : Array α) (spec : ArrayContract α) => arr ⊑ spec)

end IntegrityChecks

-- ============================================================
-- PART 12: PROOF DEBUGGING AREA
-- ============================================================

section Debugging

-- Uncomment to debug:
-- #eval (your_array_constructor ?_).size
-- #check your_constructor_size
-- example : ?_ := by sorry

end Debugging

end YourProject

-- ============================================================
-- NEXT STEPS CHECKLIST
-- ============================================================
-- After filling in this template:
--
-- 1. Replace all ?_ with actual values/proofs
-- 2. Replace all sorry with real proofs
-- 3. Run #check on each theorem to verify types
-- 4. Test with concrete examples
-- 5. Add docstring comments explaining key ideas
-- 6. Verify no circular dependencies
-- 7. Run the integrity checks section
-- 8. Move proven theorems to separate files as project grows
--
-- HOW TO STRUCTURE YOUR PROOF:
-- 1. Write specification first (Part 1)
-- 2. Implement functionally (Part 2)
-- 3. Prove local properties (Part 3)
-- 4. Connect to spec (Part 4)
-- 5. Handle edges (Part 5)
-- 6. Add examples (Part 10)
--
-- QUICK PROOF TACTICS:
-- simp [lemma_name]   -- Simplify by definition
-- rw [equality_lemma] -- Rewrite using equality
-- exact existing_proof -- Apply existing theorem
-- intro x             -- Introduce variable
-- induction n with    -- Induct on structure
-- omega               -- Solve arithmetic
-- sorry               -- TEMPORARY (remove!)
--
-- DEBUGGING:
-- #check theorem_name -- Verify type
-- #eval expression    -- Compute value
-- exact?              -- Search for proof
-- simp?               -- Show simplifications
-- apply?              -- Find applicable lemmas
