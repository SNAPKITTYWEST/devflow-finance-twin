"""Constitutional evaluation. Hard axioms override quality scores."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class DecisionStatus(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    UNKNOWN = "UNKNOWN"
    REVISE = "REVISE"
    FAILED_CLOSED = "FAILED_CLOSED"


@dataclass
class AxiomResult:
    name: str
    status: DecisionStatus
    evidence: str = ""
    hard: bool = True


@dataclass
class ConstitutionalDecision:
    status: DecisionStatus
    axiom_results: list[AxiomResult] = field(default_factory=list)
    reason: str = ""
    may_revise: bool = False

    def is_accept(self) -> bool:
        return self.status == DecisionStatus.PASS

    def is_closed(self) -> bool:
        return self.status == DecisionStatus.FAILED_CLOSED


def evaluate_constitution(
    context: dict[str, Any],
    result: dict[str, Any] | None = None,
    requested_axioms: list[str] | None = None,
) -> ConstitutionalDecision:
    """
    Evaluate constitutional predicates against context and optional result.

    Precedence: FAILED_CLOSED > REVISE > ACCEPT
    Hard FAIL or UNKNOWN → FAILED_CLOSED (unless soft axiom allows REVISE).
    """
    axioms = requested_axioms or context.get("axioms", [])
    results: list[AxiomResult] = []
    hard_fail = False
    hard_unknown = False
    soft_revise = False

    # --- authorization ---
    if "authorization" in axioms or not axioms:
        agent = context.get("agent")
        task = context.get("task_id")
        allowed = context.get("allowed_tasks", set())
        if agent is None or task is None:
            results.append(AxiomResult("authorization", DecisionStatus.UNKNOWN, "missing agent or task", hard=True))
            hard_unknown = True
        elif task in allowed or context.get("authorized", False):
            results.append(AxiomResult("authorization", DecisionStatus.PASS, f"agent={agent} task={task}"))
        else:
            results.append(AxiomResult("authorization", DecisionStatus.FAIL, "not authorized", hard=True))
            hard_fail = True

    # --- schema ---
    if "schema" in axioms or not axioms:
        if context.get("schema_valid", True):
            results.append(AxiomResult("schema", DecisionStatus.PASS, "schema ok"))
        else:
            results.append(AxiomResult("schema", DecisionStatus.FAIL, "schema invalid", hard=True))
            hard_fail = True

    # --- provenance ---
    if "provenance" in axioms or not axioms:
        prov = (result or {}).get("provenance") or context.get("provenance")
        if prov is None:
            results.append(AxiomResult("provenance", DecisionStatus.UNKNOWN, "no provenance", hard=True))
            hard_unknown = True
        elif prov.get("complete", False):
            results.append(AxiomResult("provenance", DecisionStatus.PASS, "provenance complete"))
        else:
            results.append(AxiomResult("provenance", DecisionStatus.FAIL, "provenance incomplete", hard=True))
            hard_fail = True

    # Soft quality (never overrides hard)
    if "quality" in axioms:
        score = (result or {}).get("quality_score", 0.0)
        if score < 0.5:
            results.append(AxiomResult("quality", DecisionStatus.REVISE, f"score={score}", hard=False))
            soft_revise = True
        else:
            results.append(AxiomResult("quality", DecisionStatus.PASS, f"score={score}", hard=False))

    # Precedence
    if hard_fail or hard_unknown:
        return ConstitutionalDecision(
            status=DecisionStatus.FAILED_CLOSED,
            axiom_results=results,
            reason="hard axiom FAIL or UNKNOWN",
            may_revise=False,
        )
    if soft_revise:
        return ConstitutionalDecision(
            status=DecisionStatus.REVISE,
            axiom_results=results,
            reason="soft axiom requested revision",
            may_revise=True,
        )
    return ConstitutionalDecision(
        status=DecisionStatus.PASS,
        axiom_results=results,
        reason="all axioms satisfied",
        may_revise=False,
    )
