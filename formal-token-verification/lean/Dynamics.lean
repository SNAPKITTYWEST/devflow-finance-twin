/-
  Dynamics.lean
  Formal verification of dynamical system properties
  
  This file defines and proves:
  - Discrete dynamical systems
  - Fixed points
  - Invariant sets
  - Attractors (local and global)
  - Deterministic evaluation
  - Distinction between threshold crossing and attractors
-/

import Mathlib.Topology.Basic
import Mathlib.Topology.MetricSpace.Basic

namespace TokenModel

/-! ## Discrete Dynamical System -/

/-- A discrete dynamical system -/
def DynamicalSystem (V : Type*) := V → V

/-- Iteration of a dynamical system -/
def iterate {V : Type*} (F : DynamicalSystem V) : ℕ → V → V
  | 0, z => z
  | n + 1, z => F (iterate F n z)

/-- Notation: F^t(z) -/
notation F " ^{" t "} " z => iterate F t z

/-! ## DYN-001: Deterministic Evaluation -/

/-- Deterministic evaluation: equal inputs produce equal outputs -/
theorem deterministicEvaluation {V : Type*} (F : DynamicalSystem V)
    (z₁ z₂ : V) (h : z₁ = z₂) :
    F z₁ = F z₂ := by
  rw [h]

/-- Deterministic iteration -/
theorem deterministicIteration {V : Type*} (F : DynamicalSystem V)
    (z₁ z₂ : V) (n : ℕ) (h : z₁ = z₂) :
    F^{n} z₁ = F^{n} z₂ := by
  rw [h]

/-! ## DYN-002: Fixed Points -/

/-- Fixed point definition -/
def isFixedPoint {V : Type*} (F : DynamicalSystem V) (z : V) : Prop :=
  F z = z

/-- Fixed points are invariant under iteration -/
theorem fixedPointInvariant {V : Type*} (F : DynamicalSystem V)
    (z : V) (hz : isFixedPoint F z) :
    ∀ n : ℕ, F^{n} z = z := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih =>
    simp [iterate]
    rw [ih, hz]

/-! ## DYN-003: Attractors -/

/-- Local basin of attraction -/
def localBasin {V : Type*} [TopologicalSpace V] (F : DynamicalSystem V)
    (z* : V) : Set V :=
  { z₀ : V | Filter.Tendsto (fun n => F^{n} z₀) Filter.atTop (nhds z*) }

/-- Local attractor -/
def isLocalAttractor {V : Type*} [TopologicalSpace V] (F : DynamicalSystem V)
    (z* : V) : Prop :=
  isFixedPoint F z* ∧ ∃ U : Set V, z* ∈ U ∧ IsOpen U ∧
    ∀ z₀ ∈ U, Filter.Tendsto (fun n => F^{n} z₀) Filter.atTop (nhds z*)

/-- Global attractor -/
def isGlobalAttractor {V : Type*} [TopologicalSpace V] (F : DynamicalSystem V)
    (z* : V) : Prop :=
  isFixedPoint F z* ∧ ∀ z₀ : V, Filter.Tendsto (fun n => F^{n} z₀) Filter.atTop (nhds z*)

/-! ## DYN-004: Threshold ≠ Attractor -/

/-- Threshold predicate (repeated for self-containment) -/
def thoughtFires {V : Type*} [InnerProductSpace ℝ V]
    (y v : V) (θ : ℝ) : Prop :=
  inner y v > θ

/-- Counterexample: Threshold crossing without attractor -/
theorem thresholdNotAttractor :
    ¬ (∀ {V : Type*} [InnerProductSpace ℝ V] [TopologicalSpace V]
         (F : DynamicalSystem V) (v : V) (θ : ℝ) (z₀ : V),
       thoughtFires z₀ v θ → isLocalAttractor F z₀) := by
  intro h
  -- Consider the shift operator F(z) = z + 1 on ℝ
  have := h (fun z => z + 1) (1 : ℝ) (0 : ℝ) (0.5 : ℝ)
  simp [thoughtFires, isLocalAttractor, isFixedPoint, iterate] at this
  -- 0.5 > 0 is true, but F(0.5) = 1.5 ≠ 0.5
  linarith

/-- Threshold crossing is a one-step property, not a dynamical property -/
theorem thresholdIsOneStepProperty {V : Type*} [InnerProductSpace ℝ V]
    (y v : V) (θ : ℝ) :
    thoughtFires y v θ ↔ inner y v > θ :=
  Iff.rfl

end TokenModel
