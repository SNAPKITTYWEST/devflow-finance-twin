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

"""Quantum gates: base class, single-qubit, multi-qubit, controlled, parameterized."""
import math
import cmath
from typing import List, Optional, Tuple, Callable
from quantum_computer.core.complex import Complex, ZERO, ONE, I, NEG_ONE, INV_SQRT2, NEG_I
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product

class Gate:
    __slots__ = ('_name', '_n_qubits', '_matrix', '_is_unitary', '_params')
    def __init__(self, name: str, n_qubits: int, matrix: Matrix, params: Optional[dict] = None):
        self._name = name
        self._n_qubits = n_qubits
        self._matrix = matrix
        self._is_unitary = matrix.is_unitary()
        self._params = params or {}
    @property
    def name(self) -> str:
        return self._name
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    @property
    def matrix(self) -> Matrix:
        return self._matrix
    @property
    def is_unitary(self) -> bool:
        return self._is_unitary
    @property
    def params(self) -> dict:
        return dict(self._params)
    def __repr__(self):
        return f"Gate('{self._name}', {self._n_qubits}q)"

class SingleQubitGate(Gate):
    def __init__(self, name: str, matrix: Matrix, params: Optional[dict] = None):
        super().__init__(name, 1, matrix, params)

class TwoQubitGate(Gate):
    def __init__(self, name: str, matrix: Matrix, params: Optional[dict] = None):
        super().__init__(name, 2, matrix, params)

class ThreeQubitGate(Gate):
    def __init__(self, name: str, matrix: Matrix, params: Optional[dict] = None):
        super().__init__(name, 3, matrix, params)

class ParameterizedGate(Gate):
    __slots__ = ('_param_names', '_generator')
    def __init__(self, name: str, n_qubits: int, param_names: List[str],
                 generator: Callable[[dict], Matrix]):
        self._param_names = param_names
        self._generator = generator
        default_params = {p: 0.0 for p in param_names}
        super().__init__(name, n_qubits, generator(default_params), default_params)
    def bind(self, **kwargs) -> Gate:
        params = dict(self._params)
        for k, v in kwargs.items():
            if k not in self._param_names:
                raise ValueError(f"Unknown parameter '{k}'")
            params[k] = v
        matrix = self._generator(params)
        return Gate(self._name, self._n_qubits, matrix, params)
    @property
    def param_names(self) -> List[str]:
        return self._param_names[:]
    def with_params(self, *args) -> Gate:
        if len(args) != len(self._param_names):
            raise ValueError(f"Expected {len(self._param_names)} params, got {len(args)}")
        params = dict(self._params)
        for name, val in zip(self._param_names, args):
            params[name] = val
        matrix = self._generator(params)
        return Gate(self._name, self._n_qubits, matrix, params)

# === SINGLE-QUBIT GATES ===

I_GATE = SingleQubitGate("I", Matrix([[ONE, ZERO], [ZERO, ONE]]))
X_GATE = SingleQubitGate("X", Matrix([[ZERO, ONE], [ONE, ZERO]]))
Y_GATE = SingleQubitGate("Y", Matrix([[ZERO, NEG_I], [I, ZERO]]))
Z_GATE = SingleQubitGate("Z", Matrix([[ONE, ZERO], [ZERO, NEG_ONE]]))
H_GATE = SingleQubitGate("H", Matrix([[INV_SQRT2, INV_SQRT2], [INV_SQRT2, -INV_SQRT2]]))

S_GATE = SingleQubitGate("S", Matrix([[ONE, ZERO], [ZERO, I]]))
T_GATE = SingleQubitGate("T", Matrix([
    [ONE, ZERO],
    [ZERO, Complex(math.cos(math.pi/4), math.sin(math.pi/4))]
]))
SDG_GATE = SingleQubitGate("Sdg", Matrix([[ONE, ZERO], [ZERO, NEG_I]]))
TDG_GATE = SingleQubitGate("Tdg", Matrix([
    [ONE, ZERO],
    [ZERO, Complex(math.cos(math.pi/4), -math.sin(math.pi/4))]
]))

