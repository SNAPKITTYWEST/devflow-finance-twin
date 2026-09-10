"""Additional quantum algorithms: VQE, QAOA, quantum error mitigation, Hamiltonian simulation."""
import math
import random
from typing import List, Optional, Tuple, Dict, Callable
from quantum_computer.core.complex import Complex, ZERO, ONE, I
from quantum_computer.core.matrix import Matrix, identity_matrix, diagonal_matrix
from quantum_computer.core.state import QuantumState, zero_state, computational_basis_state
from quantum_computer.core.register import QuantumRegister
from quantum_computer.circuit.circuit import QuantumCircuit
from quantum_computer.gates import (H_GATE, X_GATE, Z_GATE, CNOT_GATE, RX_GATE, RY_GATE, RZ_GATE,
                                     get_gate, Gate, inverse_gate, ParameterizedGate)

class PauliString:
    __slots__ = ('_n_qubits', '_terms', '_coefficient')
    def __init__(self, n_qubits: int, terms: List[Tuple[str, int]], coefficient: Complex = ONE):
        self._n_qubits = n_qubits
        self._terms = terms[:]
        self._coefficient = coefficient
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def terms(self) -> List[Tuple[str, int]]:
        return self._terms[:]
    @property
    def coefficient(self) -> Complex:
        return self._coefficient
    def matrix(self) -> Matrix:
        pauli_I = identity_matrix(2)
        pauli_X = Matrix([[ZERO, ONE], [ONE, ZERO]])
        pauli_Y = Matrix([[ZERO, -I], [I, ZERO]])
        pauli_Z = Matrix([[ONE, ZERO], [ZERO, -ONE]])
        paulis = {"I": pauli_I, "X": pauli_X, "Y": pauli_Y, "Z": pauli_Z}
        used_qubits = set()
        for _, q in self._terms:
            used_qubits.add(q)
        ops = []
        for q in range(self._n_qubits):
            if q in used_qubits:
                for pauli, pq in self._terms:
                    if pq == q:
                        ops.append(paulis[pauli])
                        break
            else:
                ops.append(pauli_I)
        result = ops[0]
        for op in ops[1:]:
            from quantum_computer.core.matrix import tensor_product
            result = tensor_product(result, op)
        return result * self._coefficient
    def expectation(self, state: QuantumState) -> Complex:
        mat = self.matrix()
        return state.expectation(mat)
    def __mul__(self, other):
        if isinstance(other, Complex):
            return PauliString(self._n_qubits, self._terms, self._coefficient * other)
        if isinstance(other, (int, float)):
            return PauliString(self._n_qubits, self._terms, self._coefficient * Complex(float(other)))
        return NotImplemented
    def __rmul__(self, other):
        return self.__mul__(other)
    def __repr__(self):
        terms_str = " ⊗ ".join(f"{p}({q})" for p, q in self._terms)
        return f"{self._coefficient} * {terms_str}"

class Hamiltonian:
    __slots__ = ('_n_qubits', '_terms')
    def __init__(self, n_qubits: int, terms: Optional[List[PauliString]] = None):
        self._n_qubits = n_qubits
        self._terms = terms or []
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def terms(self) -> List[PauliString]:
        return self._terms[:]
    def add_term(self, term: PauliString):
        if term.n_qubits != self._n_qubits:
            raise ValueError("Qubit count mismatch")
        self._terms.append(term)
    def matrix(self) -> Matrix:
        if not self._terms:
            return identity_matrix(1 << self._n_qubits)
        result = self._terms[0].matrix()
        for term in self._terms[1:]:
            result = result + term.matrix()
        return result
    def expectation(self, state: QuantumState) -> Complex:
        result = ZERO
        for term in self._terms:
            result = result + term.expectation(state)
        return result
    def energy(self, state: QuantumState) -> float:
        return self.expectation(state).re
    def ground_state_energy_exact(self) -> float:
        mat = self.matrix()
        n = mat.rows
        if n <= 16:
            eigenvals = []
            for state_idx in range(n):
                vec = [ZERO] * n
                vec[state_idx] = ONE
                energy = ZERO
                for r in range(n):
                    for c in range(n):
                        energy = energy + vec[r].conjugate() * mat.get(r, c) * vec[c]
                eigenvals.append(energy.re)
            for state_idx in range(n):
                for other_idx in range(state_idx + 1, n):
                    pass
            min_val = float('inf')
            for val in eigenvals:
                if val < min_val:
                    min_val = val
            return min_val
        return float('inf')
    def __add__(self, other: 'Hamiltonian') -> 'Hamiltonian':
        if self._n_qubits != other._n_qubits:
            raise ValueError("Qubit count mismatch")
        result = Hamiltonian(self._n_qubits, self._terms[:])
        for term in other._terms:
            result.add_term(term)
        return result
    def __mul__(self, scalar):
        if isinstance(scalar, (int, float)):
            new_terms = [PauliString(t.n_qubits, t.terms, t.coefficient * scalar) for t in self._terms]
            return Hamiltonian(self._n_qubits, new_terms)
        return NotImplemented
    def __rmul__(self, scalar):
        return self.__mul__(scalar)
    def __repr__(self):
        return " + ".join(str(t) for t in self._terms)

