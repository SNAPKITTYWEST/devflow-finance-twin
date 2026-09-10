"""Circuit representation, composition, scheduling, and DAG."""
import json
import math
import time
from typing import List, Optional, Tuple, Dict, Set
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix
from quantum_computer.core.register import QuantumRegister, ClassicalRegister, RegisterManager
from quantum_computer.gates import Gate, GATE_SET, get_gate

class Instruction:
    __slots__ = ('_gate', '_qubits', '_classical_bits', '_condition', '_metadata')
    def __init__(self, gate: Gate, qubits: List[int],
                 classical_bits: Optional[List[int]] = None,
                 condition: Optional[Tuple[int, int]] = None,
                 metadata: Optional[dict] = None):
        self._gate = gate
        self._qubits = qubits[:]
        self._classical_bits = classical_bits[:] if classical_bits else []
        self._condition = condition
        self._metadata = metadata or {}
    @property
    def gate(self) -> Gate:
        return self._gate
    @property
    def qubits(self) -> List[int]:
        return self._qubits[:]
    @property
    def classical_bits(self) -> List[int]:
        return self._classical_bits[:]
    @property
    def condition(self) -> Optional[Tuple[int, int]]:
        return self._condition
    @property
    def metadata(self) -> dict:
        return dict(self._metadata)
    def qubit_set(self) -> Set[int]:
        return set(self._qubits)
    def involves_qubit(self, q: int) -> bool:
        return q in self._qubits
    def depends_on(self, other: 'Instruction') -> bool:
        return bool(self.qubit_set() & other.qubit_set())
    def __repr__(self):
        qstr = ",".join(str(q) for q in self._qubits)
        return f"Instruction({self._gate.name}, [{qstr}])"

class Measurement:
    __slots__ = ('_qubit', '_classical_bit', '_register_name')
    def __init__(self, qubit: int, classical_bit: int, register_name: str = "c"):
        self._qubit = qubit
        self._classical_bit = classical_bit
        self._register_name = register_name
    @property
    def qubit(self) -> int:
        return self._qubit
    @property
    def classical_bit(self) -> int:
        return self._classical_bit
    @property
    def register_name(self) -> str:
        return self._register_name
    def __repr__(self):
        return f"Measure(q{self._qubit}->c{self._classical_bit})"

