# Constitutional Datalog axioms (declarative specification)
# Evaluated by constitution/evaluator.py
#
# Predicates:
# allowed(Task, Context)
# authorized(Agent, Task)
# valid(Result)
# consistent(ResultA, ResultB)
# provenance_complete(Result)
#
# Hard outcomes:
# PASS
# FAIL
# UNKNOWN
#
# Hard axioms:
# UNKNOWN → FAILED_CLOSED
# FAIL → FAILED_CLOSED
#
# Soft axioms may emit REVISE

# Authorization must be explicit
authorized(Agent, Task) :- allowed(Agent, Task), has_capability(Agent, Task).

# A result is only valid if provenance is complete and no hard failure
valid(Result) :- provenance_complete(Result), not hard_fail(Result).

# Consistency between two results
consistent(A, B) :- same_contract(A, B), equivalent_payload(A, B).

# Default closed: absence of positive evidence yields UNKNOWN
# (implemented in evaluator as fail-closed default)
