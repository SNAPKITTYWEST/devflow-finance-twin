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

"""Quantum error correction: repetition codes, syndrome extraction, stabilizer, surface code."""
import math
from typing import List, Optional, Tuple, Dict, Set
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product
from quantum_computer.core.state import QuantumState, zero_state
from quantum_computer.core.register import QuantumRegister
from quantum_computer.circuit.circuit import QuantumCircuit
from quantum_computer.gates import X_GATE, Z_GATE, CNOT_GATE, H_GATE, get_gate, Gate

class StabilizerCode:
    __slots__ = ('_n_qubits', '_n_stabilizers', '_stabilizers', '_logical_x', '_logical_z')
    def __init__(self, n_qubits: int, stabilizers: List[List[Tuple[str, int]]],
                 logical_x: Optional[List[Tuple[str, int]]] = None,
                 logical_z: Optional[List[Tuple[str, int]]] = None):
        self._n_qubits = n_qubits
        self._n_stabilizers = len(stabilizers)
        self._stabilizers = stabilizers[:]
        self._logical_x = logical_x or []
        self._logical_z = logical_z or []
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def n_stabilizers(self) -> int:
        return self._n_stabilizers
    @property
    def n_logical_qubits(self) -> int:
        return self._n_qubits - self._n_stabilizers
    @property
    def stabilizers(self) -> List[List[Tuple[str, int]]]:
        return [s[:] for s in self._stabilizers]
    @property
    def logical_x(self) -> List[Tuple[str, int]]:
        return self._logical_x[:]
    @property
    def logical_z(self) -> List[Tuple[str, int]]:
        return self._logical_z[:]
    def encode(self, data_qubit: int, syndrome_qubits: List[int]) -> QuantumCircuit:
        n_total = self._n_qubits
        circ = QuantumCircuit(n_total)
        for stab in self._stabilizers:
            for pauli, qubit in stab:
                if pauli == "X":
                    circ.x(qubit)
                elif pauli == "Z":
                    circ.z(qubit)
                elif pauli == "Y":
                    circ.y(qubit)
        return circ
    def syndrome_extraction_circuit(self) -> QuantumCircuit:
        circ = QuantumCircuit(self._n_qubits + self._n_stabilizers)
        data_start = 0
        anc_start = self._n_qubits
        for i, stab in enumerate(self._stabilizers):
            circ.h(anc_start + i)
            for pauli, qubit in stab:
                if pauli == "X":
                    circ.cnot(qubit, anc_start + i)
                elif pauli == "Z":
                    circ.cnot(anc_start + i, qubit)
                elif pauli == "Y":
                    circ.cnot(anc_start + i, qubit)
                    circ.cnot(qubit, anc_start + i)
            circ.h(anc_start + i)
        return circ
    def decode_syndrome(self, syndrome: List[int]) -> List[int]:
        error_qubits = []
        for i, bit in enumerate(syndrome):
            if bit == 1:
                for pauli, qubit in self._stabilizers[i]:
                    if qubit not in error_qubits:
                        error_qubits.append(qubit)
        return error_qubits
    def __repr__(self):
        return f"StabilizerCode(n={self._n_qubits}, k={self.n_logical_qubits}, stabilizers={self._n_stabilizers})"

class RepetitionCode:
    __slots__ = ('_n_data', '_n_total', '_code_type')
    def __init__(self, n_data: int, code_type: str = "bit"):
        if n_data < 1:
            raise ValueError("Need at least 1 data qubit")
        self._n_data = n_data
        self._n_total = 3 * n_data
        self._code_type = code_type
    @property
    def n_data_qubits(self) -> int:
        return self._n_data
    @property
    def n_ancilla_qubits(self) -> int:
        return 2 * self._n_data
    @property
    def n_total_qubits(self) -> int:
        return self._n_total
    @property
    def code_type(self) -> str:
        return self._code_type
    def encoding_circuit(self) -> QuantumCircuit:
        circ = QuantumCircuit(self._n_total)
        for i in range(self._n_data):
            data_idx = 3 * i
            circ.cnot(data_idx, data_idx + 1)
            circ.cnot(data_idx, data_idx + 2)
        return circ
    def syndrome_extraction_circuit(self) -> QuantumCircuit:
        n_data = self._n_data
        n_anc = 2 * n_data
        circ = QuantumCircuit(n_data + n_anc)
        data_start = 0
        anc_start = n_data
        for i in range(n_data):
            d0 = 3 * i
            d1 = 3 * i + 1
            d2 = 3 * i + 2
            a0 = anc_start + 2 * i
            a1 = anc_start + 2 * i + 1
            circ.h(a0)
            circ.h(a1)
            circ.cnot(d0, a0)
            circ.cnot(d1, a0)
            circ.cnot(d1, a1)
            circ.cnot(d2, a1)
            circ.h(a0)
            circ.h(a1)
        return circ
    def decode_syndrome(self, syndrome: List[int]) -> List[int]:
        errors = []
        for i in range(self._n_data):
            s0 = syndrome[2 * i] if 2 * i < len(syndrome) else 0
            s1 = syndrome[2 * i + 1] if 2 * i + 1 < len(syndrome) else 0
            if s0 == 1 and s1 == 0:
                errors.append(3 * i)
            elif s0 == 0 and s1 == 1:
                errors.append(3 * i + 2)
            elif s0 == 1 and s1 == 1:
                errors.append(3 * i + 1)
        return errors
    def correction_circuit(self) -> QuantumCircuit:
        n_data = self._n_data
        n_anc = 2 * n_data
        circ = QuantumCircuit(n_data + n_anc)
        anc_start = n_data
        for i in range(n_data):
            a0 = anc_start + 2 * i
            a1 = anc_start + 2 * i + 1
            circ.cnot(a0, 3 * i)
            circ.ccx(a0, a1, 3 * i + 1)
            circ.cnot(a1, 3 * i + 2)
        return circ
    def full_circuit(self) -> QuantumCircuit:
        enc = self.encoding_circuit()
        syn = self.syndrome_extraction_circuit()
        corr = self.correction_circuit()
        n_total = max(enc.n_qubits, syn.n_qubits, corr.n_qubits)
        full = QuantumCircuit(n_total)
        for inst in enc.instructions:
            full.add_instruction(inst.gate, inst.qubits)
        for inst in syn.instructions:
            full.add_instruction(inst.gate, inst.qubits)
        for inst in corr.instructions:
            full.add_instruction(inst.gate, inst.qubits)
        return full
    def __repr__(self):
        return f"RepetitionCode(data={self._n_data}, total={self._n_total})"

