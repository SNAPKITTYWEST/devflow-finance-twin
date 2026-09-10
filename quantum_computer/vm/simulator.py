"""Quantum simulator backend: deterministic simulation, state snapshots, density matrix."""
import math
import random
from typing import List, Optional, Tuple, Dict, Any
from quantum_computer.core.complex import Complex, ZERO, ONE, I
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product
from quantum_computer.core.state import QuantumState, zero_state, computational_basis_state
from quantum_computer.core.register import QuantumRegister, ClassicalRegister
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction
from quantum_computer.gates import Gate, get_gate

class DensityMatrix:
    __slots__ = ('_n_qubits', '_matrix', '_dim')
    def __init__(self, n_qubits: int, matrix: Optional[Matrix] = None):
        self._n_qubits = n_qubits
        self._dim = 1 << n_qubits
        if matrix is not None:
            self._matrix = matrix
        else:
            data = [[ZERO] * self._dim for _ in range(self._dim)]
            data[0][0] = ONE
            self._matrix = Matrix(data)
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def dim(self) -> int:
        return self._dim
    @property
    def matrix(self) -> Matrix:
        return self._matrix
    def trace(self) -> Complex:
        return self._matrix.trace()
    def purity(self) -> float:
        return (self._matrix * self._matrix).trace().re
    def is_pure(self, tol: float = 1e-10) -> bool:
        return abs(self.purity() - 1.0) < tol
    def fidelity(self, other: 'DensityMatrix') -> float:
        if self._n_qubits != other._n_qubits:
            raise ValueError("Qubit count mismatch")
        sqrt_a = self._matrix_sqrt()
        product = sqrt_a * other._matrix * sqrt_a
        sqrt_product = product._matrix_sqrt() if hasattr(product, '_matrix_sqrt') else self._matrix_sqrt()
        trace_val = sqrt_product.trace()
        return trace_val.abs_sq()
    def _matrix_sqrt(self) -> 'DensityMatrix':
        n = self._dim
        data = [[ZERO] * n for _ in range(n)]
        for i in range(n):
            val = self._matrix.get(i, i)
            if val.re >= 0:
                data[i][i] = Complex(math.sqrt(val.re))
            else:
                data[i][i] = ZERO
        return DensityMatrix(self._n_qubits, Matrix(data))
    def partial_trace(self, trace_qubits: List[int]) -> 'DensityMatrix':
        keep = [i for i in range(self._n_qubits) if i not in trace_qubits]
        n_keep = len(keep)
        new_dim = 1 << n_keep
        new_data = [[ZERO] * new_dim for _ in range(new_dim)]
        for r in range(self._dim):
            for c in range(self._dim):
                keep_r = 0
                keep_c = 0
                for i, k in enumerate(keep):
                    bit_r = (r >> (self._n_qubits - 1 - k)) & 1
                    bit_c = (c >> (self._n_qubits - 1 - k)) & 1
                    keep_r |= bit_r << (n_keep - 1 - i)
                    keep_c |= bit_c << (n_keep - 1 - i)
                trace_match = True
                for t in trace_qubits:
                    bit_r = (r >> (self._n_qubits - 1 - t)) & 1
                    bit_c = (c >> (self._n_qubits - 1 - t)) & 1
                    if bit_r != bit_c:
                        trace_match = False
                        break
                if trace_match:
                    new_data[keep_r][keep_c] = new_data[keep_r][keep_c] + self._matrix.get(r, c)
        return DensityMatrix(n_keep, Matrix(new_data))
    def apply_gate(self, gate_matrix: Matrix, qubits: Optional[List[int]] = None):
        if qubits is None or (gate_matrix.rows == self._dim):
            self._matrix = gate_matrix * self._matrix * gate_matrix.dagger()
        else:
            full_gate = self._expand_gate(gate_matrix, qubits)
            self._matrix = full_gate * self._matrix * full_gate.dagger()
    def _expand_gate(self, gate: Matrix, qubits: List[int]) -> Matrix:
        dim = 1 << self._n_qubits
        data = [[ZERO] * dim for _ in range(dim)]
        for state in range(dim):
            gate_idx = 0
            for q in qubits:
                bit = (state >> (self._n_qubits - 1 - q)) & 1
                gate_idx = (gate_idx << 1) | bit
            other_positions = [b for b in range(self._n_qubits) if b not in qubits]
            for new_gate_idx in range(gate.rows):
                coeff = gate.get(gate_idx, new_gate_idx)
                if coeff.abs_sq() < 1e-24:
                    continue
                new_state = 0
                for b in other_positions:
                    bit = (state >> (self._n_qubits - 1 - b)) & 1
                    new_state |= bit << (self._n_qubits - 1 - b)
                for i, q in enumerate(qubits):
                    new_bit = (new_gate_idx >> (len(qubits) - 1 - i)) & 1
                    new_state |= new_bit << (self._n_qubits - 1 - q)
                data[new_state][state] = data[new_state][state] + coeff
        return Matrix(data)
    def apply_channel(self, kraus_ops: List[Matrix]):
        new_data = [[ZERO] * self._dim for _ in range(self._dim)]
        for k in kraus_ops:
            k_rho = k * self._matrix * k.dagger()
            for r in range(self._dim):
                for c in range(self._dim):
                    new_data[r][c] = new_data[r][c] + k_rho.get(r, c)
        self._matrix = Matrix(new_data)
    def measure(self, qubit: int) -> Tuple[int, 'DensityMatrix']:
        prob_0 = ZERO
        for state in range(self._dim):
            bit = (state >> (self._n_qubits - 1 - qubit)) & 1
            if bit == 0:
                prob_0 = prob_0 + Complex(self._matrix.get(state, state).re)
        p0 = prob_0.re
        outcome = 0 if random.random() < p0 else 1
        new_data = [[ZERO] * self._dim for _ in range(self._dim)]
        norm = 0.0
        for state in range(self._dim):
            bit = (state >> (self._n_qubits - 1 - qubit)) & 1
            if bit == outcome:
                for c in range(self._dim):
                    bit_c = (c >> (self._n_qubits - 1 - qubit)) & 1
                    if bit_c == outcome:
                        new_data[state][c] = self._matrix.get(state, c)
                        if state == c:
                            norm += self._matrix.get(state, c).re
        if norm > 1e-12:
            inv_norm = 1.0 / norm
            for r in range(self._dim):
                for c in range(self._dim):
                    new_data[r][c] = new_data[r][c] * inv_norm
        return outcome, DensityMatrix(self._n_qubits, Matrix(new_data))
    def expectation(self, observable: Matrix) -> Complex:
        return (self._matrix * observable).trace()
    def von_neumann_entropy(self) -> float:
        eigenvals = []
        for i in range(self._dim):
            val = self._matrix.get(i, i).re
            if val > 1e-12:
                eigenvals.append(val)
        entropy = 0.0
        for v in eigenvals:
            entropy -= v * math.log(v)
        return entropy
    @staticmethod
    def from_state(state: QuantumState) -> 'DensityMatrix':
        n = state.n_qubits
        dim = state.dim
        data = []
        for r in range(dim):
            row = []
            for c in range(dim):
                row.append(state.amplitudes[r] * state.amplitudes[c].conjugate())
            data.append(row)
        return DensityMatrix(n, Matrix(data))
    def __repr__(self):
        return f"DensityMatrix(n_qubits={self._n_qubits}, purity={self.purity():.4f})"

