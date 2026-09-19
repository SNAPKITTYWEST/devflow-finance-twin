"""Replay semantics: recorded outcomes only, never live discovery calls."""
from dataclasses import dataclass, field
from typing import Any, Dict, List

from ..tree import DiscoveryTree, TreeNode
from ..policy.engine import SearchPolicy


@dataclass(frozen=True)
class WorldReplay:
    world_id: str
    score: float
    visited: int
    selected_branches: int
    cost: float
    sparse_requests: int
    stop_reasons: List[str] = field(default_factory=list)


@dataclass(frozen=True)
class PolicyReplay:
    score: float
    worlds: int
    visited: int
    selected_branches: int
    cost: float
    sparse_requests: int
    details: List[WorldReplay] = field(default_factory=list)


class HistoricalReplay:
    def replay(self, policy: SearchPolicy, worlds: List[DiscoveryTree]) -> PolicyReplay:
        details = [self.replay_world(policy, world) for world in worlds]
        if not details:
            return PolicyReplay(0.0, 0, 0, 0, 0.0, 0, [])
        return PolicyReplay(
            sum(item.score for item in details) / len(details),
            len(details),
            sum(item.visited for item in details),
            sum(item.selected_branches for item in details),
            sum(item.cost for item in details),
            sum(item.sparse_requests for item in details),
            details,
        )

    def replay_world(self, policy: SearchPolicy, world: DiscoveryTree) -> WorldReplay:
        frontier = [world.get(world.root_id)]
        visited = selected = sparse = 0
        spent = 0.0
        best = 0.0
        reasons = []
        while frontier and visited < policy.max_nodes and spent < policy.budget:
            node = frontier.pop(0)
            visited += 1
            best = max(best, float(node.score))
            spent += float(node.cost)
            decision = policy.decide(
                depth=int(node.metadata.get("depth", 0)),
                current_score=float(node.score),
                frontier_size=len(frontier),
                spent=spent,
            )
            if decision.stop:
                reasons.append(decision.reason)
                continue
            children = [world.get(identifier) for identifier in node.children]
            requested = decision.branch_count
            if requested > len(children):
                sparse += requested - len(children)
                requested = len(children)
            if decision.ordering == "score_desc":
                children.sort(key=lambda child: child.score, reverse=True)
            elif decision.ordering == "score_asc":
                children.sort(key=lambda child: child.score)
            frontier.extend(children[:requested])
            selected += requested
        return WorldReplay(world.tree_id, best, visited, selected, spent, sparse, reasons)
