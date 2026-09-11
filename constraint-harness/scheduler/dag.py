# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

"""DAG construction and topological ordering. Fail closed on cycles."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

from mxml.schema import TaskDecl


class DAGError(Exception):
    pass


@dataclass
class DAG:
    nodes: dict[str, TaskDecl]
    edges: dict[str, list[str]]  # task â†’ list of dependencies (predecessors)
    order: list[str] = field(default_factory=list)

    def predecessors(self, task_id: str) -> list[str]:
        return list(self.edges.get(task_id, []))

    def ready(self, completed: set[str]) -> list[str]:
        out = []
        for tid, deps in self.edges.items():
            if tid not in completed and all(d in completed for d in deps):
                out.append(tid)
        return out


def build_dag(tasks: Iterable[TaskDecl]) -> DAG:
    nodes = {t.id: t for t in tasks}
    edges: dict[str, list[str]] = {t.id: list(t.depends_on) for t in tasks}

    # Validate references
    for tid, deps in edges.items():
        for d in deps:
            if d not in nodes:
                raise DAGError(f"missing dependency '{d}' for task '{tid}'")
            if d == tid:
                raise DAGError(f"self-dependency on '{tid}'")

    # Kahn topological sort
    in_degree = {tid: 0 for tid in nodes}
    for tid, deps in edges.items():
        in_degree[tid] = len(deps)

    successors: dict[str, list[str]] = {tid: [] for tid in nodes}
    for tid, deps in edges.items():
        for d in deps:
            successors[d].append(tid)

    queue = [tid for tid, deg in in_degree.items() if deg == 0]
    order: list[str] = []
    while queue:
        n = queue.pop(0)
        order.append(n)
        for s in successors[n]:
            in_degree[s] -= 1
            if in_degree[s] == 0:
                queue.append(s)

    if len(order) != len(nodes):
        raise DAGError("dependency cycle detected")

    return DAG(nodes=nodes, edges=edges, order=order)
