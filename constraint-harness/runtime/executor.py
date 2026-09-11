# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

"""High-level execution driver wiring state machine + constitution + scheduler."""

from __future__ import annotations

import uuid
from typing import Any

from constitution import evaluate_constitution, DecisionStatus
from mxml.parser import parse_mxml, MXMLParseError
from mxml.validator import validate_mxml, ValidationError
from runtime.context import ExecutionContext
from runtime.states import State
from runtime.transitions import StateMachine, IllegalTransitionError
from scheduler.dag import build_dag, DAGError
from scheduler.scheduler import Scheduler


class Executor:
    def __init__(self) -> None:
        self.sm = StateMachine()
        self.ctx: ExecutionContext | None = None

    def run(self, mxml_source: str, *, agent: str = "default", authorized: bool = True) -> dict[str, Any]:
        eid = self.sm.execution_id
        self.ctx = ExecutionContext(execution_id=eid, agent=agent, authorized=authorized)

        try:
            # RECEIVE â†’ PARSE
            self.sm.transition(State.PARSE, reason="begin parse")
            doc = parse_mxml(mxml_source)
            validate_mxml(doc)
            self.ctx.document = doc
            self.ctx.schema_valid = True
            self.ctx.allowed_tasks = {t.id for t in doc.runtime.tasks}
            self.ctx.metadata["current_task"] = "*"

            # CONSTITUTION_CHECK
            self.sm.transition(State.CONSTITUTION_CHECK, reason="constitution")
            decision = evaluate_constitution(
                self.ctx.to_constitution_dict(),
                requested_axioms=["authorization", "schema"],
            )
            if decision.status == DecisionStatus.FAILED_CLOSED:
                self.sm.transition(State.FAILED_CLOSED, reason=decision.reason)
                return self._result("FAILED_CLOSED", decision.reason)

            # DECOMPOSE + ROUTE
            self.sm.transition(State.DECOMPOSE, reason="build dag")
            dag = build_dag(doc.runtime.tasks)
            self.sm.transition(State.ROUTE, reason="topological order")

            # DISPATCH
            self.sm.transition(State.DISPATCH, reason="schedule")
            sched = Scheduler(doc.runtime.limits.max_workers, doc.runtime.limits.timeout_seconds)
            task_results = sched.run(dag, doc.runtime)
            self.ctx.task_results = task_results

            # SUPERVISE â†’ VALIDATE
            self.sm.transition(State.SUPERVISE, reason="collect")
            self.sm.transition(State.VALIDATE, reason="verify")
            self.ctx.provenance = {
                "complete": True,
                "execution_id": eid,
                "task_count": len(task_results),
            }
            decision2 = evaluate_constitution(
                self.ctx.to_constitution_dict(),
                result={"provenance": self.ctx.provenance},
            )
            if decision2.status == DecisionStatus.FAILED_CLOSED:
                self.sm.transition(State.FAILED_CLOSED, reason=decision2.reason)
                return self._result("FAILED_CLOSED", decision2.reason)
            if decision2.status == DecisionStatus.REVISE:
                if self.sm.revision_count >= doc.runtime.limits.max_revisions:
                    self.sm.transition(State.FAILED_CLOSED, reason="max revisions exceeded")
                    return self._result("FAILED_CLOSED", "MAX_REVISIONS_EXCEEDED")
                self.sm.transition(State.REVISE, reason="soft revise")
                return self._result("REVISE", decision2.reason)

            self.sm.transition(State.CROSS_CHECK, reason="cross-check")
            self.sm.transition(State.SYNTHESIZE, reason="synthesize")
            self.sm.transition(State.FINALIZE, reason="finalize")
            self.sm.transition(State.RETURN, reason="done")
            return self._result("SUCCESS", "completed", task_results)

        except (MXMLParseError, ValidationError, DAGError, IllegalTransitionError) as exc:
            try:
                self.sm.transition(State.FAILED_CLOSED, reason=str(exc))
            except IllegalTransitionError:
                pass
            return self._result("FAILED_CLOSED", str(exc))

    def _result(self, status: str, reason: str, task_results: Any = None) -> dict[str, Any]:
        out: dict[str, Any] = {
            "status": status,
            "reason": reason,
            "execution_id": self.sm.execution_id,
            "history": [
                {"from": e.from_state, "to": e.to_state, "reason": e.reason, "ts": e.timestamp}
                for e in self.sm.history
            ],
        }
        if task_results is not None:
            out["task_results"] = task_results
        return out
