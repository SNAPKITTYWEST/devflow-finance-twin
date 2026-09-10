"""Qubit state model and register allocation."""
import random
import math
from typing import List, Optional, Tuple, Dict
from quantum_computer.core.complex import Complex, ZERO, ONE, I, INV_SQRT2
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product
from quantum_computer.core.state import QuantumState, zero_state, computational_basis_state

class Qubit:
    __slots__ = ('_index', '_label', '_allocated')
    def __init__(self, index: int, label: Optional[str] = None):
        self._index = index
        self._label = label or f"q{index}"
        self._allocated = True
    @property
    def index(self) -> int:
        return self._index
    @property
    def label(self) -> str:
        return self._label
    @property
    def allocated(self) -> bool:
        return self._allocated
    def deallocate(self):
        self._allocated = False
    def __repr__(self):
        return f"Qubit({self._index}, '{self._label}')"
    def __eq__(self, other):
        if isinstance(other, Qubit):
            return self._index == other._index
        return NotImplemented
    def __hash__(self):
        return hash(self._index)

class QuantumRegister:
    __slots__ = ('_name', '_qubits', '_size', '_state')
    def __init__(self, size: int, name: str = "q"):
        if size < 1:
            raise ValueError("Register size must be >= 1")
        self._name = name
        self._size = size
        self._qubits = [Qubit(i, f"{name}{i}") for i in range(size)]
        self._state = zero_state(size)
    @property
    def name(self) -> str:
        return self._name
    @property
    def size(self) -> int:
        return self._size
    @property
    def qubits(self) -> List[Qubit]:
        return self._qubits[:]
    @property
    def state(self) -> QuantumState:
        return self._state
    def get_qubit(self, index: int) -> Qubit:
        if index < 0 or index >= self._size:
            raise IndexError(f"Qubit index {index} out of range")
        return self._qubits[index]
    def set_state(self, state: QuantumState):
        if state.n_qubits != self._size:
            raise ValueError("State size mismatch")
        self._state = state
    def apply_gate(self, gate: Matrix, qubit_indices: List[int]):
        for idx in qubit_indices:
            if idx < 0 or idx >= self._size:
                raise IndexError(f"Qubit index {idx} out of range")
        if len(qubit_indices) == 1:
            full_gate = self._embed_single_gate(gate, qubit_indices[0])
            self._state.apply_gate(full_gate)
        elif len(qubit_indices) == 2:
            self._apply_two_qubit_gate(gate, qubit_indices[0], qubit_indices[1])
        else:
            self._apply_multi_qubit_gate(gate, qubit_indices)
    def _embed_single_gate(self, gate: Matrix, target: int) -> Matrix:
        if self._size == 1:
            return gate
        parts = []
        for i in range(self._size):
            if i == target:
                parts.append(gate)
            else:
                parts.append(identity_matrix(2))
        result = parts[0]
        for i in range(1, len(parts)):
            result = tensor_product(result, parts[i])
        return result
    def _apply_two_qubit_gate(self, gate: Matrix, q0: int, q1: int):
        if self._size == 2:
            self._state.apply_gate(gate)
            return
        dim = 1 << self._size
        gate_dim = gate.rows
        new_amps = [ZERO] * dim
        for state in range(dim):
            bits0 = (state >> (self._size - 1 - q0)) & 1
            bits1 = (state >> (self._size - 1 - q1)) & 1
            input_idx = bits0 * 2 + bits1
            other_positions = []
            for b in range(self._size):
                if b != q0 and b != q1:
                    other_positions.append(b)
            for new_b0 in range(2):
                for new_b1 in range(2):
                    output_idx = new_b0 * 2 + new_b1
                    coeff = gate.get(input_idx, output_idx)
                    if coeff.abs_sq() < 1e-24:
                        continue
                    new_state = 0
                    for b in other_positions:
                        bit_val = (state >> (self._size - 1 - b)) & 1
                        new_state |= bit_val << (self._size - 1 - b)
                    if new_b0 == 1:
                        new_state |= (1 << (self._size - 1 - q0))
                    if new_b1 == 1:
                        new_state |= (1 << (self._size - 1 - q1))
                    new_amps[new_state] = new_amps[new_state] + coeff * self._amplitudes[state]
        self._state = QuantumState(self._size, new_amps)
    def _apply_multi_qubit_gate(self, gate: Matrix, qubit_indices: List[int]):
        dim = 1 << self._size
        n_gate = len(qubit_indices)
        gate_dim = 1 << n_gate
        if gate.rows != gate_dim or gate.cols != gate_dim:
            raise ValueError(f"Gate dimension {gate.rows}x{gate.cols} doesn't match {n_gate} qubits")
        new_amps = [ZERO] * dim
        self_amps = self._state.amplitudes
        for state in range(dim):
            gate_idx = 0
            for i, q in enumerate(qubit_indices):
                bit = (state >> (self._size - 1 - q)) & 1
                gate_idx |= bit << (n_gate - 1 - i)
            for new_state in range(dim):
                other_match = True
                for b in range(self._size):
                    if b not in qubit_indices:
                        if ((state >> (self._size - 1 - b)) & 1) != ((new_state >> (self._size - 1 - b)) & 1):
                            other_match = False
                            break
                if not other_match:
                    continue
                new_gate_idx = 0
                for i, q in enumerate(qubit_indices):
                    bit = (new_state >> (self._size - 1 - q)) & 1
                    new_gate_idx |= bit << (n_gate - 1 - i)
                coeff = gate.get(gate_idx, new_gate_idx)
                if coeff.abs_sq() > 1e-24:
                    new_amps[new_state] = new_amps[new_state] + coeff * self_amps[state]
        self._state = QuantumState(self._size, new_amps)
    def h(self, qubit: int):
        from quantum_computer.gates import H_GATE
        self.apply_gate(H_GATE.matrix, [qubit])
    def x(self, qubit: int):
        from quantum_computer.gates import X_GATE
        self.apply_gate(X_GATE.matrix, [qubit])
    def y(self, qubit: int):
        from quantum_computer.gates import Y_GATE
        self.apply_gate(Y_GATE.matrix, [qubit])
    def z(self, qubit: int):
        from quantum_computer.gates import Z_GATE
        self.apply_gate(Z_GATE.matrix, [qubit])
    def s(self, qubit: int):
        from quantum_computer.gates import S_GATE
        self.apply_gate(S_GATE.matrix, [qubit])
    def t(self, qubit: int):
        from quantum_computer.gates import T_GATE
        self.apply_gate(T_GATE.matrix, [qubit])
    def cnot(self, control: int, target: int):
        from quantum_computer.gates import CNOT_GATE, controlled_gate
        full = controlled_gate(CNOT_GATE, control, target, self._size)
        self._state.apply_gate(full)
    def swap(self, q0: int, q1: int):
        from quantum_computer.gates import SWAP_GATE, controlled_gate
        full = controlled_gate(SWAP_GATE, q0, q1, self._size) if self._size > 2 else SWAP_GATE.matrix
        self._state.apply_gate(full)
    @property
    def _amplitudes(self):
        return self._state.amplitudes
    def measure_qubit(self, index: int) -> int:
        outcome, new_state = self._state.measure_qubit(index)
        self._state = new_state
        return outcome
    def measure_all(self) -> List[int]:
        return self._state.measure_all()
    def probabilities(self) -> List[float]:
        return [a.abs_sq() for a in self._state.amplitudes]
    def reset(self):
        self._state = zero_state(self._size)
    def clone(self) -> 'QuantumRegister':
        reg = QuantumRegister(self._size, self._name + "_copy")
        reg._state = self._state.copy()
        return reg
    def __repr__(self):
        return f"QuantumRegister(name='{self._name}', size={self._size})"

