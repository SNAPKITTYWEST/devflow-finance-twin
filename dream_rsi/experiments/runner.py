"""Integration runner for all domains and baseline comparisons."""
from dataclasses import dataclass
from typing import Any, Dict

from ..core.orchestrator import RSIOrchestrator
from ..discovery.agent import AlgorithmEvaluator, FixedDiscoveryAgent, GPUKernelEvaluator, MathematicalEvaluator
from .baselines import FixedExplorationBaseline, SimpleTESBaseline


@dataclass(frozen=True)
class ExperimentResult:
    name: str
    domain: str
    metrics: Dict[str, Any]


class ExperimentRunner:
    def __init__(self, task, rounds=3, revisions=4, domain="algorithm", discovery=None):
        self.task = task
        self.rounds = rounds
        self.revisions = revisions
        self.domain = domain
        self.discovery = discovery or FixedDiscoveryAgent()

    def evaluator(self):
        values = {
            "algorithm": AlgorithmEvaluator,
            "math": MathematicalEvaluator,
            "gpu": GPUKernelEvaluator,
        }
        if self.domain not in values:
            raise ValueError(f"unknown domain: {self.domain}")
        return values[self.domain]()

    def board(self):
        return RSIOrchestrator(discovery=self.discovery, evaluator=self.evaluator())

    def run_dream_rsi(self):
        board = self.board()
        result = board.run(self.task, self.rounds, self.revisions)
        return ExperimentResult("dream-rsi", self.domain, result["metrics"])

    def run_fixed(self):
        board = self.board()
        metrics = FixedExplorationBaseline(board).run(self.task, self.rounds)
        return ExperimentResult("recursive-fixed-exploration", self.domain, metrics)

    def run_simple_tes(self):
        board = self.board()
        metrics = SimpleTESBaseline(board).run(self.task, self.rounds)
        return ExperimentResult("simple-tes", self.domain, metrics)

    def run_all(self):
        return [self.run_fixed(), self.run_simple_tes(), self.run_dream_rsi()]
