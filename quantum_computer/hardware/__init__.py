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

"""Hardware abstraction: connectivity maps, gate sets, transpilation, routing."""
import math
from typing import List, Optional, Tuple, Dict, Set
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction
from quantum_computer.gates import Gate, get_gate, GATE_SET, SWAP_GATE

class QubitConnectivity:
    __slots__ = ('_n_qubits', '_edges', '_adjacency')
    def __init__(self, n_qubits: int, edges: Optional[List[Tuple[int, int]]] = None):
        self._n_qubits = n_qubits
        self._edges = []
        self._adjacency: Dict[int, Set[int]] = {i: set() for i in range(n_qubits)}
        if edges:
            for e in edges:
                self.add_edge(e[0], e[1])
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def edges(self) -> List[Tuple[int, int]]:
        return self._edges[:]
    def add_edge(self, q0: int, q1: int):
        if q0 < 0 or q0 >= self._n_qubits or q1 < 0 or q1 >= self._n_qubits:
            raise IndexError("Qubit index out of range")
        if q0 == q1:
            raise ValueError("Self-loops not allowed")
        if q1 not in self._adjacency[q0]:
            self._edges.append((q0, q1))
            self._adjacency[q0].add(q1)
            self._adjacency[q1].add(q0)
    def are_connected(self, q0: int, q1: int) -> bool:
        return q1 in self._adjacency[q0]
    def neighbors(self, qubit: int) -> List[int]:
        return list(self._adjacency[qubit])
    def shortest_path(self, src: int, dst: int) -> List[int]:
        if src == dst:
            return [src]
        visited = {src}
        queue = [(src, [src])]
        while queue:
            current, path = queue.pop(0)
            for neighbor in self._adjacency[current]:
                if neighbor == dst:
                    return path + [neighbor]
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append((neighbor, path + [neighbor]))
        return []
    def swap_distance(self, q0: int, q1: int) -> int:
        path = self.shortest_path(q0, q1)
        return len(path) - 1 if path else -1
    def is_linear(self) -> bool:
        for q in range(self._n_qubits):
            if len(self._adjacency[q]) > 2:
                return False
        return True
    def is_fully_connected(self) -> bool:
        expected = self._n_qubits * (self._n_qubits - 1) // 2
        return len(self._edges) == expected
    def __repr__(self):
        return f"QubitConnectivity(n={self._n_qubits}, edges={len(self._edges)})"

class HardwareGateSet:
    __slots__ = ('_native_gates', '_gate_durations', '_gate_errors')
    def __init__(self):
        self._native_gates: List[str] = ["I", "X", "Z", "H", "CNOT", "Rz"]
        self._gate_durations: Dict[str, float] = {
            "I": 0.0, "X": 35.0, "Z": 35.0, "H": 35.0, "CNOT": 300.0, "Rz": 35.0
        }
        self._gate_errors: Dict[str, float] = {
            "I": 0.0, "X": 0.001, "Z": 0.001, "H": 0.001, "CNOT": 0.01, "Rz": 0.001
        }
    @property
    def native_gates(self) -> List[str]:
        return self._native_gates[:]
    def set_native_gates(self, gates: List[str]):
        self._native_gates = gates[:]
    def get_duration(self, gate_name: str) -> float:
        return self._gate_durations.get(gate_name, 100.0)
    def get_error_rate(self, gate_name: str) -> float:
        return self._gate_errors.get(gate_name, 0.01)
    def set_error_rate(self, gate_name: str, rate: float):
        self._gate_errors[gate_name] = rate
    def set_duration(self, gate_name: str, duration: float):
        self._gate_durations[gate_name] = duration
    def is_native(self, gate_name: str) -> bool:
        return gate_name in self._native_gates
    def total_duration(self, circuit: QuantumCircuit) -> float:
        total = 0.0
        for inst in circuit.instructions:
            total += self.get_duration(inst.gate.name)
        return total
    def total_error_rate(self, circuit: QuantumCircuit) -> float:
        total = 1.0
        for inst in circuit.instructions:
            total *= (1 - self.get_error_rate(inst.gate.name))
        return 1 - total
    def __repr__(self):
        return f"HardwareGateSet(native={self._native_gates})"

