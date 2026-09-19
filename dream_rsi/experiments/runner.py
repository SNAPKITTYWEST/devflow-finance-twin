"""Controlled runner for Dream-RSI and fixed-policy baselines."""
from dataclasses import dataclass
from typing import Any, Dict
from ..core.orchestrator import RSIOrchestrator
from ..discovery.agent import AlgorithmEvaluator
from .baselines import FixedExplorationBaseline, SimpleTESBaseline


@dataclass(frozen=True)
class ExperimentResult:
    name: str
    metrics: Dict[str, Any]


class ExperimentRunner:
    def __init__(self, task: str, rounds: int = 3, revisions: int = 4,
                 discovery=None, evaluator=None):
        self.task = task
        self.rounds = rounds
        self.revisions = revisions
        self.discovery = discovery
        self.evaluator = evaluator or AlgorithmEvaluator()

    def _board(self):
        return RSIOrchestrator(discovery=self.discovery, evaluator=self.evaluator)

    def run_dream_rsi(self):
        board = self._board()
        result = board.run(self.task, self.rounds, self.revisions)
        return ExperimentResult("dream-rsi", result["metrics"])

    def run_fixed(self):
        board = self._board()
        metrics = FixedExplorationBaseline(board).run(self.task, self.rounds)
        return ExperimentResult("recursive-fixed-exploration", metrics)

    def run_simple_tes(self):
        board = self._board()
        metrics = SimpleTESBaseline(board).run(self.task, self.rounds)
        return ExperimentResult("simple-tes", metrics)

    def run_all(self):
        return [self.run_fixed(), self.run_simple_tes(), self.run_dream_rsi()]
