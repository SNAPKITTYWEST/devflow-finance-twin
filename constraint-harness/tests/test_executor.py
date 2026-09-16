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

from pathlib import Path
from runtime.executor import Executor


def test_basic_run():
    src = Path("examples/basic.mxml").read_text()
    ex = Executor()
    result = ex.run(src, authorized=True)
    assert result["status"] in ("SUCCESS", "REVISE")
    assert result["execution_id"]
    assert len(result["history"]) >= 3


def test_parallel_run():
    src = Path("examples/parallel.mxml").read_text()
    ex = Executor()
    result = ex.run(src, authorized=True)
    assert result["status"] in ("SUCCESS", "REVISE")
    assert "t1" in result.get("task_results", {}) or result["status"] != "SUCCESS"


def test_unauthorized_fails_closed():
    src = Path("examples/basic.mxml").read_text()
    ex = Executor()
    result = ex.run(src, authorized=False)
    assert result["status"] == "FAILED_CLOSED"