class Transpiler:
    __slots__ = ('_gate_set', '_connectivity')
    def __init__(self, gate_set: Optional[HardwareGateSet] = None,
                 connectivity: Optional[QubitConnectivity] = None):
        self._gate_set = gate_set or HardwareGateSet()
        self._connectivity = connectivity
    @property
    def gate_set(self) -> HardwareGateSet:
        return self._gate_set
    def transpile(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        result = self._decompose_gates(result)
        if self._connectivity:
            result = self._route(result)
        return result
    def _decompose_gates(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = QuantumCircuit(circuit.n_qubits, circuit.n_classical, circuit.name)
        for inst in circuit.instructions:
            if self._gate_set.is_native(inst.gate.name) or inst.gate.name == "barrier":
                result.add_instruction(inst.gate, inst.qubits, inst.classical_bits, inst.condition)
            else:
                decomposed = self._decompose_instruction(inst)
                for d_inst in decomposed:
                    result.add_instruction(d_inst.gate, d_inst.qubits)
        for meas in circuit.measurements:
            result._measurements.append(meas)
        return result
    def _decompose_instruction(self, inst: Instruction) -> List[Instruction]:
        name = inst.gate.name
        qubits = inst.qubits
        if name == "T":
            return [Instruction(get_gate("Rz").with_params(math.pi / 4), qubits)]
        elif name == "Tdg":
            return [Instruction(get_gate("Rz").with_params(-math.pi / 4), qubits)]
        elif name == "S":
            return [Instruction(get_gate("Rz").with_params(math.pi / 2), qubits)]
        elif name == "Sdg":
            return [Instruction(get_gate("Rz").with_params(-math.pi / 2), qubits)]
        elif name == "Y":
            return [Instruction(get_gate("Rz").with_params(math.pi), qubits),
                    Instruction(get_gate("X"), qubits),
                    Instruction(get_gate("Rz").with_params(math.pi), qubits)]
        elif name == "SWAP":
            return [Instruction(get_gate("CNOT"), [qubits[0], qubits[1]]),
                    Instruction(get_gate("CNOT"), [qubits[1], qubits[0]]),
                    Instruction(get_gate("CNOT"), [qubits[0], qubits[1]])]
        elif name == "Toffoli":
            return self._decompose_toffoli(qubits)
        elif name == "Fredkin":
            return self._decompose_fredkin(qubits)
        elif name == "CZ":
            return [Instruction(get_gate("H"), [qubits[1]]),
                    Instruction(get_gate("CNOT"), qubits),
                    Instruction(get_gate("H"), [qubits[1]])]
        elif name == "Rx":
            theta = inst.gate.params.get("theta", 0)
            return [Instruction(get_gate("H"), qubits),
                    Instruction(get_gate("Rz").with_params(theta), qubits),
                    Instruction(get_gate("H"), qubits)]
        elif name == "Ry":
            theta = inst.gate.params.get("theta", 0)
            return [Instruction(get_gate("Rz").with_params(math.pi / 2), qubits),
                    Instruction(get_gate("H"), qubits),
                    Instruction(get_gate("Rz").with_params(theta), qubits),
                    Instruction(get_gate("H"), qubits),
                    Instruction(get_gate("Rz").with_params(-math.pi / 2), qubits)]
        else:
            return [inst]
    def _decompose_toffoli(self, qubits: List[int]) -> List[Instruction]:
        a, b, c = qubits
        return [
            Instruction(get_gate("H"), [c]),
            Instruction(get_gate("CNOT"), [b, c]),
            Instruction(get_gate("Rz").with_params(-math.pi / 4), [c]),
            Instruction(get_gate("CNOT"), [a, c]),
            Instruction(get_gate("Rz").with_params(math.pi / 4), [c]),
            Instruction(get_gate("CNOT"), [b, c]),
            Instruction(get_gate("Rz").with_params(-math.pi / 4), [c]),
            Instruction(get_gate("CNOT"), [a, c]),
            Instruction(get_gate("Rz").with_params(math.pi / 4), [c]),
            Instruction(get_gate("H"), [c]),
        ]
    def _decompose_fredkin(self, qubits: List[int]) -> List[Instruction]:
        s, c0, c1 = qubits
        return [
            Instruction(get_gate("CNOT"), [c1, s]),
            Instruction(get_gate("H"), [c1]),
            Instruction(get_gate("CNOT"), [c0, c1]),
            Instruction(get_gate("H"), [c1]),
            Instruction(get_gate("CNOT"), [c1, s]),
        ]
    def _route(self, circuit: QuantumCircuit) -> QuantumCircuit:
        router = Router(self._connectivity)
        return router.route(circuit)

class Router:
    __slots__ = ('_connectivity')
    def __init__(self, connectivity: QubitConnectivity):
        self._connectivity = connectivity
    def route(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = QuantumCircuit(circuit.n_qubits, circuit.n_classical, circuit.name)
        qubit_map = {i: i for i in range(circuit.n_qubits)}
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                result.add_instruction(inst.gate, inst.qubits)
                continue
            mapped_qubits = [qubit_map[q] for q in inst.qubits]
            if len(mapped_qubits) == 2:
                if not self._connectivity.are_connected(mapped_qubits[0], mapped_qubits[1]):
                    path = self._connectivity.shortest_path(mapped_qubits[0], mapped_qubits[1])
                    if path and len(path) > 1:
                        for i in range(len(path) - 1):
                            result.add_instruction(SWAP_GATE, [path[i], path[i + 1]])
                        mapped_qubits = [qubit_map[q] for q in inst.qubits]
            result.add_instruction(inst.gate, mapped_qubits, inst.classical_bits, inst.condition)
        return result
    def insert_swaps(self, circuit: QuantumCircuit, q0: int, q1: int) -> QuantumCircuit:
        result = circuit.copy()
        path = self._connectivity.shortest_path(q0, q1)
        if path:
            for i in range(len(path) - 1):
                result.add_instruction(SWAP_GATE, [path[i], path[i + 1]])
        return result

class HardwareBackend:
    __slots__ = ('_name', '_n_qubits', '_connectivity', '_gate_set', '_t1', '_t2', '_gate_time')
    def __init__(self, name: str, n_qubits: int,
                 connectivity: Optional[QubitConnectivity] = None,
                 gate_set: Optional[HardwareGateSet] = None,
                 t1: float = 50e-6, t2: float = 70e-6, gate_time: float = 35e-9):
        self._name = name
        self._n_qubits = n_qubits
        self._connectivity = connectivity or QubitConnectivity(n_qubits)
        self._gate_set = gate_set or HardwareGateSet()
        self._t1 = t1
        self._t2 = t2
        self._gate_time = gate_time
    @property
    def name(self) -> str:
        return self._name
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def connectivity(self) -> QubitConnectivity:
        return self._connectivity
    @property
    def gate_set(self) -> HardwareGateSet:
        return self._gate_set
    @property
    def t1(self) -> float:
        return self._t1
    @property
    def t2(self) -> float:
        return self._t2
    def validate_circuit(self, circuit: QuantumCircuit) -> List[str]:
        errors = []
        if circuit.n_qubits > self._n_qubits:
            errors.append(f"Circuit requires {circuit.n_qubits} qubits, backend has {self._n_qubits}")
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                continue
            if not self._gate_set.is_native(inst.gate.name):
                errors.append(f"Gate '{inst.gate.name}' not in native gate set")
            if len(inst.qubits) == 2:
                if not self._connectivity.are_connected(inst.qubits[0], inst.qubits[1]):
                    errors.append(f"Qubits {inst.qubits[0]} and {inst.qubits[1]} not connected")
        return errors
    def estimate_execution_time(self, circuit: QuantumCircuit) -> float:
        return self._gate_set.total_duration(circuit)
    def estimate_fidelity(self, circuit: QuantumCircuit) -> float:
        return 1.0 - self._gate_set.total_error_rate(circuit)
    def __repr__(self):
        return f"HardwareBackend('{self._name}', n_qubits={self._n_qubits})"

def create_linear_backend(n_qubits: int, name: str = "linear") -> HardwareBackend:
    connectivity = QubitConnectivity(n_qubits)
    for i in range(n_qubits - 1):
        connectivity.add_edge(i, i + 1)
    return HardwareBackend(name, n_qubits, connectivity)

def create_fully_connected_backend(n_qubits: int, name: str = "fully_connected") -> HardwareBackend:
    connectivity = QubitConnectivity(n_qubits)
    for i in range(n_qubits):
        for j in range(i + 1, n_qubits):
            connectivity.add_edge(i, j)
    return HardwareBackend(name, n_qubits, connectivity)

def create_grid_backend(rows: int, cols: int, name: str = "grid") -> HardwareBackend:
    n = rows * cols
    connectivity = QubitConnectivity(n)
    for r in range(rows):
        for c in range(cols):
            idx = r * cols + c
            if c + 1 < cols:
                connectivity.add_edge(idx, idx + 1)
            if r + 1 < rows:
                connectivity.add_edge(idx, idx + cols)
    return HardwareBackend(name, n, connectivity)
