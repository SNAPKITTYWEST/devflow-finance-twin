from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

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
    def __init__(self, trees: Optional[List[DiscoveryTree]] = None):
        self.trees: List[DiscoveryTree] = list(trees or [])

    def add(self, tree: DiscoveryTree):
        valid, reason = tree.validate()
        if not valid:
            raise ValueError(reason)
        self.trees.append(tree)

    def __len__(self) -> int:
        return len(self.trees)


class ReplayEngine:
    """Readable offline replayer: no live discovery-agent calls."""

    def replay(self, policy: ExplorationPolicy, pool: SimulatorPool) -> ReplayResult:
        if not pool.trees:
            return ReplayResult(0.0, 0, 0, 0.0, worlds=0)

        world_scores = []
        visited_nodes = 0
        branches = 0
        cost = 0.0
        sparse = 0

        for tree in pool.trees:
            value = self._replay_tree(policy, tree)
            world_scores.append(value["score"])
            visited_nodes += value["visited_nodes"]
            branches += value["branches"]
            cost += value["cost"]
            sparse += value["sparse_requests"]

        score = sum(world_scores) / len(world_scores)
        return ReplayResult(score, visited_nodes, branches, cost, sparse, len(pool.trees), {"world_scores": world_scores})

    def _replay_tree(self, policy: ExplorationPolicy, tree: DiscoveryTree) -> Dict[str, Any]:
        frontier = [tree.get(tree.root_id)]
        visited = 0
        branch_count = 0
        total_cost = 0.0
        sparse = 0
        best = 0.0

        while frontier and visited < policy.max_nodes:
            node = frontier.pop(0)
            visited += 1
            best = max(best, float(node.score))
            total_cost += float(node.cost)
            decision = policy.decide(node, frontier, total_cost)
            if decision.get("stop"):
                continue

            children = [tree.get(child_id) for child_id in node.children]
            requested = int(decision.get("branch_count", 0))
            if requested > len(children):
                sparse += requested - len(children)
                requested = len(children)
            if requested <= 0:
                continue

            if policy.branch_order == "score_desc":
                children.sort(key=lambda item: item.score, reverse=True)
            else:
                children.sort(key=lambda item: item.score)

            frontier.extend(children[:requested])
            branch_count += requested

        return {
            "score": best,
            "visited_nodes": visited,
            "branches": branch_count,
            "cost": total_cost,
            "sparse_requests": sparse,
        }
