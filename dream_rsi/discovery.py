from dataclasses import dataclass
from typing import Any, Dict
import hashlib


@dataclass
class Candidate:
    value: Dict[str, Any]
    score: float = 0.0


class DiscoveryAgent:
    """Fixed online discovery agent. It proposes and executes, but is not mutated."""

    name = "fixed-discovery-agent"

    def propose(self, task: str, decision: Dict[str, Any], parent) -> Dict[str, Any]:
        branch = int(decision.get("branch", 0))
        seed = f"{task}:{parent.node_id}:{branch}"
        digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()[:12]
        return {"task": task, "branch": branch, "proposal": digest}

    def execute(self, candidate: Dict[str, Any], task: str) -> Dict[str, Any]:
        return {"candidate": candidate, "task": task, "executed": True}


class DomainAdapter:
    name = "generic"

    def evaluate(self, candidate: Dict[str, Any], task: str) -> Dict[str, Any]:
        raise NotImplementedError


class AlgorithmEngineering(DomainAdapter):
    name = "algorithm-engineering"

    def evaluate(self, candidate: Dict[str, Any], task: str) -> Dict[str, Any]:
        value = int(candidate["proposal"][:4], 16) / 65535.0
        result = {"score": round(value, 6), "correct": value >= 0.25, "domain": self.name}
        return result


class MathematicalOptimization(DomainAdapter):
    name = "mathematical-optimization"

    def evaluate(self, candidate: Dict[str, Any], task: str) -> Dict[str, Any]:
        value = 1.0 - int(candidate["proposal"][-4:], 16) / 65535.0
        result = {"score": round(value, 6), "feasible": value >= 0.25, "domain": self.name}
        return result


class GPUKernelEngineering(DomainAdapter):
    name = "gpu-kernel-engineering"

    def evaluate(self, candidate: Dict[str, Any], task: str) -> Dict[str, Any]:
        value = int(candidate["proposal"][4:8], 16) / 65535.0
        result = {"score": round(value, 6), "valid": value >= 0.20, "domain": self.name}
        return result