class SyndromeExtractor:
    __slots__ = ('_code', '_n_ancilla')
    def __init__(self, code: StabilizerCode):
        self._code = code
        self._n_ancilla = code.n_stabilizers
    @property
    def n_ancilla(self) -> int:
        return self._n_ancilla
    def extract(self, state: QuantumState) -> List[int]:
        syndrome = []
        for stab in self._code.stabilizers:
            eigenval = self._measure_stabilizer(state, stab)
            syndrome.append(eigenval)
        return syndrome
    def _measure_stabilizer(self, state: QuantumState, stabilizer: List[Tuple[str, int]]) -> int:
        n = state.n_qubits
        sign = 1
        for pauli, qubit in stabilizer:
            if pauli == "X":
                for amp_idx in range(state.dim):
                    if ((amp_idx >> (n - 1 - qubit)) & 1) == 0:
                        partner = amp_idx | (1 << (n - 1 - qubit))
                        if partner < state.dim:
                            sign *= 1
            elif pauli == "Z":
                for amp_idx in range(state.dim):
                    bit = (amp_idx >> (n - 1 - qubit)) & 1
                    if bit == 1:
                        sign *= -1
        return 0 if sign == 1 else 1
    def extract_with_circuit(self, state: QuantumState) -> Tuple[List[int], QuantumState]:
        syndrome = self.extract(state)
        return syndrome, state

class SurfaceCode:
    __slots__ = ('_distance', '_n_data', '_n_ancilla', '_n_qubits')
    def __init__(self, distance: int):
        if distance < 3 or distance % 2 == 0:
            raise ValueError("Distance must be odd and >= 3")
        self._distance = distance
        self._n_data = distance * distance
        self._n_ancilla = (distance - 1) * (distance - 1)
        self._n_qubits = self._n_data + self._n_ancilla
    @property
    def distance(self) -> int:
        return self._distance
    @property
    def n_data_qubits(self) -> int:
        return self._n_data
    @property
    def n_ancilla_qubits(self) -> int:
        return self._n_ancilla
    @property
    def n_total_qubits(self) -> int:
        return self._n_qubits
    def get_data_qubit_position(self, row: int, col: int) -> int:
        if row < 0 or row >= self._distance or col < 0 or col >= self._distance:
            raise ValueError("Position out of range")
        return row * self._distance + col
    def get_ancilla_position(self, row: int, col: int) -> int:
        if row < 0 or row >= self._distance - 1 or col < 0 or col >= self._distance - 1:
            raise ValueError("Ancilla position out of range")
        return self._n_data + row * (self._distance - 1) + col
    def get_x_stabilizers(self) -> List[List[int]]:
        stabilizers = []
        for r in range(self._distance - 1):
            for c in range(self._distance):
                stab = []
                if c > 0:
                    stab.append(self.get_data_qubit_position(r, c - 1))
                if c < self._distance - 1:
                    stab.append(self.get_data_qubit_position(r, c + 1))
                stab.append(self.get_data_qubit_position(r, c))
                if r > 0:
                    stab.append(self.get_data_qubit_position(r - 1, c))
                if r < self._distance - 1:
                    stab.append(self.get_data_qubit_position(r + 1, c))
                if stab:
                    stabilizers.append(stab)
        return stabilizers
    def get_z_stabilizers(self) -> List[List[int]]:
        stabilizers = []
        for r in range(self._distance):
            for c in range(self._distance - 1):
                stab = []
                stab.append(self.get_data_qubit_position(r, c))
                stab.append(self.get_data_qubit_position(r, c + 1))
                if c > 0:
                    stab.append(self.get_data_qubit_position(r, c - 1))
                if r > 0:
                    stab.append(self.get_data_qubit_position(r - 1, c))
                if r < self._distance - 1:
                    stab.append(self.get_data_qubit_position(r + 1, c))
                if len(stab) >= 2:
                    stabilizers.append(stab)
        return stabilizers
    def syndrome_extraction_circuit(self) -> QuantumCircuit:
        circ = QuantumCircuit(self._n_qubits)
        for r in range(self._distance - 1):
            for c in range(self._distance - 1):
                anc = self.get_ancilla_position(r, c)
                circ.h(anc)
                data_neighbors = []
                if c > 0:
                    data_neighbors.append(self.get_data_qubit_position(r, c - 1))
                if c < self._distance - 1:
                    data_neighbors.append(self.get_data_qubit_position(r, c + 1))
                data_neighbors.append(self.get_data_qubit_position(r, c))
                for d in data_neighbors:
                    circ.cnot(d, anc)
                circ.h(anc)
        return circ
    def distance_from_positions(self, positions: List[int]) -> int:
        if len(positions) < 2:
            return 0
        min_dist = float('inf')
        for i in range(len(positions)):
            for j in range(i + 1, len(positions)):
                r1, c1 = divmod(positions[i], self._distance)
                r2, c2 = divmod(positions[j], self._distance)
                dist = abs(r1 - r2) + abs(c1 - c2)
                min_dist = min(min_dist, dist)
        return min_dist
    def __repr__(self):
        return f"SurfaceCode(d={self._distance}, data={self._n_data}, ancilla={self._n_ancilla})"

