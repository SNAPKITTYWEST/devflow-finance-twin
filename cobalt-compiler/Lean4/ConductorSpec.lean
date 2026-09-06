-- Cobalt Conductor Specification
-- Formal contract for the Rust `sovereign_conductor::handler::handle_task_complete` function.
-- When Cobalt tooling is available, replace `sorry` with `exact cobalt_discharge ...`

import Lean4PolicyKernel.Policies.Core
import Lean4PolicyKernel.Policies.Governance
import Lean4PolicyKernel.Nat.Bridge

namespace Sovereign.Cobalt.ConductorSpec
open Sovereign.Policy
open Sovereign.Governance
open Sovereign.Nat

-- ── Ghost state for reasoning about Rust side effects ────────────────────────
-- Models what the Rust conductor must have published after processing a task.

structure GhostState where
  nats_outbox     : List (Subject × String)  -- (subject, payload_json)
  borrowchain_log : List (CorrelationId × String)  -- (cid, hash_hex)
  deriving Repr

/-- The Rust conductor must publish to the correct subject given a verdict.
    This is the primary routing obligation. -/
def ConductorPublishSpec (ctx : Context) (gs : GhostState) : Prop :=
  let verdict := evaluateAll ctx
  -- If verdict requires human: outbox must contain decisionPending
  (verdict.requiresHuman = true →
    ∃ payload, (Subjects.decisionPending, payload) ∈ gs.nats_outbox) ∧
  -- If verdict is final: outbox must contain bifrostCommit + borrowchain entry
  (verdict.isFinal = true →
    (∃ payload, (Subjects.bifrostCommit, payload) ∈ gs.nats_outbox) ∧
    (∃ hash, (ctx.correlation_id, hash) ∈ gs.borrowchain_log))

-- ── Proof: routing theorem for HumanGatePolicy ───────────────────────────────
-- This is the first `sorry` to discharge per Ahmad's spec.
-- It proves that when a critical task triggers HumanGatePolicy,
-- the conductor CANNOT forget to route to the human gate.

/-- Routing obligation for HumanGatePolicy on critical tasks.
    Proof: follows from humanGate_criticalTask_requiresHuman + verdict_routing_invariant. -/
theorem conductor_routes_criticalTask_to_humanGate
    (ctx : Context) (gs : GhostState)
    (hCritical : ctx.task_type ∈ criticalTasks)
    (hPublish : ConductorPublishSpec ctx gs) :
    ∃ payload, (Subjects.decisionPending, payload) ∈ gs.nats_outbox := by
  -- Step 1: HumanGatePolicy returns human_required for critical tasks
  have hGate := humanGate_criticalTask_requiresHuman ctx hCritical
  -- Step 2: evaluateAll inherits human_required because combine is priority-monotone
  have hEval : (evaluateAll ctx).requiresHuman = true := by
    simp [evaluateAll, Verdict.combine, Verdict.requiresHuman, Verdict.priority]
    simp [Policy.eval] at hGate
    simp [hGate, Verdict.requiresHuman]
  -- Step 3: ConductorPublishSpec requires the pending subject in outbox
  exact hPublish.1 hEval

/-- Routing obligation for FIB_Q: broken DID binding → reject → audit commit. -/
theorem conductor_routes_fibQ_breach_to_audit
    (ctx : Context) (gs : GhostState)
    (hMissingDid : ctx.actor ∉ ctx.evidence.signatures.map (fun (d, _) => d))
    (hNoCritical : ctx.task_type ∉ criticalTasks)
    (hPublish : ConductorPublishSpec ctx gs) :
    ∃ payload, (Subjects.bifrostCommit, payload) ∈ gs.nats_outbox := by
  -- FIB_Q rejects
  have hFibQ := fibQ_missingDid_rejects ctx hMissingDid
  -- HumanGate: not critical, need evidence check
  -- FIB_Q reject means combined verdict is reject → isFinal
  have hFinal : (evaluateAll ctx).isFinal = true := by
    simp [evaluateAll, Verdict.combine, Verdict.isFinal, Verdict.priority]
    simp [Policy.eval] at hFibQ ⊢
    simp [hNoCritical]
    -- combine of [gate_result, reject] where gate is approve/reject → isFinal
    sorry -- Discharge: case split on ctx.evidence.refs.isEmpty, both yield isFinal
  exact (hPublish.2 hFinal).1

-- ── Main theorem: The "Trust Triangle" obligation ─────────────────────────────
-- Every ctx routes to exactly one target: human gate OR audit chain.
-- No ctx is silently dropped.

theorem conductor_no_silent_drop
    (ctx : Context) (gs : GhostState)
    (hPublish : ConductorPublishSpec ctx gs) :
    (∃ payload, (Subjects.decisionPending, payload) ∈ gs.nats_outbox) ∨
    (∃ payload, (Subjects.bifrostCommit, payload) ∈ gs.nats_outbox) := by
  -- Case split on whether evaluateAll requires human or is final
  by_cases h : (evaluateAll ctx).requiresHuman = true
  · left; exact hPublish.1 h
  · right
    -- If not requiresHuman, check if isFinal
    -- evaluateAll yields approve | reject | defer | escalate — all non-human
    have hFinal : (evaluateAll ctx).isFinal = true ∨
                  (evaluateAll ctx).isFinal = false := by
      simp [Bool.eq_true_or_eq_false]
    cases hFinal with
    | inl hf => exact (hPublish.2 hf).1
    | inr _  =>
      -- defer and escalate also publish to pending
      -- These are NOT isFinal, but ConductorPublishSpec covers them via requiresHuman
      -- The conductor must handle these too — extend ConductorPublishSpec in next iteration
      sorry -- Discharge: extend spec to cover defer/escalate routing

end Sovereign.Cobalt.ConductorSpec
