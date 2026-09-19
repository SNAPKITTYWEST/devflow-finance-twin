"""Phase 2 and 3 failure-mode tests."""
from dream_rsi.core.orchestrator import RSIOrchestrator
from dream_rsi.policy.engine import PolicyDeveloper, ScoredPolicy, SearchPolicy
from dream_rsi.replay.engine import HistoricalReplay
from dream_rsi.simulator.pool import SimulationBudget, SimulatorPool
from dream_rsi.tree import DiscoveryTree


def test_regression_retains_incumbent():
    incumbent = SearchPolicy(name="incumbent")
    regression = incumbent.mutated(max_nodes=1)
    selected = PolicyDeveloper().select([
        ScoredPolicy(incumbent, 0.75),
        ScoredPolicy(regression, 0.20),
    ])
    assert selected.policy.fingerprint() == incumbent.fingerprint()
    assert selected.score == 0.75


def test_replay_uses_all_historical_worlds():
    board = RSIOrchestrator()
    first = board.explore_online("task one")
    second = board.explore_online("task two")
    result = HistoricalReplay().replay(board.policy, SimulatorPool([first, second]))
    assert result.worlds == 2
    assert len(result.details) == 2


def test_sparse_request_is_counted_not_invented():
    tree = DiscoveryTree()
    policy = SearchPolicy(branch_factor=4, max_nodes=8, budget=8)
    result = HistoricalReplay().replay(policy, [tree])
    assert result.sparse_requests >= 0
    assert result.visited == 1


def test_infinite_exploration_is_bounded():
    board = RSIOrchestrator()
    board.policy = SearchPolicy(max_depth=100000, max_nodes=5, budget=3)
    world = board.explore_online("never stop")
    assert len(world.nodes) <= 6
    assert board.metrics.compute_budget <= 3


def test_replay_budget_is_bounded():
    board = RSIOrchestrator()
    world = board.explore_online("bounded")
    result = HistoricalReplay().replay(
        board.policy, [world], budget=SimulationBudget(max_nodes=2, max_cost=1)
    )
    assert result.visited <= 2
    assert result.budget_exhausted or result.visited <= 1


def test_candidate_explosion_is_bounded():
    developer = PolicyDeveloper(maximum_candidates=3)
    candidates = developer.generate(SearchPolicy(), limit=100)
    assert len(candidates) == 3


def test_online_and_offline_counts_are_distinct():
    board = RSIOrchestrator()
    board.run("count calls", rounds=2, revisions=4)
    assert board.metrics.online_executions == board.metrics.discovery_agent_calls
    assert board.metrics.offline_evaluations == board.metrics.replay_evaluations
    assert board.metrics.replay_evaluations == 8


def test_policy_score_never_regresses_on_the_same_worlds():
    board = RSIOrchestrator()
    for _ in range(3):
        incumbent = board.policy
        result = board.run_round("monotonic", revisions=4)
        baseline = board.replay.replay(incumbent, board.worlds).score
        assert result["score"] >= baseline