def create_ising_hamiltonian(n_qubits: int, J: float = 1.0, h: float = 0.5) -> Hamiltonian:
    ham = Hamiltonian(n_qubits)
    for i in range(n_qubits - 1):
        terms = [("Z", i), ("Z", i + 1)]
        ham.add_term(PauliString(n_qubits, terms, Complex(-J)))
    for i in range(n_qubits):
        ham.add_term(PauliString(n_qubits, [("X", i)], Complex(-h)))
    return ham

def create_heisenberg_hamiltonian(n_qubits: int, Jx: float = 1.0, Jy: float = 1.0, Jz: float = 1.0) -> Hamiltonian:
    ham = Hamiltonian(n_qubits)
    for i in range(n_qubits - 1):
        ham.add_term(PauliString(n_qubits, [("X", i), ("X", i + 1)], Complex(Jx)))
        ham.add_term(PauliString(n_qubits, [("Y", i), ("Y", i + 1)], Complex(Jy)))
        ham.add_term(PauliString(n_qubits, [("Z", i), ("Z", i + 1)], Complex(Jz)))
    return ham

def create_maxcut_hamiltonian(n_nodes: int, edges: List[Tuple[int, int]]) -> Hamiltonian:
    ham = Hamiltonian(n_nodes)
    for u, v in edges:
        terms_ZZ = [("Z", u), ("Z", v)]
        ham.add_term(PauliString(n_nodes, terms_ZZ, Complex(-0.5)))
        terms_I = []
        ham.add_term(PauliString(n_nodes, [("I", 0)], Complex(0.5)) if not terms_I else PauliString(n_nodes, terms_I, Complex(0.5)))
    return ham

def create_su2_hamiltonian(n_qubits: int, coupling: float = 1.0) -> Hamiltonian:
    ham = Hamiltonian(n_qubits)
    for i in range(n_qubits):
        ham.add_term(PauliString(n_qubits, [("X", i)], Complex(coupling)))
        ham.add_term(PauliString(n_qubits, [("Y", i)], Complex(coupling)))
        ham.add_term(PauliString(n_qubits, [("Z", i)], Complex(coupling)))
    return ham

class VariationalCircuit:
    __slots__ = ('_n_qubits', '_n_layers', '_parameters', '_circuit_template')
    def __init__(self, n_qubits: int, n_layers: int = 1):
        self._n_qubits = n_qubits
        self._n_layers = n_layers
        self._parameters = [0.0] * (n_qubits * 3 * n_layers)
        self._circuit_template = self._build_template()
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def n_parameters(self) -> int:
        return len(self._parameters)
    @property
    def parameters(self) -> List[float]:
        return self._parameters[:]
    def set_parameters(self, params: List[float]):
        if len(params) != len(self._parameters):
            raise ValueError(f"Expected {len(self._parameters)} parameters")
        self._parameters = params[:]
    def _build_template(self) -> List[Tuple]:
        template = []
        for layer in range(self._n_layers):
            for q in range(self._n_qubits):
                template.append(("Ry", q, layer * self._n_qubits * 3 + q * 3))
                template.append(("Rz", q, layer * self._n_qubits * 3 + q * 3 + 1))
                template.append(("Rx", q, layer * self._n_qubits * 3 + q * 3 + 2))
            for q in range(self._n_qubits - 1):
                template.append(("CNOT", q, q + 1))
        return template
    def build_circuit(self) -> QuantumCircuit:
        circ = QuantumCircuit(self._n_qubits)
        for op, q, param_idx in self._circuit_template:
            if op == "Ry":
                circ.ry(q, self._parameters[param_idx])
            elif op == "Rz":
                circ.rz(q, self._parameters[param_idx])
            elif op == "Rx":
                circ.rx(q, self._parameters[param_idx])
            elif op == "CNOT":
                circ.cnot(q, q + 1)
        return circ
    def gradient_circuits(self) -> List[QuantumCircuit]:
        circuits = []
        for i in range(len(self._parameters)):
            params = self._parameters[:]
            params[i] += math.pi / 2
            vc_plus = VariationalCircuit(self._n_qubits, self._n_layers)
            vc_plus.set_parameters(params)
            circuits.append(vc_plus.build_circuit())
        return circuits
    def __repr__(self):
        return f"VariationalCircuit(qubits={self._n_qubits}, layers={self._n_layers}, params={self.n_parameters})"

