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

"""Quantum state vector representation and evolution."""
import math
import random
from typing import List, Optional, Tuple
from quantum_computer.core.complex import Complex, ZERO, ONE, I, tensor_product_vectors, normalize_vector, vector_norm, inner_product, scalar_mult
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product

class QuantumState:
    __slots__ = ('_n_qubits', '_amplitudes', '_dim')
    def __init__(self, n_qubits: int, amplitudes: Optional[List[Complex]] = None):
        if n_qubits < 1:
            raise ValueError("Need at least 1 qubit")
        self._n_qubits = n_qubits
        self._dim = 1 << n_qubits
        if amplitudes is not None:
            if len(amplitudes) != self._dim:
                raise ValueError(f"Expected {self._dim} amplitudes, got {len(amplitudes)}")
            self._amplitudes = amplitudes[:]
        else:
            self._amplitudes = [ZERO] * self._dim
            self._amplitudes[0] = ONE
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def dim(self) -> int:
        return self._dim
    @property
    def amplitudes(self) -> List[Complex]:
        return self._amplitudes[:]
    def get_amplitude(self, index: int) -> Complex:
        return self._amplitudes[index]
    def set_amplitude(self, index: int, val: Complex):
        self._amplitudes[index] = val
    def probability(self, index: int) -> float:
        return self._amplitudes[index].abs_sq()
    def total_probability(self) -> float:
        return sum(a.abs_sq() for a in self._amplitudes)
    def normalize(self):
        norm = self.total_probability() ** 0.5
        if norm < 1e-24:
            raise ValueError("Cannot normalize zero state")
        inv = ONE / Complex(norm)
        self._amplitudes = [a * inv for a in self._amplitudes]
    def is_normalized(self, tol: float = 1e-10) -> bool:
        return abs(self.total_probability() - 1.0) < tol
    def apply_gate(self, gate_matrix: Matrix):
        if gate_matrix.rows != self._dim or gate_matrix.cols != self._dim:
            raise ValueError(f"Gate dimension {gate_matrix.rows}x{gate_matrix.cols} doesn't match state dimension {self._dim}")
        new_amps = []
        for r in range(self._dim):
            s = ZERO
            for c in range(self._dim):
                s = s + gate_matrix.get(r, c) * self._amplitudes[c]
            new_amps.append(s)
        self._amplitudes = new_amps
    def apply_controlled_gate(self, gate_matrix: Matrix, control: int, target: int, n_qubits: int):
        if n_qubits != self._n_qubits:
            raise ValueError("Qubit count mismatch")
        dim = 1 << n_qubits
        new_amps = [ZERO] * dim
        gate_dim = gate_matrix.rows
        for state in range(dim):
            ctrl_bit = (state >> (n_qubits - 1 - control)) & 1
            if ctrl_bit == 0:
                new_amps[state] = new_amps[state] + self._amplitudes[state]
            else:
                tgt_val = (state >> (n_qubits - 1 - target)) & 1
                other_bits = 0
                for b in range(n_qubits):
                    if b != target:
                        bval = (state >> (n_qubits - 1 - b)) & 1
                        if b < target:
                            pos = b
                        else:
                            pos = b - 1
                        other_bits |= bval << pos
                for new_tgt in range(gate_dim):
                    coeff = gate_matrix.get(tgt_val, new_tgt)
                    if coeff.abs_sq() < 1e-24:
                        continue
                    new_state = 0
                    remaining = other_bits
                    for b in range(n_qubits):
                        if b == target:
                            new_state |= new_tgt << (n_qubits - 1 - b)
                        else:
                            if b < target:
                                pos = b
                            else:
                                pos = b - 1
                            bit_val = (remaining >> pos) & 1
                            new_state |= bit_val << (n_qubits - 1 - b)
                    new_amps[new_state] = new_amps[new_state] + coeff * self._amplitudes[state]
        self._amplitudes = new_amps
    def tensor(self, other: 'QuantumState') -> 'QuantumState':
        new_amps = tensor_product_vectors(self._amplitudes, other._amplitudes)
        return QuantumState(self._n_qubits + other._n_qubits, new_amps)
    def partial_trace(self, trace_qubits: List[int]) -> 'QuantumState':
        keep = [i for i in range(self._n_qubits) if i not in trace_qubits]
        n_keep = len(keep)
        n_trace = len(trace_qubits)
        new_dim = 1 << n_keep
        new_amps = [ZERO] * new_dim
        for idx in range(self._dim):
            keep_bits = 0
            for i, k in enumerate(keep):
                bit = (idx >> (self._n_qubits - 1 - k)) & 1
                keep_bits |= bit << (n_keep - 1 - i)
            new_amps[keep_bits] = new_amps[keep_bits] + self._amplitudes[idx]
        return QuantumState(n_keep, new_amps)
    def measure_qubit(self, qubit: int) -> Tuple[int, 'QuantumState']:
        prob_0 = ZERO
        for state in range(self._dim):
            if ((state >> (self._n_qubits - 1 - qubit)) & 1) == 0:
                prob_0 = prob_0 + Complex(self.probability(state))
        p0 = prob_0.re
        import random
        outcome = 0 if random.random() < p0 else 1
        new_amps = [ZERO] * self._dim
        norm_sq = 0.0
        for state in range(self._dim):
            bit = (state >> (self._n_qubits - 1 - qubit)) & 1
            if bit == outcome:
                new_amps[state] = self._amplitudes[state]
                norm_sq += self._amplitudes[state].abs_sq()
        if norm_sq > 1e-24:
            inv = ONE / Complex(norm_sq ** 0.5)
            new_amps = [a * inv for a in new_amps]
        return outcome, QuantumState(self._n_qubits, new_amps)
    def measure_all(self) -> List[int]:
        probs = [a.abs_sq() for a in self._amplitudes]
        total = sum(probs)
        if abs(total - 1.0) > 1e-10:
            inv = 1.0 / total
            probs = [p * inv for p in probs]
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
    def expectation(self, observable: 'Matrix') -> Complex:
        if observable.rows != self._dim or observable.cols != self._dim:
            raise ValueError("Observable dimension mismatch")
        result = ZERO
        for r in range(self._dim):
            for c in range(self._dim):
                result = result + self._amplitudes[r].conjugate() * observable.get(r, c) * self._amplitudes[c]
        return result
    def fidelity(self, other: 'QuantumState') -> float:
        if self._n_qubits != other._n_qubits:
            raise ValueError("Qubit count mismatch")
        overlap = inner_product(self._amplitudes, other._amplitudes)
        return overlap.abs_sq()
    def density_matrix(self) -> 'Matrix':
        n = self._dim
        data = []
        for r in range(n):
            row = []
            for c in range(n):
                row.append(self._amplitudes[r] * self._amplitudes[c].conjugate())
            data.append(row)
        return Matrix(data)
    def __repr__(self):
        terms = []
        for i in range(self._dim):
            if self._amplitudes[i].abs_sq() > 1e-12:
                bits = format(i, f'0{self._n_qubits}b')
                terms.append(f"({self._amplitudes[i]})|{bits}>")
        return " + ".join(terms) if terms else "0"
    def copy(self) -> 'QuantumState':
        return QuantumState(self._n_qubits, self._amplitudes[:])

