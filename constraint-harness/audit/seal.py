"""Decision seal: cryptographic digest over canonical decision record."""

from __future__ import annotations

import time
from dataclasses import dataclass, asdict
from typing import Any

from .hashing import hash_record


@dataclass
class DecisionRecord:
    execution_id: str
    request_hash: str
    result_hash: str
    axiom_results: list[dict[str, Any]]
    verification_results: list[dict[str, Any]]
    state_history: list[dict[str, Any]]
    timestamp: float
    decision: str
    seal: str = ""

    def compute_seal(self) -> str:
        payload = asdict(self)
        payload.pop("seal", None)
        self.seal = hash_record(payload)
        return self.seal


def seal_decision(
    execution_id: str,
    request_hash: str,
    result: dict[str, Any],
    axiom_results: list[dict[str, Any]],
    state_history: list[dict[str, Any]],
) -> DecisionRecord:
    rec = DecisionRecord(
        execution_id=execution_id,
        request_hash=request_hash,
        result_hash=hash_record(result),
        axiom_results=axiom_results,
        verification_results=[],
        state_history=state_history,
        timestamp=time.time(),
        decision=result.get("status", "UNKNOWN"),
    )
    rec.compute_seal()
    return rec
