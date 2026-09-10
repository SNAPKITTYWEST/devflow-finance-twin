"""Quantum Virtual Machine: instruction dispatch, register management, memory."""
import math
import random
from typing import List, Optional, Tuple, Dict, Any
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix
from quantum_computer.core.state import QuantumState, zero_state
from quantum_computer.core.register import QuantumRegister, ClassicalRegister, RegisterManager
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction, Measurement
from quantum_computer.gates import Gate, get_gate

class QuantumVM:
    __slots__ = ('_manager', '_pc', '_running', '_trace', '_max_steps')
    def __init__(self, max_steps: int = 100000):
        self._manager = RegisterManager()
        self._pc = 0
        self._running = False
        self._trace: List[Dict[str, Any]] = []
        self._max_steps = max_steps
    @property
    def manager(self) -> RegisterManager:
        return self._manager
    @property
    def pc(self) -> int:
        return self._pc
    @property
    def trace(self) -> List[Dict[str, Any]]:
        return self._trace[:]
    def execute(self, circuit: QuantumCircuit) -> Dict[str, Any]:
        qreg = self._manager.allocate_quantum_register(circuit.n_qubits, "q")
        if circuit.n_classical > 0:
            creg = self._manager.allocate_classical_register(circuit.n_classical, "c")
        else:
            creg = self._manager.allocate_classical_register(circuit.n_qubits, "c")
        self._running = True
        self._pc = 0
        self._trace = []
        steps = 0
        while self._running and self._pc < len(circuit.instructions) and steps < self._max_steps:
            inst = circuit.instructions[self._pc]
            self._dispatch(inst, qreg, creg)
            self._pc += 1
            steps += 1
        for meas in circuit.measurements:
            outcome = qreg.measure_qubit(meas.qubit)
            if meas.classical_bit < creg.size:
                creg.set_bit(meas.classical_bit, outcome)
        self._running = False
        result = {
            "quantum_state": qreg.state,
            "classical_registers": {creg.name: creg.get_value()},
            "measurements": [],
            "trace": self._trace,
            "steps": steps
        }
        for meas in circuit.measurements:
            if meas.classical_bit < creg.size:
                result["measurements"].append({
                    "qubit": meas.qubit,
                    "classical_bit": meas.classical_bit,
                    "outcome": creg.get_bit(meas.classical_bit)
                })
        return result
    def _dispatch(self, inst: Instruction, qreg: QuantumRegister, creg: ClassicalRegister):
        if inst.condition:
            cbit, expected = inst.condition
            if creg.get_bit(cbit) != expected:
                self._trace.append({"instruction": inst.gate.name, "skipped": True})
                return
        if inst.gate.name == "barrier":
            self._trace.append({"instruction": "barrier"})
            return
        if inst.gate.n_qubits == 1:
            qreg.apply_gate(inst.gate.matrix, inst.qubits)
        elif inst.gate.n_qubits == 2:
            qreg.apply_gate(inst.gate.matrix, inst.qubits)
        elif inst.gate.n_qubits == 3:
            from quantum_computer.algorithms import _expand_toffoli_like
            full_gate = _expand_toffoli_like(inst.gate, inst.qubits, qreg.size)
            qreg.apply_gate(full_gate, list(range(qreg.size)))
        else:
            from quantum_computer.algorithms import _expand_multi_gate
            full_gate = _expand_multi_gate(inst.gate, inst.qubits, qreg.size)
            qreg.apply_gate(full_gate, list(range(qreg.size)))
        self._trace.append({"instruction": inst.gate.name, "qubits": inst.qubits})
    def execute_with_noise(self, circuit: QuantumCircuit, noise_model) -> Dict[str, Any]:
        qreg = self._manager.allocate_quantum_register(circuit.n_qubits, "q")
        creg = self._manager.allocate_classical_register(max(circuit.n_classical, circuit.n_qubits), "c")
        self._running = True
        self._pc = 0
        self._trace = []
        steps = 0
        while self._running and self._pc < len(circuit.instructions) and steps < self._max_steps:
            inst = circuit.instructions[self._pc]
            self._dispatch(inst, qreg, creg)
            if inst.gate.name != "barrier":
                qreg._state = noise_model.apply_noise(qreg.state, inst.gate.name)
            self._pc += 1
            steps += 1
        for meas in circuit.measurements:
            outcome = qreg.measure_qubit(meas.qubit)
            if meas.classical_bit < creg.size:
                creg.set_bit(meas.classical_bit, outcome)
        self._running = False
        return {
            "quantum_state": qreg.state,
            "classical_registers": {creg.name: creg.get_value()},
            "trace": self._trace,
            "steps": steps
        }
    def run_shots(self, circuit: QuantumCircuit, n_shots: int) -> Dict[str, Any]:
        counts = {}
        all_measurements = []
        for _ in range(n_shots):
            qreg = QuantumRegister(circuit.n_qubits, "q")
            creg = ClassicalRegister(max(circuit.n_classical, circuit.n_qubits), "c")
            for inst in circuit.instructions:
                if inst.gate.name == "barrier":
                    continue
                if inst.gate.n_qubits == 1:
                    qreg.apply_gate(inst.gate.matrix, inst.qubits)
                elif inst.gate.n_qubits == 2:
                    qreg.apply_gate(inst.gate.matrix, inst.qubits)
                elif inst.gate.n_qubits == 3:
                    from quantum_computer.algorithms import _expand_toffoli_like
                    full_gate = _expand_toffoli_like(inst.gate, inst.qubits, qreg.size)
                    qreg.apply_gate(full_gate, list(range(qreg.size)))
                else:
                    from quantum_computer.algorithms import _expand_multi_gate
                    full_gate = _expand_multi_gate(inst.gate, inst.qubits, qreg.size)
                    qreg.apply_gate(full_gate, list(range(qreg.size)))
            bitstring = ""
            for meas in circuit.measurements:
                outcome = qreg.measure_qubit(meas.qubit)
                bitstring += str(outcome)
            if not bitstring:
                bits = qreg.measure_all()
                bitstring = "".join(str(b) for b in bits)
            counts[bitstring] = counts.get(bitstring, 0) + 1
            all_measurements.append(bitstring)
        return {"counts": counts, "n_shots": n_shots, "measurements": all_measurements}
    def compute_expectation(self, circuit: QuantumCircuit, observable: Matrix) -> Complex:
        result = self.execute(circuit)
        state = result["quantum_state"]
        return state.expectation(observable)
    def compute_probabilities(self, circuit: QuantumCircuit) -> List[float]:
        result = self.execute(circuit)
        state = result["quantum_state"]
        return [a.abs_sq() for a in state.amplitudes]
    def statevector(self, circuit: QuantumCircuit) -> List[Complex]:
        result = self.execute(circuit)
        return result["quantum_state"].amplitudes
    def reset(self):
        self._manager = RegisterManager()
        self._pc = 0
        self._running = False
        self._trace = []

