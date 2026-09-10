"""Noise models and quantum channels."""
import math
import random
from typing import List, Optional, Tuple, Dict
from quantum_computer.core.complex import Complex, ZERO, ONE, I
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product
from quantum_computer.core.state import QuantumState

class QuantumChannel:
    __slots__ = ('_name', '_n_qubits', '_kraus_ops')
    def __init__(self, name: str, n_qubits: int, kraus_ops: List[Matrix]):
        self._name = name
        self._n_qubits = n_qubits
        self._kraus_ops = kraus_ops[:]
        self._validate_kraus()
    def _validate_kraus(self):
        dim = 1 << self._n_qubits
        total = Matrix([[ZERO] * dim for _ in range(dim)])
        for k in self._kraus_ops:
            if k.rows != dim or k.cols != dim:
                raise ValueError(f"Kraus operator dimension mismatch: {k.rows}x{k.cols} vs {dim}x{dim}")
            total = total + k.dagger() * k
        identity = identity_matrix(dim)
        for r in range(dim):
            for c in range(dim):
                diff = total.get(r, c) - identity.get(r, c)
                if diff.abs_sq() > 1e-6:
                    raise ValueError("Kraus operators do not satisfy completeness relation")
    @property
    def name(self) -> str:
        return self._name
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def kraus_ops(self) -> List[Matrix]:
        return self._kraus_ops[:]
    def apply(self, state: QuantumState) -> QuantumState:
        if state.n_qubits != self._n_qubits:
            raise ValueError("Qubit count mismatch")
        probs = []
        collapsed_states = []
        for k in self._kraus_ops:
            new_amps = []
            dim = state.dim
            for r in range(dim):
                s = ZERO
                for c in range(dim):
                    s = s + k.get(r, c) * state.amplitudes[c]
                new_amps.append(s)
            prob = sum(a.abs_sq() for a in new_amps)
            if prob > 1e-24:
                norm = prob ** 0.5
                normalized = [a / norm for a in new_amps]
                probs.append(prob)
                collapsed_states.append(QuantumState(state.n_qubits, normalized))
        if not probs:
            return state
        total = sum(probs)
        r = random.random() * total
        cum = 0.0
        for i, p in enumerate(probs):
            cum += p
            if r < cum:
                return collapsed_states[i]
        return collapsed_states[-1]
    def compose(self, other: 'QuantumChannel') -> 'QuantumChannel':
        if self._n_qubits != other._n_qubits:
            raise ValueError("Qubit count mismatch")
        new_ops = []
        for k1 in self._kraus_ops:
            for k2 in other._kraus_ops:
                new_ops.append(k1 * k2)
        return QuantumChannel(f"{self._name}*{other._name}", self._n_qubits, new_ops)

class BitFlipChannel(QuantumChannel):
    def __init__(self, p: float, n_qubits: int = 1):
        if p < 0 or p > 1:
            raise ValueError("Probability must be in [0,1]")
        sqrt_p = math.sqrt(p)
        sqrt_1mp = math.sqrt(1 - p)
        X = Matrix([[ZERO, ONE], [ONE, ZERO]])
        I = identity_matrix(2)
        if n_qubits == 1:
            kraus = [sqrt_1mp * I, sqrt_p * X]
        else:
            kraus = []
            for i in range(n_qubits):
                ops = []
                for j in range(n_qubits):
                    if j == i:
                        ops.append(sqrt_p * X)
                    else:
                        ops.append(sqrt_1mp * I)
                k = ops[0]
                for op in ops[1:]:
                    k = tensor_product(k, op)
                kraus.append(k)
            kraus.append(sqrt_1mp ** n_qubits * identity_matrix(1 << n_qubits))
        super().__init__("BitFlip", n_qubits, kraus)

class PhaseFlipChannel(QuantumChannel):
    def __init__(self, p: float, n_qubits: int = 1):
        if p < 0 or p > 1:
            raise ValueError("Probability must be in [0,1]")
        sqrt_p = math.sqrt(p)
        sqrt_1mp = math.sqrt(1 - p)
        Z = Matrix([[ONE, ZERO], [ZERO, -ONE]])
        I = identity_matrix(2)
        if n_qubits == 1:
            kraus = [sqrt_1mp * I, sqrt_p * Z]
        else:
            kraus = []
            for i in range(n_qubits):
                ops = []
                for j in range(n_qubits):
                    if j == i:
                        ops.append(sqrt_p * Z)
                    else:
                        ops.append(sqrt_1mp * I)
                k = ops[0]
                for op in ops[1:]:
                    k = tensor_product(k, op)
                kraus.append(k)
            kraus.append(sqrt_1mp ** n_qubits * identity_matrix(1 << n_qubits))
        super().__init__("PhaseFlip", n_qubits, kraus)

