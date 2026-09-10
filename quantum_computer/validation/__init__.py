"""Validation: circuit validation, unitary validation, resource estimation."""
import math
from typing import List, Optional, Tuple, Dict
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix
from quantum_computer.core.state import QuantumState
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction
from quantum_computer.circuit.dag import CircuitDAG, circuit_to_dag
from quantum_computer.gates import Gate, GATE_SET, PARAMETERIZED_GATES, get_gate

class CircuitValidator:
    __slots__ = ('_strict',)
    def __init__(self, strict: bool = True):
        self._strict = strict
    def validate(self, circuit: QuantumCircuit) -> List[str]:
        errors = []
        errors.extend(self._validate_qubit_indices(circuit))
        errors.extend(self._validate_gate_dimensions(circuit))
        errors.extend(self._validate_classical_bits(circuit))
        errors.extend(self._validate_conditions(circuit))
        if self._strict:
            errors.extend(self._validate_dag(circuit))
        return errors
    def _validate_qubit_indices(self, circuit: QuantumCircuit) -> List[str]:
        errors = []
        for i, inst in enumerate(circuit.instructions):
            for q in inst.qubits:
                if q < 0 or q >= circuit.n_qubits:
                    errors.append(f"Instruction {i}: qubit index {q} out of range [0, {circuit.n_qubits})")
            for c in inst.classical_bits:
                if c < 0 or c >= circuit.n_classical:
                    errors.append(f"Instruction {i}: classical bit {c} out of range")
        return errors
    def _validate_gate_dimensions(self, circuit: QuantumCircuit) -> List[str]:
        errors = []
        for i, inst in enumerate(circuit.instructions):
            if inst.gate.n_qubits != len(inst.qubits):
                errors.append(f"Instruction {i}: gate '{inst.gate.name}' expects {inst.gate.n_qubits} qubits, got {len(inst.qubits)}")
        return errors
    def _validate_classical_bits(self, circuit: QuantumCircuit) -> List[str]:
        errors = []
        for meas in circuit.measurements:
            if meas.qubit < 0 or meas.qubit >= circuit.n_qubits:
                errors.append(f"Measurement: qubit {meas.qubit} out of range")
            if meas.classical_bit < 0 or meas.classical_bit >= circuit.n_classical:
                errors.append(f"Measurement: classical bit {meas.classical_bit} out of range")
        return errors
    def _validate_conditions(self, circuit: QuantumCircuit) -> List[str]:
        errors = []
        for i, inst in enumerate(circuit.instructions):
            if inst.condition:
                cbit, _ = inst.condition
                if cbit < 0 or cbit >= circuit.n_classical:
                    errors.append(f"Instruction {i}: condition bit {cbit} out of range")
        return errors
    def _validate_dag(self, circuit: QuantumCircuit) -> List[str]:
        try:
            dag = circuit_to_dag(circuit)
            return dag.validate()
        except Exception as e:
            return [f"DAG validation error: {str(e)}"]
    def validate_composition(self, circ_a: QuantumCircuit, circ_b: QuantumCircuit,
                              qubit_map: Dict[int, int]) -> List[str]:
        errors = []
        for q in qubit_map.values():
            if q < 0 or q >= circ_a.n_qubits:
                errors.append(f"Target qubit {q} out of range in destination circuit")
        for q in qubit_map.keys():
            if q < 0 or q >= circ_b.n_qubits:
                errors.append(f"Source qubit {q} out of range in source circuit")
        return errors

class UnitaryValidator:
    __slots__ = ('_tolerance',)
    def __init__(self, tolerance: float = 1e-10):
        self._tolerance = tolerance
    def is_unitary(self, matrix: Matrix) -> bool:
        if not matrix.is_square():
            return False
        product = matrix * matrix.dagger()
        identity = identity_matrix(matrix.rows)
        return self._matrix_approx_eq(product, identity)
    def is_hermitian(self, matrix: Matrix) -> bool:
        if not matrix.is_square():
            return False
        return self._matrix_approx_eq(matrix, matrix.dagger())
    def is_positive_semidefinite(self, matrix: Matrix) -> bool:
        if not self.is_hermitian(matrix):
            return False
        n = matrix.rows
        for state_idx in range(1 << n):
            vec = [ZERO] * n
            for i in range(n):
                if (state_idx >> i) & 1:
                    vec[i] = ONE
            expectation = ZERO
            for r in range(n):
                for c in range(n):
                    expectation = expectation + vec[r].conjugate() * matrix.get(r, c) * vec[c]
            if expectation.re < -self._tolerance:
                return False
        return True
    def verify_circuit_unitary(self, circuit: QuantumCircuit) -> Tuple[bool, Optional[Matrix]]:
        dim = 1 << circuit.n_qubits
        unitary = identity_matrix(dim)
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                continue
            gate_matrix = self._expand_gate(inst.gate, inst.qubits, circuit.n_qubits)
            unitary = unitary * gate_matrix
        is_u = self.is_unitary(unitary)
        return is_u, unitary
    def _expand_gate(self, gate: Gate, qubits: List[int], n_total: int) -> Matrix:
        if n_total == gate.n_qubits and qubits == list(range(n_total)):
            return gate.matrix
        dim = 1 << n_total
        data = [[ZERO] * dim for _ in range(dim)]
        for state in range(dim):
            gate_idx = 0
            for q in qubits:
                bit = (state >> (n_total - 1 - q)) & 1
                gate_idx = (gate_idx << 1) | bit
            other_bits = 0
            occupied = set(qubits)
            pos = 0
            for b in range(n_total):
                if b not in occupied:
                    bit = (state >> (n_total - 1 - b)) & 1
                    other_bits |= bit << pos
                    pos += 1
            for new_gate_idx in range(gate.matrix.rows):
                coeff = gate.matrix.get(gate_idx, new_gate_idx)
                if coeff.abs_sq() < 1e-24:
                    continue
                new_state = 0
                remaining = other_bits
                pos = 0
                for b in range(n_total):
                    if b in occupied:
                        q_pos = qubits.index(b)
                        new_bit = (new_gate_idx >> (len(qubits) - 1 - q_pos)) & 1
                        new_state |= new_bit << (n_total - 1 - b)
                    else:
                        bit = (remaining >> pos) & 1
                        new_state |= bit << (n_total - 1 - b)
                        pos += 1
                data[new_state][state] = data[new_state][state] + coeff
        return Matrix(data)
    def _matrix_approx_eq(self, a: Matrix, b: Matrix) -> bool:
        if a.rows != b.rows or a.cols != b.cols:
            return False
        for r in range(a.rows):
            for c in range(a.cols):
                diff = a.get(r, c) - b.get(r, c)
                if diff.abs_sq() > self._tolerance * self._tolerance:
                    return False
        return True

