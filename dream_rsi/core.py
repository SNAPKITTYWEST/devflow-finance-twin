from dataclasses import dataclass, field
from typing import Any, Dict, List
import time

from .discovery import DiscoveryAgent, AlgorithmEngineering
from .policy import ExplorationPolicy, PolicyDeveloper
from .replay import ReplayEngine, SimulatorPool, ReplayResult
from .tree import DiscoveryTree


@dataclass
class RunConfig:
    task: str
    rounds: int = 3
    revisions: int = 4
    online_budget: float = 8.0


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
                candidate = self.discovery.propose(task, {"branch": branch_index}, parent)
                trace = self.discovery.execute(candidate, task)
                evaluated = self.adapter.evaluate(candidate, task)
                score = float(evaluated.get("score", 0.0))
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

    def run_round(self, task: str):
        incumbent_score = self.replay.replay(self.policy, self.pool).score if self.pool.trees else 0.0
        tree = self.online_exploration(self.policy, task)
        self.pool.add(tree)

        candidate_set = [(self.policy, self.replay.replay(self.policy, self.pool).score)]
        for idx in range(self.developer.max_candidates):
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
        started = time.time()
        history = [self.run_round(config.task) for _ in range(max(0, int(config.rounds)))]
        self.metrics.wall_clock_seconds = time.time() - started
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
        for _ in range(max(0, int(config.rounds))):
            tree = self.system.online_exploration(self.system.policy, config.task)
            self.system.pool.add(tree)
        return self.system.metrics


class SimpleTESBaseline(RecursiveFixedExploration):
    """Simple fixed breadth-first style baseline."""
    pass
