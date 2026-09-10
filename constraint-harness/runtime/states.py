"""Explicit state machine states and legal transitions."""

from __future__ import annotations

from enum import Enum


class State(str, Enum):
    RECEIVE = "RECEIVE"
    PARSE = "PARSE"
    CONSTITUTION_CHECK = "CONSTITUTION_CHECK"
    DECOMPOSE = "DECOMPOSE"
    ROUTE = "ROUTE"
    DISPATCH = "DISPATCH"
    SUPERVISE = "SUPERVISE"
    VALIDATE = "VALIDATE"
    CROSS_CHECK = "CROSS_CHECK"
    SYNTHESIZE = "SYNTHESIZE"
    FINALIZE = "FINALIZE"
    RETURN = "RETURN"
    REVISE = "REVISE"
    FAILED_CLOSED = "FAILED_CLOSED"


# Legal transitions: from → set of allowed to
LEGAL_TRANSITIONS: dict[State, frozenset[State]] = {
    State.RECEIVE: frozenset({State.PARSE, State.FAILED_CLOSED}),
    State.PARSE: frozenset({State.CONSTITUTION_CHECK, State.FAILED_CLOSED}),
    State.CONSTITUTION_CHECK: frozenset({State.DECOMPOSE, State.REVISE, State.FAILED_CLOSED}),
    State.DECOMPOSE: frozenset({State.ROUTE, State.FAILED_CLOSED}),
    State.ROUTE: frozenset({State.DISPATCH, State.FAILED_CLOSED}),
    State.DISPATCH: frozenset({State.SUPERVISE, State.FAILED_CLOSED}),
    State.SUPERVISE: frozenset({State.VALIDATE, State.FAILED_CLOSED}),
    State.VALIDATE: frozenset({State.CROSS_CHECK, State.REVISE, State.FAILED_CLOSED}),
    State.CROSS_CHECK: frozenset({State.SYNTHESIZE, State.REVISE, State.FAILED_CLOSED}),
    State.SYNTHESIZE: frozenset({State.FINALIZE, State.FAILED_CLOSED}),
    State.FINALIZE: frozenset({State.RETURN, State.FAILED_CLOSED}),
    State.RETURN: frozenset(),
    State.REVISE: frozenset({State.CONSTITUTION_CHECK, State.DISPATCH, State.FAILED_CLOSED}),
    State.FAILED_CLOSED: frozenset(),
}


def can_transition(from_state: State, to_state: State) -> bool:
    return to_state in LEGAL_TRANSITIONS.get(from_state, frozenset())
