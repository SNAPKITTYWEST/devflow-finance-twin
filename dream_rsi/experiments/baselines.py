"""Experiment baselines. Both use the same discovery and evaluator interfaces."""
from dataclasses import dataclass
from typing import Any
from ..core.orchestrator import RSIOrchestrator


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
