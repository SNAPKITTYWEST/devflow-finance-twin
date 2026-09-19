"""Discovery agent interface and domain adapters."""

from dataclasses import dataclass
from typing import Any, Dict
import hashlib


@dataclass
class Candidate:
    value: Dict[str, Any]
    score: float = 0.0


class DiscoveryAgent:
    """Fixed during an RSI experiment. Online calls are the expensive boundary."""
    name = "fixed-discovery-agent"

    def propose(self, task, decision, parent):
        seed = str(decision.get("branch", 0)) + ":" + str(parent.node_id)
        digest = hashlib.sha256((task + seed).encode()).hexdigest()[:12]
        return {"task": task, "branch": decision.get("branch", 0), "proposal": digest}

    def execute(self, candidate, task):
        return {"candidate": candidate, "task": task, "executed": True}


class DomainAdapter:
    name = "generic"

    def evaluate(self, candidate, task):
        raise NotImplementedError


class AlgorithmEngineering(DomainAdapter):
    name = "algorithm-engineering"

    def evaluate(self, candidate, task):
        value = int(candidate["proposal"][:4], 16) / 65535.0
        return {"score": round(value, 6), "correct": value >= 0.25, "domain": self.name}


class MathematicalOptimization(DomainAdapter):
    name = "mathematical-optimization"

    def evaluate(self, candidate, task):
        value = 1.0 - int(candidate["proposal"][-4:], 16) / 65535.0
        return {"score": round(value, 6), "feasible": value >= 0.25, "domain": self.name}


class GPUKernelEngineering(DomainAdapter):
    name = "gpu-kernel-engineering"

    def evaluate(self, candidate, task):
        value = int(candidate["proposal"][4:8], 16) / 65535.0
        return {"score": round(value, 6), "valid": value >= 0.20, "domain": self.name}