def rx_generator(params: dict) -> Matrix:
    theta = params.get("theta", 0.0)
    c = math.cos(theta / 2)
    s = math.sin(theta / 2)
    return Matrix([
        [Complex(c), Complex(0, -s)],
        [Complex(0, -s), Complex(c)]
    ])

def ry_generator(params: dict) -> Matrix:
    theta = params.get("theta", 0.0)
    c = math.cos(theta / 2)
    s = math.sin(theta / 2)
    return Matrix([
        [Complex(c), Complex(-s)],
        [Complex(s), Complex(c)]
    ])

def rz_generator(params: dict) -> Matrix:
    theta = params.get("theta", 0.0)
    return Matrix([
        [Complex(math.cos(theta/2), -math.sin(theta/2)), ZERO],
        [ZERO, Complex(math.cos(theta/2), math.sin(theta/2))]
    ])

def phase_generator(params: dict) -> Matrix:
    phi = params.get("phi", 0.0)
    return Matrix([
        [ONE, ZERO],
        [ZERO, Complex(math.cos(phi), math.sin(phi))]
    ])

RX_GATE = ParameterizedGate("Rx", 1, ["theta"], rx_generator)
RY_GATE = ParameterizedGate("Ry", 1, ["theta"], ry_generator)
RZ_GATE = ParameterizedGate("Rz", 1, ["theta"], rz_generator)
PHASE_GATE = ParameterizedGate("Phase", 1, ["phi"], phase_generator)

U3_GATE = ParameterizedGate("U3", 1, ["theta", "phi", "lambda"],
    lambda p: Matrix([
        [Complex(math.cos(p["theta"]/2)),
         -Complex(math.sin(p["theta"]/2)) * Complex(math.cos(p["lambda"]), math.sin(p["lambda"]))],
        [Complex(math.sin(p["theta"]/2)) * Complex(math.cos(p["phi"]), math.sin(p["phi"])),
         Complex(math.cos(p["theta"]/2)) * Complex(math.cos(p["phi"]+p["lambda"]), math.sin(p["phi"]+p["lambda"]))]
    ])
)

# === TWO-QUBIT GATES ===

SWAP_MATRIX = Matrix([
    [ONE, ZERO, ZERO, ZERO],
    [ZERO, ZERO, ONE, ZERO],
    [ZERO, ONE, ZERO, ZERO],
    [ZERO, ZERO, ZERO, ONE]
])
SWAP_GATE = TwoQubitGate("SWAP", SWAP_MATRIX)

CNOT_MATRIX = Matrix([
    [ONE, ZERO, ZERO, ZERO],
    [ZERO, ONE, ZERO, ZERO],
    [ZERO, ZERO, ZERO, ONE],
    [ZERO, ZERO, ONE, ZERO]
])
CNOT_GATE = TwoQubitGate("CNOT", CNOT_MATRIX)

CZ_MATRIX = Matrix([
    [ONE, ZERO, ZERO, ZERO],
    [ZERO, ONE, ZERO, ZERO],
    [ZERO, ZERO, ONE, ZERO],
    [ZERO, ZERO, ZERO, NEG_ONE]
])
CZ_GATE = TwoQubitGate("CZ", CZ_MATRIX)

CS_MATRIX = Matrix([
    [ONE, ZERO, ZERO, ZERO],
    [ZERO, ONE, ZERO, ZERO],
    [ZERO, ZERO, ONE, ZERO],
    [ZERO, ZERO, ZERO, I]
])
CS_GATE = TwoQubitGate("CS", CS_MATRIX)

ISWAP_MATRIX = Matrix([
    [ONE, ZERO, ZERO, ZERO],
    [ZERO, ZERO, I, ZERO],
    [ZERO, I, ZERO, ZERO],
    [ZERO, ZERO, ZERO, ONE]
])
ISWAP_GATE = TwoQubitGate("iSWAP", ISWAP_MATRIX)

