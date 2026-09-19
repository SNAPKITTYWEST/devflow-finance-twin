"""Tests for the full direct implementation layers."""
from dream_rsi.core.orchestrator import RSIOrchestrator
from dream_rsi.discovery.agent import AlgorithmEvaluator, FixedDiscoveryAgent
from dream_rsi.metrics.collector import Metrics
from dream_rsi.policy.engine import PolicyDeveloper, ScoredPolicy, SearchPolicy
from dream_rsi.replay.engine import HistoricalReplay


def test_incumbent_guarantee_with_regression():
    policy = SearchPolicy()
    worse = policy.mutated(max_nodes=1)
    chosen = PolicyDeveloper().select([ScoredPolicy(policy, .8), ScoredPolicy(worse, .2)])
    assert chosen.policy.fingerprint() == policy.fingerprint()
    assert chosen.score == .8


def test_online_and_offline_are_distinct():
    board = RSIOrchestrator()
    board.run("design an algorithm", rounds=2, revisions=3)
    assert board.metrics.discovery_agent_calls == board.metrics.online_executions
    assert board.metrics.offline_evaluations == board.metrics.replay_evaluations
    # Replay counts revisions; online counts executed branches. Neither must dominate.
    assert board.metrics.offline_evaluations == 2 * 3
    assert board.metrics.discovery_agent_calls > 0


def test_replay_never_requires_discovery_agent():
    board = RSIOrchestrator()
    world = board.explore_online("a task")
    replay = HistoricalReplay().replay(board.policy, [world])
    assert replay.worlds == 1
    assert replay.visited > 0


def test_historical_worlds_accumulate():
    result = RSIOrchestrator().run("same task", rounds=3, revisions=1)
    assert len(result["worlds"]) == 3
    assert result["metrics"]["worlds"] == 3