class QuantumCircuit:
    __slots__ = ('_n_qubits', '_n_classical', '_instructions', '_measurements',
                 '_name', '_metadata', '_created_at')
    def __init__(self, n_qubits: int, n_classical: int = 0, name: str = ""):
        if n_qubits < 1:
            raise ValueError("Need at least 1 qubit")
        self._n_qubits = n_qubits
        self._n_classical = n_classical
        self._instructions: List[Instruction] = []
        self._measurements: List[Measurement] = []
        self._name = name
        self._metadata = {}
        self._created_at = time.time()
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def n_classical(self) -> int:
        return self._n_classical
    @property
    def instructions(self) -> List[Instruction]:
        return self._instructions[:]
    @property
    def measurements(self) -> List[Measurement]:
        return self._measurements[:]
    @property
    def name(self) -> str:
        return self._name
    @property
    def depth(self) -> int:
        return self._compute_depth()
    @property
    def width(self) -> int:
        return self._n_qubits + self._n_classical
    @property
    def gate_count(self) -> int:
        return len(self._instructions)
    @property
    def metadata(self) -> dict:
        return dict(self._metadata)
    def set_metadata(self, key: str, value):
        self._metadata[key] = value
    def add_instruction(self, gate: Gate, qubits: List[int],
                        classical_bits: Optional[List[int]] = None,
                        condition: Optional[Tuple[int, int]] = None):
        if gate.n_qubits != len(qubits):
            raise ValueError(f"Gate '{gate.name}' expects {gate.n_qubits} qubits, got {len(qubits)}")
        for q in qubits:
            if q < 0 or q >= self._n_qubits:
                raise IndexError(f"Qubit index {q} out of range")
        if classical_bits:
            for c in classical_bits:
                if c < 0 or c >= self._n_classical:
                    raise IndexError(f"Classical bit {c} out of range")
        if condition:
            if condition[0] < 0 or condition[0] >= self._n_classical:
                raise IndexError(f"Condition register bit out of range")
        inst = Instruction(gate, qubits, classical_bits, condition)
        self._instructions.append(inst)
    def add_measurement(self, qubit: int, classical_bit: int, register_name: str = "c"):
        if qubit < 0 or qubit >= self._n_qubits:
            raise IndexError(f"Qubit index {qubit} out of range")
        if classical_bit < 0 or classical_bit >= self._n_classical:
            raise IndexError(f"Classical bit {classical_bit} out of range")
        meas = Measurement(qubit, classical_bit, register_name)
        self._measurements.append(meas)
    def measure_all(self, classical_register: int = 0):
        for q in range(self._n_qubits):
            self._measurements.append(Measurement(q, q + classical_register * self._n_qubits))
    def h(self, qubit: int):
        self.add_instruction(get_gate("H"), [qubit])
    def x(self, qubit: int):
        self.add_instruction(get_gate("X"), [qubit])
    def y(self, qubit: int):
        self.add_instruction(get_gate("Y"), [qubit])
    def z(self, qubit: int):
        self.add_instruction(get_gate("Z"), [qubit])
    def s(self, qubit: int):
        self.add_instruction(get_gate("S"), [qubit])
    def t(self, qubit: int):
        self.add_instruction(get_gate("T"), [qubit])
    def sdg(self, qubit: int):
        self.add_instruction(get_gate("Sdg"), [qubit])
    def tdg(self, qubit: int):
        self.add_instruction(get_gate("Tdg"), [qubit])
    def rx(self, qubit: int, theta: float):
        gate = get_gate("Rx").with_params(theta)
        self.add_instruction(gate, [qubit])
    def ry(self, qubit: int, theta: float):
        gate = get_gate("Ry").with_params(theta)
        self.add_instruction(gate, [qubit])
    def rz(self, qubit: int, theta: float):
        gate = get_gate("Rz").with_params(theta)
        self.add_instruction(gate, [qubit])
    def cnot(self, control: int, target: int):
        self.add_instruction(get_gate("CNOT"), [control, target])
    def cx(self, control: int, target: int):
        self.cnot(control, target)
    def cz(self, qubit0: int, qubit1: int):
        self.add_instruction(get_gate("CZ"), [qubit0, qubit1])
    def swap(self, qubit0: int, qubit1: int):
        self.add_instruction(get_gate("SWAP"), [qubit0, qubit1])
    def ccx(self, ctrl0: int, ctrl1: int, target: int):
        self.add_instruction(get_gate("Toffoli"), [ctrl0, ctrl1, target])
    def toffoli(self, ctrl0: int, ctrl1: int, target: int):
        self.ccx(ctrl0, ctrl1, target)
    def barrier(self):
        self.add_instruction(Gate("barrier", 0, identity_matrix(1)), [])
    def compose(self, other: 'QuantumCircuit', qubit_map: Optional[Dict[int, int]] = None):
        if other._n_qubits > self._n_qubits:
            raise ValueError("Circuit to compose has more qubits")
        if qubit_map is None:
            qubit_map = {i: i for i in range(other._n_qubits)}
        for inst in other._instructions:
            new_qubits = [qubit_map[q] for q in inst.qubits]
            self.add_instruction(inst.gate, new_qubits, inst.classical_bits, inst.condition)
        for meas in other._measurements:
            new_q = qubit_map[meas.qubit]
            self._measurements.append(Measurement(new_q, meas.classical_bit, meas.register_name))
    def inverse(self) -> 'QuantumCircuit':
        inv = QuantumCircuit(self._n_qubits, self._n_classical, self._name + "_inv")
        for inst in reversed(self._instructions):
            from quantum_computer.gates import inverse_gate
            inv_gate = inverse_gate(inst.gate)
            inv.add_instruction(inv_gate, inst.qubits, inst.classical_bits, inst.condition)
        return inv
    def _compute_depth(self) -> int:
        if not self._instructions:
            return 0
        layer_end = {}
        max_depth = 0
        for inst in self._instructions:
            if inst.gate.name == "barrier":
                max_depth = max(layer_end.values()) + 1 if layer_end else 0
                layer_end = {}
                continue
            start = 0
            for q in inst.qubits:
                if q in layer_end:
                    start = max(start, layer_end[q])
            end = start + 1
            for q in inst.qubits:
                layer_end[q] = end
            max_depth = max(max_depth, end)
        return max_depth
    def qubit_lifetimes(self) -> Dict[int, int]:
        lifetimes = {}
        active = {}
        for inst in self._instructions:
            if inst.gate.name == "barrier":
                continue
            for q in inst.qubits:
                if q not in active:
                    active[q] = 0
                active[q] += 1
        return active
    def to_dict(self) -> dict:
        insts = []
        for inst in self._instructions:
            insts.append({
                "gate": inst.gate.name,
                "qubits": inst.qubits,
                "classical_bits": inst.classical_bits,
                "condition": inst.condition,
                "params": inst.gate.params
            })
        meas = []
        for m in self._measurements:
            meas.append({"qubit": m.qubit, "classical_bit": m.classical_bit})
        return {
            "n_qubits": self._n_qubits,
            "n_classical": self._n_classical,
            "name": self._name,
            "instructions": insts,
            "measurements": meas
        }
    @staticmethod
    def from_dict(d: dict) -> 'QuantumCircuit':
        circ = QuantumCircuit(d["n_qubits"], d.get("n_classical", 0), d.get("name", ""))
        for inst_d in d["instructions"]:
            gate_name = inst_d["gate"]
            params = inst_d.get("params", {})
            if params:
                from quantum_computer.gates import PARAMETERIZED_GATES
                if gate_name in PARAMETERIZED_GATES:
                    gate = PARAMETERIZED_GATES[gate_name].bind(**params)
                else:
                    gate = get_gate(gate_name)
            else:
                gate = get_gate(gate_name)
            circ.add_instruction(gate, inst_d["qubits"],
                                inst_d.get("classical_bits"),
                                inst_d.get("condition"))
        for m_d in d.get("measurements", []):
            circ._measurements.append(Measurement(m_d["qubit"], m_d["classical_bit"]))
        return circ
    def copy(self) -> 'QuantumCircuit':
        return QuantumCircuit.from_dict(self.to_dict())
    def __add__(self, other: 'QuantumCircuit') -> 'QuantumCircuit':
        if self._n_qubits != other._n_qubits:
            raise ValueError("Circuit qubit count mismatch")
        result = self.copy()
        result.compose(other)
        return result
    def __iadd__(self, other: 'QuantumCircuit'):
        self.compose(other)
        return self
    def __repr__(self):
        return f"QuantumCircuit(qubits={self._n_qubits}, classical={self._n_classical}, gates={self.gate_count}, depth={self.depth})"
    def __len__(self):
        return len(self._instructions)
    def __getitem__(self, index):
        return self._instructions[index]
    def clear(self):
        self._instructions.clear()
        self._measurements.clear()
    def remove_gate(self, index: int):
        if index < 0 or index >= len(self._instructions):
            raise IndexError("Instruction index out of range")
        del self._instructions[index]
    def replace_gate(self, index: int, gate: Gate, qubits: List[int]):
        if index < 0 or index >= len(self._instructions):
            raise IndexError("Instruction index out of range")
        if gate.n_qubits != len(qubits):
            raise ValueError("Qubit count mismatch")
        self._instructions[index] = Instruction(gate, qubits,
                                                self._instructions[index].classical_bits,
                                                self._instructions[index].condition)
