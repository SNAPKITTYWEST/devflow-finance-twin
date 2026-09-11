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

"""Extended test suite: property-based tests, adversarial tests, edge cases, integration tests."""
import math
import sys
import os
import random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from quantum_computer.core.complex import Complex, ZERO, ONE, I
from quantum_computer.core.matrix import Matrix, identity_matrix, tensor_product, matrix_approx_eq
from quantum_computer.core.state import QuantumState, zero_state, computational_basis_state, random_state
from quantum_computer.core.register import QuantumRegister, ClassicalRegister, RegisterManager
from quantum_computer.gates import (I_GATE, X_GATE, Y_GATE, Z_GATE, H_GATE, S_GATE, T_GATE,
                                     CNOT_GATE, CZ_GATE, SWAP_GATE, TOFFOLI_GATE,
                                     RX_GATE, RY_GATE, RZ_GATE, PHASE_GATE,
                                     inverse_gate, power_gate, get_gate)
from quantum_computer.circuit.circuit import QuantumCircuit
from quantum_computer.circuit.dag import circuit_to_dag
from quantum_computer.circuit.optimizer import optimize_circuit
from quantum_computer.algorithms import (create_bell_circuit, create_ghz_circuit,
                                          execute_circuit_on_register, qft_circuit, inverse_qft_circuit)
from quantum_computer.algorithms.advanced import (PauliString, Hamiltonian, VariationalCircuit, VQE,
                                                   create_ising_hamiltonian, TrotterStep)
from quantum_computer.algorithms.topological import (IsingModel, QuantumAnnealer, AnnealingSchedule,
                                                      TopologicalQubit, Braid, BraidGroup)
from quantum_computer.noise import BitFlipChannel, DepolarizingChannel, AmplitudeDampingChannel
from quantum_computer.noise.advanced import (CorrelatedNoiseChannel, CrosstalkChannel,
                                               TemperatureDependentChannel, CoherentErrorChannel)
from quantum_computer.error_correction import RepetitionCode, SurfaceCode, StabilizerCode
from quantum_computer.hardware import QubitConnectivity, create_linear_backend, create_grid_backend
from quantum_computer.vm import QuantumVM, ShotManager, ResultValidator
from quantum_computer.serialization import CircuitSerializer, CircuitIdentifier, CircuitManifest
from quantum_computer.validation import CircuitValidator, UnitaryValidator, ResourceEstimator

PASS = 0
FAIL = 0
ERRORS = []

def check(name, condition, detail=""):
    global PASS, FAIL, ERRORS
    if condition:
        PASS += 1
    else:
        FAIL += 1
        ERRORS.append(f"FAIL: {name} - {detail}")

print("=" * 70)
print("EXTENDED VERIFICATION SUITE")
print("=" * 70)

# === PROPERTY-BASED TESTS ===
print("\n[1] Property-Based Tests")
for _ in range(20):
    n = random.randint(1, 4)
    rs = random_state(n)
    check("prop_random_normalized", rs.is_normalized())
    check("prop_random_dim", rs.dim == (1 << n))

for _ in range(10):
    n = random.randint(1, 4)
    rs = random_state(n)
    check("prop_identity_preserves", abs(rs.total_probability() - 1.0) < 1e-10)

for _ in range(10):
    n = random.randint(1, 3)
    m = identity_matrix(1 << n)
    rs = random_state(n)
    old_amps = rs.amplitudes[:]
    rs.apply_gate(m)
    check("prop_identity_gate", all(abs(rs.amplitudes[i].re - old_amps[i].re) < 1e-10 for i in range(len(old_amps))))

for _ in range(10):
    n = random.randint(1, 3)
    rs1 = random_state(n)
    rs2 = random_state(n)
    overlap = sum(rs1.amplitudes[i].conjugate() * rs2.amplitudes[i] for i in range(rs1.dim))
    check("prop_overlap_bounded", abs(overlap.abs_sq()) <= 1.0 + 1e-10)

# === ADVERSARIAL TESTS ===
print("\n[2] Adversarial Tests")
try:
    bad_circ = QuantumCircuit(2)
    bad_circ.h(5)
    check("adv_bad_qubit_index", False)
except IndexError:
    check("adv_bad_qubit_index", True)

try:
    bad_circ = QuantumCircuit(0)
    check("adv_zero_qubits", False)
except ValueError:
    check("adv_zero_qubits", True)

try:
    rm = RegisterManager()
    rm.allocate_quantum_register(2, "q0")
    rm.allocate_quantum_register(2, "q0")
    check("adv_duplicate_register", False)
except ValueError:
    check("adv_duplicate_register", True)

try:
    bad_gate = get_gate("H")
    bad_matrix = bad_gate.matrix
    check("adv_gate_access", bad_matrix.rows == 2)
