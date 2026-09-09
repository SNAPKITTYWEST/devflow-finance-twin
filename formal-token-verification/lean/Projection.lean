/-
  Projection.lean
  Formal verification of orthogonal projection properties
  
  This file proves:
  - Projection idempotence (P² = P)
  - Projection self-adjointness (Pᵀ = P)
  - Complementary projection (P · P⊥ = 0)
  - Subspace preservation
  - Null-space characterization
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Analysis.InnerProductSpace.Projection
import Mathlib.LinearAlgebra.Prod

namespace TokenModel

/-! ## Orthogonal Projection -/

/-- Orthogonal projection onto a subspace -/
def orthogonalProjection {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) : V →ₗ[ℝ] V :=
  Submodule.supOrthogonalProjection S

/-- Complementary projection -/
def complementaryProjection {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) : V →ₗ[ℝ] V :=
  1 - orthogonalProjection S

/-! ## PROJ-001: Projection Idempotence -/

/-- Projection is idempotent: P² = P -/
theorem projectionIdempotence {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) :
    orthogonalProjection S ∘ₗ orthogonalProjection S = orthogonalProjection S := by
  ext x
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_sup_eq]

/-! ## PROJ-002: Projection Self-Adjointness -/

/-- Projection is self-adjoint: ⟨P(x), y⟩ = ⟨x, P(y)⟩ -/
theorem projectionSelfAdjoint {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) (x y : V) :
    inner (orthogonalProjection S x) y = inner x (orthogonalProjection S y) := by
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_inner_eq]

/-! ## PROJ-003: Complementary Projection -/

/-- Complementary projection annihilates: P · P⊥ = 0 -/
theorem complementaryProjectionAnnihilation {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) :
    orthogonalProjection S ∘ₗ complementaryProjection S = 0 := by
  ext x
  simp [orthogonalProjection, complementaryProjection]
  rw [Submodule.supOrthogonalProjection_sup_eq]
  simp [Submodule.supOrthogonalProjection_zero]

/-- Complementary projection orthogonality: P⊥ · P = 0 -/
theorem complementaryProjectionOrthogonality {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) :
    complementaryProjection S ∘ₗ orthogonalProjection S = 0 := by
  ext x
  simp [orthogonalProjection, complementaryProjection]
  rw [Submodule.supOrthogonalProjection_sup_eq]
  simp [Submodule.supOrthogonalProjection_zero]

/-! ## PROJ-004: Subspace Preservation -/

/-- Projection preserves the subspace: P_S(S) ⊆ S -/
theorem projectionPreservesSubspace {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) (x : V) (hx : x ∈ S) :
    orthogonalProjection S x ∈ S := by
  simp [orthogonalProjection]
  exact Submodule.supOrthogonalProjection_mem_sup x hx

/-- Projection fixes the subspace: P_S(x) = x for x ∈ S -/
theorem projectionFixesSubspace {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) (x : V) (hx : x ∈ S) :
    orthogonalProjection S x = x := by
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_eq_self]

/-! ## NULL-001: Null-Space Characterization -/

/-- Null space of projection is orthogonal complement -/
theorem projectionNullSpace {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) (x : V) :
    orthogonalProjection S x = 0 ↔ x ∈ Sᗮ := by
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_eq_zero]

/-- Complementary projection null space is S -/
theorem complementaryProjectionNullSpace {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) (x : V) :
    complementaryProjection S x = 0 ↔ x ∈ S := by
  simp [complementaryProjection, sub_eq_zero]
  rw [projectionNullSpace]
  rw [Submodule.mem_orthogonal_singleton_iff_inner_left]
  constructor
  · intro h
    intro y hy
    have := h y hy
    simp at this
    exact this
  · intro h
    intro y hy
    simp
    exact h y hy

/-! ## NULL-002: Orthogonal Complement -/

/-- Orthogonal complement: P_S · P⊥ = 0 -/
theorem orthogonalComplementProduct {V : Type*} [InnerProductSpace ℝ V]
    [CompleteSpace V] (S : Submodule ℝ V) :
    orthogonalProjection S ∘ₗ complementaryProjection S = 0 :=
  complementaryProjectionAnnihilation S

end TokenModel
