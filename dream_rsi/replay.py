"""Replay historical trees without calling the discovery agent."""

from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List
from .tree import DiscoveryTree
from .policy import ExplorationPolicy


@dataclass
class ReplayResult:
    score: float
    visited_nodes: int
    branches: int
    cost: float
    sparse_requests: int = 0
    worlds: int = 0
    details: Dict[str, Any] = field(default_factory=dict)


class SimulatorPool:
    def __init__(self, trees=None):
        self.trees: List[DiscoveryTree] = list(trees or [])

    def add(self, tree):
        valid, error = tree.validate()
        if not valid:
            raise ValueError(error)
        self.trees.append(tree)

    def __len__(self):
        return len(self.trees)


class ReplayEngine:
    """Reuses evaluator_result fields; it has no reference to DiscoveryAgent."""

    def replay(self, policy: ExplorationPolicy, pool: SimulatorPool):
        if not pool.trees:
            return ReplayResult(0.0, 0, 0, 0.0, worlds=0)
        scores = []
        visited = branches = sparse = cost = 0
        per_world = []
        for tree in pool.trees:
            result = self._replay_tree(policy, tree)
            scores.append(result.score)
            visited += result.visited_nodes
            branches += result.branches
            sparse += result.sparse_requests
            cost += result.cost
            per_world.append(result.score)
        return ReplayResult(sum(scores) / len(scores), visited, branches, cost,
                            sparse, len(pool), {"world_scores": per_world})

    def _replay_tree(self, policy, tree):
        frontier = [tree.get(tree.root_id)]
        visited = branches = sparse = 0
        total_score = 0.0
        total_cost = 0.0
        while frontier and visited < policy.max_nodes:
            node = frontier.pop(0)
            visited += 1
            total_score = max(total_score, float(node.score))
            total_cost += float(node.cost)
            decision = policy.decide(node, frontier, total_cost)
            if decision.get("stop"):
                continue
            children = [tree.get(child) for child in node.children]
            count = decision.get("branch_count", 0)
            if count > len(children):
                sparse += count - len(children)
                count = len(children)  # never invent an outcome
            if policy.branch_order == "score_desc":
                children.sort(key=lambda item: item.score, reverse=True)
            else:
                children.sort(key=lambda item: item.score)
            frontier.extend(children[:count])
            branches += count
        return ReplayResult(total_score, visited, branches, total_cost, sparse, 1)
