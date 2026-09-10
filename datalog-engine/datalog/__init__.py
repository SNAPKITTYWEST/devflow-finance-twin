"""Deterministic Datalog knowledge engine.

Side-effect free. Open-world (TRUE / FALSE / UNKNOWN).
Independent of MXML, PyTorch, models, or orchestration.
"""

from .terms import Variable, Constant, Atom, Term
from .kb import KnowledgeBase, Fact, Rule
from .query import QueryResult, KnowledgeStatus
from .errors import (
    ParseError,
    UnsafeRuleError,
    StratificationError,
    InvalidQueryError,
    EvaluationError,
)

__version__ = "0.1.0"
__all__ = [
    "Variable",
    "Constant",
    "Atom",
    "Term",
    "KnowledgeBase",
    "Fact",
    "Rule",
    "QueryResult",
    "KnowledgeStatus",
    "ParseError",
    "UnsafeRuleError",
    "StratificationError",
    "InvalidQueryError",
    "EvaluationError",
]