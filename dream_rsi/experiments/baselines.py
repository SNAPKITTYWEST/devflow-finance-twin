"""Baseline strategies for controlled comparisons."""
from dataclasses import dataclass
from typing import Any, Dict

from ..core.orchestrator import RSIOrchestrator
from ..policy.engine import SearchPolicy


class FixedExplorationBaseline:
    name = "recursive-fixed-exploration"

    def __init__(self, orchestrator: RSIOrchestrator):
        self.orchestrator = orchestrator

    def run(self, task: str, rounds: int = 3):
        for _ in range(max(0, int(rounds))):
            world = self.orchestrator.explore_online(task)
            self.orchestrator.worlds.append(world)
        self.orchestrator.metrics.worlds = len(self.orchestrator.worlds)
        return self.orchestrator.metrics.snapshot()


class SimpleTESBaseline(FixedExplorationBaseline):
    name = "simple-tes"

    def run(self, task: str, rounds: int = 3):
        original = self.orchestrator.policy
        self.orchestrator.policy = SearchPolicy(
            name="simple-tes", max_depth=original.max_depth,
            max_nodes=original.max_nodes, branch_factor=original.branch_factor,
            budget=original.budget, stop_score=original.stop_score,
            ordering="fifo", parallel_group_size=1,
        )
        return super().run(task, rounds)
