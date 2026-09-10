from constitution import evaluate_constitution, DecisionStatus


def test_pass_when_authorized():
    ctx = {
        "agent": "worker",
        "task_id": "t1",
        "allowed_tasks": {"t1"},
        "authorized": True,
        "schema_valid": True,
        "provenance": {"complete": True},
        "axioms": ["authorization", "schema", "provenance"],
    }
    d = evaluate_constitution(ctx, result={"provenance": {"complete": True}})
    assert d.status == DecisionStatus.PASS


def test_fail_closed_on_unauthorized():
    ctx = {
        "agent": "worker",
        "task_id": "secret",
        "allowed_tasks": set(),
        "authorized": False,
        "schema_valid": True,
        "axioms": ["authorization"],
    }
    d = evaluate_constitution(ctx)
    assert d.status == DecisionStatus.FAILED_CLOSED


def test_unknown_provenance():
    ctx = {
        "agent": "worker",
        "task_id": "t1",
        "allowed_tasks": {"t1"},
        "authorized": True,
        "schema_valid": True,
        "axioms": ["provenance"],
    }
    d = evaluate_constitution(ctx)
    assert d.status == DecisionStatus.FAILED_CLOSED
