"""Dream-RSI reconstruction package."""

from dataclasses import dataclass, asdict
from typing import Any, Dict, List, Optional

from .core import DreamRSI, RunConfig, RunMetrics, RecursiveFixedExploration, SimpleTESBaseline
from .discovery import AlgorithmEngineering, MathematicalOptimization, GPUKernelEngineering


@dataclass
class ExperimentResult:
    name: str
    metrics: Dict[str, Any]
    worlds: int
    policy: Dict[str, Any]


class ExperimentRunner:
    """Runs controlled experiments with identical task and initial policy."""

    def __init__(self, task: str, rounds: int = 3, revisions: int = 4, adapter=None):
        self.task = task
        self.config = RunConfig(task, rounds, revisions)
        self.adapter = adapter or AlgorithmEngineering()

    def run_dream_rsi(self):
        system = DreamRSI(adapter=self.adapter)
        result = system.run(self.config)
        return ExperimentResult("dream-rsi", asdict(result["metrics"]), result["worlds"], result["policy"].__dict__.copy())

    def run_fixed(self):
        system = DreamRSI(adapter=self.adapter)
        RecursiveFixedExploration(system).run(self.config)
        return ExperimentResult("recursive-fixed-exploration", asdict(system.metrics), len(system.pool.trees), system.policy.__dict__.copy())

    def run_simple_tes(self):
        system = DreamRSI(adapter=self.adapter)
        SimpleTESBaseline(system).run(self.config)
        return ExperimentResult("simple-tes", asdict(system.metrics), len(system.pool.trees), system.policy.__dict__.copy())

    def run_all(self):
        return [self.run_fixed(), self.run_simple_tes(), self.run_dream_rsi()]


def adapter_for(domain: str):
    adapters = {
        "algorithm": AlgorithmEngineering,
        "math": MathematicalOptimization,
        "gpu": GPUKernelEngineering,
    }
    factory = adapters.get(domain)
    if factory is None:
        raise ValueError(f"unknown domain: {domain}")
    return factory()