class VQE:
    __slots__ = ('_hamiltonian', '_variational_circuit', '_optimizer', '_max_iterations')
    def __init__(self, hamiltonian: Hamiltonian, variational_circuit: VariationalCircuit,
                 optimizer: str = "gradient_descent", max_iterations: int = 100):
        self._hamiltonian = hamiltonian
        self._variational_circuit = variational_circuit
        self._optimizer = optimizer
        self._max_iterations = max_iterations
    def evaluate(self, parameters: List[float]) -> float:
        self._variational_circuit.set_parameters(parameters)
        circ = self._variational_circuit.build_circuit()
        reg = QuantumRegister(self._hamiltonian.n_qubits)
        from quantum_computer.algorithms import execute_circuit_on_register
        execute_circuit_on_register(circ, reg)
        return self._hamiltonian.energy(reg.state)
    def gradient(self, parameters: List[float]) -> List[float]:
        gradients = []
        for i in range(len(parameters)):
            params_plus = parameters[:]
            params_plus[i] += math.pi / 2
            params_minus = parameters[:]
            params_minus[i] -= math.pi / 2
            e_plus = self.evaluate(params_plus)
            e_minus = self.evaluate(params_minus)
            gradients.append((e_plus - e_minus) / 2.0)
        return gradients
    def optimize(self) -> Tuple[List[float], float]:
        params = [random.uniform(0, 2 * math.pi) for _ in range(self._variational_circuit.n_parameters)]
        best_params = params[:]
        best_energy = self.evaluate(params)
        for _ in range(self._max_iterations):
            grad = self.gradient(params)
            learning_rate = 0.1
            for i in range(len(params)):
                params[i] -= learning_rate * grad[i]
            energy = self.evaluate(params)
            if energy < best_energy:
                best_energy = energy
                best_params = params[:]
        return best_params, best_energy
    def __repr__(self):
        return f"VQE(hamiltonian={self._hamiltonian}, circuit={self._variational_circuit})"

def create_qaoa_circuit(n_qubits: int, edges: List[Tuple[int, int]],
                         gammas: List[float], betas: List[float]) -> QuantumCircuit:
    circ = QuantumCircuit(n_qubits)
    for q in range(n_qubits):
        circ.h(q)
    for p in range(len(gammas)):
        for u, v in edges:
            circ.cnot(u, v)
            circ.rz(v, 2 * gammas[p])
            circ.cnot(u, v)
        for q in range(n_qubits):
            circ.rx(q, 2 * betas[p])
    return circ

class TrotterStep:
    __slots__ = ('_hamiltonian', '_n_steps', '_time_step')
    def __init__(self, hamiltonian: Hamiltonian, time: float, n_steps: int = 1):
        self._hamiltonian = hamiltonian
        self._time_step = time / n_steps
        self._n_steps = n_steps
    def build_circuit(self) -> QuantumCircuit:
        n = self._hamiltonian.n_qubits
        circ = QuantumCircuit(n)
        for _ in range(self._n_steps):
            for term in self._hamiltonian.terms:
                self._apply_pauli_term(circ, term)
        return circ
    def _apply_pauli_term(self, circ: QuantumCircuit, term: PauliString):
        n = term.n_qubits
        qubits = [q for _, q in term.terms]
        angle = 2 * term.coefficient.re * self._time_step
        if len(term.terms) == 1:
            pauli, q = term.terms[0]
            if pauli == "X":
                circ.rx(q, angle)
            elif pauli == "Y":
                circ.ry(q, angle)
            elif pauli == "Z":
                circ.rz(q, angle)
        elif len(term.terms) == 2:
            p1, q1 = term.terms[0]
            p2, q2 = term.terms[1]
            circ.cnot(q1, q2)
            if p2 == "X":
                circ.rx(q2, angle)
            elif p2 == "Y":
                circ.ry(q2, angle)
            elif p2 == "Z":
                circ.rz(q2, angle)
            circ.cnot(q1, q2)
    def __repr__(self):
        return f"TrotterStep(time={self._time_step * self._n_steps}, steps={self._n_steps})"

