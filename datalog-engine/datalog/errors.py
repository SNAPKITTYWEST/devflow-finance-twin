"""Datalog engine error types."""

from __future__ import annotations


class ParseError(Exception):
    pass


class UnsafeRuleError(Exception):
    def __init__(self, message: str, rule_id: str = "") -> None:
        self.rule_id = rule_id
        super().__init__(message)


class StratificationError(Exception):
    pass


class InvalidQueryError(Exception):
    pass


class EvaluationError(Exception):
    pass