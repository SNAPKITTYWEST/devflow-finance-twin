"""Policy execution, mutation, validation, and incumbent-safe selection."""
from dataclasses import dataclass, replace
from typing import Any, Dict, Iterable, List, Sequence, Tuple
import copy
import hashlib
import json
import math


@dataclass(frozen=True)
class PolicyDecision:
    stop: bool
    reason: str = ""
    branch_count: int = 0
    ordering: str = "score_desc"
    parallel_group_size: int = 1
    remaining_budget: float = 0.0


@dataclass(frozen=True)
class SearchPolicy:
    """Executable exploration controller, not a passive configuration object."""
    name: str = "baseline"
    max_depth: int = 3
    max_nodes: int = 32
    branch_factor: int = 2
    budget: float = 32.0
    stop_score: float = 0.98
    ordering: str = "score_desc"
    parallel_group_size: int = 1

    def __post_init__(self):
        if any(type(value) is not int for value in (self.max_depth, self.max_nodes, self.branch_factor, self.parallel_group_size)):
            raise ValueError("search limits must be integers")
        if self.max_depth < 0 or self.max_nodes < 1 or self.branch_factor < 1:
            raise ValueError("invalid search limits")
        if not math.isfinite(self.budget) or self.budget <= 0 or not 0 <= self.stop_score <= 1 or self.parallel_group_size < 1:
            raise ValueError("invalid budget or stop score")
        if self.ordering not in ("score_desc", "score_asc", "fifo"):
            raise ValueError("unknown branch ordering")

    def decide(self, *, depth: int, current_score: float, frontier_size: int, spent: float) -> PolicyDecision:
        remaining = max(0.0, self.budget - spent)
        if remaining <= 0:
            return PolicyDecision(True, "budget", remaining_budget=remaining)
        if depth >= self.max_depth:
            return PolicyDecision(True, "depth", remaining_budget=remaining)
        if current_score >= self.stop_score:
            return PolicyDecision(True, "score", remaining_budget=remaining)
        count = min(self.branch_factor, self.max_nodes - frontier_size, int(remaining))
        if count <= 0:
            return PolicyDecision(True, "node_limit", remaining_budget=remaining)
        return PolicyDecision(False, "continue", count, self.ordering,
                              self.parallel_group_size, remaining)

    def fingerprint(self) -> str:
        payload = json.dumps(self.__dict__, sort_keys=True)
        return hashlib.sha256(payload.encode()).hexdigest()

    def mutated(self, **changes) -> "SearchPolicy":
        values = copy.deepcopy(self.__dict__)
        values.update(changes)
        values["name"] = f"{self.name}*"
        return SearchPolicy(**values)


@dataclass(frozen=True)
class ScoredPolicy:
    policy: SearchPolicy
    score: float
    cost: float = 0.0
    worlds: int = 0


class PolicyDeveloper:
    """Creates a bounded candidate set and never edits the discovery agent."""
    def __init__(self, maximum_candidates: int = 8):
        self.maximum_candidates = max(0, int(maximum_candidates))

    def generate(self, incumbent: SearchPolicy, limit: int = None) -> List[SearchPolicy]:
        if limit is not None and (type(limit) is not int or limit < 0):
            raise ValueError("revision limit must be a non-negative integer")
        limit = self.maximum_candidates if limit is None else min(limit, self.maximum_candidates)
        mutations = (
            {"branch_factor": min(8, incumbent.branch_factor + 1)},
            {"branch_factor": max(1, incumbent.branch_factor - 1)},
            {"max_depth": min(16, incumbent.max_depth + 1)},
            {"ordering": "score_asc" if incumbent.ordering == "score_desc" else "score_desc"},
            {"parallel_group_size": min(8, incumbent.parallel_group_size + 1)},
            {"stop_score": max(0.1, incumbent.stop_score - 0.05)},
            {"budget": min(256.0, incumbent.budget * 1.25)},
            {"max_nodes": min(512, incumbent.max_nodes + 8)},
        )
        return [incumbent.mutated(**mutations[i % len(mutations)]) for i in range(limit)]

    def select(self, candidates: Sequence[ScoredPolicy]) -> ScoredPolicy:
        if not candidates:
            raise ValueError("candidate set cannot be empty")
        incumbent = candidates[0]
        winner = max(candidates, key=lambda item: (item.score, -item.cost))
        return incumbent if winner.score < incumbent.score else winner