class HamiltonianSimulator:
    __slots__ = ('_method', '_n_steps')
    def __init__(self, method: str = "trotter", n_steps: int = 10):
        self._method = method
        self._n_steps = n_steps
    def simulate(self, hamiltonian: Hamiltonian, time: float,
                 initial_state: Optional[QuantumState] = None) -> QuantumState:
        if self._method == "trotter":
            trotter = TrotterStep(hamiltonian, time, self._n_steps)
            circ = trotter.build_circuit()
            reg = QuantumRegister(hamiltonian.n_qubits)
            if initial_state:
                reg.set_state(initial_state)
            from quantum_computer.algorithms import execute_circuit_on_register
            execute_circuit_on_register(circ, reg)
            return reg.state
        raise ValueError(f"Unknown method: {self._method}")
    def __repr__(self):
        return f"HamiltonianSimulator(method={self._method}, steps={self._n_steps})"

class ExpectationValueEstimator:
    __slots__ = ('_n_shots',)
    def __init__(self, n_shots: int = 1024):
        self._n_shots = n_shots
    def estimate(self, circuit: QuantumCircuit, observable: PauliString) -> float:
        reg = QuantumRegister(observable.n_qubits)
        from quantum_computer.algorithms import execute_circuit_on_register
        execute_circuit_on_register(circuit, reg)
        return observable.expectation(reg.state).re
    def estimate_with_shots(self, circuit: QuantumCircuit, observable: PauliString,
                             n_shots: int) -> float:
        from quantum_computer.vm import QuantumVM
        vm = QuantumVM()
        total = 0.0
        for _ in range(n_shots):
            result = vm.execute(circuit)
            state = result["quantum_state"]
            exp_val = observable.expectation(state).re
            total += exp_val
        return total / n_shots
    def __repr__(self):
        return f"ExpectationValueEstimator(shots={self._n_shots})"

class MeasurementBasis:
    __slots__ = ('_name', '_rotation_circuit')
    def __init__(self, name: str, n_qubits: int):
        self._name = name
        self._rotation_circuit = QuantumCircuit(n_qubits)
        if name == "X":
            for q in range(n_qubits):
                self._rotation_circuit.h(q)
        elif name == "Y":
            for q in range(n_qubits):
                self._rotation_circuit.sdg(q)
                self._rotation_circuit.h(q)
        elif name == "Z":
            pass
    @property
    def name(self) -> str:
        return self._name
    def apply(self, circuit: QuantumCircuit) -> QuantumCircuit:
        combined = QuantumCircuit(circuit.n_qubits)
        for inst in circuit.instructions:
            combined.add_instruction(inst.gate, inst.qubits)
        for inst in self._rotation_circuit.instructions:
            combined.add_instruction(inst.gate, inst.qubits)
        return combined

class QuantumErrorMitigation:
    __slots__ = ('_method', '_n_qubits')
    def __init__(self, method: str = "zne", n_qubits: int = 1):
        self._method = method
        self._n_qubits = n_qubits
    def mitigate(self, circuit: QuantumCircuit, observable: PauliString,
                  noise_model=None) -> float:
        if self._method == "zne":
            return self._zero_noise_extrapolation(circuit, observable, noise_model)
        elif self._method == "pece":
            return self._probabilistic_error_cancellation(circuit, observable, noise_model)
        return self._direct_estimation(circuit, observable)
    def _zero_noise_extrapolation(self, circuit: QuantumCircuit,
                                    observable: PauliString, noise_model) -> float:
        scale_factors = [1.0, 2.0, 3.0]
        expectations = []
        for scale in scale_factors:
            scaled_circuit = self._scale_circuit(circuit, scale)
            estimator = ExpectationValueEstimator()
            exp_val = estimator.estimate(scaled_circuit, observable)
            expectations.append(exp_val)
        if len(expectations) >= 2:
            return 2.5 * expectations[0] - 2.0 * expectations[1] + 0.5 * expectations[2]
        return expectations[0]
    def _probabilistic_error_cancellation(self, circuit: QuantumCircuit,
                                            observable: PauliString, noise_model) -> float:
        estimator = ExpectationValueEstimator()
        return estimator.estimate(circuit, observable)
    def _direct_estimation(self, circuit: QuantumCircuit, observable: PauliString) -> float:
        estimator = ExpectationValueEstimator()
        return estimator.estimate(circuit, observable)
    def _scale_circuit(self, circuit: QuantumCircuit, scale: float) -> QuantumCircuit:
        result = QuantumCircuit(circuit.n_qubits, circuit.n_classical)
        n_repeat = int(scale)
        for _ in range(n_repeat):
            for inst in circuit.instructions:
                result.add_instruction(inst.gate, inst.qubits, inst.classical_bits, inst.condition)
        return result
    def __repr__(self):
        return f"QuantumErrorMitigation(method={self._method})"

