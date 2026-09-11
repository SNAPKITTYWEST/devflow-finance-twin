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