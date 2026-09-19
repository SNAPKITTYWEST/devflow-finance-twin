from dataclasses import asdict

from .core import RunMetrics

METRIC_NAMES = (
    "discovery_agent_calls",
    "generations",
    "wall_clock_seconds",
    "compute_budget",
    "best_solution_score",
    "branches",
    "tree_size",
    "policy_revisions",
    "replay_evaluations",
    "online_executions",
    "offline_evaluations",
    "policy_improvement",
)


def metrics_dict(metrics):
    if isinstance(metrics, RunMetrics):
        data = asdict(metrics)
    else:
        data = dict(metrics)
    return {key: data.get(key, 0) for key in METRIC_NAMES}


def compare(*results):
    rows = []
    for item in results:
        metrics = getattr(item, "metrics", item)
        row = metrics_dict(metrics)
        if hasattr(item, "name"):
            row["name"] = item.name
        rows.append(row)
    return rows