class LogicalQubit:
    __slots__ = ('_code', '_state', '_physical_qubits')
    def __init__(self, code: StabilizerCode, physical_qubits: Optional[List[int]] = None):
        self._code = code
        self._state = zero_state(code.n_qubits)
        self._physical_qubits = physical_qubits or list(range(code.n_qubits))
    @property
    def code(self) -> StabilizerCode:
        return self._code
    @property
    def state(self) -> QuantumState:
        return self._state
    @property
    def physical_qubits(self) -> List[int]:
        return self._physical_qubits[:]
    def encode(self, data_state: QuantumState):
        if data_state.n_qubits != self._code.n_logical_qubits:
            raise ValueError("Data state qubit count mismatch")
        n = self._code.n_qubits
        self._state = zero_state(n)
        self._state = data_state.tensor(zero_state(n - data_state.n_qubits))
        for stab in self._code.stabilizers:
            pass
    def apply_logical_x(self):
        for pauli, qubit in self._code.logical_x:
            if pauli == "X":
                from quantum_computer.gates import X_GATE
                pass
            elif pauli == "Z":
                from quantum_computer.gates import Z_GATE
                pass
    def apply_logical_z(self):
        for pauli, qubit in self._code.logical_z:
            if pauli == "Z":
                from quantum_computer.gates import Z_GATE
                pass
    def syndrome(self) -> List[int]:
        extractor = SyndromeExtractor(self._code)
        return extractor.extract(self._state)
    def __repr__(self):
        return f"LogicalQubit(code={self._code}, physical_qubits={self._physical_qubits})"

class LogicalGate:
    __slots__ = ('_name', '_circuit', '_code')
    def __init__(self, name: str, code: StabilizerCode, circuit: QuantumCircuit):
        self._name = name
        self._code = code
        self._circuit = circuit
    @property
    def name(self) -> str:
        return self._name
    @property
    def circuit(self) -> QuantumCircuit:
        return self._circuit
    @property
    def code(self) -> StabilizerCode:
        return self._code
    def __repr__(self):
        return f"LogicalGate('{self._name}', code={self._code})"

class FaultInjectionTester:
    __slots__ = ('_code', '_n_faults')
    def __init__(self, code: StabilizerCode, n_faults: int = 1):
        self._code = code
        self._n_faults = n_faults
    def inject_single_fault(self, state: QuantumState, qubit: int) -> QuantumState:
        from quantum_computer.gates import X_GATE
        n = state.n_qubits
        dim = 1 << n
        new_amps = state.amplitudes[:]
        for i in range(dim):
            if ((i >> (n - 1 - qubit)) & 1) == 0:
                partner = i | (1 << (n - 1 - qubit))
                if partner < dim:
                    new_amps[i], new_amps[partner] = new_amps[partner], new_amps[i]
        return QuantumState(n, new_amps)
    def test_single_fault_tolerance(self, state: QuantumState) -> bool:
        for q in range(self._code.n_qubits):
            faulty = self.inject_single_fault(state, q)
            extractor = SyndromeExtractor(self._code)
            syndrome = extractor.extract(faulty)
            if sum(syndrome) > self._code.n_stabilizers // 2:
                return False
        return True
    def test_all_single_faults(self, state: QuantumState) -> Dict[int, List[int]]:
        results = {}
        extractor = SyndromeExtractor(self._code)
        for q in range(self._code.n_qubits):
            faulty = self.inject_single_fault(state, q)
            syndrome = extractor.extract(faulty)
            results[q] = syndrome
        return results
    def __repr__(self):
        return f"FaultInjectionTester(code={self._code}, n_faults={self._n_faults})"