class StateSnapshot:
    __slots__ = ('_step', '_state', '_density_matrix', '_metadata')
    def __init__(self, step: int, state: QuantumState, metadata: Optional[dict] = None):
        self._step = step
        self._state = state
        self._density_matrix = DensityMatrix.from_state(state)
        self._metadata = metadata or {}
    @property
    def step(self) -> int:
        return self._step
    @property
    def state(self) -> QuantumState:
        return self._state
    @property
    def density_matrix(self) -> DensityMatrix:
        return self._density_matrix
    @property
    def metadata(self) -> dict:
        return dict(self._metadata)
    def __repr__(self):
        return f"StateSnapshot(step={self._step})"

class DeterministicSimulator:
    __slots__ = ('_n_qubits', '_snapshots', '_record_snapshots')
    def __init__(self, n_qubits: int, record_snapshots: bool = False):
        self._n_qubits = n_qubits
        self._snapshots: List[StateSnapshot] = []
        self._record_snapshots = record_snapshots
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def snapshots(self) -> List[StateSnapshot]:
        return self._snapshots[:]
    def simulate(self, circuit: QuantumCircuit) -> QuantumState:
        reg = QuantumRegister(self._n_qubits)
        self._snapshots = []
        step = 0
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                continue
            if inst.gate.n_qubits == 1:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            elif inst.gate.n_qubits == 2:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            elif inst.gate.n_qubits == 3:
                from quantum_computer.algorithms import _expand_toffoli_like
                full_gate = _expand_toffoli_like(inst.gate, inst.qubits, reg.size)
                reg.apply_gate(full_gate, list(range(reg.size)))
            else:
                from quantum_computer.algorithms import _expand_multi_gate
                full_gate = _expand_multi_gate(inst.gate, inst.qubits, reg.size)
                reg.apply_gate(full_gate, list(range(reg.size)))
            if self._record_snapshots:
                self._snapshots.append(StateSnapshot(step, reg.state.copy(), {"gate": inst.gate.name}))
            step += 1
        return reg.state
    def simulate_density_matrix(self, circuit: QuantumCircuit) -> DensityMatrix:
        state = self.simulate(circuit)
        return DensityMatrix.from_state(state)
    def simulate_with_measurements(self, circuit: QuantumCircuit,
                                    measurements: List[int]) -> Tuple[QuantumState, List[int]]:
        reg = QuantumRegister(self._n_qubits)
        step = 0
        meas_idx = 0
        outcomes = []
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                continue
            if inst.gate.n_qubits == 1:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            elif inst.gate.n_qubits == 2:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            else:
                from quantum_computer.algorithms import _expand_toffoli_like
                full_gate = _expand_toffoli_like(inst.gate, inst.qubits, reg.size)
                reg.apply_gate(full_gate, list(range(reg.size)))
            step += 1
        for q in measurements:
            outcome, new_state = reg.state.measure_qubit(q)
            reg.set_state(new_state)
            outcomes.append(outcome)
        return reg.state, outcomes
    def compute_fidelity(self, circuit_a: QuantumCircuit, circuit_b: QuantumCircuit) -> float:
        state_a = self.simulate(circuit_a)
        state_b = self.simulate(circuit_b)
        return state_a.fidelity(state_b)
    def compute_trace_distance(self, rho: DensityMatrix, sigma: DensityMatrix) -> float:
        diff = rho.matrix - sigma.matrix
        n = diff.rows
        eigenvals = []
        for i in range(n):
            val = diff.get(i, i).re
            eigenvals.append(abs(val))
        return sum(eigenvals) / 2.0

