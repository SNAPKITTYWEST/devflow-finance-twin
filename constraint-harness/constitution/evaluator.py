"""Thin re-export for Datalog-style evaluation entry point."""

from .constitution import evaluate_constitution, ConstitutionalDecision, DecisionStatus

__all__ = ["evaluate_constitution", "ConstitutionalDecision", "DecisionStatus"]
