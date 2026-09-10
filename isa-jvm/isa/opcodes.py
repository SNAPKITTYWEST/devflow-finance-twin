"""Custom ISA opcode table.

Every opcode has an unambiguous semantic definition.
No implicit behavior is allowed from the implementation.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum, auto
from typing import Sequence


class OpFamily(IntEnum):
    DATA = auto()
    ARITH = auto()
    COMPARE = auto()
    CONTROL = auto()
    MEMORY = auto()
    SYNC = auto()
    STATE = auto()
    CHANNEL = auto()
    AGENT = auto()
    TENSOR = auto()
    LIFECYCLE = auto()


class OperandKind(IntEnum):
    REG = auto() # virtual register Rn
    IMM = auto() # immediate integer
    MEM = auto() # memory [Rn] or [Rn+imm]
    LABEL = auto() # control-flow target
    CHAN = auto() # channel handle
    NONE = auto()


@dataclass(frozen=True)
class OpcodeDesc:
    opcode: int
    mnemonic: str
    family: OpFamily
    arity: int
    operand_kinds: tuple[OperandKind, ...]
    result_regs: int # how many registers written
    effects: frozenset[str] # "read_mem", "write_mem", "branch", "call", "sync", ...
    doc: str


def _op(
    code: int,
    mnemonic: str,
    family: OpFamily,
    kinds: Sequence[OperandKind],
    results: int = 0,
    effects: Sequence[str] = (),
    doc: str = "",
) -> OpcodeDesc:
    return OpcodeDesc(
        opcode=code,
        mnemonic=mnemonic,
        family=family,
        arity=len(kinds),
        operand_kinds=tuple(kinds),
        result_regs=results,
        effects=frozenset(effects),
        doc=doc,
    )


# ---- Opcode table (stable numeric codes) ----

OPCODES: dict[str, OpcodeDesc] = {}
_BY_CODE: dict[int, OpcodeDesc] = {}


def _reg(m: str, code: int, family: OpFamily, kinds: Sequence[OperandKind], results: int = 1, effects: Sequence[str] = (), doc: str = "") -> None:
    d = _op(code, m, family, kinds, results, effects, doc)
    OPCODES[m] = d
    _BY_CODE[code] = d


# Data movement
_reg("NOP", 0x00, OpFamily.DATA, (), 0, (), "No operation")
_reg("MOVE", 0x01, OpFamily.DATA, (OperandKind.REG, OperandKind.REG), 1, (), "Rd = Rs")
_reg("LOAD_IMM", 0x02, OpFamily.DATA, (OperandKind.REG, OperandKind.IMM), 1, (), "Rd = imm")
_reg("PUSH", 0x03, OpFamily.DATA, (OperandKind.REG,), 0, ("stack",), "Push Rn onto operand stack")
_reg("POP", 0x04, OpFamily.DATA, (OperandKind.REG,), 1, ("stack",), "Pop operand stack into Rn")

# Arithmetic
_reg("ADD", 0x10, OpFamily.ARITH, (OperandKind.REG, OperandKind.REG, OperandKind.REG), 1, (), "Rd = Ra + Rb")
_reg("SUB", 0x11, OpFamily.ARITH, (OperandKind.REG, OperandKind.REG, OperandKind.REG), 1, (), "Rd = Ra - Rb")
_reg("MUL", 0x12, OpFamily.ARITH, (OperandKind.REG, OperandKind.REG, OperandKind.REG), 1, (), "Rd = Ra * Rb")
_reg("DIV", 0x13, OpFamily.ARITH, (OperandKind.REG, OperandKind.REG, OperandKind.REG), 1, (), "Rd = Ra / Rb (trunc toward zero)")

# Compare / flags
_reg("CMP", 0x20, OpFamily.COMPARE, (OperandKind.REG, OperandKind.REG), 0, ("flags",), "Compare Ra, Rb; set flags")
_reg("TEST", 0x21, OpFamily.COMPARE, (OperandKind.REG,), 0, ("flags",), "Test Rn; set flags")

# Control flow
_reg("JMP", 0x30, OpFamily.CONTROL, (OperandKind.LABEL,), 0, ("branch",), "Unconditional jump")
_reg("JE", 0x31, OpFamily.CONTROL, (OperandKind.LABEL,), 0, ("branch",), "Jump if equal")
_reg("JNE", 0x32, OpFamily.CONTROL, (OperandKind.LABEL,), 0, ("branch",), "Jump if not equal")
_reg("JL", 0x33, OpFamily.CONTROL, (OperandKind.LABEL,), 0, ("branch",), "Jump if less")
_reg("JG", 0x34, OpFamily.CONTROL, (OperandKind.LABEL,), 0, ("branch",), "Jump if greater")
_reg("CALL", 0x35, OpFamily.CONTROL, (OperandKind.LABEL,), 0, ("call", "stack"), "Call target")
_reg("RET", 0x36, OpFamily.CONTROL, (), 0, ("call", "stack"), "Return")
_reg("HALT", 0x3F, OpFamily.LIFECYCLE, (), 0, ("halt",), "Halt execution")

# Memory
_reg("LOAD", 0x40, OpFamily.MEMORY, (OperandKind.REG, OperandKind.REG), 1, ("read_mem",), "Rd = mem[Rs]")
_reg("STORE", 0x41, OpFamily.MEMORY, (OperandKind.REG, OperandKind.REG), 0, ("write_mem",), "mem[Rd] = Rs")

# Synchronization
_reg("SYNC", 0x50, OpFamily.SYNC, (), 0, ("sync",), "Memory fence")
_reg("CAS", 0x51, OpFamily.SYNC, (OperandKind.REG, OperandKind.REG, OperandKind.REG), 1, ("read_mem", "write_mem"), "Compare-and-swap")

# Channels
_reg("CHAN_CREATE", 0x60, OpFamily.CHANNEL, (OperandKind.REG, OperandKind.IMM), 1, (), "Create channel with capacity")
_reg("CHAN_WRITE", 0x61, OpFamily.CHANNEL, (OperandKind.REG, OperandKind.REG), 0, ("sync",), "Write to channel")
_reg("CHAN_READ", 0x62, OpFamily.CHANNEL, (OperandKind.REG, OperandKind.REG), 1, ("sync",), "Read from channel")

# Agents
_reg("AGENT_SPAWN", 0x70, OpFamily.AGENT, (OperandKind.LABEL,), 1, ("call",), "Spawn agent at label")
_reg("AGENT_SEND", 0x71, OpFamily.AGENT, (OperandKind.REG, OperandKind.REG), 0, ("sync",), "Send value to agent")
_reg("AGENT_YIELD", 0x72, OpFamily.AGENT, (), 0, ("sync",), "Yield execution")
_reg("AGENT_HALT", 0x73, OpFamily.LIFECYCLE, (), 0, ("halt",), "Terminate agent")

# Tensor (placeholder)
_reg("TENSOR_ADD", 0x80, OpFamily.TENSOR, (OperandKind.REG, OperandKind.REG, OperandKind.REG), 1, (), "Element-wise tensor add")


def get_opcode(mnemonic: str) -> OpcodeDesc:
    if mnemonic not in OPCODES:
        raise KeyError(f"unknown mnemonic: {mnemonic}")
    return OPCODES[mnemonic]


def get_by_code(code: int) -> OpcodeDesc:
    if code not in _BY_CODE:
        raise KeyError(f"unknown opcode: 0x{code:02X}")
    return _BY_CODE[code]


def all_mnemonics() -> list[str]:
    return sorted(OPCODES.keys())