class DepolarizingChannel(QuantumChannel):
    def __init__(self, p: float, n_qubits: int = 1):
        if p < 0 or p > 1:
            raise ValueError("Probability must be in [0,1]")
        dim = 1 << n_qubits
        X = Matrix([[ZERO, ONE], [ONE, ZERO]])
        Y = Matrix([[ZERO, -I], [I, ZERO]])
        Z = Matrix([[ONE, ZERO], [ZERO, -ONE]])
        I_mat = identity_matrix(2)
        paulis = [I_mat, X, Y, Z]
        kraus = []
        identity_coeff = math.sqrt(1 - p)
        kraus.append(identity_coeff * identity_matrix(dim))
        for pauli in paulis[1:]:
            ops = [pauli]
            for _ in range(n_qubits - 1):
                ops.append(I_mat)
            full = ops[0]
            for op in ops[1:]:
                full = tensor_product(full, op)
            coeff = math.sqrt(p / 3)
            kraus.append(coeff * full)
        super().__init__("Depolarizing", n_qubits, kraus)

class AmplitudeDampingChannel(QuantumChannel):
    def __init__(self, gamma: float, n_qubits: int = 1):
        if gamma < 0 or gamma > 1:
            raise ValueError("Gamma must be in [0,1]")
        sqrt_g = math.sqrt(gamma)
        sqrt_1g = math.sqrt(1 - gamma)
        K0 = Matrix([[ONE, ZERO], [ZERO, Complex(sqrt_1g)]])
        K1 = Matrix([[ZERO, Complex(sqrt_g)], [ZERO, ZERO]])
        if n_qubits == 1:
            kraus = [K0, K1]
        else:
            kraus = []
            for i in range(n_qubits):
                ops = []
                for j in range(n_qubits):
                    if j == i:
                        ops.append(K0)
                    else:
                        ops.append(identity_matrix(2))
                k0 = ops[0]
                for op in ops[1:]:
                    k0 = tensor_product(k0, op)
                ops1 = []
                for j in range(n_qubits):
                    if j == i:
                        ops1.append(K1)
                    else:
                        ops1.append(identity_matrix(2))
                k1 = ops1[0]
                for op in ops1[1:]:
                    k1 = tensor_product(k1, op)
                kraus.append(k0)
                kraus.append(k1)
        super().__init__("AmplitudeDamping", n_qubits, kraus)

class PhaseDampingChannel(QuantumChannel):
    def __init__(self, gamma: float, n_qubits: int = 1):
        if gamma < 0 or gamma > 1:
            raise ValueError("Gamma must be in [0,1]")
        sqrt_g = math.sqrt(gamma)
        K0 = Matrix([[ONE, ZERO], [ZERO, Complex(math.sqrt(1 - gamma))]])
        K1 = Matrix([[ZERO, ZERO], [ZERO, Complex(sqrt_g)]])
        if n_qubits == 1:
            kraus = [K0, K1]
        else:
            kraus = []
            for i in range(n_qubits):
                ops = []
                for j in range(n_qubits):
                    if j == i:
                        ops.append(K0)
                    else:
                        ops.append(identity_matrix(2))
                k0 = ops[0]
                for op in ops[1:]:
                    k0 = tensor_product(k0, op)
                ops1 = []
                for j in range(n_qubits):
                    if j == i:
                        ops1.append(K1)
                    else:
                        ops1.append(identity_matrix(2))
                k1 = ops1[0]
                for op in ops1[1:]:
                    k1 = tensor_product(k1, op)
                kraus.append(k0)
                kraus.append(k1)
        super().__init__("PhaseDamping", n_qubits, kraus)

