"""Replay engine with explicit multi-world and resource budgets."""
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from ..policy.engine import SearchPolicy
from ..simulator.pool import HistoricalWorld, SimulationBudget, WorldSimulator, SimulatorPool
from ..tree import DiscoveryTree


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
    budget_exhausted: bool
    details: List[WorldReplay] = field(default_factory=list)


class HistoricalReplay:
    def __init__(self, simulator=None):
        self.simulator = simulator or WorldSimulator()

    def replay(self, policy: SearchPolicy, worlds, *, max_worlds: Optional[int] = None,
               budget: Optional[SimulationBudget] = None) -> PolicyReplay:
        if isinstance(worlds, SimulatorPool):
            source = list(worlds.snapshot())
        else:
            source = list(worlds)
        if max_worlds is not None and (type(max_worlds) is not int or max_worlds < 0):
            raise ValueError("max_worlds must be a non-negative integer")
        limit = len(source) if max_worlds is None else max_worlds
        if budget is not None:
            limit = min(limit, budget.max_worlds)
        worlds_exhausted = len(source) > limit
        source = source[:limit]
        details = []
        for world in source:
            if not isinstance(world, HistoricalWorld):
                world = HistoricalWorld(world)
            result = self.simulator.run(policy, world, budget)
            details.append(WorldReplay(world.world_id, result.best_score, result.visited_nodes,
                                       result.selected_branches, result.cost,
                                       result.sparse_requests, list(result.stop_reasons)))
        if not details:
            return PolicyReplay(0.0, 0, 0, 0, 0.0, 0, worlds_exhausted, [])
        return PolicyReplay(
            score=sum(item.score for item in details) / len(details),
            worlds=len(details),
            visited=sum(item.visited for item in details),
            selected_branches=sum(item.selected_branches for item in details),
            cost=sum(item.cost for item in details),
            sparse_requests=sum(item.sparse_requests for item in details),
            budget_exhausted=worlds_exhausted or any("simulation_budget" in item.stop_reasons for item in details),
            details=details,
        )