class ClassicalRegister:
    __slots__ = ('_name', '_size', '_bits')
    def __init__(self, size: int, name: str = "c"):
        if size < 1:
            raise ValueError("Register size must be >= 1")
        self._name = name
        self._size = size
        self._bits = [0] * size
    @property
    def name(self) -> str:
        return self._name
    @property
    def size(self) -> int:
        return self._size
    def get_bit(self, index: int) -> int:
        if index < 0 or index >= self._size:
            raise IndexError(f"Bit index {index} out of range")
        return self._bits[index]
    def set_bit(self, index: int, value: int):
        if index < 0 or index >= self._size:
            raise IndexError(f"Bit index {index} out of range")
        self._bits[index] = value & 1
    def set_value(self, value: int):
        for i in range(self._size):
            self._bits[i] = (value >> i) & 1
    def get_value(self) -> int:
        val = 0
        for i in range(self._size):
            val |= self._bits[i] << i
        return val
    def reset(self):
        self._bits = [0] * self._size
    def __getitem__(self, index: int) -> int:
        return self.get_bit(index)
    def __setitem__(self, index: int, value: int):
        self.set_bit(index, value)
    def __repr__(self):
        bits_str = "".join(str(b) for b in reversed(self._bits))
        return f"ClassicalRegister(name='{self._name}', value=0b{bits_str})"
    def clone(self) -> 'ClassicalRegister':
        reg = ClassicalRegister(self._size, self._name + "_copy")
        reg._bits = self._bits[:]
        return reg

