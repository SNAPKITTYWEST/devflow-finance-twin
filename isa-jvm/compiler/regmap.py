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

"""Deterministic ISA register â†’ JVM local-variable mapping."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class RegMap:
    """R0..R(n-1) map to JVM locals starting at base.
    Local 0 is reserved for 'this' in instance methods; we use static methods
    so locals 0..n-1 are free for registers. Stack is the JVM operand stack.
    """
    n_regs: int = 32
    base: int = 0

    def local(self, reg: int) -> int:
        if reg < 0 or reg >= self.n_regs:
            raise IndexError(f"R{reg} out of range")
        return self.base + reg

    def max_locals(self) -> int:
        return self.base + self.n_regs
