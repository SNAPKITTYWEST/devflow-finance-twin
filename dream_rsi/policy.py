"""Executable exploration policies and bounded policy development."""

from dataclasses import dataclass, field, replace
from typing import Any, Dict, Tuple
import copy
import hashlib
import json


@dataclass(frozen=True)
class ExplorationPolicy:
    name: str = "baseline"
    branch_factor: int = 2
    max_depth: int = 3
    max_nodes: int = 8
    branch_order: str = "score_desc"
    stop_threshold: float = 0.95
    parallel_groups: int = 1
    budget: float = 8.0
    metadata: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self):
        if self.branch_factor < 1 or self.max_depth < 0 or self.max_nodes < 1:
            raise ValueError("policy limits must be positive")
        if self.parallel_groups < 1 or self.budget <= 0:
            raise ValueError("invalid policy budget")

    def decide(self, node, candidates, spent):
        """Executable policy decision; no static configuration-only shortcut."""
        if spent >= self.budget or len(candidates) == 0:
            return {"stop": True, "reason": "budget"}
        if node.metadata.get("depth", 0) >= self.max_depth:
            return {"stop": True, "reason": "depth"}
        if node.score >= self.stop_threshold:
            return {"stop": True, "reason": "threshold"}
        remaining = min(self.branch_factor, self.max_nodes - len(candidates))
        return {"stop": remaining <= 0, "branch_count": max(0, remaining),
                "order": self.branch_order, "parallel_group": self.parallel_groups}

    def fingerprint(self):
        encoded = json.dumps(self.__dict__, sort_keys=True, default=str)
        return hashlib.sha256(encoded.encode()).hexdigest()

    def mutate(self, mutation):
        values = copy.deepcopy(self.__dict__)
        values.update(mutation)
        values["name"] = values.get("name", self.name) + "*"
        return ExplorationPolicy(**values)


class PolicyDeveloper:
    """Generates bounded controller revisions, never discovery-agent revisions."""

    def __init__(self, max_candidates=4):
        self.max_candidates = max(1, int(max_candidates))

    def revise(self, policy, index=0):
        mutations = [
            {"branch_factor": min(policy.branch_factor + 1, 8)},
            {"max_depth": min(policy.max_depth + 1, 12)},
            {"branch_order": "score_asc" if policy.branch_order == "score_desc" else "score_desc"},
            {"stop_threshold": max(0.1, policy.stop_threshold - 0.05)},
        ]
        return policy.mutate(mutations[index % len(mutations)])

    def candidates(self, incumbent):
        return [self.revise(incumbent, i) for i in range(self.max_candidates)]

    @staticmethod
    def select_best(candidates):
        """The incumbent must already be present in candidates."""
        if not candidates:
            raise ValueError("candidate set cannot be empty")
        incumbent = candidates[0]
        winner = max(candidates, key=lambda pair: pair[1])
        if winner[1] < incumbent[1]:
            return incumbent
        return winner