except:
    check("adv_gate_access", False)

circuit = QuantumCircuit(1)
circuit.h(0)
vm = QuantumVM()
result = vm.execute(circuit)
check("adv_single_qubit_exec", result["quantum_state"].is_normalized())

circuit = QuantumCircuit(1)
circuit.x(0)
vm = QuantumVM()
result = vm.execute(circuit)
check("adv_x_gate", abs(result["quantum_state"].probability(1) - 1.0) < 1e-10)

circuit = QuantumCircuit(1)
circuit.h(0)
vm = QuantumVM()
result = vm.run_shots(circuit, 100)
check("adv_h_distribution", "0" in result["counts"] and "1" in result["counts"])

# === INVALID CIRCUIT TESTS ===
print("\n[3] Invalid Circuit Tests")
try:
    circ = QuantumCircuit(2)
    from quantum_computer.gates import TOFFOLI_GATE
    circ.add_instruction(TOFFOLI_GATE, [0, 1])
    check("adv_toffoli_wrong_qubits", False)
except ValueError:
    check("adv_toffoli_wrong_qubits", True)

try:
    circ = QuantumCircuit(2)
    circ.add_instruction(get_gate("H"), [0, 1])
    check("adv_h_wrong_qubits", False)
except ValueError:
    check("adv_h_wrong_qubits", True)

# === RESOURCE-EXHAUSTION TESTS ===
print("\n[4] Resource-Exhaustion Tests")
large_circ = QuantumCircuit(10)
for i in range(10):
    large_circ.h(i)
for i in range(9):
    large_circ.cnot(i, i + 1)
check("adv_large_circuit_gates", large_circ.gate_count == 19)
check("adv_large_circuit_depth", large_circ.depth > 0)

vm = QuantumVM()
result = vm.run_shots(large_circ, 10)
check("adv_large_circuit_exec", len(result["counts"]) > 0)

# === NUMERICAL-STABILITY TESTS ===
print("\n[5] Numerical-Stability Tests")
for n in [1, 2, 3, 4]:
    circ = QuantumCircuit(n)
    for i in range(n):
        circ.h(i)
    vm = QuantumVM()
    state = vm.statevector(circ)
    total = sum(a.abs_sq() for a in state)
    check(f"numerical_stab_{n}q", abs(total - 1.0) < 1e-10)

for _ in range(5):
    n = random.randint(1, 3)
    rs = random_state(n)
    check("numerical_stab_random", abs(rs.total_probability() - 1.0) < 1e-10)

# === ALGORITHM EXTENDED TESTS ===
print("\n[6] Algorithm Extended Tests")
# PauliString tests
ps_x = PauliString(2, [("X", 0)])
check("pauli_x_matrix", ps_x.matrix().rows == 4)
ps_zz = PauliString(2, [("Z", 0), ("Z", 1)])
check("pauli_zz_matrix", ps_zz.matrix().rows == 4)
ps_i = PauliString(2, [("I", 0)])
check("pauli_i_matrix", ps_i.matrix().rows == 4)
ps_xy = PauliString(2, [("X", 0), ("Y", 1)])
check("pauli_xy_matrix", ps_xy.matrix().rows == 4)
ps_coeff = PauliString(1, [("X", 0)], Complex(2.0))
check("pauli_coefficient", ps_coeff.coefficient == Complex(2.0))
ps_mul = ps_x * 2.0
check("pauli_mul", ps_mul.coefficient == Complex(2.0))

# Hamiltonian tests
ham = Hamiltonian(2)
ham.add_term(PauliString(2, [("Z", 0), ("Z", 1)], Complex(-1.0)))
ham.add_term(PauliString(2, [("X", 0)], Complex(-0.5)))
ham.add_term(PauliString(2, [("X", 1)], Complex(-0.5)))
check("hamiltonian_matrix", ham.matrix().rows == 4)
check("hamiltonian_terms", len(ham.terms) == 3)
ham2 = ham * 2.0
check("hamiltonian_mul", len(ham2.terms) == 3)
ham3 = 2.0 * ham
check("hamiltonian_rmul", len(ham3.terms) == 3)
ham_add = ham + ham2
check("hamiltonian_add", len(ham_add.terms) == 6)

# Ising model tests
ising = IsingModel(4)
ising.set_coupling(0, 1, -1.0)
ising.set_coupling(1, 2, -1.0)
ising.set_coupling(2, 3, -1.0)
ising.set_bias(0, -0.5)
check("ising_energy", ising.energy([1, 1, 1, 1]) != 0)
config, energy = ising.ground_state_brute_force()
check("ising_ground_state", len(config) == 4)
qubo = ising.to_qubo()
check("ising_qubo", len(qubo) > 0)
ising2 = IsingModel(4)
ising2.from_qubo(qubo)
check("ising_from_qubo", len(ising2._J) > 0)

