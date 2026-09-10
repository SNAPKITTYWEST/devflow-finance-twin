"""Advanced noise models: correlated noise, crosstalk, temperature-dependent noise."""
import math
import random
from typing import List, Optional, Tuple, Dict
from quantum_computer.core.complex import Complex, ZERO, ONE, I
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product
from quantum_computer.core.state import QuantumState
from quantum_computer.circuit.circuit import QuantumCircuit
from quantum_computer.gates import Gate, get_gate
from quantum_computer.noise import QuantumChannel, BitFlipChannel, PhaseFlipChannel, DepolarizingChannel

class CorrelatedNoiseChannel(QuantumChannel):
    __slots__ = ('_correlation_matrix', '_n_qubits')
    def __init__(self, error_rate: float, correlation: float, n_qubits: int):
        if error_rate < 0 or error_rate > 1:
            raise ValueError("Error rate must be in [0,1]")
        if correlation < 0 or correlation > 1:
            raise ValueError("Correlation must be in [0,1]")
        self._n_qubits = n_qubits
        dim = 1 << n_qubits
        self._correlation_matrix = [[ZERO] * dim for _ in range(dim)]
        kraus = []
        I_mat = identity_matrix(2)
        X = Matrix([[ZERO, ONE], [ONE, ZERO]])
        sqrt_p = math.sqrt(error_rate)
        sqrt_1mp = math.sqrt(1 - error_rate)
        for i in range(n_qubits):
            ops = []
            for j in range(n_qubits):
                if j == i:
                    ops.append(sqrt_p * X)
                else:
                    ops.append(sqrt_1mp * I_mat)
            k = ops[0]
            for op in ops[1:]:
                k = tensor_product(k, op)
            kraus.append(k)
        identity_coeff = math.sqrt(1 - error_rate)
        kraus.append(identity_coeff * identity_matrix(dim))
        super().__init__("CorrelatedNoise", n_qubits, kraus)

class CrosstalkChannel(QuantumChannel):
    __slots__ = ('_crosstalk_pairs', '_crosstalk_strength', '_n_qubits')
    def __init__(self, n_qubits: int, crosstalk_pairs: List[Tuple[int, int]],
                 crosstalk_strength: float = 0.01):
        self._n_qubits = n_qubits
        self._crosstalk_pairs = crosstalk_pairs[:]
        self._crosstalk_strength = crosstalk_strength
        dim = 1 << n_qubits
        kraus = []
        I_mat = identity_matrix(2)
        X = Matrix([[ZERO, ONE], [ONE, ZERO]])
        for pair in crosstalk_pairs:
            i, j = pair
            ops = []
            for q in range(n_qubits):
                if q == i or q == j:
                    ops.append(math.sqrt(crosstalk_strength) * X)
                else:
                    ops.append(math.sqrt(1 - crosstalk_strength) * I_mat)
            k = ops[0]
            for op in ops[1:]:
                k = tensor_product(k, op)
            kraus.append(k)
        identity_coeff = math.sqrt(1 - crosstalk_strength * len(crosstalk_pairs))
        kraus.append(identity_coeff * identity_matrix(dim))
        super().__init__("Crosstalk", n_qubits, kraus)

class TemperatureDependentChannel(QuantumChannel):
    __slots__ = ('_temperature', '_frequency', '_n_qubits')
    def __init__(self, temperature: float, frequency: float, n_qubits: int = 1):
        self._temperature = temperature
        self._frequency = frequency
        self._n_qubits = n_qubits
        kB = 1.380649e-23
        h = 6.62607015e-34
        if temperature > 0:
            p_thermal = 1.0 / (math.exp(h * frequency / (kB * temperature)) + 1)
        else:
            p_thermal = 0.0
        p_bitflip = p_thermal
        kraus = []
        sqrt_p = math.sqrt(p_bitflip)
        sqrt_1mp = math.sqrt(1 - p_bitflip)
        X = Matrix([[ZERO, ONE], [ONE, ZERO]])
        I_mat = identity_matrix(2)
        if n_qubits == 1:
            kraus = [sqrt_1mp * I_mat, sqrt_p * X]
        else:
            for i in range(n_qubits):
                ops = []
                for j in range(n_qubits):
                    if j == i:
                        ops.append(sqrt_p * X)
                    else:
                        ops.append(sqrt_1mp * I_mat)
                k = ops[0]
                for op in ops[1:]:
                    k = tensor_product(k, op)
                kraus.append(k)
            kraus.append(sqrt_1mp ** n_qubits * identity_matrix(1 << n_qubits))
        super().__init__("TemperatureDependent", n_qubits, kraus)

