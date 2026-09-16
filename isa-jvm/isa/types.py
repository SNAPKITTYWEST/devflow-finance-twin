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

"""ISA type system and machine state model."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any


class ISAType(Enum):
    I32 = auto()
    I64 = auto()
    F32 = auto()
    F64 = auto()
    BOOL = auto()
    BYTE = auto()
    REFERENCE = auto()
    ADDRESS = auto()
    CHANNEL = auto()
    AGENT_CTX = auto()
    OPAQUE = auto()
    UNDEF = auto()


class AgentStatus(Enum):
    CREATED = auto()
    READY = auto()
    RUNNING = auto()
    WAITING = auto()
    SUSPENDED = auto()
    TERMINATED = auto()
    FAILED = auto()


@dataclass
class RegisterFile:
    """Virtual registers R0..R(n-1). Default width I64."""
    n: int = 32
    values: list[int] = field(default_factory=list)
    types: list[ISAType] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.values:
            self.values = [0] * self.n
        if not self.types:
            self.types = [ISAType.I64] * self.n

    def get(self, idx: int) -> int:
        if idx < 0 or idx >= self.n:
            raise IndexError(f"register R{idx} out of range")
        return self.values[idx]

    def set(self, idx: int, value: int, typ: ISAType = ISAType.I64) -> None:
        if idx < 0 or idx >= self.n:
            raise IndexError(f"register R{idx} out of range")
        self.values[idx] = value
        self.types[idx] = typ

    def snapshot(self) -> tuple[tuple[int, ...], tuple[ISAType, ...]]:
        return (tuple(self.values), tuple(self.types))


@dataclass
class Flags:
    eq: bool = False
    lt: bool = False
    gt: bool = False
    zero: bool = False

    def clear(self) -> None:
        self.eq = self.lt = self.gt = self.zero = False


@dataclass
class MachineState:
    """Explicit machine state. Source of truth for interpreter and for differential tests."""
    registers: RegisterFile = field(default_factory=RegisterFile)
    stack: list[int] = field(default_factory=list)
    memory: dict[int, int] = field(default_factory=dict) # address â†’ value (word)
    pc: int = 0
    flags: Flags = field(default_factory=Flags)
    agent_id: int = 0
    status: AgentStatus = AgentStatus.READY
    halted: bool = False
    # simple channel store: chan_id â†’ list of messages
    channels: dict[int, list[int]] = field(default_factory=dict)
    next_chan_id: int = 1
    # agent mailboxes: agent_id â†’ list of messages
    mailboxes: dict[int, list[int]] = field(default_factory=dict)
    next_agent_id: int = 1

    def copy(self) -> "MachineState":
        import copy
        return copy.deepcopy(self)
