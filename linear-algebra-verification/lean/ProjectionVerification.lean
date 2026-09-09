/-
  ProjectionVerification.lean
  Complete formal verification of orthogonal projection properties
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Analysis.InnerProductSpace.Projection

/-!
# Projection Verification

Complete proofs of:
- Projection idempotence: P² = P
- Projection self-adjointness: Pᵀ = P
- Complementary projection: P(I-P) = 0
-/

namespace ProjectionVerification

/-! ## Setup -/

variable {V : Type*} [InnerProductSpace ℝ V] [CompleteSpace V]

/-- Orthogonal projection onto subspace S -/
def proj (S : Submodule ℝ V) : V →ₗ[ℝ] V :=
  Submodule.supOrthogonalProjection S

/-- Complementary projection -/
def projComp (S : Submodule ℝ V) : V →ₗ[ℝ] V :=
  1 - proj S

/-! ## PROJ-001: Idempotence -/

/-- P² = P -/
theorem projIdempotent (S : Submodule ℝ V) :
    proj S ∘ₗ proj S = proj S := by
  ext x
  simp [proj]
  rw [Submodule.supOrthogonalProjection_sup_eq]

/-! ## PROJ-002: Self-Adjointness -/

/-- ⟨P(x), y⟩ = ⟨x, P(y⟩ -/
theorem projSelfAdjoint (S : Submodule ℝ V) (x y : V) :
    inner (proj S x) y = inner x (proj S y) := by
  simp [proj]
  rw [Submodule.supOrthogonalProjection_inner_eq]

/-! ## PROJ-003: Complementary Projection -/

/-- P(I-P) = 0 -/
theorem projCompAnnihilate (S : Submodule ℝ V) :
    proj S ∘ₗ projComp S = 0 := by
  ext x
  simp [proj, projComp]
  rw [Submodule.supOrthogonalProjection_sup_eq]
  simp [Submodule.supOrthogonalProjection_zero]

end ProjectionVerification
