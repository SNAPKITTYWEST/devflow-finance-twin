import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))

from dream_rsi.experiments import ExperimentRunner, adapter_for
from dream_rsi.persistence import WorldStore
from dream_rsi.core import DreamRSI


def test_world_store_round_trip(tmp_path):
    system = DreamRSI()
    tree = system.online_exploration(system.policy, "persist this world")
    path = tmp_path / "worlds.jsonl"
    store = WorldStore(path)
    store.append(tree)
    pool = store.pool()
    assert len(pool) == 1
    assert pool.trees[0].validate() == (True, None)


def test_controlled_baselines_share_domain_adapter():
    results = ExperimentRunner("optimize a kernel", rounds=1, adapter=adapter_for("gpu")).run_all()
    assert [item.name for item in results] == ["recursive-fixed-exploration", "simple-tes", "dream-rsi"]
    assert all(item.metrics["discovery_agent_calls"] > 0 for item in results)


def test_metric_categories_are_explicit():
    result = ExperimentRunner("solve", rounds=1).run_dream_rsi()
    assert "replay_evaluations" in result.metrics
    assert "online_executions" in result.metrics
    assert "offline_evaluations" in result.metrics
