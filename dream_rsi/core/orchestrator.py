"""Production-style orchestrator for the online/offline RSI loop."""
from typing import Any, Dict, List
import math

from ..tree import DiscoveryTree
from ..policy.engine import PolicyDeveloper, ScoredPolicy, SearchPolicy
from ..discovery.agent import FixedDiscoveryAgent, DomainEvaluator, AlgorithmEvaluator
from ..replay.engine import HistoricalReplay
from ..metrics.collector import Metrics, Timer
from ..evaluation.protocol import validate_score


class RSIOrchestrator:
    def __init__(self, discovery=None, evaluator=None, policy=None, developer=None, replay=None):
        self.discovery = discovery or FixedDiscoveryAgent()
        self.evaluator = evaluator or AlgorithmEvaluator()
        self.policy = policy or SearchPolicy()
        self.developer = developer or PolicyDeveloper()
        self.replay = replay or HistoricalReplay()
        self.worlds: List[DiscoveryTree] = []
        self.metrics = Metrics()

    def explore_online(self, task: str) -> DiscoveryTree:
        policy = self.policy
        tree = DiscoveryTree(metadata={"task": task, "policy": policy.__dict__.copy()})
        frontier = [tree.get(tree.root_id)]
        spent = 0.0
        while frontier and len(tree.nodes) - 1 < policy.max_nodes and spent < policy.budget:
            parent = frontier.pop(0)
            decision = policy.decide(
                depth=int(parent.metadata.get("depth", 0)),
                current_score=parent.score,
                frontier_size=len(frontier),
                spent=spent,
            )
            if decision.stop:
                parent.status = "stopped"
                continue
            for branch in range(decision.branch_count):
                if len(tree.nodes) - 1 >= policy.max_nodes or spent >= policy.budget:
                    break
                candidate = self.discovery.propose(task, branch, parent.node_id)
                execution = self.discovery.execute(candidate)
                if not math.isfinite(execution.cost) or execution.cost < 0:
                    raise ValueError("execution cost must be finite and non-negative")
                if execution.cost > policy.budget - spent:
                    raise ValueError("execution cost exceeds remaining budget")
                evaluated = self.evaluator.evaluate(execution, task)
                child = tree.add(
                    parent.node_id,
                    policy_decision=decision.__dict__,
                    branch_id=str(branch),
                    candidate=candidate.__dict__,
                    execution_trace=[execution.__dict__],
                    evaluator_result=dict(evaluated),
                    score=validate_score(evaluated.get("score", 0.0)) if evaluated.get("valid", True) else 0.0,
                    status="completed",
                    cost=float(execution.cost),
                    metadata={"depth": int(parent.metadata.get("depth", 0)) + 1},
                )
                frontier.append(child)
                spent += execution.cost
                self.metrics.discovery_agent_calls += 1
                self.metrics.online_executions += 1
                self.metrics.branches += 1
                if spent >= policy.budget:
                    break
        self.metrics.tree_nodes += len(tree.nodes)
        self.metrics.compute_budget += spent
        return tree

    def run_round(self, task: str, revisions: int = None) -> Dict[str, Any]:
        tree = self.explore_online(task)
        self.worlds.append(tree)
        replayed = self.replay.replay(self.policy, self.worlds)
        incumbent = ScoredPolicy(self.policy, replayed.score, replayed.cost, replayed.worlds)
        candidates = [incumbent]
        for candidate in self.developer.generate(self.policy, revisions):
            result = self.replay.replay(candidate, self.worlds)
            candidates.append(ScoredPolicy(candidate, result.score, result.cost, result.worlds))
            self.metrics.policy_revisions += 1
            self.metrics.replay_evaluations += 1
            self.metrics.offline_evaluations += 1
        selected = self.developer.select(candidates)
        self.policy = selected.policy
        self.metrics.generations += 1
        self.metrics.worlds = len(self.worlds)
        self.metrics.best_solution_score = max(self.metrics.best_solution_score, selected.score)
        self.metrics.policy_improvement += max(0.0, selected.score - incumbent.score)
        return {"policy": selected.policy, "score": selected.score, "candidates": candidates, "tree": tree}

    def run(self, task: str, rounds: int = 3, revisions: int = 4) -> Dict[str, Any]:
        timer = Timer()
        history = [self.run_round(task, revisions) for _ in range(max(0, rounds))]
        self.metrics.wall_clock_seconds = timer.elapsed()
        return {"history": history, "metrics": self.metrics.snapshot(), "policy": self.policy, "worlds": self.worlds}
