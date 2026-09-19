"""Fixed discovery-agent boundary used only by online exploration."""
from dataclasses import dataclass
from typing import Any, Dict, Protocol
import hashlib


@dataclass(frozen=True)
class DiscoveryCandidate:
    candidate_id: str
    task: str
    branch: int
    payload: Dict[str, Any]


@dataclass(frozen=True)
class Execution:
    candidate_id: str
    output: Dict[str, Any]
    cost: float


class DiscoveryAgentProtocol(Protocol):
    name: str
    def propose(self, task: str, branch: int, parent_id: str) -> DiscoveryCandidate: ...
    def execute(self, candidate: DiscoveryCandidate) -> Execution: ...


class FixedDiscoveryAgent:
    """Deterministic stand-in for the expensive coding/discovery model."""
    name = "fixed-discovery-agent"

    def propose(self, task: str, branch: int, parent_id: str) -> DiscoveryCandidate:
        seed = f"{task}|{parent_id}|{branch}".encode()
        identifier = hashlib.sha256(seed).hexdigest()[:16]
        return DiscoveryCandidate(identifier, task, branch, {"proposal_hash": identifier})

    def execute(self, candidate: DiscoveryCandidate) -> Execution:
        return Execution(candidate.candidate_id, {
            "task": candidate.task,
            "branch": candidate.branch,
            "proposal_hash": candidate.payload["proposal_hash"],
        }, 1.0)


class DomainEvaluator(Protocol):
    name: str
    def evaluate(self, execution: Execution, task: str) -> Dict[str, Any]: ...


class AlgorithmEvaluator:
    name = "algorithm-engineering"
    def evaluate(self, execution, task):
        value = int(execution.candidate_id[:8], 16) / 0xFFFFFFFF
        return {"score": value, "valid": value >= 0.25, "domain": self.name}


class MathematicalEvaluator:
    name = "mathematical-optimization"
    def evaluate(self, execution, task):
        value = 1.0 - int(execution.candidate_id[-8:], 16) / 0xFFFFFFFF
        return {"score": value, "valid": value >= 0.25, "domain": self.name}


class GPUKernelEvaluator:
    name = "gpu-kernel-engineering"
    def evaluate(self, execution, task):
        value = int(execution.candidate_id[4:12], 16) / 0xFFFFFFFF
        return {"score": value, "valid": value >= 0.20, "domain": self.name}
