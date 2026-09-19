from dataclasses import dataclass, field, replace
from typing import Any, Dict, List
import time
import math

from ..discovery.legacy import DiscoveryAgent, AlgorithmEngineering
from ..policy.legacy import ExplorationPolicy, PolicyDeveloper
from ..replay.legacy import ReplayEngine, SimulatorPool, ReplayResult
from ..tree import DiscoveryTree
from ..evaluation.protocol import validate_score


@dataclass
class RunConfig:
    task: str
    rounds: int = 3
    revisions: int = 4
    online_budget: float = 8.0

    def __post_init__(self):
        if type(self.rounds) is not int or self.rounds < 0 or type(self.revisions) is not int or self.revisions < 0:
            raise ValueError("rounds and revisions must be non-negative integers")
        if not math.isfinite(self.online_budget) or self.online_budget <= 0:
            raise ValueError("online_budget must be finite and positive")


@dataclass
class RunMetrics:
    discovery_agent_calls: int = 0
    generations: int = 0
    wall_clock_seconds: float = 0.0
    compute_budget: float = 0.0
    best_solution_score: float = 0.0
    branches: int = 0
    tree_size: int = 0
    policy_revisions: int = 0
    replay_evaluations: int = 0
    online_executions: int = 0
    offline_evaluations: int = 0
    policy_improvement: float = 0.0


class DreamRSI:
    def __init__(self, discovery=None, adapter=None, developer=None, replay=None):
        self.discovery = discovery or DiscoveryAgent()
        self.adapter = adapter or AlgorithmEngineering()
        self.developer = developer or PolicyDeveloper()
        self.replay = replay or ReplayEngine()
        self.pool = SimulatorPool()
        self.policy = ExplorationPolicy()
        self.metrics = RunMetrics()

    def online_exploration(self, policy: ExplorationPolicy, task: str) -> DiscoveryTree:
        tree = DiscoveryTree(metadata={"task": task, "policy": policy.__dict__})
        frontier = [tree.get(tree.root_id)]
        spent = 0.0

        while frontier and len(tree.nodes) - 1 < policy.max_nodes and spent < policy.budget:
            parent = frontier.pop(0)
            decision = policy.decide(parent, frontier, spent)
            if decision.get("stop"):
                parent.status = "stopped"
                continue

            for branch_index in range(int(decision.get("branch_count", 0))):
                if len(tree.nodes) - 1 >= policy.max_nodes or spent + 1 > policy.budget:
                    break
                candidate = self.discovery.propose(task, {"branch": branch_index}, parent)
                trace = self.discovery.execute(candidate, task)
                evaluated = self.adapter.evaluate(candidate, task)
                accepted = all(evaluated.get(key, True) for key in ("valid", "correct", "feasible"))
                score = validate_score(evaluated.get("score", 0.0)) if accepted else 0.0
                child = tree.add(
                    parent.node_id,
                    policy_decision=decision,
                    branch_id=str(branch_index),
                    candidate=candidate,
                    execution_trace=[trace],
                    evaluator_result=evaluated,
                    score=score,
                    status="completed",
                    cost=1.0,
                    metadata={"depth": int(parent.metadata.get("depth", 0)) + 1},
                )
                frontier.append(child)
                spent += 1.0
                self.metrics.discovery_agent_calls += 1
                self.metrics.online_executions += 1
                self.metrics.branches += 1
                if spent >= policy.budget:
                    break

        self.metrics.tree_size += len(tree.nodes)
        self.metrics.compute_budget += spent
        return tree

    def run_round(self, task: str, revisions=None):
        tree = self.online_exploration(self.policy, task)
        self.pool.add(tree)

        candidate_set = [(self.policy, self.replay.replay(self.policy, self.pool).score)]
        incumbent_score = candidate_set[0][1]
        limit = self.developer.max_candidates if revisions is None else min(revisions, self.developer.max_candidates)
        for idx in range(limit):
            candidate = self.developer.revise(self.policy, idx)
            score = self.replay.replay(candidate, self.pool).score
            candidate_set.append((candidate, score))
            self.metrics.policy_revisions += 1
            self.metrics.replay_evaluations += 1
            self.metrics.offline_evaluations += 1

        winner, score = self.developer.select_best(candidate_set)
        self.policy = winner
        self.metrics.best_solution_score = max(self.metrics.best_solution_score, score)
        self.metrics.policy_improvement += max(0.0, score - incumbent_score)
        self.metrics.generations += 1

        return {
            "policy": winner,
            "score": score,
            "candidates": [(p.name, s) for p, s in candidate_set],
            "tree": tree,
        }

    def run(self, config: RunConfig):
        started = time.perf_counter()
        self.policy = replace(self.policy, budget=config.online_budget)
        history = [self.run_round(config.task, config.revisions) for _ in range(config.rounds)]
        self.metrics.wall_clock_seconds = time.perf_counter() - started
        return {
            "history": history,
            "metrics": self.metrics,
            "worlds": len(self.pool),
            "policy": self.policy,
        }


class RecursiveFixedExploration:
    """Baseline: fixed policy with no adaptation."""

    def __init__(self, system):
        self.system = system

    def run(self, config: RunConfig):
        self.system.policy = replace(self.system.policy, budget=config.online_budget)
        for _ in range(max(0, int(config.rounds))):
            tree = self.system.online_exploration(self.system.policy, config.task)
            self.system.pool.add(tree)
        return self.system.metrics


class SimpleTESBaseline(RecursiveFixedExploration):
    """Simple fixed breadth-first style baseline."""
    pass
