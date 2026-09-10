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