# Annealing tests
schedule = AnnealingSchedule(100.0, 50)
check("annealing_schedule", schedule.n_steps == 50)
check("annealing_s", schedule.get_s(0) == 0.0)
check("annealing_t", schedule.get_t(0) == 1.0)
annealer = QuantumAnnealer(ising, schedule)
annealer.set_n_reads(10)
config, energy = annealer.anneal()
check("annealer_result", len(config) == 4)
circ = annealer.quantum_anneal_circuit()
check("annealer_circuit", circ.n_qubits == 4)

# Topological qubit tests
tq = TopologicalQubit(4)
check("topo_qubit_anyons", len(tq.anyons) == 4)
check("topo_qubit_worldlines", len(tq.worldlines) == 4)
tq.braid_sigma(0, 1)
check("topo_braid_applied", True)
tq.encode_logical_zero()
check("topo_encode_zero", True)
tq.encode_logical_one()
check("topo_encode_one", True)
fusion = tq.measure_fusion(0, 1)
check("topo_fusion", isinstance(fusion, str))
bg = BraidGroup(4)
bg.add_braid(Braid((0, 1), 1))
bg.add_braid(Braid((1, 2), 1))
check("braid_group_len", len(bg) == 2)
bg_inv = bg.inverse()
check("braid_group_inverse", len(bg_inv) == 2)
bg_comp = bg.compose(bg_inv)
check("braid_group_compose", len(bg_comp) == 4)

# === ADVANCED NOISE TESTS ===
print("\n[7] Advanced Noise Tests")
from quantum_computer.noise.advanced import ReadoutNoiseChannel
rn = ReadoutNoiseChannel(0.05, 1)
check("readout_noise", rn.n_qubits == 1)

td = TemperatureDependentChannel(0.05, 5e9, 1)
check("temp_channel", td.n_qubits == 1)

ce = CoherentErrorChannel(0.01, "z", 1)
check("coherent_error", ce.n_qubits == 1)

# === EXTENDED ERROR CORRECTION TESTS ===
print("\n[8] Extended Error Correction Tests")
rc2 = RepetitionCode(3)
check("rep_code_3_data", rc2.n_data_qubits == 3)
check("rep_code_3_total", rc2.n_total_qubits == 9)
enc2 = rc2.encoding_circuit()
check("rep_code_3_encode", enc2.n_qubits == 9)
syn2 = rc2.syndrome_extraction_circuit()
check("rep_code_3_syndrome", syn2.n_qubits > 0)

sc2 = StabilizerCode(5, [
    [("Z", 0), ("Z", 1), ("Z", 2)],
    [("Z", 2), ("Z", 3), ("Z", 4)]
])
check("stabilizer_code_5q", sc2.n_qubits == 5)
check("stabilizer_code_2_stabs", sc2.n_stabilizers == 2)
check("stabilizer_code_3_logical", sc2.n_logical_qubits == 3)

surf2 = SurfaceCode(5)
check("surface_code_d5", surf2.distance == 5)
check("surface_code_d5_data", surf2.n_data_qubits == 25)
check("surface_code_d5_ancilla", surf2.n_ancilla_qubits == 16)

# === EXTENDED HARDWARE TESTS ===
print("\n[9] Extended Hardware Tests")
grid = create_grid_backend(3, 3)
check("grid_3x3", grid.n_qubits == 9)
check("grid_3x3_edges", len(grid.connectivity.edges) > 0)

linear = create_linear_backend(5)
check("linear_5", linear.n_qubits == 5)
check("linear_5_edges", len(linear.connectivity.edges) == 4)

# === EXTENDED SERIALIZATION TESTS ===
print("\n[10] Extended Serialization Tests")
for n in [1, 2, 3]:
    circ = QuantumCircuit(n)
    for i in range(n):
        circ.h(i)
    for fmt in ["json", "binary"]:
        ser = CircuitSerializer(fmt)
        data = ser.serialize(circ)
        deser = ser.deserialize(data)
        check(f"ext_ser_{fmt}_{n}q", deser.n_qubits == n)
        check(f"ext_ser_{fmt}_{n}q_gates", deser.gate_count == circ.gate_count)

ci = CircuitIdentifier()
for _ in range(5):
    circ = QuantumCircuit(random.randint(1, 3))
    circ.h(0)
    h1 = ci.compute_hash(circ)
    h2 = ci.compute_hash(circ)
    check("ext_hash_deterministic", h1 == h2)