class NoisySimulator:
    __slots__ = ('_base_simulator', '_noise_model', '_n_shots')
    def __init__(self, n_qubits: int, noise_model=None, n_shots: int = 1024):
        self._base_simulator = DeterministicSimulator(n_qubits)
        self._noise_model = noise_model
        self._n_shots = n_shots
    def simulate(self, circuit: QuantumCircuit) -> QuantumState:
        if self._noise_model is None:
            return self._base_simulator.simulate(circuit)
        reg = QuantumRegister(circuit.n_qubits)
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                continue
            if inst.gate.n_qubits == 1:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            elif inst.gate.n_qubits == 2:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            else:
                from quantum_computer.algorithms import _expand_toffoli_like
                full_gate = _expand_toffoli_like(inst.gate, inst.qubits, reg.size)
                reg.apply_gate(full_gate, list(range(reg.size)))
            if hasattr(self._noise_model, 'apply_noise'):
                reg._state = self._noise_model.apply_noise(reg.state, inst.gate.name)
            elif hasattr(self._noise_model, 'apply'):
                reg._state = self._noise_model.apply(reg.state)
        return reg.state
    def run_shots(self, circuit: QuantumCircuit) -> Dict[str, int]:
        counts = {}
        for _ in range(self._n_shots):
            state = self.simulate(circuit)
            bits = []
            for q in range(circuit.n_qubits):
                prob_1 = state.probability(1 << (circuit.n_qubits - 1 - q))
                bit = 1 if random.random() < prob_1 else 0
                bits.append(str(bit))
            bitstring = "".join(bits)
            counts[bitstring] = counts.get(bitstring, 0) + 1
        return counts
    def compute_expectation(self, circuit: QuantumCircuit, observable: Matrix) -> float:
        state = self.simulate(circuit)
        return state.expectation(observable).re
    def __repr__(self):
        return f"NoisySimulator(n_qubits={self._base_simulator.n_qubits})"

class StatevectorSimulator:
    __slots__ = ('_n_qubits')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    def simulate(self, circuit: QuantumCircuit) -> List[Complex]:
        reg = QuantumRegister(self._n_qubits)
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                continue
            if inst.gate.n_qubits == 1:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            elif inst.gate.n_qubits == 2:
                reg.apply_gate(inst.gate.matrix, inst.qubits)
            else:
                from quantum_computer.algorithms import _expand_toffoli_like
                full_gate = _expand_toffoli_like(inst.gate, inst.qubits, reg.size)
                reg.apply_gate(full_gate, list(range(reg.size)))
        return reg.state.amplitudes
    def probabilities(self, circuit: QuantumCircuit) -> List[float]:
        amps = self.simulate(circuit)
        return [a.abs_sq() for a in amps]
    def measure(self, circuit: QuantumCircuit) -> List[int]:
        probs = self.probabilities(circuit)
        total = sum(probs)
        if total > 0:
            probs = [p / total for p in probs]
        r = random.random()
        cum = 0.0
        outcome = 0
        for i, p in enumerate(probs):
            cum += p
            if r < cum:
                outcome = i
                break
        bits = []
        for q in range(self._n_qubits):
            bits.append((outcome >> (self._n_qubits - 1 - q)) & 1)
        return bits
    def __repr__(self):
        return f"StatevectorSimulator(n_qubits={self._n_qubits})"