class ShotManager:
    __slots__ = ('_n_shots', '_results', '_counts')
    def __init__(self, n_shots: int = 1024):
        if n_shots < 1:
            raise ValueError("Need at least 1 shot")
        self._n_shots = n_shots
        self._results: List[str] = []
        self._counts: Dict[str, int] = {}
    @property
    def n_shots(self) -> int:
        return self._n_shots
    @property
    def counts(self) -> Dict[str, int]:
        return dict(self._counts)
    def record(self, bitstring: str):
        self._results.append(bitstring)
        self._counts[bitstring] = self._counts.get(bitstring, 0) + 1
    def probabilities(self) -> Dict[str, float]:
        return {k: v / self._n_shots for k, v in self._counts.items()}
    def most_frequent(self) -> str:
        if not self._counts:
            return ""
        return max(self._counts, key=self._counts.get)
    def histogram(self) -> List[Tuple[str, int]]:
        return sorted(self._counts.items(), key=lambda x: -x[1])
    def validate(self) -> bool:
        return sum(self._counts.values()) == self._n_shots

class ResultValidator:
    __slots__ = ('_tolerance')
    def __init__(self, tolerance: float = 0.01):
        self._tolerance = tolerance
    def validate_distribution(self, observed: Dict[str, float],
                               expected: Dict[str, float]) -> Tuple[bool, List[str]]:
        errors = []
        all_keys = set(observed.keys()) | set(expected.keys())
        for key in all_keys:
            obs = observed.get(key, 0.0)
            exp = expected.get(key, 0.0)
            if abs(obs - exp) > self._tolerance:
                errors.append(f"Key '{key}': observed={obs:.4f}, expected={exp:.4f}")
        return len(errors) == 0, errors
    def validate_statevector(self, observed: List[Complex],
                              expected: List[Complex]) -> Tuple[bool, float]:
        if len(observed) != len(expected):
            return False, 1.0
        overlap = sum(o.conjugate() * e for o, e in zip(observed, expected))
        fidelity = overlap.abs_sq()
        return fidelity > 1 - self._tolerance, fidelity
    def validate_bell_state(self, state: QuantumState) -> bool:
        amps = state.amplitudes
        if len(amps) != 4:
            return False
        return (abs(amps[0].abs_sq() - 0.5) < self._tolerance and
                abs(amps[3].abs_sq() - 0.5) < self._tolerance and
                abs(amps[1].abs_sq()) < self._tolerance and
                abs(amps[2].abs_sq()) < self._tolerance)
    def validate_ghz_state(self, state: QuantumState) -> bool:
        amps = state.amplitudes
        n = len(amps)
        return (abs(amps[0].abs_sq() - 0.5) < self._tolerance and
                abs(amps[n - 1].abs_sq() - 0.5) < self._tolerance and
                all(abs(amps[i].abs_sq()) < self._tolerance for i in range(1, n - 1)))
