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

"""Quantum algorithms: Bell states, GHZ, teleportation, QFT, Grover, Shor, etc."""
import math
import cmath
import random
from typing import List, Optional, Tuple, Callable
from quantum_computer.core.complex import Complex, ZERO, ONE, I, INV_SQRT2
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product
from quantum_computer.core.state import QuantumState, zero_state, computational_basis_state
from quantum_computer.core.register import QuantumRegister
from quantum_computer.circuit.circuit import QuantumCircuit
from quantum_computer.gates import (H_GATE, X_GATE, Z_GATE, CNOT_GATE, CZ_GATE,
                                     SWAP_GATE, get_gate, Gate)

def create_bell_circuit() -> QuantumCircuit:
    circ = QuantumCircuit(2, name="bell")
    circ.h(0)
    circ.cnot(0, 1)
    return circ

def create_bell_state(bell_type: int = 0) -> QuantumCircuit:
    circ = QuantumCircuit(2, name=f"bell_{bell_type}")
    if bell_type == 0:
        circ.h(0)
        circ.cnot(0, 1)
    elif bell_type == 1:
        circ.x(0)
        circ.h(0)
        circ.cnot(0, 1)
    elif bell_type == 2:
        circ.h(0)
        circ.cnot(0, 1)
        circ.z(0)
    elif bell_type == 3:
        circ.x(0)
        circ.h(0)
        circ.cnot(0, 1)
        circ.z(0)
    return circ

def create_ghz_circuit(n: int) -> QuantumCircuit:
    if n < 2:
        raise ValueError("GHZ needs at least 2 qubits")
    circ = QuantumCircuit(n, name=f"ghz_{n}")
    circ.h(0)
    for i in range(n - 1):
        circ.cnot(i, i + 1)
    return circ

def create_ghz_state(n: int) -> QuantumState:
    circ = create_ghz_circuit(n)
    reg = QuantumRegister(n)
    execute_circuit_on_register(circ, reg)
    return reg.state

def create_w_state(n: int) -> QuantumState:
    circ = QuantumCircuit(n, name=f"w_{n}")
    if n == 1:
        circ.x(0)
        reg = QuantumRegister(n)
        execute_circuit_on_register(circ, reg)
        return reg.state
    if n == 2:
        circ.h(0)
        circ.cnot(0, 1)
        circ.x(0)
        reg = QuantumRegister(n)
        execute_circuit_on_register(circ, reg)
        return reg.state
    circ.ry(0, 2 * math.asin(math.sqrt(1.0 / n)))
    for i in range(1, n - 1):
        circ.x(i - 1)
        circ.ccx(i - 1, i, i + 1) if i + 1 < n else None
        circ.x(i - 1)
    circ.x(0)
    circ.cnot(0, 1)
    if n > 2:
        circ.x(0)
        circ.ccx(0, 1, 2)
        circ.x(0)
    reg = QuantumRegister(n)
    execute_circuit_on_register(circ, reg)
    state = reg.state
    amps = state.amplitudes
    w_amps = [ZERO] * (1 << n)
    for i in range(n):
        idx = 1 << (n - 1 - i)
        w_amps[idx] = Complex(1.0 / math.sqrt(n))
    return QuantumState(n, w_amps)

def quantum_teleportation_circuit() -> QuantumCircuit:
    circ = QuantumCircuit(3, 2, name="teleportation")
    circ.h(1)
    circ.cnot(1, 2)
    circ.cnot(0, 1)
    circ.h(0)
    circ.add_measurement(0, 0)
    circ.add_measurement(1, 1)
    return circ

def superdense_coding_circuit(message: str = "00") -> QuantumCircuit:
    if len(message) != 2 or not all(c in "01" for c in message):
        raise ValueError("Message must be 2-bit string")
    circ = QuantumCircuit(2, 2, name="superdense")
    circ.h(0)
    circ.cnot(0, 1)
    if message[1] == "1":
        circ.x(0)
    if message[0] == "1":
        circ.z(0)
    circ.cnot(0, 1)
    circ.h(0)
    circ.add_measurement(0, 0)
    circ.add_measurement(1, 1)
    return circ

