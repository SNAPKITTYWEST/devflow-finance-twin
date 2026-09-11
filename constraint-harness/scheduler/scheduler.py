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

"""Bounded concurrent scheduler over a DAG."""

from __future__ import annotations

import concurrent.futures
import time
from typing import Any

from mxml.schema import RuntimeConfig
from scheduler.dag import DAG


class Scheduler:
    def __init__(self, max_workers: int = 4, timeout_seconds: int = 60) -> None:
        self.max_workers = max(1, max_workers)
        self.timeout = timeout_seconds

    def run(self, dag: DAG, runtime: RuntimeConfig) -> dict[str, Any]:
        """Execute tasks respecting dependencies. Returns task_id â†’ result dict."""
        completed: set[str] = set()
        results: dict[str, Any] = {}
        cmd_map = {c.id: c for c in runtime.commands}

        def execute_one(task_id: str) -> tuple[str, dict[str, Any]]:
            task = dag.nodes[task_id]
            cmd = cmd_map.get(task.command)
            start = time.time()
            if cmd and cmd.type == "python":
                payload = {
                    "status": "ok",
                    "command": task.command,
                    "input": task.input,
                    "echo": task.input.get("code", task.input.get("expr", "")),
                }
            else:
                payload = {
                    "status": "ok",
                    "command": task.command,
                    "input": task.input,
                    "note": "stub execution (no external model)",
                }
            payload["duration_ms"] = int((time.time() - start) * 1000)
            payload["task_id"] = task_id
            return task_id, payload

        remaining = set(dag.nodes.keys())
        deadline = time.time() + self.timeout

        with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_workers) as pool:
            while remaining:
                if time.time() > deadline:
                    for tid in remaining:
                        results[tid] = {"status": "timeout", "task_id": tid}
                    break
                ready = [t for t in dag.ready(completed) if t in remaining]
                if not ready:
                    for tid in list(remaining):
                        results[tid] = {"status": "blocked", "task_id": tid}
                    break
                futures = {pool.submit(execute_one, tid): tid for tid in ready}
                for fut in concurrent.futures.as_completed(futures, timeout=max(1, int(deadline - time.time()))):
                    tid, res = fut.result()
                    results[tid] = res
                    completed.add(tid)
                    remaining.discard(tid)

        return results