class UnitarySimulator:
    __slots__ = ('_n_qubits')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    def simulate(self, circuit: QuantumCircuit) -> Matrix:
        dim = 1 << self._n_qubits
        unitary = identity_matrix(dim)
        for inst in circuit.instructions:
            if inst.gate.name == "barrier":
                continue
            gate_matrix = self._expand_gate(inst.gate, inst.qubits)
            unitary = unitary * gate_matrix
        return unitary
    def _expand_gate(self, gate: Gate, qubits: List[int]) -> Matrix:
        if self._n_qubits == gate.n_qubits and qubits == list(range(self._n_qubits)):
            return gate.matrix
        dim = 1 << self._n_qubits
        data = [[ZERO] * dim for _ in range(dim)]
        gate_mat = gate.matrix
        for state in range(dim):
            gate_idx = 0
            for q in qubits:
                bit = (state >> (self._n_qubits - 1 - q)) & 1
                gate_idx = (gate_idx << 1) | bit
            other_positions = [b for b in range(self._n_qubits) if b not in qubits]
            for new_gate_idx in range(gate_mat.rows):
                coeff = gate_mat.get(gate_idx, new_gate_idx)
                if coeff.abs_sq() < 1e-24:
                    continue
                new_state = 0
                for b in other_positions:
                    bit = (state >> (self._n_qubits - 1 - b)) & 1
                    new_state |= bit << (self._n_qubits - 1 - b)
                for i, q in enumerate(qubits):
                    new_bit = (new_gate_idx >> (len(qubits) - 1 - i)) & 1
                    new_state |= new_bit << (self._n_qubits - 1 - q)
                data[new_state][state] = data[new_state][state] + coeff
        return Matrix(data)
    def is_unitary(self, circuit: QuantumCircuit) -> bool:
        u = self.simulate(circuit)
        return u.is_unitary()
    def __repr__(self):
        return f"UnitarySimulator(n_qubits={self._n_qubits})"

class MatrixProductState:
    __slots__ = ('_n_qubits', '_tensors')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        self._tensors = []
        for i in range(n_qubits):
            if i == 0:
                self._tensors.append([[ONE, ZERO]])
            elif i == n_qubits - 1:
                self._tensors.append([[ONE], [ZERO]])
            else:
                self._tensors.append([[ONE, ZERO], [ZERO, ZERO]])
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    def apply_single_qubit_gate(self, gate: Matrix, target: int):
        if target == 0:
            new_tensor = []
            for j in range(gate.rows):
                row = []
                for k in range(len(self._tensors[0][0])):
                    s = ZERO
                    for l in range(gate.cols):
                        s = s + gate.get(j, l) * Complex(self._tensors[0][l][k] if l < len(self._tensors[0]) else 0)
                    row.append(s)
                new_tensor.append(row)
            self._tensors[0] = new_tensor
        elif target == self._n_qubits - 1:
            n = len(self._tensors[-1])
            new_tensor = []
            for j in range(n):
                row = []
                for k in range(gate.cols):
                    s = ZERO
                    for l in range(gate.rows):
                        s = s + gate.get(l, k) * Complex(self._tensors[-1][j][l] if l < len(self._tensors[-1][j]) else 0)
                    row.append(s)
                new_tensor.append(row)
            self._tensors[-1] = new_tensor
    def inner_product(self, other: 'MatrixProductState') -> Complex:
        if self._n_qubits != other._n_qubits:
            raise ValueError("Qubit count mismatch")
        result = ONE
        for i in range(self._n_qubits):
            a = self._tensors[i]
            b = other._tensors[i]
            s = ZERO
            for r in range(len(a)):
                for c in range(len(a[r])):
                    if r < len(b) and c < len(b[r]):
                        s = s + a[r][c].conjugate() * b[r][c]
            result = result * s
        return result
    def norm(self) -> float:
        ip = self.inner_product(self)
        return math.sqrt(ip.re)
    def __repr__(self):
        return f"MatrixProductState(n_qubits={self._n_qubits})"
