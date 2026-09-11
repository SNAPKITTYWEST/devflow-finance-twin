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

"""Execution context shared across layers."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from mxml.schema import MXMLDocument


@dataclass
class ExecutionContext:
    execution_id: str
    document: MXMLDocument | None = None
    agent: str = "default"
    allowed_tasks: set[str] = field(default_factory=set)
    authorized: bool = False
    schema_valid: bool = True
    provenance: dict[str, Any] = field(default_factory=dict)
    task_results: dict[str, Any] = field(default_factory=dict)
    revision_count: int = 0
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_constitution_dict(self) -> dict[str, Any]:
        return {
            "agent": self.agent,
            "task_id": self.metadata.get("current_task"),
            "allowed_tasks": self.allowed_tasks,
            "authorized": self.authorized,
            "schema_valid": self.schema_valid,
            "provenance": self.provenance,
            "axioms": list(self.document.runtime.axioms) if self.document else [],
        }
