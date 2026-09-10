"""ISA Intermediate Representation.

Preserves instruction semantics, dependencies, and effects.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from isa.opcodes import OpcodeDesc, OperandKind


@dataclass(frozen=True)
class Operand:
    kind: OperandKind
    reg: int | None = None
    imm: int | None = None
    label: str | None = None

    def __str__(self) -> str:
        if self.kind == OperandKind.REG:
            return f"R{self.reg}"
        if self.kind == OperandKind.IMM:
            return str(self.imm)
        if self.kind == OperandKind.LABEL:
            return self.label or "?"
        if self.kind == OperandKind.MEM:
            return f"[R{self.reg}]"
        return "?"


@dataclass
class Instruction:
    opcode: OpcodeDesc
    operands: tuple[Operand, ...]
    source_line: int = 0
    labels: tuple[str, ...] = () # labels attached to this instruction
    # Analysis (filled later)
    deps: set[int] = field(default_factory=set) # instruction indices this depends on
    successors: list[int] = field(default_factory=list)
    index: int = -1

    def mnemonic(self) -> str:
        return self.opcode.mnemonic

    def __str__(self) -> str:
        ops = ", ".join(str(o) for o in self.operands)
        lab = ",".join(self.labels)
        prefix = f"{lab}: " if lab else ""
        return f"{prefix}{self.opcode.mnemonic} {ops}".strip()


@dataclass
class BasicBlock:
    id: int
    start: int # instruction index
    end: int # exclusive
    labels: list[str] = field(default_factory=list)
    successors: list[int] = field(default_factory=list) # block ids


@dataclass
class ControlFlowGraph:
    blocks: list[BasicBlock]
    entry: int = 0


@dataclass
class Program:
    """Parsed + verified ISA program."""
    instructions: list[Instruction]
    labels: dict[str, int] # label → instruction index
    cfg: ControlFlowGraph | None = None
    source_name: str = ""

    def __len__(self) -> int:
        return len(self.instructions)
