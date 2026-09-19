import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))

from dream_rsi.core import DreamRSI, RunConfig
from dream_rsi.policy import ExplorationPolicy
from dream_rsi.replay import ReplayEngine, SimulatorPool
from dream_rsi.tree import DiscoveryTree


def test_tree_round_trip_and_validation():
    tree = DiscoveryTree()
    root = tree.get(tree.root_id)
    child = tree.add(root.node_id, score=0.7, status="completed")
    restored = DiscoveryTree.from_json(tree.to_json())
    assert restored.get(child.node_id).score == 0.7
    assert restored.validate() == (True, None)


def test_replay_does_not_need_discovery_agent():
    system = DreamRSI()
    tree = system.online_exploration(system.policy, "algorithm task")
    result = ReplayEngine().replay(system.policy, SimulatorPool([tree]))
    assert result.visited_nodes > 0
    assert result.worlds == 1


def test_incumbent_is_preserved_on_regression():
    system = DreamRSI()
    incumbent = system.policy
    selected = system.developer.select_best([(incumbent, 0.8), (incumbent.mutate({"max_nodes": 1}), 0.2)])
    assert selected[0].fingerprint() == incumbent.fingerprint()
    assert selected[1] == 0.8


def test_multi_world_run_and_metrics():
    result = DreamRSI().run(RunConfig("optimize kernel", rounds=2))
    assert result["worlds"] == 2
    assert result["metrics"].discovery_agent_calls > 0
    assert result["metrics"].offline_evaluations > 0