class CoherentErrorChannel(QuantumChannel):
    __slots__ = ('_rotation_error', '_axis', '_n_qubits')
    def __init__(self, rotation_error: float, axis: str = "z", n_qubits: int = 1):
        if axis not in ("x", "y", "z"):
            raise ValueError("Axis must be x, y, or z")
        self._rotation_error = rotation_error
        self._axis = axis
        self._n_qubits = n_qubits
        angle = rotation_error
        if axis == "x":
            R = Matrix([
                [Complex(math.cos(angle/2)), Complex(0, -math.sin(angle/2))],
                [Complex(0, -math.sin(angle/2)), Complex(math.cos(angle/2))]
            ])
        elif axis == "y":
            R = Matrix([
                [Complex(math.cos(angle/2)), Complex(-math.sin(angle/2))],
                [Complex(math.sin(angle/2)), Complex(math.cos(angle/2))]
            ])
        else:
            R = Matrix([
                [Complex(math.cos(angle/2), -math.sin(angle/2)), ZERO],
                [ZERO, Complex(math.cos(angle/2), math.sin(angle/2))]
            ])
        if n_qubits == 1:
            kraus = [R]
        else:
            ops = [R]
            for _ in range(n_qubits - 1):
                ops.append(identity_matrix(2))
            k = ops[0]
            for op in ops[1:]:
                k = tensor_product(k, op)
            kraus = [k]
        super().__init__("CoherentError", n_qubits, kraus)

class ReadoutNoiseChannel(QuantumChannel):
    __slots__ = ('_bit_flip_prob', '_n_qubits')
    def __init__(self, bit_flip_prob: float, n_qubits: int = 1):
        if bit_flip_prob < 0 or bit_flip_prob > 1:
            raise ValueError("Probability must be in [0,1]")
        self._bit_flip_prob = bit_flip_prob
        self._n_qubits = n_qubits
        dim = 1 << n_qubits
        kraus = []
        for outcome in range(dim):
            proj = [[ZERO] * dim for _ in range(dim)]
            proj[outcome][outcome] = ONE
            for bit in range(n_qubits):
                if (outcome >> bit) & 1:
                    flipped = outcome ^ (1 << bit)
                    proj[flipped][outcome] = Complex(math.sqrt(bit_flip_prob))
                    proj[outcome][outcome] = Complex(math.sqrt(1 - bit_flip_prob))
            kraus.append(Matrix(proj))
        super().__init__("ReadoutNoise", n_qubits, kraus)

class AdvancedNoiseModel:
    __slots__ = ('_channels', '_correlations', '_temporal_model', '_n_qubits')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        self._channels: Dict[str, QuantumChannel] = {}
        self._correlations: List[Tuple[int, int, float]] = []
        self._temporal_model: Dict[str, float] = {}
    def add_channel(self, name: str, channel: QuantumChannel):
        self._channels[name] = channel
    def set_correlated_errors(self, pairs: List[Tuple[int, int, float]]):
        self._correlations = pairs[:]
    def set_temporal_model(self, t1: float, t2: float, gate_time: float):
        self._temporal_model = {"t1": t1, "t2": t2, "gate_time": gate_time}
    def apply_noise(self, state: QuantumState, gate_name: str = "") -> QuantumState:
        result = state
        for name, channel in self._channels.items():
            result = channel.apply(result)
        return result
    def apply_correlated_noise(self, state: QuantumState) -> QuantumState:
        result = state
        for i, j, strength in self._correlations:
            if random.random() < strength:
                bf = BitFlipChannel(0.5, self._n_qubits)
                result = bf.apply(result)
        return result
    def compose(self, other: 'AdvancedNoiseModel') -> 'AdvancedNoiseModel':
        combined = AdvancedNoiseModel(self._n_qubits)
        for name, ch in self._channels.items():
            combined._channels[name] = ch
        for name, ch in other._channels.items():
            if name in combined._channels:
                combined._channels[name] = combined._channels[name].compose(ch)
            else:
                combined._channels[name] = ch
        combined._correlations = self._correlations + other._correlations
        return combined
    def __repr__(self):
        return f"AdvancedNoiseModel(channels={list(self._channels.keys())}, correlations={len(self._correlations)})"