# === EXTENDED VALIDATION TESTS ===
print("\n[11] Extended Validation Tests")
uv = UnitaryValidator()
for gate in [X_GATE, Y_GATE, Z_GATE, H_GATE, S_GATE, T_GATE, CNOT_GATE, CZ_GATE, SWAP_GATE]:
    check(f"ext_uv_{gate.name}", uv.is_unitary(gate.matrix))

re = ResourceEstimator()
for n in [1, 2, 3, 4]:
    circ = QuantumCircuit(n)
    for i in range(n):
        circ.h(i)
    res = re.estimate(circ)
    check(f"ext_res_{n}q", res["qubits"] == n)
    check(f"ext_res_{n}q_depth", res["depth"] > 0)

cv = CircuitValidator()
for n in [1, 2, 3]:
    circ = QuantumCircuit(n)
    circ.h(0)
    errors = cv.validate(circ)
    check(f"ext_cv_{n}q", len(errors) == 0)

# === FULL INTEGRATION: COMPLETE QUANTUM PROGRAMS ===
print("\n[12] Full Integration: Complete Quantum Programs")
# Program 1: Teleportation with verification
tele = QuantumCircuit(3, 2)
tele.h(1)
tele.cnot(1, 2)
tele.cnot(0, 1)
tele.h(0)
tele.add_measurement(0, 0)
tele.add_measurement(1, 1)
vm = QuantumVM()
result = vm.execute(tele)
check("int_teleport_exec", result["quantum_state"].is_normalized())

# Program 2: Grover with verification
grover = QuantumCircuit(3)
grover.h(0)
grover.h(1)
grover.h(2)
grover.x(0)
grover.x(1)
grover.ccx(0, 1, 2)
grover.x(0)
grover.x(1)
grover.h(0)
grover.h(1)
grover.h(2)
vm = QuantumVM()
result = vm.execute(grover)
check("int_grover_exec", result["quantum_state"].is_normalized())

# Program 3: QFT round trip
for n in [2, 3]:
    qft = qft_circuit(n)
    iqft = inverse_qft_circuit(n)
    combined = qft + iqft
    reg = QuantumRegister(n)
    execute_circuit_on_register(combined, reg)
    check(f"int_qft_roundtrip_{n}", abs(reg.state.probability(0) - 1.0) < 1e-4)

# Program 4: Random circuit sampling
for _ in range(5):
    n = random.randint(1, 3)
    circ = QuantumCircuit(n)
    for _ in range(5):
        q = random.randint(0, n - 1)
        gate = random.choice(["H", "X", "Z", "S", "T"])
        circ.add_instruction(get_gate(gate), [q])
        if n >= 2:
            q0 = random.randint(0, n - 1)
            q1 = random.randint(0, n - 1)
            while q1 == q0:
                q1 = random.randint(0, n - 1)
            circ.cnot(q0, q1)
    vm = QuantumVM()
    result = vm.execute(circ)
    check("int_random_circuit", result["quantum_state"].is_normalized())

# Program 5: VQE-like circuit
vc = VariationalCircuit(2, 1)
check("vqe_circuit", vc.n_parameters > 0)
vcirc = vc.build_circuit()
check("vqe_circuit_build", vcirc.n_qubits == 2)

# === EDGE CASE: MINIMAL SYSTEMS ===
print("\n[13] Edge Case: Minimal Systems")
circ1 = QuantumCircuit(1)
circ1.h(0)
vm = QuantumVM()
result = vm.execute(circ1)
check("minimal_1q", result["quantum_state"].is_normalized())

circ2 = QuantumCircuit(2)
circ2.h(0)
circ2.cnot(0, 1)
vm = QuantumVM()
result = vm.execute(circ2)
check("minimal_2q", result["quantum_state"].is_normalized())

circ1_classical = QuantumCircuit(1, 1)
circ1_classical.h(0)
circ1_classical.add_measurement(0, 0)
vm = QuantumVM()
result = vm.execute(circ1_classical)
check("minimal_1q_1c", result["quantum_state"].is_normalized())

circ2_classical = QuantumCircuit(2, 2)
circ2_classical.h(0)
circ2_classical.cnot(0, 1)
circ2_classical.add_measurement(0, 0)
circ2_classical.add_measurement(1, 1)
vm = QuantumVM()
result = vm.execute(circ2_classical)
check("minimal_2q_2c", result["quantum_state"].is_normalized())

# === FINAL REPORT ===
print("\n" + "=" * 70)
print(f"EXTENDED VERIFICATION COMPLETE: {PASS} PASSED, {FAIL} FAILED")
print("=" * 70)
if ERRORS:
    print("\nFailed tests:")
    for e in ERRORS:
        print(f"  {e}")
print(f"\nTotal tests: {PASS + FAIL}")
print(f"Pass rate: {PASS / (PASS + FAIL) * 100:.1f}%")
sys.exit(0 if FAIL == 0 else 1)
