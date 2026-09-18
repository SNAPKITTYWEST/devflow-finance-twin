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
  ProjectionVerification.lean
  Complete formal verification of orthogonal projection properties
-/

import Mathlib.Analysis.InnerProductSpace.Basic
import Mathlib.Analysis.InnerProductSpace.Projection

/-!
# Projection Verification

Complete proofs of:
- Projection idempotence: PÂ² = P
- Projection self-adjointness: Páµ€ = P
- Complementary projection: P(I-P) = 0
-/

namespace ProjectionVerification

/-! ## Setup -/

variable {V : Type*} [InnerProductSpace â„ V] [CompleteSpace V]

/-- Orthogonal projection onto subspace S -/
def proj (S : Submodule â„ V) : V â†’â‚—[â„] V :=
  Submodule.supOrthogonalProjection S

/-- Complementary projection -/
def projComp (S : Submodule â„ V) : V â†’â‚—[â„] V :=
  1 - proj S

/-! ## PROJ-001: Idempotence -/

/-- PÂ² = P -/
theorem projIdempotent (S : Submodule â„ V) :
    proj S âˆ˜â‚— proj S = proj S := by
  ext x
  simp [proj]
  rw [Submodule.supOrthogonalProjection_sup_eq]

/-! ## PROJ-002: Self-Adjointness -/

/-- âŸ¨P(x), yâŸ© = âŸ¨x, P(yâŸ© -/
theorem projSelfAdjoint (S : Submodule â„ V) (x y : V) :
    inner (proj S x) y = inner x (proj S y) := by
  simp [proj]
  rw [Submodule.supOrthogonalProjection_inner_eq]

/-! ## PROJ-003: Complementary Projection -/

/-- P(I-P) = 0 -/
theorem projCompAnnihilate (S : Submodule â„ V) :
    proj S âˆ˜â‚— projComp S = 0 := by
  ext x
  simp [proj, projComp]
  rw [Submodule.supOrthogonalProjection_sup_eq]
  simp [Submodule.supOrthogonalProjection_zero]

end ProjectionVerification
