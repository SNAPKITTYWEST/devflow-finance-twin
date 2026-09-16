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

"""Explicit command registry. Unknown commands fail closed."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable


@dataclass
class CommandSpec:
    name: str
    version: str
    required_capabilities: tuple[str, ...]
    isolation_mode: str
    handler: Callable[..., dict[str, Any]]


class CommandRegistry:
    def __init__(self) -> None:
        self._cmds: dict[str, CommandSpec] = {}

    def register(self, spec: CommandSpec) -> None:
        self._cmds[spec.name] = spec

    def get(self, name: str) -> CommandSpec | None:
        return self._cmds.get(name)

    def require(self, name: str) -> CommandSpec:
        spec = self.get(name)
        if spec is None:
            raise KeyError(f"unknown command '{name}'")
        return spec


def default_registry() -> CommandRegistry:
    from .python_command import run_python
    from .pytorch_command import run_pytorch
    from .model_command import run_model

    reg = CommandRegistry()
    reg.register(CommandSpec("python", "1.0", (), "process", run_python))
    reg.register(CommandSpec("pytorch", "1.0", ("pytorch",), "process", run_pytorch))
    reg.register(CommandSpec("model", "1.0", ("model",), "none", run_model))
    return reg