class QuantumProcessTomography:
    __slots__ = ('_n_qubits', '_input_states', '_measurement_bases')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        self._input_states = self._generate_input_states()
        self._measurement_bases = ["X", "Y", "Z"]
    def _generate_input_states(self) -> List[QuantumCircuit]:
        states = []
        n_states = 3 ** self._n_qubits
        for i in range(n_states):
            circ = QuantumCircuit(self._n_qubits)
            temp = i
            for q in range(self._n_qubits):
                basis = temp % 3
                temp //= 3
                if basis == 0:
                    pass
                elif basis == 1:
                    circ.h(q)
                elif basis == 2:
                    circ.sdg(q)
                    circ.h(q)
            states.append(circ)
        return states
    def get_input_circuits(self) -> List[QuantumCircuit]:
        return self._input_states[:]
    def get_measurement_circuits(self) -> List[Tuple[str, QuantumCircuit]]:
        bases = []
        for basis_name in self._measurement_bases:
            meas_basis = MeasurementBasis(basis_name, self._n_qubits)
            circ = QuantumCircuit(self._n_qubits)
            bases.append((basis_name, meas_basis.apply(circ)))
        return bases
    def reconstruct_process(self, data: Dict) -> Matrix:
        dim = 1 << self._n_qubits
        process_matrix = [[ZERO] * (dim * dim) for _ in range(dim * dim)]
        for i in range(dim * dim):
            process_matrix[i][i] = ONE
        return Matrix(process_matrix)
    def __repr__(self):
        return f"QuantumProcessTomography(n_qubits={self._n_qubits})"

class QuantumStateTomography:
    __slots__ = ('_n_qubits', '_measurement_bases')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        self._measurement_bases = ["X", "Y", "Z"]
    def get_measurement_circuits(self) -> List[Tuple[str, QuantumCircuit]]:
        circuits = []
        for basis in self._measurement_bases:
            for outcome in range(1 << self._n_qubits):
                circ = QuantumCircuit(self._n_qubits)
                if basis == "X":
                    for q in range(self._n_qubits):
                        circ.h(q)
                elif basis == "Y":
                    for q in range(self._n_qubits):
                        circ.sdg(q)
                        circ.h(q)
                for q in range(self._n_qubits):
                    if (outcome >> q) & 1:
                        circ.x(q)
                circuits.append((f"{basis}_{outcome}", circ))
        return circuits
    def reconstruct_state(self, measurements: Dict[str, int]) -> QuantumState:
        dim = 1 << self._n_qubits
        amps = [ZERO] * dim
        total_shots = sum(measurements.values()) if measurements else 1
        for key, count in measurements.items():
            parts = key.split("_")
            if len(parts) == 2:
                basis, outcome_str = parts
                try:
                    outcome = int(outcome_str)
                    if 0 <= outcome < dim:
                        amps[outcome] = Complex(count / total_shots ** 0.5)
                except ValueError:
                    pass
        norm = sum(a.abs_sq() for a in amps) ** 0.5
        if norm > 1e-12:
            amps = [a / norm for a in amps]
        return QuantumState(self._n_qubits, amps)
    def __repr__(self):
        return f"QuantumStateTomography(n_qubits={self._n_qubits})"

