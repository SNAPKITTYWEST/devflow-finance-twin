"""Machine-readable audit event types."""

from __future__ import annotations

EVENT_TYPES = frozenset({
    "execution_started",
    "contract_loaded",
    "axiom_evaluated",
    "task_created",
    "task_routed",
    "task_started",
    "task_completed",
    "verification_started",
    "verification_completed",
    "revision_started",
    "state_transition",
    "execution_committed",
    "execution_failed_closed",
    "decision_sealed",
})
