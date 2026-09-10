from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class VerificationResult:
    status: str  # PASS | FAIL | UNKNOWN
    score: float = 1.0
    evidence: list[str] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def structural_check(result: dict[str, Any]) -> VerificationResult:
    vr = VerificationResult(status="PASS")
    if "status" not in result:
        vr.status = "FAIL"
        vr.failures.append("missing status field")
        vr.score = 0.0
    return vr
