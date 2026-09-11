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

from mxml.schema import TaskDecl
from scheduler.dag import build_dag, DAGError
import pytest


def test_topo_order():
    tasks = [
        TaskDecl(id="t1", command="py"),
        TaskDecl(id="t2", command="py"),
        TaskDecl(id="t3", command="py", depends_on=("t1", "t2")),
    ]
    dag = build_dag(tasks)
    assert dag.order.index("t1") < dag.order.index("t3")
    assert dag.order.index("t2") < dag.order.index("t3")


def test_cycle_detected():
    tasks = [
        TaskDecl(id="a", command="py", depends_on=("b",)),
        TaskDecl(id="b", command="py", depends_on=("a",)),
    ]
    with pytest.raises(DAGError):
        build_dag(tasks)


def test_missing_dep():
    tasks = [TaskDecl(id="a", command="py", depends_on=("missing",))]
    with pytest.raises(DAGError):
        build_dag(tasks)
