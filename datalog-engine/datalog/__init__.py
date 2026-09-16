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