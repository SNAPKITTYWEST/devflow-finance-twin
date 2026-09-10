"""Circuit scheduling and dependency analysis."""
from typing import List, Dict, Set, Optional
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction
from quantum_computer.circuit.dag import CircuitDAG, circuit_to_dag

class ScheduleEntry:
    __slots__ = ('_instruction', '_time_step', '_qubits')
    def __init__(self, instruction: Instruction, time_step: int, qubits: List[int]):
        self._instruction = instruction
        self._time_step = time_step
        self._qubits = qubits[:]
    @property
    def instruction(self) -> Instruction:
        return self._instruction
    @property
    def time_step(self) -> int:
        return self._time_step
    @property
    def qubits(self) -> List[int]:
        return self._qubits[:]
    def __repr__(self):
        return f"ScheduleEntry({self._instruction.gate.name}, t={self._time_step})"

class CircuitSchedule:
    __slots__ = ('_entries', '_total_time', '_parallelism')
    def __init__(self):
        self._entries: List[ScheduleEntry] = []
        self._total_time = 0
        self._parallelism: List[int] = []
    @property
    def entries(self) -> List[ScheduleEntry]:
        return self._entries[:]
    @property
    def total_time(self) -> int:
        return self._total_time
    @property
    def parallelism(self) -> List[int]:
        return self._parallelism[:]
    def add_entry(self, entry: ScheduleEntry):
        self._entries.append(entry)
        self._total_time = max(self._total_time, entry.time_step + 1)
    def get_time_step(self, step: int) -> List[ScheduleEntry]:
        return [e for e in self._entries if e.time_step == step]
    def compute_parallelism(self):
        self._parallelism = [0] * self._total_time
        for e in self._entries:
            self._parallelism[e.time_step] += 1
    def __repr__(self):
        return f"CircuitSchedule(time={self._total_time}, entries={len(self._entries)})"

class Scheduler:
    __slots__ = ('_strategy')
    def __init__(self, strategy: str = "asap"):
        if strategy not in ("asap", "alap", "depth"):
            raise ValueError(f"Unknown strategy: {strategy}")
        self._strategy = strategy
    def schedule(self, circuit: QuantumCircuit) -> CircuitSchedule:
        if self._strategy == "asap":
            return self._schedule_asap(circuit)
        elif self._strategy == "alap":
            return self._schedule_alap(circuit)
        else:
            return self._schedule_depth(circuit)
    def _schedule_asap(self, circuit: QuantumCircuit) -> CircuitSchedule:
        schedule = CircuitSchedule()
        dag = circuit_to_dag(circuit)
        qubit_ready = [0] * circuit.n_qubits
        for idx in dag.topological_order:
            node = dag.nodes[idx]
            inst = node.instruction
            if inst.gate.name == "barrier":
                t = max(qubit_ready) if qubit_ready else 0
                schedule.add_entry(ScheduleEntry(inst, t, inst.qubits))
                continue
            t = 0
            for q in inst.qubits:
                t = max(t, qubit_ready[q])
            schedule.add_entry(ScheduleEntry(inst, t, inst.qubits))
            for q in inst.qubits:
                qubit_ready[q] = t + 1
        schedule.compute_parallelism()
        return schedule
    def _schedule_alap(self, circuit: QuantumCircuit) -> CircuitSchedule:
        asap = self._schedule_asap(circuit)
        max_time = asap.total_time
        schedule = CircuitSchedule()
        dag = circuit_to_dag(circuit)
        qubit_latest = [max_time] * circuit.n_qubits
        reversed_order = list(reversed(dag.topological_order))
        for idx in reversed_order:
            node = dag.nodes[idx]
            inst = node.instruction
            if inst.gate.name == "barrier":
                t = min(qubit_latest) - 1 if qubit_latest else 0
                schedule.add_entry(ScheduleEntry(inst, t, inst.qubits))
                continue
            latest_start = max_time
            for q in inst.qubits:
                latest_start = min(latest_start, qubit_latest[q] - 1)
            schedule.add_entry(ScheduleEntry(inst, latest_start, inst.qubits))
            for q in inst.qubits:
                qubit_latest[q] = latest_start
        schedule.compute_parallelism()
        return schedule
    def _schedule_depth(self, circuit: QuantumCircuit) -> CircuitSchedule:
        return self._schedule_asap(circuit)

def analyze_dependencies(circuit: QuantumCircuit) -> Dict[int, Set[int]]:
    deps = {}
    last_writer = {}
    for i, inst in enumerate(circuit.instructions):
        deps[i] = set()
        for q in inst.qubits:
            if q in last_writer:
                deps[i].add(last_writer[q])
            last_writer[q] = i
    return deps

def get_critical_path(circuit: QuantumCircuit) -> List[int]:
    dag = circuit_to_dag(circuit)
    if not dag.topological_order:
        return []
    dist = {idx: 0 for idx in dag.topological_order}
    prev = {idx: -1 for idx in dag.topological_order}
    for idx in dag.topological_order:
        node = dag.nodes[idx]
        for s in node.successors:
            if dist[s] < dist[idx] + 1:
                dist[s] = dist[idx] + 1
                prev[s] = idx
    end = max(dist, key=dist.get)
    path = []
    while end != -1:
        path.append(end)
        end = prev[end]
    return list(reversed(path))

def parallelism_ratio(circuit: QuantumCircuit) -> float:
    schedule = Scheduler("asap").schedule(circuit)
    if schedule.total_time == 0:
        return 0.0
    return schedule.entries.__len__() / schedule.total_time
