"""Bounded simulation primitives for historical-world replay."""
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple

from ..tree import DiscoveryTree, TreeNode
from ..policy.engine import PolicyDecision, SearchPolicy


@dataclass(frozen=True)
class SimulationBudget:
    max_nodes: int = 128
    max_cost: float = 128.0
    max_worlds: int = 128

    def __post_init__(self):
        if self.max_nodes < 1 or self.max_cost <= 0 or self.max_worlds < 1:
            raise ValueError("simulation limits must be positive")


@dataclass
class SimulationState:
    visited_nodes: int = 0
    selected_branches: int = 0
    sparse_requests: int = 0
    cost: float = 0.0
    best_score: float = 0.0
    stop_reasons: List[str] = field(default_factory=list)

    def exhausted(self, budget: SimulationBudget) -> bool:
        return self.visited_nodes >= budget.max_nodes or self.cost >= budget.max_cost


class HistoricalWorld:
    """Validated immutable-by-convention wrapper around a discovery tree."""
    def __init__(self, tree: DiscoveryTree):
        valid, error = tree.validate()
        if not valid:
            raise ValueError(error)
        self.tree = tree

    @property
    def world_id(self):
        return self.tree.tree_id

    def root(self):
        return self.tree.get(self.tree.root_id)

    def node(self, node_id):
        return self.tree.get(node_id)


class BranchSelector:
    def select(self, children: List[TreeNode], decision: PolicyDecision) -> List[TreeNode]:
        if decision.ordering == "score_desc":
            children = sorted(children, key=lambda item: item.score, reverse=True)
        elif decision.ordering == "score_asc":
            children = sorted(children, key=lambda item: item.score)
        return children[:decision.branch_count]


class WorldSimulator:
    """Replays a world using only nodes already present in its tree."""
    def __init__(self, selector: Optional[BranchSelector] = None):
        self.selector = selector or BranchSelector()

    def run(self, policy: SearchPolicy, world: HistoricalWorld,
            budget: Optional[SimulationBudget] = None) -> SimulationState:
        budget = budget or SimulationBudget(max_nodes=policy.max_nodes, max_cost=policy.budget)
        state = SimulationState()
        frontier = [world.root()]
        while frontier and not state.exhausted(budget):
            node = frontier.pop(0)
            state.visited_nodes += 1
            state.cost += max(0.0, float(node.cost))
            state.best_score = max(state.best_score, float(node.score))
            if state.exhausted(budget):
                state.stop_reasons.append("simulation_budget")
                break
            decision = policy.decide(
                depth=int(node.metadata.get("depth", 0)),
                current_score=float(node.score),
                frontier_size=len(frontier),
                spent=state.cost,
            )
            if decision.stop:
                state.stop_reasons.append(decision.reason)
                continue
            children = [world.node(child_id) for child_id in node.children]
            if decision.branch_count > len(children):
                state.sparse_requests += decision.branch_count - len(children)
            selected = self.selector.select(children, decision)
            frontier.extend(selected)
            state.selected_branches += len(selected)
        if not frontier and not state.stop_reasons:
            state.stop_reasons.append("frontier_empty")
        return state


class SimulatorPool:
    """Accumulated historical worlds with bounded multi-world execution."""
    def __init__(self, worlds: Iterable[DiscoveryTree] = ()):
        self.worlds: List[HistoricalWorld] = []
        self.extend(worlds)

    def add(self, world):
        if isinstance(world, DiscoveryTree):
            world = HistoricalWorld(world)
        if not isinstance(world, HistoricalWorld):
            raise TypeError("world must be a DiscoveryTree or HistoricalWorld")
        self.worlds.append(world)

    def extend(self, worlds):
        for world in worlds:
            self.add(world)

    def snapshot(self):
        return tuple(self.worlds)

    def bounded(self, maximum):
        return SimulatorPool(item.tree for item in self.worlds[-maximum:])

    def __len__(self):
        return len(self.worlds)
