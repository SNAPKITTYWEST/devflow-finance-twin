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

"""MXML schema dataclasses. No silent defaults for required fields."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class Limits:
    max_workers: int
    max_revisions: int
    timeout_seconds: int
    max_tasks: int = 256
    max_tool_calls: int = 64


@dataclass(frozen=True)
class CommandDecl:
    id: str
    type: str
    isolation: str = "none"  # none | process
    version: str = "1.0"


@dataclass(frozen=True)
class TaskDecl:
    id: str
    command: str
    depends_on: tuple[str, ...] = ()
    input: dict[str, Any] = field(default_factory=dict)
    revision_limit: int | None = None


@dataclass(frozen=True)
class RuntimeConfig:
    id: str
    limits: Limits
    axioms: tuple[str, ...]
    commands: tuple[CommandDecl, ...]
    tasks: tuple[TaskDecl, ...]


@dataclass(frozen=True)
class MXMLDocument:
    version: str
    runtime: RuntimeConfig
    raw_hash: str = ""
