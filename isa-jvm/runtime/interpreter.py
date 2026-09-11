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

"""Reference ISA interpreter.

Semantic oracle for differential testing against the JVM backend.
Deterministic. Side-effect free except on the explicit MachineState.
"""

from __future__ import annotations

from isa.opcodes import OperandKind
from isa.types import MachineState, AgentStatus, ISAType
from compiler.ir import Program, Instruction, Operand


class RuntimeError(Exception):
    pass


class Interpreter:
    def __init__(self, program: Program, state: MachineState | None = None) -> None:
        self.program = program
        self.state = state or MachineState()
        self.trace: list[dict] = []
        self.max_steps = 100_000

    def run(self, collect_trace: bool = False) -> MachineState:
        steps = 0
        while not self.state.halted and self.state.pc < len(self.program.instructions):
            if steps >= self.max_steps:
                raise RuntimeError("exceeded max steps")
            instr = self.program.instructions[self.state.pc]
            if collect_trace:
                self.trace.append({
                    "pc": self.state.pc,
                    "op": instr.mnemonic(),
                    "operands": [str(o) for o in instr.operands],
                    "regs": list(self.state.registers.values[:8]),
                })
            self._exec(instr)
            steps += 1
        return self.state

    def step(self) -> bool:
        """Execute one instruction. Returns False if halted."""
        if self.state.halted or self.state.pc >= len(self.program.instructions):
            self.state.halted = True
            return False
        instr = self.program.instructions[self.state.pc]
        self._exec(instr)
        return not self.state.halted

    def _reg(self, op: Operand) -> int:
        assert op.kind == OperandKind.REG and op.reg is not None
        return op.reg

    def _val(self, op: Operand) -> int:
        if op.kind == OperandKind.REG:
            return self.state.registers.get(op.reg) # type: ignore
        if op.kind == OperandKind.IMM:
            return op.imm # type: ignore
        raise RuntimeError(f"cannot get value of {op}")

    def _exec(self, instr: Instruction) -> None:
        op = instr.opcode.mnemonic
        ops = instr.operands
        st = self.state
        next_pc = st.pc + 1

        if op == "NOP":
            pass
        elif op == "MOVE":
            st.registers.set(self._reg(ops[0]), st.registers.get(self._reg(ops[1])))
        elif op == "LOAD_IMM":
            st.registers.set(self._reg(ops[0]), ops[1].imm) # type: ignore
        elif op == "PUSH":
            st.stack.append(st.registers.get(self._reg(ops[0])))
        elif op == "POP":
            if not st.stack:
                raise RuntimeError("stack underflow")
            st.registers.set(self._reg(ops[0]), st.stack.pop())
        elif op == "ADD":
            a = st.registers.get(self._reg(ops[1]))
            b = st.registers.get(self._reg(ops[2]))
            st.registers.set(self._reg(ops[0]), a + b)
        elif op == "SUB":
            a = st.registers.get(self._reg(ops[1]))
            b = st.registers.get(self._reg(ops[2]))
            st.registers.set(self._reg(ops[0]), a - b)
        elif op == "MUL":
            a = st.registers.get(self._reg(ops[1]))
            b = st.registers.get(self._reg(ops[2]))
            st.registers.set(self._reg(ops[0]), a * b)
        elif op == "DIV":
            a = st.registers.get(self._reg(ops[1]))
            b = st.registers.get(self._reg(ops[2]))
            if b == 0:
                raise RuntimeError("division by zero")
            st.registers.set(self._reg(ops[0]), int(a / b)) # trunc toward zero
        elif op == "CMP":
            a = st.registers.get(self._reg(ops[0]))
            b = st.registers.get(self._reg(ops[1]))
            st.flags.eq = a == b
            st.flags.lt = a < b
            st.flags.gt = a > b
            st.flags.zero = a == b
        elif op == "TEST":
            a = st.registers.get(self._reg(ops[0]))
            st.flags.zero = a == 0
            st.flags.eq = a == 0
        elif op == "JMP":
            next_pc = self.program.labels[ops[0].label] # type: ignore
        elif op == "JE":
            if st.flags.eq:
                next_pc = self.program.labels[ops[0].label] # type: ignore
        elif op == "JNE":
            if not st.flags.eq:
                next_pc = self.program.labels[ops[0].label] # type: ignore
        elif op == "JL":
            if st.flags.lt:
                next_pc = self.program.labels[ops[0].label] # type: ignore
        elif op == "JG":
            if st.flags.gt:
                next_pc = self.program.labels[ops[0].label] # type: ignore
        elif op == "CALL":
            st.stack.append(next_pc)
            next_pc = self.program.labels[ops[0].label] # type: ignore
        elif op == "RET":
            if not st.stack:
                raise RuntimeError("stack underflow on RET")
            next_pc = st.stack.pop()
        elif op == "LOAD":
            addr = st.registers.get(self._reg(ops[1]))
            if addr not in st.memory:
                raise RuntimeError(f"uninitialized memory at {addr}")
            st.registers.set(self._reg(ops[0]), st.memory[addr])
        elif op == "STORE":
            addr = st.registers.get(self._reg(ops[0]))
            val = st.registers.get(self._reg(ops[1]))
            st.memory[addr] = val
        elif op == "CHAN_CREATE":
            cid = st.next_chan_id
            st.next_chan_id += 1
            st.channels[cid] = []
            st.registers.set(self._reg(ops[0]), cid)
        elif op == "CHAN_WRITE":
            cid = st.registers.get(self._reg(ops[0]))
            val = st.registers.get(self._reg(ops[1]))
            if cid not in st.channels:
                raise RuntimeError(f"invalid channel {cid}")
            st.channels[cid].append(val)
        elif op == "CHAN_READ":
            cid = st.registers.get(self._reg(ops[1]))
            if cid not in st.channels or not st.channels[cid]:
                st.registers.set(self._reg(ops[0]), 0)
            else:
                st.registers.set(self._reg(ops[0]), st.channels[cid].pop(0))
        elif op == "AGENT_SPAWN":
            aid = st.next_agent_id
            st.next_agent_id += 1
            st.registers.set(self._reg(ops[0]), aid)
        elif op == "AGENT_SEND":
            aid = st.registers.get(self._reg(ops[0]))
            val = st.registers.get(self._reg(ops[1]))
            if aid not in st.mailboxes:
                st.mailboxes[aid] = []
            st.mailboxes[aid].append(val)
        elif op == "AGENT_YIELD":
            st.status = AgentStatus.SUSPENDED
            st.halted = True
        elif op == "AGENT_HALT" or op == "HALT":
            st.halted = True
            st.status = AgentStatus.TERMINATED
        elif op == "SYNC":
            pass # memory fence â€” no-op in sequential execution
        elif op == "CAS":
            addr = st.registers.get(self._reg(ops[0]))
            expected = st.registers.get(self._reg(ops[1]))
            new_val = st.registers.get(self._reg(ops[2]))
            cur = st.memory.get(addr, 0)
            if cur == expected:
                st.memory[addr] = new_val
                st.registers.set(self._reg(ops[0]), 1)
            else:
                st.registers.set(self._reg(ops[0]), 0)
        else:
            raise RuntimeError(f"unimplemented opcode: {op}")

        st.pc = next_pc