def crz_generator(params: dict) -> Matrix:
    theta = params.get("theta", 0.0)
    c = math.cos(theta / 2)
    s = math.sin(theta / 2)
    return Matrix([
        [ONE, ZERO, ZERO, ZERO],
        [ZERO, ONE, ZERO, ZERO],
        [ZERO, ZERO, Complex(c), Complex(0, -s)],
        [ZERO, ZERO, Complex(0, -s), Complex(c)]
    ])

CRZ_GATE = ParameterizedGate("CRz", 2, ["theta"], crz_generator)

def crx_generator(params: dict) -> Matrix:
    theta = params.get("theta", 0.0)
    c = math.cos(theta / 2)
    s = math.sin(theta / 2)
    return Matrix([
        [ONE, ZERO, ZERO, ZERO],
        [ZERO, ONE, ZERO, ZERO],
        [ZERO, ZERO, Complex(c), Complex(0, -s)],
        [ZERO, ZERO, Complex(0, -s), Complex(c)]
    ])

CRX_GATE = ParameterizedGate("CRx", 2, ["theta"], crx_generator)

def cry_generator(params: dict) -> Matrix:
    theta = params.get("theta", 0.0)
    c = math.cos(theta / 2)
    s = math.sin(theta / 2)
    return Matrix([
        [ONE, ZERO, ZERO, ZERO],
        [ZERO, ONE, ZERO, ZERO],
        [ZERO, ZERO, Complex(c), Complex(-s)],
        [ZERO, ZERO, Complex(s), Complex(c)]
    ])

CRY_GATE = ParameterizedGate("CRy", 2, ["theta"], cry_generator)

# === THREE-QUBIT GATES ===

TOFFOLI_MATRIX_DATA = [[ZERO] * 8 for _ in range(8)]
for i in range(8):
    TOFFOLI_MATRIX_DATA[i][i] = ONE
TOFFOLI_MATRIX_DATA[6][6] = ZERO
TOFFOLI_MATRIX_DATA[6][7] = ONE
TOFFOLI_MATRIX_DATA[7][6] = ONE
TOFFOLI_MATRIX_DATA[7][7] = ZERO
TOFFOLI_MATRIX = Matrix(TOFFOLI_MATRIX_DATA)
TOFFOLI_GATE = ThreeQubitGate("Toffoli", TOFFOLI_MATRIX)

FREDKIN_MATRIX_DATA = [[ZERO] * 8 for _ in range(8)]
for i in range(8):
    FREDKIN_MATRIX_DATA[i][i] = ONE
FREDKIN_MATRIX_DATA[5][5] = ZERO
FREDKIN_MATRIX_DATA[5][6] = ONE
FREDKIN_MATRIX_DATA[6][5] = ONE
FREDKIN_MATRIX_DATA[6][6] = ZERO
FREDKIN_MATRIX = Matrix(FREDKIN_MATRIX_DATA)
FREDKIN_GATE = ThreeQubitGate("Fredkin", FREDKIN_MATRIX)

def controlled_gate(base_gate: Gate, control: int, target: int, n_qubits: int) -> Matrix:
    gate_dim = 1 << n_qubits
    gate_mat = base_gate.matrix
    result = [[ZERO] * gate_dim for _ in range(gate_dim)]
    for state in range(gate_dim):
        ctrl_bit = (state >> (n_qubits - 1 - control)) & 1
        if ctrl_bit == 0:
            result[state][state] = ONE
        else:
            tgt_val = (state >> (n_qubits - 1 - target)) & 1
            other_bits = 0
            for b in range(n_qubits):
                if b != target:
                    bval = (state >> (n_qubits - 1 - b)) & 1
                    pos = b if b < target else b - 1
                    other_bits |= bval << pos
            for new_tgt in range(gate_mat.rows):
                coeff = gate_mat.get(tgt_val, new_tgt)
                if coeff.abs_sq() < 1e-24:
                    continue
                new_state = other_bits
                if new_tgt == 1:
                    new_state |= (1 << (n_qubits - 1 - target))
                elif new_tgt == 0:
                    new_state = new_state & ~(1 << (n_qubits - 1 - target))
                for b in range(n_qubits):
                    if b != target and b != control:
                        pos = b if b < target else b - 1
                        bval = (other_bits >> pos) & 1
                result[new_state][state] = result[new_state][state] + coeff
    return Matrix(result)

