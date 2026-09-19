"""Metrics that keep online executions separate from offline replay."""
from dataclasses import asdict, dataclass
from typing import Dict
import time


@dataclass
class Metrics:
    discovery_agent_calls: int = 0
    online_executions: int = 0
    offline_evaluations: int = 0
    replay_evaluations: int = 0
    policy_revisions: int = 0
    generations: int = 0
    branches: int = 0
    tree_nodes: int = 0
    worlds: int = 0
    compute_budget: float = 0.0
    best_solution_score: float = 0.0
    policy_improvement: float = 0.0
    wall_clock_seconds: float = 0.0

    def snapshot(self) -> Dict[str, object]:
        return asdict(self)


class Timer:
    def __init__(self):
        self.started = time.perf_counter()

    def elapsed(self) -> float:
        return time.perf_counter() - self.started