class ResourceEstimator:
    __slots__ = ('_gate_costs',)
    def __init__(self):
        self._gate_costs = {
            "I": 0, "X": 1, "Y": 1, "Z": 1, "H": 1, "S": 1, "T": 1,
            "CNOT": 10, "SWAP": 30, "Toffoli": 15, "Fredkin": 20,
            "Rx": 1, "Ry": 1, "Rz": 1, "Phase": 1
        }
    def estimate(self, circuit: QuantumCircuit) -> Dict[str, int]:
        return {
            "qubits": circuit.n_qubits,
            "classical_bits": circuit.n_classical,
            "depth": circuit.depth,
            "gate_count": circuit.gate_count,
            "t_gates": self._count_gate_type(circuit, "T"),
            "cnot_count": self._count_gate_type(circuit, "CNOT"),
            "t_depth": self._compute_t_depth(circuit),
            "t_count": self._count_gate_type(circuit, "T"),
            "cost": self._compute_cost(circuit)
        }
    def _count_gate_type(self, circuit: QuantumCircuit, gate_name: str) -> int:
        count = 0
        for inst in circuit.instructions:
            if inst.gate.name == gate_name:
                count += 1
        return count
    def _compute_t_depth(self, circuit: QuantumCircuit) -> int:
        t_depth = 0
        current_t_depth = 0
        qubit_t_depth = {}
        for inst in circuit.instructions:
            if inst.gate.name == "T" or inst.gate.name == "Tdg":
                max_d = 0
                for q in inst.qubits:
                    max_d = max(max_d, qubit_t_depth.get(q, 0))
                new_d = max_d + 1
                for q in inst.qubits:
                    qubit_t_depth[q] = new_d
                current_t_depth = max(current_t_depth, new_d)
                t_depth = max(t_depth, current_t_depth)
        return t_depth
    def _compute_cost(self, circuit: QuantumCircuit) -> int:
        total = 0
        for inst in circuit.instructions:
            cost = self._gate_costs.get(inst.gate.name, 1)
            total += cost
        return total
    def estimate_qubit_lifetime(self, circuit: QuantumCircuit) -> Dict[int, int]:
        lifetimes = {}
        first_use = {}
        last_use = {}
        for i, inst in enumerate(circuit.instructions):
            for q in inst.qubits:
                if q not in first_use:
                    first_use[q] = i
                last_use[q] = i
        for q in set(list(first_use.keys()) + list(last_use.keys())):
            lifetimes[q] = last_use[q] - first_use[q] + 1
        return lifetimes
    def estimate_parallelism(self, circuit: QuantumCircuit) -> float:
        depth = circuit.depth
        if depth == 0:
            return 0.0
        return circuit.gate_count / depth
    def compare_circuits(self, a: QuantumCircuit, b: QuantumCircuit) -> Dict[str, any]:
        ea = self.estimate(a)
        eb = self.estimate(b)
        return {
            "depth_ratio": ea["depth"] / eb["depth"] if eb["depth"] > 0 else float('inf'),
            "gate_ratio": ea["gate_count"] / eb["gate_count"] if eb["gate_count"] > 0 else float('inf'),
            "t_ratio": ea["t_count"] / eb["t_count"] if eb["t_count"] > 0 else float('inf'),
            "cost_ratio": ea["cost"] / eb["cost"] if eb["cost"] > 0 else float('inf')
        }

class DimensionValidator:
    __slots__ = ('_tolerance',)
    def __init__(self, tolerance: float = 1e-10):
        self._tolerance = tolerance
    def validate_register_consistency(self, circuit: QuantumCircuit) -> List[str]:
        errors = []
        for inst in circuit.instructions:
            if inst.gate.n_qubits != len(inst.qubits):
                errors.append(f"Gate '{inst.gate.name}' dimension mismatch")
        return errors
    def validate_state_dimensions(self, state: QuantumState, expected_qubits: int) -> List[str]:
        errors = []
        if state.n_qubits != expected_qubits:
            errors.append(f"State has {state.n_qubits} qubits, expected {expected_qubits}")
        if state.dim != (1 << expected_qubits):
            errors.append(f"State dimension {state.dim} doesn't match 2^{expected_qubits}")
        return errors
    def validate_circuit_state_match(self, circuit: QuantumCircuit, state: QuantumState) -> List[str]:
        errors = []
        if circuit.n_qubits != state.n_qubits:
            errors.append(f"Circuit has {circuit.n_qubits} qubits, state has {state.n_qubits}")
        return errors
