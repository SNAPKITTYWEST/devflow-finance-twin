"""Agent scheduler and channel runtime (ISA-level semantics)."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Any

from isa.types import AgentStatus, MachineState
from compiler.ir import Program
from runtime.interpreter import Interpreter


class ChannelState(Enum):
    OPEN = auto()
    CLOSED = auto()


@dataclass
class Channel:
    id: int
    capacity: int
    messages: list[int] = field(default_factory=list)
    state: ChannelState = ChannelState.OPEN

    def write(self, val: int) -> bool:
        if self.state != ChannelState.OPEN:
            return False
        if self.capacity and len(self.messages) >= self.capacity:
            return False # backpressure
        self.messages.append(val)
        return True

    def read(self) -> int | None:
        if not self.messages:
            return None
        return self.messages.pop(0)

    def close(self) -> None:
        self.state = ChannelState.CLOSED


@dataclass
class Agent:
    id: int
    program: Program
    state: MachineState
    status: AgentStatus = AgentStatus.READY
    mailbox: list[int] = field(default_factory=list)

    def step(self) -> bool:
        if self.status in (AgentStatus.TERMINATED, AgentStatus.FAILED):
            return False
        self.status = AgentStatus.RUNNING
        interp = Interpreter(self.program, self.state)
        # single step
        alive = interp.step()
        self.state = interp.state
        if self.state.halted or self.state.status == AgentStatus.TERMINATED:
            self.status = AgentStatus.TERMINATED
            return False
        if self.state.status == AgentStatus.SUSPENDED:
            self.status = AgentStatus.SUSPENDED
            return True
        self.status = AgentStatus.READY
        return alive


@dataclass
class AgentScheduler:
    agents: dict[int, Agent] = field(default_factory=dict)
    channels: dict[int, Channel] = field(default_factory=dict)
    next_id: int = 1
    next_chan: int = 1

    def spawn(self, program: Program, parent: MachineState | None = None) -> int:
        aid = self.next_id
        self.next_id += 1
        st = MachineState()
        if parent:
            st.registers = parent.registers.copy() if hasattr(parent.registers, "copy") else parent.registers
        agent = Agent(id=aid, program=program, state=st)
        self.agents[aid] = agent
        return aid

    def create_channel(self, capacity: int = 0) -> int:
        cid = self.next_chan
        self.next_chan += 1
        self.channels[cid] = Channel(id=cid, capacity=capacity)
        return cid

    def send(self, agent_id: int, value: int) -> None:
        if agent_id in self.agents:
            self.agents[agent_id].mailbox.append(value)

    def run_round_robin(self, max_steps: int = 1000) -> None:
        steps = 0
        while steps < max_steps:
            runnable = [a for a in self.agents.values() if a.status in (AgentStatus.READY, AgentStatus.RUNNING)]
            if not runnable:
                break
            for a in runnable:
                a.step()
                steps += 1
                if steps >= max_steps:
                    break
