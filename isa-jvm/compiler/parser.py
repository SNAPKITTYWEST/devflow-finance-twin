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

"""ISA text parser.

Grammar (line-oriented):
  [label:] MNEMONIC [op1, op2, ...]
  ; comment
  # comment
"""

from __future__ import annotations

import re
from typing import List

from isa.opcodes import OPCODES, OperandKind, get_opcode
from compiler.ir import Instruction, Operand, Program


class ParseError(Exception):
    def __init__(self, message: str, line: int = 0) -> None:
        self.line = line
        super().__init__(f"line {line}: {message}")


_LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_REG = re.compile(r"^R(\d+)$", re.IGNORECASE)
_MEM = re.compile(r"^\[R(\d+)\]$", re.IGNORECASE)
_IMM = re.compile(r"^-?\d+$")
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _parse_operand(tok: str, expected: OperandKind) -> Operand:
    tok = tok.strip()
    if expected == OperandKind.REG:
        m = _REG.match(tok)
        if not m:
            raise ParseError(f"expected register, got {tok!r}")
        return Operand(OperandKind.REG, reg=int(m.group(1)))
    if expected == OperandKind.IMM:
        if not _IMM.match(tok):
            raise ParseError(f"expected immediate, got {tok!r}")
        return Operand(OperandKind.IMM, imm=int(tok))
    if expected == OperandKind.LABEL:
        if not _IDENT.match(tok):
            raise ParseError(f"expected label, got {tok!r}")
        return Operand(OperandKind.LABEL, label=tok)
    if expected == OperandKind.MEM:
        m = _MEM.match(tok)
        if not m:
            raise ParseError(f"expected memory [Rn], got {tok!r}")
        return Operand(OperandKind.MEM, reg=int(m.group(1)))
    raise ParseError(f"unsupported operand kind {expected}")


def parse_program(source: str, source_name: str = "") -> Program:
    instructions: List[Instruction] = []
    labels: dict[str, int] = {}
    pending_labels: list[str] = []

    for lineno, raw in enumerate(source.splitlines(), 1):
        line = raw.split(";")[0].split("#")[0].strip()
        if not line:
            continue

        # label: rest
        m = _LABEL.match(line)
        if m:
            lab, rest = m.group(1), m.group(2).strip()
            if lab in labels:
                raise ParseError(f"duplicate label {lab}", lineno)
            pending_labels.append(lab)
            if not rest:
                continue
            line = rest

        parts = line.replace(",", " ").split()
        if not parts:
            continue
        mnem = parts[0].upper()
        if mnem not in OPCODES:
            raise ParseError(f"unknown mnemonic {mnem}", lineno)
        desc = get_opcode(mnem)
        tokens = parts[1:]
        if len(tokens) != desc.arity:
            raise ParseError(
                f"{mnem} expects {desc.arity} operands, got {len(tokens)}", lineno
            )
        operands = []
        for tok, kind in zip(tokens, desc.operand_kinds):
            try:
                operands.append(_parse_operand(tok, kind))
            except ParseError as e:
                raise ParseError(str(e), lineno) from e

        idx = len(instructions)
        for lab in pending_labels:
            labels[lab] = idx
        instr = Instruction(
            opcode=desc,
            operands=tuple(operands),
            source_line=lineno,
            labels=tuple(pending_labels),
            index=idx,
        )
        instructions.append(instr)
        pending_labels = []

    if pending_labels:
        # trailing labels point past end
        idx = len(instructions)
        for lab in pending_labels:
            labels[lab] = idx

    # Resolve label operands to ensure they exist
    for instr in instructions:
        for op in instr.operands:
            if op.kind == OperandKind.LABEL and op.label not in labels:
                raise ParseError(f"undefined label {op.label}", instr.source_line)

    return Program(instructions=instructions, labels=labels, source_name=source_name)