def zero_state(n_qubits: int) -> QuantumState:
    return QuantumState(n_qubits)

def plus_state(n_qubits: int) -> QuantumState:
    dim = 1 << n_qubits
    amps = [ONE / Complex(dim ** 0.5)] * dim
    return QuantumState(n_qubits, amps)

def bell_state(n_qubits: int = 2) -> QuantumState:
    if n_qubits < 2:
        raise ValueError("Bell state needs at least 2 qubits")
    amps = [ZERO] * (1 << n_qubits)
    inv_sqrt2 = ONE / Complex(math.sqrt(2))
    amps[0] = inv_sqrt2
    amps[(1 << n_qubits) - 1] = inv_sqrt2
    return QuantumState(n_qubits, amps)

def ghz_state(n_qubits: int) -> QuantumState:
    if n_qubits < 2:
        raise ValueError("GHZ state needs at least 2 qubits")
    amps = [ZERO] * (1 << n_qubits)
    inv_sqrt2 = ONE / Complex(math.sqrt(2))
    amps[0] = inv_sqrt2
    amps[(1 << n_qubits) - 1] = inv_sqrt2
    return QuantumState(n_qubits, amps)

def computational_basis_state(index: int, n_qubits: int) -> QuantumState:
    dim = 1 << n_qubits
    if index < 0 or index >= dim:
        raise ValueError(f"Index {index} out of range for {n_qubits} qubits")
    amps = [ZERO] * dim
    amps[index] = ONE
    return QuantumState(n_qubits, amps)

def random_state(n_qubits: int) -> QuantumState:
    import random
    dim = 1 << n_qubits
    amps = []
    for _ in range(dim):
        re = random.gauss(0, 1)
        im = random.gauss(0, 1)
        amps.append(Complex(re, im))
    norm = sum(a.abs_sq() for a in amps) ** 0.5
    amps = [a / norm for a in amps]
    return QuantumState(n_qubits, amps)