def multi_controlled_gate(base_gate: Gate, controls: List[int], target: int, n_qubits: int) -> Matrix:
    gate_dim = 1 << n_qubits
    gate_mat = base_gate.matrix
    result = [[ZERO] * gate_dim for _ in range(gate_dim)]
    for state in range(gate_dim):
        all_controls_set = True
        for ctrl in controls:
            if ((state >> (n_qubits - 1 - ctrl)) & 1) == 0:
                all_controls_set = False
                break
        if not all_controls_set:
            result[state][state] = ONE
        else:
            tgt_val = (state >> (n_qubits - 1 - target)) & 1
            occupied = set(controls) | {target}
            other_bits = 0
            free_pos = 0
            for b in range(n_qubits):
                if b not in occupied:
                    bval = (state >> (n_qubits - 1 - b)) & 1
                    other_bits |= bval << free_pos
                    free_pos += 1
            for new_tgt in range(gate_mat.rows):
                coeff = gate_mat.get(tgt_val, new_tgt)
                if coeff.abs_sq() < 1e-24:
                    continue
                new_state = other_bits
                if new_tgt == 1:
                    new_state |= (1 << (n_qubits - 1 - target))
                elif new_tgt == 0:
                    new_state = new_state & ~(1 << (n_qubits - 1 - target))
                free_pos = 0
                for b in range(n_qubits):
                    if b not in occupied:
                        bval = (other_bits >> free_pos) & 1
                        new_state |= bval << (n_qubits - 1 - b)
                        free_pos += 1
                result[new_state][state] = result[new_state][state] + coeff
    return Matrix(result)

def power_gate(gate: Gate, n: int) -> Gate:
    if n == 0:
        return Gate("I", gate.n_qubits, identity_matrix(1 << gate.n_qubits))
    if n == 1:
        return gate
    if n < 0:
        return power_gate(gate, -n)
    result = identity_matrix(1 << gate.n_qubits)
    base = gate.matrix
    exp = n
    while exp > 0:
        if exp & 1:
            result = result * base
        base = base * base
        exp >>= 1
    return Gate(f"{gate.name}^{n}", gate.n_qubits, result, gate.params)

def inverse_gate(gate: Gate) -> Gate:
    inv_matrix = gate.matrix.inverse()
    return Gate(f"{gate.name}dg", gate.n_qubits, inv_matrix, gate.params)

GATE_SET = {
    "I": I_GATE, "X": X_GATE, "Y": Y_GATE, "Z": Z_GATE, "H": H_GATE,
    "S": S_GATE, "T": T_GATE, "Sdg": SDG_GATE, "Tdg": TDG_GATE,
    "SWAP": SWAP_GATE, "CNOT": CNOT_GATE, "CZ": CZ_GATE,
    "CS": CS_GATE, "iSWAP": ISWAP_GATE,
    "Toffoli": TOFFOLI_GATE, "Fredkin": FREDKIN_GATE,
}

PARAMETERIZED_GATES = {
    "Rx": RX_GATE, "Ry": RY_GATE, "Rz": RZ_GATE, "Phase": PHASE_GATE,
    "U3": U3_GATE, "CRz": CRZ_GATE, "CRx": CRX_GATE, "CRy": CRY_GATE,
}

def get_gate(name: str) -> Gate:
    if name in GATE_SET:
        return GATE_SET[name]
    if name in PARAMETERIZED_GATES:
        return PARAMETERIZED_GATES[name]
    raise KeyError(f"Gate '{name}' not found")

def list_gates() -> List[str]:
    return list(GATE_SET.keys()) + list(PARAMETERIZED_GATES.keys())