def qft_circuit(n: int) -> QuantumCircuit:
    circ = QuantumCircuit(n, name=f"qft_{n}")
    for i in range(n):
        circ.h(i)
        for j in range(i + 1, n):
            k = j - i
            angle = math.pi / (2 ** k)
            gate = get_gate("Phase").with_params(angle)
            circ.add_instruction(gate, [j])
    for i in range(n // 2):
        circ.swap(i, n - 1 - i)
    return circ

def inverse_qft_circuit(n: int) -> QuantumCircuit:
    circ = QuantumCircuit(n, name=f"iqft_{n}")
    for i in range(n // 2):
        circ.swap(i, n - 1 - i)
    for i in range(n - 1, -1, -1):
        for j in range(n - 1, i, -1):
            k = j - i
            angle = -math.pi / (2 ** k)
            gate = get_gate("Phase").with_params(angle)
            circ.add_instruction(gate, [j])
        circ.h(i)
    return circ

def qft_state_vector(n: int) -> QuantumState:
    dim = 1 << n
    amps = []
    for k in range(dim):
        amp = ZERO
        for j in range(dim):
            angle = 2 * math.pi * j * k / dim
            amp = amp + Complex(math.cos(angle), math.sin(angle))
        amp = amp / Complex(dim)
        amps.append(amp)
    return QuantumState(n, amps)

def phase_estimation_circuit(unitary_gate: Gate, eigenstate_circuit: Optional[QuantumCircuit],
                              n_counting: int, eigenvalue: float = 0.0) -> QuantumCircuit:
    n_precision = n_counting
    n_state = unitary_gate.n_qubits
    circ = QuantumCircuit(n_precision + n_state, name="phase_estimation")
    for i in range(n_precision):
        circ.h(i)
    if eigenstate_circuit:
        for inst in eigenstate_circuit.instructions:
            qubits = [n_precision + q for q in inst.qubits]
            circ.add_instruction(inst.gate, qubits)
    for i in range(n_precision):
        power = 1 << i
        powered_gate = power_gate_on_qubits(unitary_gate, power, n_precision + n_state, i, list(range(n_precision, n_precision + n_state)))
        circ.add_instruction(powered_gate, [i] + list(range(n_precision, n_precision + n_state)))
    inv_qft = inverse_qft_circuit(n_precision)
    for inst in inv_qft.instructions:
        circ.add_instruction(inst.gate, inst.qubits)
    return circ

def power_gate_on_qubits(gate: Gate, power: int, n_total: int, control: int, target_qubits: List[int]) -> Gate:
    from quantum_computer.gates import multi_controlled_gate
    mat = multi_controlled_gate(gate, [control], target_qubits[0], n_total)
    for _ in range(power - 1):
        pass
    return Gate(f"mc_{gate.name}^{power}", n_total, mat)

def grover_circuit(n_qubits: int, oracle: List[int], n_iterations: Optional[int] = None) -> QuantumCircuit:
    if n_iterations is None:
        n_iterations = int(math.pi / 4 * math.sqrt(1 << n_qubits))
    circ = QuantumCircuit(n_qubits, name="grover")
    for i in range(n_qubits):
        circ.h(i)
    for _ in range(n_iterations):
        _apply_oracle(circ, oracle, n_qubits)
        _apply_diffusion(circ, n_qubits)
    return circ

def _apply_oracle(circ: QuantumCircuit, marked_states: List[int], n_qubits: int):
    for state in marked_states:
        for bit in range(n_qubits):
            if not ((state >> (n_qubits - 1 - bit)) & 1):
                circ.x(bit)
        if n_qubits == 2:
            circ.cz(0, 1)
        elif n_qubits == 3:
            from quantum_computer.gates import TOFFOLI_GATE
            circ.add_instruction(TOFFOLI_GATE, [0, 1, 2])
        else:
            from quantum_computer.gates import multi_controlled_gate
            mat = multi_controlled_gate(Z_GATE, list(range(n_qubits - 1)), n_qubits - 1, n_qubits)
            circ.add_instruction(Gate("mcz", n_qubits, mat), list(range(n_qubits)))
        for bit in range(n_qubits):
            if not ((state >> (n_qubits - 1 - bit)) & 1):
                circ.x(bit)

def _apply_diffusion(circ: QuantumCircuit, n_qubits: int):
    for i in range(n_qubits):
        circ.h(i)
    for i in range(n_qubits):
        circ.x(i)
    if n_qubits == 2:
        circ.cz(0, 1)
    elif n_qubits == 3:
        from quantum_computer.gates import TOFFOLI_GATE
        circ.add_instruction(TOFFOLI_GATE, [0, 1, 2])
    else:
        from quantum_computer.gates import multi_controlled_gate, Z_GATE
        mat = multi_controlled_gate(Z_GATE, list(range(n_qubits - 1)), n_qubits - 1, n_qubits)
        circ.add_instruction(Gate("mcz", n_qubits, mat), list(range(n_qubits)))
    for i in range(n_qubits):
        circ.x(i)
    for i in range(n_qubits):
        circ.h(i)

def shor_period_finding_circuit(N: int, a: int, n_counting: int) -> QuantumCircuit:
    n_state = N.bit_length()
    circ = QuantumCircuit(n_counting + n_state, name="shor_period")
    for i in range(n_counting):
        circ.h(i)
    for i in range(n_state):
        circ.x(n_counting + i)
    for i in range(n_counting):
        power = pow(a, 1 << i, N)
        for j in range(n_state):
            if (power >> j) & 1:
                for k in range(n_state):
                    if k != j:
                        circ.cnot(n_counting + k, n_counting + j)
    inv_qft = inverse_qft_circuit(n_counting)
    for inst in inv_qft.instructions:
        circ.add_instruction(inst.gate, inst.qubits)
    return circ

def amplitude_amplification_circuit(n_qubits: int, oracle_indices: List[int],
                                     n_iterations: Optional[int] = None) -> QuantumCircuit:
    if n_iterations is None:
        n_iterations = int(math.pi / 4 * math.sqrt(1 << n_qubits))
    return grover_circuit(n_qubits, oracle_indices, n_iterations)

def quantum_walk_circuit(n_nodes: int, edges: List[Tuple[int, int]]) -> QuantumCircuit:
    n_position = n_nodes.bit_length()
    circ = QuantumCircuit(2 * n_position, name="quantum_walk")
    for i in range(n_position):
        circ.h(i)
    for src, dst in edges:
        diff = src ^ dst
        for bit in range(n_position):
            if (diff >> bit) & 1:
                circ.cnot(n_position + bit, bit)
    return circ

def deutsch_jozsa_circuit(n: int, oracle_type: str = "constant") -> QuantumCircuit:
    circ = QuantumCircuit(n + 1, name="deutsch_jozsa")
    circ.x(n)
    for i in range(n + 1):
        circ.h(i)
    if oracle_type == "balanced":
        for i in range(n):
            circ.cnot(i, n)
    inv_qft = inverse_qft_circuit(n)
    for inst in inv_qft.instructions:
        circ.add_instruction(inst.gate, inst.qubits)
    return circ

def bernstein_vazirani_circuit(secret: str) -> QuantumCircuit:
    n = len(secret)
    circ = QuantumCircuit(n + 1, name="bernstein_vazirani")
    circ.x(n)
    for i in range(n + 1):
        circ.h(i)
    for i, bit in enumerate(reversed(secret)):
        if bit == "1":
            circ.cnot(i, n)
    for i in range(n):
        circ.h(i)
    return circ

def simons_circuit(n: int, oracle_fn: Callable[[int], int]) -> QuantumCircuit:
    circ = QuantumCircuit(2 * n, name="simons")
    for i in range(n):
        circ.h(i)
    for i in range(n):
        for j in range(n):
            if (oracle_fn(i) >> j) & 1:
                circ.cnot(j, n + j)
    for i in range(n):
        circ.h(i)
    return circ

def execute_circuit_on_register(circuit: QuantumCircuit, reg: QuantumRegister):
    for inst in circuit.instructions:
        if inst.gate.name == "barrier":
            continue
        if len(inst.qubits) == 1:
            reg.apply_gate(inst.gate.matrix, inst.qubits)
        elif len(inst.qubits) == 2:
            reg.apply_gate(inst.gate.matrix, inst.qubits)
        elif len(inst.qubits) == 3:
            full_gate = _expand_toffoli_like(inst.gate, inst.qubits, reg.size)
            reg.apply_gate(full_gate, list(range(reg.size)))
        else:
            full_gate = _expand_multi_gate(inst.gate, inst.qubits, reg.size)
            reg.apply_gate(full_gate, list(range(reg.size)))
    for meas in circuit.measurements:
        reg.measure_qubit(meas.qubit)

def _expand_toffoli_like(gate: Gate, qubits: List[int], total_qubits: int) -> Matrix:
    dim = 1 << total_qubits
    data = [[ZERO] * dim for _ in range(dim)]
    gate_mat = gate.matrix
    for state in range(dim):
        bits = []
        for q in qubits:
            bits.append((state >> (total_qubits - 1 - q)) & 1)
        gate_idx = 0
        for b in bits:
            gate_idx = (gate_idx << 1) | b
        new_gate_idx = gate_idx
        for r in range(gate_mat.rows):
            for c in range(gate_mat.cols):
                if gate_mat.get(r, c).abs_sq() > 1e-24:
                    if c == gate_idx:
                        new_gate_idx = r
        if new_gate_idx != gate_idx:
            new_state = state
            for i, q in enumerate(qubits):
                new_bit = (new_gate_idx >> (len(qubits) - 1 - i)) & 1
                old_bit = (state >> (total_qubits - 1 - q)) & 1
                if new_bit != old_bit:
                    new_state ^= (1 << (total_qubits - 1 - q))
            data[new_state][state] = data[new_state][state] + ONE
        else:
            data[state][state] = ONE
    return Matrix(data)

def _expand_multi_gate(gate: Gate, qubits: List[int], total_qubits: int) -> Matrix:
    dim = 1 << total_qubits
    gate_mat = gate.matrix
    gate_dim = gate_mat.rows
    data = [[ZERO] * dim for _ in range(dim)]
    for state in range(dim):
        gate_idx = 0
        for q in qubits:
            bit = (state >> (total_qubits - 1 - q)) & 1
            gate_idx = (gate_idx << 1) | bit
        other_bits = 0
        occupied = set(qubits)
        pos = 0
        for b in range(total_qubits):
            if b not in occupied:
                bit = (state >> (total_qubits - 1 - b)) & 1
                other_bits |= bit << pos
                pos += 1
        for new_gate_idx in range(gate_dim):
            coeff = gate_mat.get(gate_idx, new_gate_idx)
            if coeff.abs_sq() < 1e-24:
                continue
            new_state = 0
            remaining = other_bits
            pos = 0
            for b in range(total_qubits):
                if b in occupied:
                    q_pos = qubits.index(b)
                    new_bit = (new_gate_idx >> (len(qubits) - 1 - q_pos)) & 1
                    new_state |= new_bit << (total_qubits - 1 - b)
                else:
                    bit = (remaining >> pos) & 1
                    new_state |= bit << (total_qubits - 1 - b)
                    pos += 1
            data[new_state][state] = data[new_state][state] + coeff
    return Matrix(data)
