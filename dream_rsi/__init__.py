"""Dream-RSI independent reconstruction.

This package implements the mechanism described in the supplied design brief:
fixed discovery agent, replayable historical trees, executable exploration
policies, multi-world replay, and incumbent-preserving policy selection.
"""

from .core import DreamRSI, RunConfig, RunMetrics
from .policy import ExplorationPolicy, PolicyDeveloper
from .tree import DiscoveryTree, TreeNode
from .replay import SimulatorPool, ReplayEngine, ReplayResult

__all__ = [
    "DreamRSI", "RunConfig", "RunMetrics", "ExplorationPolicy",
    "PolicyDeveloper", "DiscoveryTree", "TreeNode", "SimulatorPool",
    "ReplayEngine", "ReplayResult",
]