class NoiseCharacterizer:
    __slots__ = ('_n_qubits', '_calibration_data')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        self._calibration_data: Dict[str, List[float]] = {}
    def characterize_bit_flip(self, circuit_fn, n_shots: int = 1000) -> float:
        errors = 0
        for _ in range(n_shots):
            result = circuit_fn()
            measured = result.get("measured", [0])
            expected = result.get("expected", [0])
            if measured != expected:
                errors += 1
        return errors / n_shots
    def characterize_phase_flip(self, circuit_fn, n_shots: int = 1000) -> float:
        errors = 0
        for _ in range(n_shots):
            result = circuit_fn()
            measured = result.get("measured", [0])
            expected = result.get("expected", [0])
            if measured != expected:
                errors += 1
        return errors / n_shots
    def characterize_depolarizing(self, circuit_fn, n_shots: int = 1000) -> float:
        errors = 0
        for _ in range(n_shots):
            result = circuit_fn()
            measured = result.get("measured", [0])
            expected = result.get("expected", [0])
            if measured != expected:
                errors += 1
        return errors / n_shots
    def characterize_crosstalk(self, circuit_fns: Dict[str, callable],
                                 n_shots: int = 1000) -> Dict[str, float]:
        results = {}
        for name, fn in circuit_fns.items():
            errors = 0
            for _ in range(n_shots):
                result = fn()
                measured = result.get("measured", [0])
                expected = result.get("expected", [0])
                if measured != expected:
                    errors += 1
            results[name] = errors / n_shots
        return results
    def store_calibration(self, name: str, data: List[float]):
        self._calibration_data[name] = data[:]
    def get_calibration(self, name: str) -> Optional[List[float]]:
        return self._calibration_data.get(name)
    def __repr__(self):
        return f"NoiseCharacterizer(n_qubits={self._n_qubits})"

class DynamicalDecouplingSequences:
    __slots__ = ('_sequences')
    def __init__(self):
        self._sequences = {
            "spin_echo": self._spin_echo,
            "cpmg": self._cpmg,
            "uhrig": self._uhrig,
            "xy4": self._xy4,
            "kdd": self._kdd,
        }
    def apply(self, sequence_name: str, circuit: QuantumCircuit,
              qubit: int, idle_time: float) -> QuantumCircuit:
        if sequence_name not in self._sequences:
            raise ValueError(f"Unknown sequence: {sequence_name}")
        return self._sequences[sequence_name](circuit, qubit, idle_time)
    def _spin_echo(self, circuit: QuantumCircuit, qubit: int,
                    idle_time: float) -> QuantumCircuit:
        result = circuit.copy()
        result.x(qubit)
        return result
    def _cpmg(self, circuit: QuantumCircuit, qubit: int,
               idle_time: float, n_pulses: int = 4) -> QuantumCircuit:
        result = circuit.copy()
        for _ in range(n_pulses):
            result.x(qubit)
        return result
    def _uhrig(self, circuit: QuantumCircuit, qubit: int,
                idle_time: float, n_pulses: int = 8) -> QuantumCircuit:
        result = circuit.copy()
        for i in range(n_pulses):
            t = (i + 0.5) * idle_time / n_pulses
            result.x(qubit)
        return result
    def _xy4(self, circuit: QuantumCircuit, qubit: int,
              idle_time: float) -> QuantumCircuit:
        result = circuit.copy()
        result.x(qubit)
        result.y(qubit)
        result.x(qubit)
        result.y(qubit)
        return result
    def _kdd(self, circuit: QuantumCircuit, qubit: int,
              idle_time: float) -> QuantumCircuit:
        result = circuit.copy()
        result.x(qubit)
        result.y(qubit)
        result.x(qubit)
        result.y(qubit)
        result.x(qubit)
        return result
    def list_sequences(self) -> List[str]:
        return list(self._sequences.keys())
    def __repr__(self):
        return f"DynamicalDecouplingSequences(sequences={list(self._sequences.keys())})"
