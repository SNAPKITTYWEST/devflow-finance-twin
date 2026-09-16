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
  Projection.lean
  Formal verification of orthogonal projection properties
  
  This file proves:
  - Projection idempotence (PÂ² = P)
  - Projection self-adjointness (Páµ€ = P)
  - Complementary projection (P Â· PâŠ¥ = 0)
  - Subspace preservation
  - Null-space characterization
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Analysis.InnerProductSpace.Projection
import Mathlib.LinearAlgebra.Prod

namespace TokenModel

/-! ## Orthogonal Projection -/

/-- Orthogonal projection onto a subspace -/
def orthogonalProjection {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) : V â†’â‚—[â„] V :=
  Submodule.supOrthogonalProjection S

/-- Complementary projection -/
def complementaryProjection {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) : V â†’â‚—[â„] V :=
  1 - orthogonalProjection S

/-! ## PROJ-001: Projection Idempotence -/

/-- Projection is idempotent: PÂ² = P -/
theorem projectionIdempotence {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) :
    orthogonalProjection S âˆ˜â‚— orthogonalProjection S = orthogonalProjection S := by
  ext x
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_sup_eq]

/-! ## PROJ-002: Projection Self-Adjointness -/

/-- Projection is self-adjoint: âŸ¨P(x), yâŸ© = âŸ¨x, P(y)âŸ© -/
theorem projectionSelfAdjoint {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) (x y : V) :
    inner (orthogonalProjection S x) y = inner x (orthogonalProjection S y) := by
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_inner_eq]

/-! ## PROJ-003: Complementary Projection -/

/-- Complementary projection annihilates: P Â· PâŠ¥ = 0 -/
theorem complementaryProjectionAnnihilation {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) :
    orthogonalProjection S âˆ˜â‚— complementaryProjection S = 0 := by
  ext x
  simp [orthogonalProjection, complementaryProjection]
  rw [Submodule.supOrthogonalProjection_sup_eq]
  simp [Submodule.supOrthogonalProjection_zero]

/-- Complementary projection orthogonality: PâŠ¥ Â· P = 0 -/
theorem complementaryProjectionOrthogonality {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) :
    complementaryProjection S âˆ˜â‚— orthogonalProjection S = 0 := by
  ext x
  simp [orthogonalProjection, complementaryProjection]
  rw [Submodule.supOrthogonalProjection_sup_eq]
  simp [Submodule.supOrthogonalProjection_zero]

/-! ## PROJ-004: Subspace Preservation -/

/-- Projection preserves the subspace: P_S(S) âŠ† S -/
theorem projectionPreservesSubspace {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) (x : V) (hx : x âˆˆ S) :
    orthogonalProjection S x âˆˆ S := by
  simp [orthogonalProjection]
  exact Submodule.supOrthogonalProjection_mem_sup x hx

/-- Projection fixes the subspace: P_S(x) = x for x âˆˆ S -/
theorem projectionFixesSubspace {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) (x : V) (hx : x âˆˆ S) :
    orthogonalProjection S x = x := by
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_eq_self]

/-! ## NULL-001: Null-Space Characterization -/

/-- Null space of projection is orthogonal complement -/
theorem projectionNullSpace {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) (x : V) :
    orthogonalProjection S x = 0 â†” x âˆˆ Sá—® := by
  simp [orthogonalProjection]
  rw [Submodule.supOrthogonalProjection_eq_zero]

/-- Complementary projection null space is S -/
theorem complementaryProjectionNullSpace {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) (x : V) :
    complementaryProjection S x = 0 â†” x âˆˆ S := by
  simp [complementaryProjection, sub_eq_zero]
  rw [projectionNullSpace]
  rw [Submodule.mem_orthogonal_singleton_iff_inner_left]
  constructor
  Â· intro h
    intro y hy
    have := h y hy
    simp at this
    exact this
  Â· intro h
    intro y hy
    simp
    exact h y hy

/-! ## NULL-002: Orthogonal Complement -/

/-- Orthogonal complement: P_S Â· PâŠ¥ = 0 -/
theorem orthogonalComplementProduct {V : Type*} [InnerProductSpace â„ V]
    [CompleteSpace V] (S : Submodule â„ V) :
    orthogonalProjection S âˆ˜â‚— complementaryProjection S = 0 :=
  complementaryProjectionAnnihilation S

end TokenModel