class RegisterManager:
    __slots__ = ('_qregs', '_cregs', '_qubit_map', '_total_qubits')
    def __init__(self):
        self._qregs: Dict[str, QuantumRegister] = {}
        self._cregs: Dict[str, ClassicalRegister] = {}
        self._qubit_map: Dict[str, int] = {}
        self._total_qubits = 0
    def allocate_quantum_register(self, size: int, name: Optional[str] = None) -> QuantumRegister:
        if name is None:
            name = f"q{len(self._qregs)}"
        if name in self._qregs:
            raise ValueError(f"Register '{name}' already exists")
        reg = QuantumRegister(size, name)
        self._qregs[name] = reg
        for i in range(size):
            self._qubit_map[f"{name}{i}"] = self._total_qubits + i
        self._total_qubits += size
        return reg
    def allocate_classical_register(self, size: int, name: Optional[str] = None) -> ClassicalRegister:
        if name is None:
            name = f"c{len(self._cregs)}"
        if name in self._cregs:
            raise ValueError(f"Register '{name}' already exists")
        reg = ClassicalRegister(size, name)
        self._cregs[name] = reg
        return reg
    def get_quantum_register(self, name: str) -> QuantumRegister:
        if name not in self._qregs:
            raise KeyError(f"Quantum register '{name}' not found")
        return self._qregs[name]
    def get_classical_register(self, name: str) -> ClassicalRegister:
        if name not in self._cregs:
            raise KeyError(f"Classical register '{name}' not found")
        return self._cregs[name]
    def get_qubit_index(self, label: str) -> int:
        if label not in self._qubit_map:
            raise KeyError(f"Qubit '{label}' not found")
        return self._qubit_map[label]
    @property
    def total_qubits(self) -> int:
        return self._total_qubits
    @property
    def quantum_registers(self) -> Dict[str, QuantumRegister]:
        return dict(self._qregs)
    @property
    def classical_registers(self) -> Dict[str, ClassicalRegister]:
        return dict(self._cregs)
    def all_qubit_labels(self) -> List[str]:
        labels = []
        for name, reg in self._qregs.items():
            for i in range(reg.size):
                labels.append(f"{name}{i}")
        return labels
    def reset_all(self):
        for reg in self._qregs.values():
            reg.reset()
        for reg in self._cregs.values():
            reg.reset()
    def __repr__(self):
        qreg_names = list(self._qregs.keys())
        creg_names = list(self._cregs.keys())
        return f"RegisterManager(qregs={qreg_names}, cregs={creg_names}, total_qubits={self._total_qubits})"
