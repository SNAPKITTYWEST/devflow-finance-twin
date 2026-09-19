"""Regression coverage for the repaired RSI audit defects."""
import importlib
import math

import pytest

from dream_rsi import DreamRSI, RunConfig, RSIOrchestrator, SearchPolicy, HistoricalReplay, SimulationBudget, SimulatorPool
from dream_rsi.tree import DiscoveryTree, TreeNode


@pytest.mark.parametrize("name", ["core", "discovery", "evaluation", "experiments", "metrics", "persistence", "policy", "replay"])
def test_both_implementation_generations_import(name):
    importlib.import_module("dream_rsi." + name)
    importlib.import_module("dream_rsi." + name + ".legacy")


def test_empty_replay_and_zero_rounds():
    assert HistoricalReplay().replay(SearchPolicy(), []).worlds == 0
    board = RSIOrchestrator()
    assert board.run("empty", rounds=0)["worlds"] == []
    assert board.metrics.discovery_agent_calls == 0


def test_replay_does_not_execute_discovery():
    board = RSIOrchestrator()
    world = board.explore_online("audit")
    class ForbiddenDiscovery:
        def __getattr__(self, name):
            raise AssertionError("offline replay accessed discovery")
    board.discovery = ForbiddenDiscovery()
    assert board.replay.replay(board.policy, [world]).worlds == 1


def test_online_node_limit_inside_branch_batch():
    board = RSIOrchestrator(policy=SearchPolicy(max_nodes=3, branch_factor=2, budget=20, stop_score=1))
    assert len(board.explore_online("limit").nodes) - 1 <= 3


def test_tree_rejects_orphan():
    tree = DiscoveryTree()
    tree.nodes["orphan"] = TreeNode(node_id="orphan", parent_id="missing")
    assert not tree.validate()[0]


def test_tree_rejects_cycle():
    tree = DiscoveryTree()
    root = tree.get(tree.root_id)
    root.parent_id = root.node_id
    root.children.append(root.node_id)
    assert not tree.validate()[0]


def test_replay_honors_world_budget():
    worlds = [DiscoveryTree(), DiscoveryTree()]
    assert HistoricalReplay().replay(SearchPolicy(), worlds, budget=SimulationBudget(max_worlds=1)).worlds == 1


def test_replay_does_not_overspend():
    tree = DiscoveryTree()
    tree.add(tree.root_id, score=.5, cost=10, metadata={"depth": 1})
    result = HistoricalReplay().replay(SearchPolicy(), [tree], budget=SimulationBudget(max_cost=1))
    assert result.cost <= 1


def test_policy_rejects_nan_budget():
    with pytest.raises(ValueError):
        SearchPolicy(budget=math.nan)


def test_zero_pool_bound_is_empty():
    assert len(SimulatorPool([DiscoveryTree()]).bounded(0)) == 0


def test_legacy_zero_revisions():
    result = DreamRSI().run(RunConfig("zero revisions", rounds=1, revisions=0))
    assert result["metrics"].policy_revisions == 0


@pytest.mark.parametrize("budget", [math.nan, math.inf, -1, 0])
def test_invalid_budgets_rejected_in_both_generations(budget):
    from dream_rsi import ExplorationPolicy
    for factory in (SearchPolicy, ExplorationPolicy):
        with pytest.raises(ValueError):
            factory(budget=budget)


def test_legacy_config_applies_fractional_budget_and_node_limit():
    from dream_rsi import ExplorationPolicy
    system = DreamRSI()
    system.policy = ExplorationPolicy(max_nodes=3, budget=20, stop_threshold=1)
    assert len(system.online_exploration(system.policy, "limit").nodes) <= 4
    result = DreamRSI().run(RunConfig("limited", rounds=1, revisions=0, online_budget=1.5))
    assert result["metrics"].compute_budget == 1


def test_legacy_replay_enforces_cost_limit():
    from dream_rsi import ExplorationPolicy, ReplayEngine
    from dream_rsi.replay.legacy import SimulatorPool as LegacyPool
    tree = DiscoveryTree()
    tree.add(tree.root_id, cost=10, score=.5, metadata={"depth": 1})
    assert ReplayEngine().replay(ExplorationPolicy(budget=1), LegacyPool([tree])).cost <= 1


def test_deserialization_rejects_duplicate_node_ids():
    tree = DiscoveryTree()
    payload = tree.to_dict()
    payload["nodes"].append(payload["nodes"][0].copy())
    with pytest.raises(ValueError, match="duplicate"):
        DiscoveryTree.from_dict(payload)


@pytest.mark.parametrize("module", ["dream_rsi.persistence.legacy", "dream_rsi.persistence.worlds"])
def test_persistence_rejects_malformed_world_on_load(tmp_path, module):
    import json
    payload = DiscoveryTree().to_dict()
    payload["nodes"][0]["children"] = ["missing"]
    path = tmp_path / "worlds.jsonl"
    path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="line 1"):
        importlib.import_module(module).WorldStore(path).load()


def test_pool_captures_tree_before_caller_mutation():
    tree = DiscoveryTree()
    pool = SimulatorPool([tree])
    tree.add(tree.root_id, score=.8)
    assert len(pool.snapshot()[0].tree.nodes) == 1


def test_world_budget_reports_truncation():
    result = HistoricalReplay().replay(SearchPolicy(), [DiscoveryTree(), DiscoveryTree()],
                                       budget=SimulationBudget(max_worlds=1))
    assert result.worlds == 1 and result.budget_exhausted
    assert HistoricalReplay().replay(SearchPolicy(), [DiscoveryTree()], max_worlds=0).worlds == 0
    with pytest.raises(ValueError):
        HistoricalReplay().replay(SearchPolicy(), [], max_worlds=-1)


def test_policy_improvement_uses_same_pool():
    board = RSIOrchestrator()
    board.run("fixed policy", rounds=3, revisions=0)
    assert board.metrics.policy_improvement == 0


@pytest.mark.parametrize("field,value", [("max_nodes", 1.5), ("parallel_group_size", 0), ("branch_factor", True)])
def test_invalid_policy_limits(field, value):
    with pytest.raises(ValueError):
        SearchPolicy(**{field: value})
