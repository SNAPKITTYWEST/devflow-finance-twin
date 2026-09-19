"""Dream-RSI reconstruction package."""

from .core import DreamRSI, RunConfig, RunMetrics, RSIOrchestrator
from .discovery import (
    DiscoveryAgent,
    DomainAdapter,
    AlgorithmEngineering,
    MathematicalOptimization,
    GPUKernelEngineering,
    AlgorithmEvaluator,
    FixedDiscoveryAgent,
    DomainEvaluator,
    MathematicalEvaluator,
    GPUKernelEvaluator,
)
from .policy import ExplorationPolicy, PolicyDeveloper, SearchPolicy, ScoredPolicy, PolicyDecision
from .replay import ReplayEngine, ReplayResult, SimulatorPool, HistoricalReplay, PolicyReplay, WorldReplay
from .metrics import Metrics, Timer
from .evaluation import Evaluation, Evaluator, validate_score
from .experiments import (
    ExperimentRunner,
    ExperimentResult,
    LayeredExperimentRunner,
    LayeredExperimentResult,
    FixedExplorationBaseline,
    SimpleTESBaseline,
    adapter_for,
)
from .simulator import SimulationBudget, SimulatorPool
from .persistence import WorldStore
from .tree import DiscoveryTree, TreeNode

__all__ = [
    "DreamRSI",
    "RunConfig",
    "RunMetrics",
    "RSIOrchestrator",
    "DiscoveryAgent",
    "DomainAdapter",
    "AlgorithmEngineering",
    "MathematicalOptimization",
    "GPUKernelEngineering",
    "AlgorithmEvaluator",
    "FixedDiscoveryAgent",
    "DomainEvaluator",
    "MathematicalEvaluator",
    "GPUKernelEvaluator",
    "ExplorationPolicy",
    "PolicyDeveloper",
    "SearchPolicy",
    "ScoredPolicy",
    "PolicyDecision",
    "ReplayEngine",
    "ReplayResult",
    "SimulatorPool",
    "HistoricalReplay",
    "PolicyReplay",
    "WorldReplay",
    "Metrics",
    "Timer",
    "Evaluation",
    "Evaluator",
    "validate_score",
    "ExperimentRunner",
    "ExperimentResult",
    "LayeredExperimentRunner",
    "LayeredExperimentResult",
    "FixedExplorationBaseline",
    "SimpleTESBaseline",
    "adapter_for",
    "SimulationBudget",
    "WorldStore",
    "DiscoveryTree",
    "TreeNode",
]