class ThermalRelaxationChannel(QuantumChannel):
    def __init__(self, t1: float, t2: float, gate_time: float, n_qubits: int = 1):
        if t2 > 2 * t1:
            raise ValueError("T2 cannot exceed 2*T1")
        if gate_time <= 0:
            raise ValueError("Gate time must be positive")
        p_reset = 1 - math.exp(-gate_time / t1)
        p_01 = p_reset * (1 - math.exp(-gate_time / t1)) if t1 > 0 else 0
        gamma_z = 1 - math.exp(-gate_time / t2) if t2 > 0 else 0
        gamma_amp = p_reset
        gamma_phase = gamma_z / 2 - gamma_amp / 2 if gamma_z > gamma_amp else 0
        gamma_phase = max(0, gamma_phase)
        A0 = Matrix([[ONE, ZERO], [ZERO, Complex(math.sqrt(1 - gamma_amp - gamma_phase))]])
        A1 = Matrix([[ZERO, Complex(math.sqrt(gamma_amp))], [ZERO, ZERO]])
        A2 = Matrix([[ZERO, ZERO], [ZERO, Complex(math.sqrt(gamma_phase))]])
        if n_qubits == 1:
            kraus = [A0, A1, A2]
        else:
            kraus = []
            for i in range(n_qubits):
                ops = []
                for j in range(n_qubits):
                    if j == i:
                        ops.append(A0)
                    else:
                        ops.append(identity_matrix(2))
                k = ops[0]
                for op in ops[1:]:
                    k = tensor_product(k, op)
                kraus.append(k)
                ops1 = []
                for j in range(n_qubits):
                    if j == i:
                        ops1.append(A1)
                    else:
                        ops1.append(identity_matrix(2))
                k1 = ops1[0]
                for op in ops1[1:]:
                    k1 = tensor_product(k1, op)
                kraus.append(k1)
                ops2 = []
                for j in range(n_qubits):
                    if j == i:
                        ops2.append(A2)
                    else:
                        ops2.append(identity_matrix(2))
                k2 = ops2[0]
                for op in ops2[1:]:
                    k2 = tensor_product(k2, op)
                kraus.append(k2)
        super().__init__("ThermalRelaxation", n_qubits, kraus)

class NoiseModel:
    __slots__ = ('_channels', '_gate_overhead', '_n_qubits')
    def __init__(self, n_qubits: int = 1):
        self._n_qubits = n_qubits
        self._channels: Dict[str, QuantumChannel] = {}
        self._gate_overhead: Dict[str, float] = {}
    def add_channel(self, name: str, channel: QuantumChannel):
        self._channels[name] = channel
    def set_gate_error(self, gate_name: str, error_rate: float):
        self._gate_overhead[gate_name] = error_rate
    def apply_noise(self, state: QuantumState, gate_name: str = "") -> QuantumState:
        result = state
        for name, channel in self._channels.items():
            result = channel.apply(result)
        if gate_name in self._gate_overhead:
            p = self._gate_overhead[gate_name]
            if p > 0:
                channel = BitFlipChannel(p, state.n_qubits)
                result = channel.apply(result)
        return result
    def compose(self, other: 'NoiseModel') -> 'NoiseModel':
        combined = NoiseModel(self._n_qubits)
        for name, ch in self._channels.items():
            combined._channels[name] = ch
        for name, ch in other._channels.items():
            if name in combined._channels:
                combined._channels[name] = combined._channels[name].compose(ch)
            else:
                combined._channels[name] = ch
        combined._gate_overhead = {**self._gate_overhead, **other._gate_overhead}
        return combined
    def __repr__(self):
        return f"NoiseModel(channels={list(self._channels.keys())})"

def build_depolarizing_model(p: float, n_qubits: int = 1) -> NoiseModel:
    model = NoiseModel(n_qubits)
    model.add_channel("depolarizing", DepolarizingChannel(p, n_qubits))
    return model

def build_amplitude_damping_model(gamma: float, n_qubits: int = 1) -> NoiseModel:
    model = NoiseModel(n_qubits)
    model.add_channel("amplitude_damping", AmplitudeDampingChannel(gamma, n_qubits))
    return model

def build_realistic_model(t1: float, t2: float, gate_time: float,
                           readout_error: float = 0.01, n_qubits: int = 1) -> NoiseModel:
    model = NoiseModel(n_qubits)
    model.add_channel("thermal", ThermalRelaxationChannel(t1, t2, gate_time, n_qubits))
    model.set_gate_error("readout", readout_error)
    return model
