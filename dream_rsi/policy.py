from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Tuple
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
        if self.branch_factor < 1:
            raise ValueError("branch_factor must be >= 1")
        if self.max_depth < 0:
            raise ValueError("max_depth must be >= 0")
        if self.max_nodes < 1:
            raise ValueError("max_nodes must be >= 1")
        if self.parallel_groups < 1:
            raise ValueError("parallel_groups must be >= 1")
        if self.budget <= 0:
            raise ValueError("budget must be > 0")

    def decide(self, node, frontier, spent: float) -> Dict[str, Any]:
        """Executable policy logic; it decides when to branch and stop."""
        depth = int(node.metadata.get("depth", 0))
        if spent >= self.budget:
            return {"stop": True, "reason": "budget"}
        if depth >= self.max_depth:
            return {"stop": True, "reason": "depth"}
        if node.score >= self.stop_threshold:
            return {"stop": True, "reason": "threshold"}
        branches = min(self.branch_factor, max(0, self.max_nodes - len(frontier)))
        return {
            "stop": branches <= 0,
            "branch_count": max(0, branches),
            "order": self.branch_order,
            "parallel_group": self.parallel_groups,
            "budget": self.budget,
        }

    def fingerprint(self) -> str:
        payload = json.dumps(self.__dict__, sort_keys=True, default=str)
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def mutate(self, update: Dict[str, Any]) -> "ExplorationPolicy":
        values = copy.deepcopy(self.__dict__)
        values.update(update)
        values["name"] = values.get("name", self.name) + "*"
        return ExplorationPolicy(**values)


class PolicyDeveloper:
    """Produces candidate policy revisions while the discovery agent stays fixed."""

    def __init__(self, max_candidates: int = 4):
        self.max_candidates = max(1, int(max_candidates))

    def revise(self, policy: ExplorationPolicy, index: int = 0) -> ExplorationPolicy:
        updates = [
            {"branch_factor": min(policy.branch_factor + 1, 8)},
            {"max_depth": min(policy.max_depth + 1, 12)},
            {"branch_order": "score_asc" if policy.branch_order == "score_desc" else "score_desc"},
            {"stop_threshold": max(0.10, policy.stop_threshold - 0.05)},
            {"parallel_groups": min(policy.parallel_groups + 1, 4)},
        ]
        chosen = updates[index % len(updates)]
        return policy.mutate(chosen)

    def candidates(self, policy: ExplorationPolicy) -> List[ExplorationPolicy]:
        return [self.revise(policy, i) for i in range(self.max_candidates)]

    @staticmethod
    def select_best(candidates: Iterable[Tuple[ExplorationPolicy, float]]):
        if not candidates:
            raise ValueError("candidate set cannot be empty")
        items = list(candidates)
        incumbent = items[0]
        best = max(items, key=lambda pair: pair[1])
        if best[1] < incumbent[1]:
            return incumbent
        return best
