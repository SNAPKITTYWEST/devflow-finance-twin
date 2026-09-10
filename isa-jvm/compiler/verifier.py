"""ISA verifier. Fail closed on any semantic violation."""

from __future__ import annotations

from isa.opcodes import OperandKind
from compiler.ir import Program, ControlFlowGraph, BasicBlock


class VerifyError(Exception):
    def __init__(self, message: str, line: int = 0) -> None:
        self.line = line
        super().__init__(f"line {line}: {message}" if line else message)


def verify(program: Program) -> ControlFlowGraph:
    """Verify program and build CFG. Raises VerifyError on failure."""
    if not program.instructions:
        raise VerifyError("empty program")

    # Register range check
    for instr in program.instructions:
        for op in instr.operands:
            if op.kind in (OperandKind.REG, OperandKind.MEM) and op.reg is not None:
                if op.reg < 0 or op.reg >= 32:
                    raise VerifyError(f"register R{op.reg} out of range 0..31", instr.source_line)

    # Build basic blocks
    leaders = {0}
    for i, instr in enumerate(program.instructions):
        if "branch" in instr.opcode.effects or "call" in instr.opcode.effects:
            if i + 1 < len(program.instructions):
                leaders.add(i + 1)
            for op in instr.operands:
                if op.kind == OperandKind.LABEL and op.label in program.labels:
                    leaders.add(program.labels[op.label])
        if instr.labels:
            leaders.add(i)

    sorted_leaders = sorted(leaders)
    blocks: list[BasicBlock] = []
    for bi, start in enumerate(sorted_leaders):
        end = sorted_leaders[bi + 1] if bi + 1 < len(sorted_leaders) else len(program.instructions)
        labs = list(program.instructions[start].labels) if start < len(program.instructions) else []
        blocks.append(BasicBlock(id=bi, start=start, end=end, labels=labs))

    # Map instruction index → block id
    instr_to_block: dict[int, int] = {}
    for b in blocks:
        for i in range(b.start, b.end):
            instr_to_block[i] = b.id

    # Successors
    for b in blocks:
        if b.start >= len(program.instructions):
            continue
        last = program.instructions[b.end - 1] if b.end > b.start else None
        if last and ("branch" in last.opcode.effects or last.opcode.mnemonic == "JMP"):
            for op in last.operands:
                if op.kind == OperandKind.LABEL and op.label in program.labels:
                    target = program.labels[op.label]
                    if target in instr_to_block:
                        b.successors.append(instr_to_block[target])
            if last.opcode.mnemonic not in ("JMP", "RET", "HALT"):
                # conditional: also fall through
                if b.end < len(program.instructions) and b.end in instr_to_block:
                    b.successors.append(instr_to_block[b.end])
        elif last and last.opcode.mnemonic in ("RET", "HALT"):
            pass
        else:
            if b.end < len(program.instructions) and b.end in instr_to_block:
                b.successors.append(instr_to_block[b.end])

    cfg = ControlFlowGraph(blocks=blocks, entry=0)
    program.cfg = cfg
    return cfg