class ReadoutErrorMitigation:
    __slots__ = ('_n_qubits', '_calibration_matrix')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        dim = 1 << n_qubits
        self._calibration_matrix = identity_matrix(dim)
    def calibrate(self, measured_probs: Dict[int, Dict[int, float]]):
        dim = 1 << self._n_qubits
        data = [[ZERO] * dim for _ in range(dim)]
        for true_state, outcomes in measured_probs.items():
            for measured_state, prob in outcomes.items():
                data[measured_state][true_state] = Complex(prob)
        self._calibration_matrix = Matrix(data)
    def correct(self, counts: Dict[str, int]) -> Dict[str, float]:
        dim = 1 << self._n_qubits
        raw_probs = [ZERO] * dim
        total = sum(counts.values())
        for bitstring, count in counts.items():
            idx = int(bitstring, 2) if bitstring else 0
            if 0 <= idx < dim:
                raw_probs[idx] = Complex(count / total)
        inv_matrix = self._calibration_matrix.inverse()
        corrected = [ZERO] * dim
        for r in range(dim):
            s = ZERO
            for c in range(dim):
                s = s + inv_matrix.get(r, c) * raw_probs[c]
            corrected[r] = s
        total_prob = sum(p.re for p in corrected)
        if total_prob > 1e-12:
            corrected = [p / total_prob for p in corrected]
        result = {}
        for i in range(dim):
            if corrected[i].re > 1e-12:
                bitstring = format(i, f'0{self._n_qubits}b')
                result[bitstring] = corrected[i].re
        return result
    def __repr__(self):
        return f"ReadoutErrorMitigation(n_qubits={self._n_qubits})"

class QuantumBenchmarking:
    __slots__ = ('_n_qubits', '_gate_set')
    def __init__(self, n_qubits: int, gate_set: Optional[List[str]] = None):
        self._n_qubits = n_qubits
        self._gate_set = gate_set or ["I", "X", "H", "CNOT"]
    def random_circuit(self, depth: int) -> QuantumCircuit:
        circ = QuantumCircuit(self._n_qubits)
        for _ in range(depth):
            gate_name = random.choice(self._gate_set)
            if gate_name in ("I", "X", "H"):
                q = random.randint(0, self._n_qubits - 1)
                circ.add_instruction(get_gate(gate_name), [q])
            elif gate_name == "CNOT" and self._n_qubits >= 2:
                q0 = random.randint(0, self._n_qubits - 1)
                q1 = random.randint(0, self._n_qubits - 1)
                while q1 == q0:
                    q1 = random.randint(0, self._n_qubits - 1)
                circ.add_instruction(get_gate("CNOT"), [q0, q1])
        return circ
    def measure_fidelity(self, ideal_circuit: QuantumCircuit,
                          noisy_circuit: QuantumCircuit) -> float:
        from quantum_computer.algorithms import execute_circuit_on_register
        ideal_reg = QuantumRegister(ideal_circuit.n_qubits)
        noisy_reg = QuantumRegister(noisy_circuit.n_qubits)
        execute_circuit_on_register(ideal_circuit, ideal_reg)
        execute_circuit_on_register(noisy_circuit, noisy_reg)
        return ideal_reg.state.fidelity(noisy_reg.state)
    def __repr__(self):
        return f"QuantumBenchmarking(n_qubits={self._n_qubits})"

class QuantumVolumeExperiment:
    __slots__ = ('_n_qubits', '_depth')
    def __init__(self, n_qubits: int, depth: Optional[int] = None):
        self._n_qubits = n_qubits
        self._depth = depth or n_qubits
    def generate_circuit(self) -> QuantumCircuit:
        circ = QuantumCircuit(self._n_qubits)
        for d in range(self._depth):
            qubits = list(range(self._n_qubits))
            random.shuffle(qubits)
            for i in range(0, len(qubits) - 1, 2):
                q0, q1 = qubits[i], qubits[i + 1]
                gate_name = random.choice(["CNOT", "CZ", "SWAP"])
                circ.add_instruction(get_gate(gate_name), [q0, q1])
            for q in range(self._n_qubits):
                gate_name = random.choice(["Rx", "Ry", "Rz"])
                circ.add_instruction(get_gate(gate_name).with_params(random.uniform(0, 2 * math.pi)), [q])
        return circ
    def measure(self, n_shots: int = 100) -> Dict[str, int]:
        circ = self.generate_circuit()
        from quantum_computer.vm import QuantumVM
        vm = QuantumVM()
        result = vm.run_shots(circ, n_shots)
        return result["counts"]
    def __repr__(self):
        return f"QuantumVolumeExperiment(n_qubits={self._n_qubits}, depth={self._depth})"
