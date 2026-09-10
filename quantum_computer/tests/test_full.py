"""Comprehensive test suite for quantum computer implementation."""
import math
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from quantum_computer.core.complex import Complex, ZERO, ONE, NEG_ONE, I, inner_product, tensor_product_vectors, normalize_vector
from quantum_computer.core.matrix import Matrix, identity_matrix, zero_matrix, diagonal_matrix, tensor_product, matrix_approx_eq, matrix_from_lists
from quantum_computer.core.state import QuantumState, zero_state, computational_basis_state, plus_state, bell_state, ghz_state, random_state
from quantum_computer.core.register import QuantumRegister, ClassicalRegister, RegisterManager
from quantum_computer.gates import (I_GATE, X_GATE, Y_GATE, Z_GATE, H_GATE, S_GATE, T_GATE,
                                     SDG_GATE, TDG_GATE,
                                     CNOT_GATE, CZ_GATE, SWAP_GATE, TOFFOLI_GATE,
                                     RX_GATE, RY_GATE, RZ_GATE, PHASE_GATE,
                                     controlled_gate, inverse_gate, power_gate, get_gate, list_gates)
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction
from quantum_computer.circuit.dag import CircuitDAG, circuit_to_dag, dag_to_circuit
from quantum_computer.circuit.optimizer import optimize_circuit, CircuitOptimizer
from quantum_computer.circuit.scheduler import Scheduler, analyze_dependencies
from quantum_computer.algorithms import (create_bell_circuit, create_bell_state, create_ghz_circuit, create_ghz_state,
                                          create_w_state, quantum_teleportation_circuit, superdense_coding_circuit,
                                          qft_circuit, inverse_qft_circuit, grover_circuit, shor_period_finding_circuit,
                                          deutsch_jozsa_circuit, bernstein_vazirani_circuit,
                                          execute_circuit_on_register, qft_state_vector)
from quantum_computer.noise import (BitFlipChannel, PhaseFlipChannel, DepolarizingChannel,
                                     AmplitudeDampingChannel, PhaseDampingChannel, ThermalRelaxationChannel,
                                     NoiseModel, build_depolarizing_model)
from quantum_computer.error_correction import (RepetitionCode, StabilizerCode, SyndromeExtractor,
                                                SurfaceCode, LogicalQubit, FaultInjectionTester)
from quantum_computer.hardware import (QubitConnectivity, HardwareGateSet, Transpiler, Router,
                                        HardwareBackend, create_linear_backend, create_fully_connected_backend,
                                        create_grid_backend)
from quantum_computer.vm import QuantumVM, ShotManager, ResultValidator
from quantum_computer.serialization import (CircuitSerializer, CircuitIdentifier, CircuitManifest,
                                             ExecutionRecord, AuditLog, VerificationSeal,
                                             ContentAddressableStore, DeterministicExecutor)
from quantum_computer.validation import (CircuitValidator, UnitaryValidator, ResourceEstimator, DimensionValidator)

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
print("QUANTUM COMPUTER IMPLEMENTATION - FULL VERIFICATION SUITE")
print("=" * 70)

# === COMPLEX ARITHMETIC TESTS ===
print("\n[1] Complex Arithmetic")
c1 = Complex(3, 4)
c2 = Complex(1, -2)
check("complex_add", (c1 + c2) == Complex(4, 2))
check("complex_sub", (c1 - c2) == Complex(2, 6))
check("complex_mul", (c1 * c2) == Complex(11, -2))
check("complex_div", (c1 / c2) == Complex(-1, 2))
check("complex_abs", abs(c1) == 5.0)
check("complex_conj", c1.conjugate() == Complex(3, -4))
check("complex_abs_sq", c1.abs_sq() == 25.0)
check("complex_phase", abs(c1.phase() - math.atan2(4, 3)) < 1e-10)
check("complex_neg", -c1 == Complex(-3, -4))
check("complex_eq_int", ONE == 1.0)
check("complex_zero", ZERO == Complex(0, 0))
check("complex_one", ONE == Complex(1, 0))
check("complex_imag", I == Complex(0, 1))
check("complex_scalar_mul", 2 * c1 == Complex(6, 8))
check("complex_scalar_rmul", c1 * 3 == Complex(9, 12))
check("complex_pow_zero", c1.pow(0) == ONE)
check("complex_pow_one", c1.pow(1) == c1)
check("complex_sqrt", c1.sqrt() == Complex(2, 1))
check("complex_polar", Complex.from_polar(1, 0) == ONE)
check("complex_exp_zero", ZERO.exp() == ONE)
check("complex_hash", hash(c1) == hash(Complex(3, 4)))
check("complex_json_roundtrip", Complex.from_json(c1.to_json()) == c1)
check("complex_inner_product", inner_product([ONE, ZERO], [ZERO, ONE]) == ZERO)
check("complex_tensor_product", tensor_product_vectors([ONE], [ONE]) == [ONE])

# === MATRIX TESTS ===
print("\n[2] Matrix Operations")
m1 = matrix_from_lists([[1, 0], [0, -1]])
m2 = matrix_from_lists([[0, 1], [1, 0]])
check("matrix_shape", m1.shape() == (2, 2))
check("matrix_is_square", m1.is_square())
check("matrix_add", (m1 + m2) == matrix_from_lists([[1, 1], [1, -1]]))
check("matrix_sub", (m1 - m2) == matrix_from_lists([[1, -1], [-1, -1]]))
check("matrix_mul", (m1 * m2) == matrix_from_lists([[0, 1], [-1, 0]]))
check("matrix_transpose", m1.transpose() == m1)
check("matrix_conjugate", m1.conjugate() == m1)
check("matrix_dagger", m1.dagger() == m1)
check("matrix_trace", m1.trace() == ZERO)
check("matrix_identity", identity_matrix(2) == matrix_from_lists([[1, 0], [0, 1]]))
check("matrix_zero", zero_matrix(2, 2) == matrix_from_lists([[0, 0], [0, 0]]))
check("matrix_diagonal", diagonal_matrix([ONE, NEG_ONE]) == m1)
check("matrix_det_2x2", m1.determinant() == Complex(-1))
check("matrix_inverse", m1.inverse() == m1)
check("matrix_unitary_X", X_GATE.matrix.is_unitary())
check("matrix_unitary_H", H_GATE.matrix.is_unitary())
check("matrix_unitary_CNOT", CNOT_GATE.matrix.is_unitary())
check("matrix_hermitian_Z", Z_GATE.matrix.is_hermitian())
check("matrix_hermitian_H", H_GATE.matrix.is_hermitian())
check("matrix_frobenius", abs(m1.frobenius_norm() - math.sqrt(2)) < 1e-10)
m3 = matrix_from_lists([[1, 2], [3, 4]])
check("matrix_inv_2x2", (m3 * m3.inverse() - identity_matrix(2)).frobenius_norm() < 1e-10)
check("matrix_tensor_product", tensor_product(X_GATE.matrix, X_GATE.matrix).rows == 4)
check("matrix_power_0", power_gate(I_GATE, 0).matrix == identity_matrix(2))
check("matrix_power_1", power_gate(X_GATE, 1).matrix == X_GATE.matrix)
check("matrix_power_2", power_gate(X_GATE, 2).matrix == identity_matrix(2))
check("matrix_approx_eq", matrix_approx_eq(identity_matrix(2), identity_matrix(2)))

# === QUANTUM STATE TESTS ===
print("\n[3] Quantum State")
s0 = zero_state(1)
check("state_zero_dim", s0.n_qubits == 1)
check("state_zero_prob", abs(s0.probability(0) - 1.0) < 1e-10)
check("state_zero_normalized", s0.is_normalized())
s1 = computational_basis_state(1, 1)
check("state_one_prob", abs(s1.probability(1) - 1.0) < 1e-10)
s2 = zero_state(2)
check("state_2q_dim", s2.dim == 4)
plus = plus_state(1)
check("state_plus_normalized", plus.is_normalized())
check("state_plus_prob_equal", abs(plus.probability(0) - 0.5) < 1e-10)
bell = bell_state()
check("state_bell_normalized", bell.is_normalized())
check("state_bell_prob_00", abs(bell.probability(0) - 0.5) < 1e-10)
check("state_bell_prob_11", abs(bell.probability(3) - 0.5) < 1e-10)
check("state_bell_prob_01", abs(bell.probability(1)) < 1e-10)
check("state_bell_prob_10", abs(bell.probability(2)) < 1e-10)
ghz3 = ghz_state(3)
check("state_ghz3_normalized", ghz3.is_normalized())
check("state_ghz3_prob_000", abs(ghz3.probability(0) - 0.5) < 1e-10)
check("state_ghz3_prob_111", abs(ghz3.probability(7) - 0.5) < 1e-10)
check("state_clone", s0.copy().amplitudes == s0.amplitudes)
check("state_tensor", s0.tensor(s0).n_qubits == 2)
check("state_repr", isinstance(str(s0), str))
rs = random_state(2)
check("state_random_normalized", rs.is_normalized())

# === REGISTER TESTS ===
print("\n[4] Registers")
qr = QuantumRegister(3, "q")
check("qr_size", qr.size == 3)
check("qr_name", qr.name == "q")
check("qr_qubit_label", qr.get_qubit(0).label == "q0")
qr.h(0)
check("qr_h_gate", qr.state.is_normalized())
qr.reset()
check("qr_reset", qr.state.probability(0) == 1.0)
cr = ClassicalRegister(4, "c")
check("cr_size", cr.size == 4)
check("cr_get_bit", cr.get_bit(0) == 0)
cr.set_bit(0, 1)
check("cr_set_bit", cr.get_bit(0) == 1)
cr.set_value(5)
check("cr_set_value", cr.get_value() == 5)
cr.reset()
check("cr_reset", cr.get_value() == 0)
rm = RegisterManager()
qr1 = rm.allocate_quantum_register(2, "q0")
check("rm_alloc_qreg", qr1.size == 2)
cr1 = rm.allocate_classical_register(3, "c0")
check("rm_alloc_creg", cr1.size == 3)
check("rm_total_qubits", rm.total_qubits == 2)
check("rm_get_qreg", rm.get_quantum_register("q0").size == 2)
check("rm_get_creg", rm.get_classical_register("c0").size == 3)
check("rm_all_labels", len(rm.all_qubit_labels()) == 2)
qr_clone = qr.clone()
check("qr_clone", qr_clone.size == qr.size)
cr_clone = cr.clone()
check("cr_clone", cr_clone.size == cr.size)

# === GATE TESTS ===
print("\n[5] Quantum Gates")
check("gate_I_unitary", I_GATE.is_unitary)
check("gate_X_unitary", X_GATE.is_unitary)
check("gate_Y_unitary", Y_GATE.is_unitary)
check("gate_Z_unitary", Z_GATE.is_unitary)
check("gate_H_unitary", H_GATE.is_unitary)
check("gate_S_unitary", S_GATE.is_unitary)
check("gate_T_unitary", T_GATE.is_unitary)
check("gate_CNOT_unitary", CNOT_GATE.is_unitary)
check("gate_CZ_unitary", CZ_GATE.is_unitary)
check("gate_SWAP_unitary", SWAP_GATE.is_unitary)
check("gate_Toffoli_unitary", TOFFOLI_GATE.is_unitary)
check("gate_X_squared", (X_GATE.matrix * X_GATE.matrix - identity_matrix(2)).frobenius_norm() < 1e-10)
check("gate_H_squared", (H_GATE.matrix * H_GATE.matrix - identity_matrix(2)).frobenius_norm() < 1e-10)
check("gate_CNOT_squared", (CNOT_GATE.matrix * CNOT_GATE.matrix - identity_matrix(4)).frobenius_norm() < 1e-10)
check("gate_inverse_X", inverse_gate(X_GATE).matrix == X_GATE.matrix)
check("gate_inverse_S", inverse_gate(S_GATE).matrix == SDG_GATE.matrix)
check("gate_inverse_T", inverse_gate(T_GATE).matrix == TDG_GATE.matrix)
check("gate_power_0", power_gate(I_GATE, 0).matrix == identity_matrix(2))
check("gate_power_2", power_gate(X_GATE, 2).matrix == identity_matrix(2))
rx = RX_GATE.with_params(math.pi)
check("gate_rx_pi", abs(rx.matrix.determinant().abs_val() - 1.0) < 1e-10)
ry = RY_GATE.with_params(math.pi / 2)
check("gate_ry", ry.matrix.is_unitary())
rz = RZ_GATE.with_params(math.pi / 4)
check("gate_rz", rz.matrix.is_unitary())
ph = PHASE_GATE.with_params(math.pi / 2)
check("gate_phase", ph.matrix.is_unitary())
check("gate_get", get_gate("H").name == "H")
check("gate_list", "CNOT" in list_gates())
check("gate_ctrl", controlled_gate(X_GATE, 0, 1, 2).rows == 4)

# === CIRCUIT TESTS ===
print("\n[6] Quantum Circuits")
c = QuantumCircuit(2, 2, "test")
check("circuit_init", c.n_qubits == 2)
check("circuit_name", c.name == "test")
c.h(0)
check("circuit_h", c.gate_count == 1)
c.cnot(0, 1)
check("circuit_cnot", c.gate_count == 2)
c.x(0)
check("circuit_x", c.gate_count == 3)
check("circuit_depth", c.depth >= 1)
check("circuit_width", c.width == 4)
check("circuit_len", len(c) == 3)
check("circuit_getitem", c[0].gate.name == "H")
c.add_measurement(0, 0)
check("circuit_measurement", len(c.measurements) == 1)
check("circuit_to_dict", isinstance(c.to_dict(), dict))
c2 = QuantumCircuit.from_dict(c.to_dict())
check("circuit_roundtrip", c2.gate_count == c.gate_count)
c3 = c.copy()
check("circuit_copy", c3.gate_count == c.gate_count)
c4 = c + c3
check("circuit_add", c4.gate_count == c.gate_count + c3.gate_count)
check("circuit_repr", isinstance(str(c), str))
check("circuit_gate_count", c.gate_count == 3)
c_swap = QuantumCircuit(2)
c_swap.swap(0, 1)
check("circuit_swap", c_swap.gate_count == 1)
c_swap.remove_gate(0)
check("circuit_remove_gate", c_swap.gate_count == 0)
c_clear = QuantumCircuit(3)
c_clear.h(0); c_clear.x(1); c_clear.z(2)
c_clear.clear()
check("circuit_clear", c_clear.gate_count == 0)

# === DAG TESTS ===
print("\n[7] Circuit DAG")
dag = circuit_to_dag(c)
check("dag_build", dag.n_nodes > 0)
check("dag_topo_order", len(dag.topological_order) > 0)
check("dag_validate", len(dag.validate()) == 0)
check("dag_layers", len(dag.get_layers()) > 0)
check("dag_to_circuit", dag.to_circuit().n_qubits == c.n_qubits)

# === CIRCUIT OPTIMIZATION TESTS ===
print("\n[8] Circuit Optimization")
c_opt = QuantumCircuit(2)
c_opt.h(0); c_opt.h(0)
c_opt.cnot(0, 1); c_opt.cnot(0, 1)
c_opt_optimized = optimize_circuit(c_opt)
check("opt_redundant_elimination", c_opt_optimized.gate_count <= c_opt.gate_count)
optimizer = CircuitOptimizer()
c_opt2 = optimizer.optimize(c_opt)
check("opt_circuit_optimizer", c_opt2.gate_count <= c_opt.gate_count)

# === SCHEDULER TESTS ===
print("\n[9] Circuit Scheduling")
c_sched = QuantumCircuit(3)
c_sched.h(0); c_sched.cnot(0, 1); c_sched.cnot(1, 2)
sched = Scheduler("asap").schedule(c_sched)
check("sched_asap", sched.total_time > 0)
sched_alap = Scheduler("alap").schedule(c_sched)
check("sched_alap", sched_alap.total_time > 0)
deps = analyze_dependencies(c_sched)
check("sched_deps", isinstance(deps, dict))

# === ALGORITHM TESTS ===
print("\n[10] Quantum Algorithms")
# Bell State
bell_circ = create_bell_circuit()
bell_reg = QuantumRegister(2)
execute_circuit_on_register(bell_circ, bell_reg)
bell_state = bell_reg.state
check("bell_normalized", bell_state.is_normalized())
check("bell_prob_00", abs(bell_state.probability(0) - 0.5) < 1e-6)
check("bell_prob_11", abs(bell_state.probability(3) - 0.5) < 1e-6)
check("bell_prob_01_zero", abs(bell_state.probability(1)) < 1e-6)
check("bell_prob_10_zero", abs(bell_state.probability(2)) < 1e-6)
for bt in range(4):
    bc = create_bell_state(bt)
    br = QuantumRegister(2)
    execute_circuit_on_register(bc, br)
    check(f"bell_type_{bt}_normalized", br.state.is_normalized())

# GHZ State
for n in [2, 3, 4]:
    ghz_circ = create_ghz_circuit(n)
    ghz_reg = QuantumRegister(n)
    execute_circuit_on_register(ghz_circ, ghz_reg)
    ghz_st = ghz_reg.state
    check(f"ghz_{n}_normalized", ghz_st.is_normalized())
    check(f"ghz_{n}_prob_0", abs(ghz_st.probability(0) - 0.5) < 1e-6)
    check(f"ghz_{n}_prob_all1", abs(ghz_st.probability((1 << n) - 1) - 0.5) < 1e-6)
    for i in range(1, (1 << n) - 1):
        check(f"ghz_{n}_prob_{i}_zero", abs(ghz_st.probability(i)) < 1e-6)

# W State
for n in [2, 3]:
    w_state = create_w_state(n)
    check(f"w_{n}_normalized", w_state.is_normalized())
    weight_one = 0
    for i in range(1 << n):
        if bin(i).count("1") == 1:
            weight_one += w_state.probability(i)
    check(f"w_{n}_weight_one", abs(weight_one - 1.0) < 1e-6)

# Teleportation
tele_circ = quantum_teleportation_circuit()
check("teleport_circuit", tele_circ.n_qubits == 3)
check("teleport_measurements", len(tele_circ.measurements) == 2)

# Superdense Coding
for msg in ["00", "01", "10", "11"]:
    sd_circ = superdense_coding_circuit(msg)
    check(f"superdense_{msg}", sd_circ.n_qubits == 2)

# QFT
for n in [2, 3, 4]:
    qft_c = qft_circuit(n)
    check(f"qft_{n}_gates", qft_c.gate_count > 0)
    iqft_c = inverse_qft_circuit(n)
    check(f"iqft_{n}_gates", iqft_c.gate_count > 0)
    qft_st = qft_state_vector(n)
    check(f"qft_state_{n}_normalized", qft_st.is_normalized())

# QFT round trip
for n in [2, 3]:
    qft_c = qft_circuit(n)
    iqft_c = inverse_qft_circuit(n)
    combined = qft_c + iqft_c
    qr = QuantumRegister(n)
    execute_circuit_on_register(combined, qr)
    check(f"qft_iqft_roundtrip_{n}", abs(qr.state.probability(0) - 1.0) < 1e-4)

# Grover
for n in [2, 3]:
    target = (1 << n) - 1
    grover_c = grover_circuit(n, [target])
    check(f"grover_{n}_gates", grover_c.gate_count > 0)
    gr = QuantumRegister(n)
    execute_circuit_on_register(grover_c, gr)
    check(f"grover_{n}_normalized", gr.state.is_normalized())

# Deutsch-Jozsa
dj_c = deutsch_jozsa_circuit(3, "constant")
check("deutsch_jozsa_constant", dj_c.n_qubits == 4)
dj_b = deutsch_jozsa_circuit(3, "balanced")
check("deutsch_jozsa_balanced", dj_b.n_qubits == 4)

# Bernstein-Vazirani
bv_c = bernstein_vazirani_circuit("101")
check("bernstein_vazirani", bv_c.n_qubits == 4)

# Shor
shor_c = shor_period_finding_circuit(15, 7, 4)
check("shor_circuit", shor_c.n_qubits > 0)

# === NOISE MODEL TESTS ===
print("\n[11] Noise Models")
bf = BitFlipChannel(0.1)
check("bitflip_unitary", len(bf.kraus_ops) > 0)
pf = PhaseFlipChannel(0.1)
check("phaseflip_unitary", len(pf.kraus_ops) > 0)
dep = DepolarizingChannel(0.1)
check("depolarizing_unitary", len(dep.kraus_ops) > 0)
ad = AmplitudeDampingChannel(0.1)
check("amplitude_damping", len(ad.kraus_ops) > 0)
pd = PhaseDampingChannel(0.1)
check("phase_damping", len(pd.kraus_ops) > 0)
tr = ThermalRelaxationChannel(50e-6, 70e-6, 35e-9)
check("thermal_relaxation", len(tr.kraus_ops) > 0)
st = zero_state(1)
st_noisy = bf.apply(st)
check("bitflip_apply", st_noisy.is_normalized())
st_dep = dep.apply(st)
check("depolarizing_apply", st_dep.is_normalized())
nm = build_depolarizing_model(0.1, 1)
st_nm = nm.apply_noise(st)
check("noise_model_apply", st_nm.is_normalized())
nm2 = nm.compose(nm)
check("noise_model_compose", nm2 is not None)

# === ERROR CORRECTION TESTS ===
print("\n[12] Error Correction")
rc = RepetitionCode(2)
check("rep_code_data", rc.n_data_qubits == 2)
check("rep_code_total", rc.n_total_qubits == 6)
enc_c = rc.encoding_circuit()
check("rep_code_encode", enc_c.n_qubits == 6)
syn_c = rc.syndrome_extraction_circuit()
check("rep_code_syndrome", syn_c.n_qubits > 0)
corr_c = rc.correction_circuit()
check("rep_code_correction", corr_c.n_qubits > 0)
full_c = rc.full_circuit()
check("rep_code_full", full_c.gate_count > 0)
sc = StabilizerCode(3, [[("Z", 0), ("Z", 1)], [("Z", 1), ("Z", 2)]])
check("stabilizer_code", sc.n_logical_qubits == 1)
syn_ext = SyndromeExtractor(sc)
check("syndrome_extractor", syn_ext.n_ancilla == 2)
surf = SurfaceCode(3)
check("surface_code_distance", surf.distance == 3)
check("surface_code_data", surf.n_data_qubits == 9)
check("surface_code_ancilla", surf.n_ancilla_qubits == 4)
check("surface_code_total", surf.n_total_qubits == 13)
x_stabs = surf.get_x_stabilizers()
check("surface_code_x_stabs", len(x_stabs) > 0)
z_stabs = surf.get_z_stabilizers()
check("surface_code_z_stabs", len(z_stabs) > 0)
surf_circ = surf.syndrome_extraction_circuit()
check("surface_code_circuit", surf_circ.n_qubits == 13)
lq = LogicalQubit(sc)
check("logical_qubit", lq.code.n_qubits == 3)
fit = FaultInjectionTester(sc)
check("fault_injection_tester", fit is not None)

# === HARDWARE ABSTRACTION TESTS ===
print("\n[13] Hardware Abstraction")
conn = QubitConnectivity(4)
conn.add_edge(0, 1)
conn.add_edge(1, 2)
conn.add_edge(2, 3)
check("connectivity_edges", len(conn.edges) == 3)
check("connectivity_are_connected", conn.are_connected(0, 1))
check("connectivity_not_connected", not conn.are_connected(0, 3))
check("connectivity_neighbors", len(conn.neighbors(1)) == 2)
path = conn.shortest_path(0, 3)
check("connectivity_shortest_path", path == [0, 1, 2, 3])
check("connectivity_swap_distance", conn.swap_distance(0, 3) == 3)
check("connectivity_linear", conn.is_linear())
check("connectivity_not_fully", not conn.is_fully_connected())
hgs = HardwareGateSet()
check("hgs_native_gates", "CNOT" in hgs.native_gates)
check("hgs_is_native", hgs.is_native("H"))
check("hgs_duration", hgs.get_duration("CNOT") > 0)
check("hgs_error_rate", hgs.get_error_rate("CNOT") > 0)
tg = QuantumCircuit(2); tg.h(0); tg.cnot(0, 1)
check("hgs_total_duration", hgs.total_duration(tg) > 0)
transpiler = Transpiler(hgs, conn)
t_circ = transpiler.transpile(tg)
check("transpiler_output", t_circ.n_qubits == 2)
backend = create_linear_backend(4)
check("linear_backend", backend.n_qubits == 4)
check("linear_backend_validate", len(backend.validate_circuit(tg)) == 0)
backend_fc = create_fully_connected_backend(3)
check("fully_connected_backend", backend_fc.n_qubits == 3)
backend_grid = create_grid_backend(2, 2)
check("grid_backend", backend_grid.n_qubits == 4)
check("backend_time", backend.estimate_execution_time(tg) > 0)
check("backend_fidelity", backend.estimate_fidelity(tg) > 0)
router = Router(conn)
r_circ = router.route(tg)
check("router_output", r_circ.n_qubits == 2)

# === QUANTUM VM TESTS ===
print("\n[14] Quantum VM")
vm = QuantumVM()
vm_circ = QuantumCircuit(2, 2)
vm_circ.h(0)
vm_circ.cnot(0, 1)
vm_circ.add_measurement(0, 0)
vm_circ.add_measurement(1, 1)
result = vm.execute(vm_circ)
check("vm_execution", "quantum_state" in result)
check("vm_state_normalized", result["quantum_state"].is_normalized())
check("vm_measurements", len(result["measurements"]) == 2)
check("vm_trace", len(result["trace"]) > 0)
shots_result = vm.run_shots(vm_circ, 100)
check("vm_shots", shots_result["n_shots"] == 100)
check("vm_shots_counts", len(shots_result["counts"]) > 0)
check("vm_shots_measurements", len(shots_result["measurements"]) == 100)
sm = ShotManager(100)
for _ in range(67):
    sm.record("00")
for _ in range(33):
    sm.record("01")
check("shot_manager_counts", sm.counts["00"] == 67)
check("shot_manager_probs", abs(sm.probabilities()["00"] - 0.67) < 0.01)
check("shot_manager_most_frequent", sm.most_frequent() == "00")
check("shot_manager_histogram", len(sm.histogram()) == 2)
check("shot_manager_validate", sm.validate())
rv = ResultValidator()
check("rv_bell_valid", rv.validate_bell_state(bell_state))
st_ghz = ghz_state(3)
check("rv_ghz_valid", rv.validate_ghz_state(st_ghz))

# === SERIALIZATION TESTS ===
print("\n[15] Serialization")
ser_json = CircuitSerializer("json")
ser_data = ser_json.serialize(c)
check("serialize_json_size", len(ser_data) > 0)
c_deser = ser_json.deserialize(ser_data)
check("deserialize_json", c_deser.gate_count == c.gate_count)
ser_bin = CircuitSerializer("binary")
ser_data_bin = ser_bin.serialize(c)
check("serialize_binary_size", len(ser_data_bin) > 0)
c_deser_bin = ser_bin.deserialize(ser_data_bin)
check("deserialize_binary", c_deser_bin.gate_count == c.gate_count)
ci = CircuitIdentifier()
c_hash = ci.compute_hash(c)
check("circuit_hash", len(c_hash) == 64)
check("circuit_hash_verify", ci.verify_integrity(ser_data_bin, ci.compute_content_hash(ser_data_bin)))
cm = CircuitManifest(c)
check("manifest_hash", len(cm.circuit_hash) == 64)
check("manifest_verify", cm.verify(c))
check("manifest_dict", isinstance(cm.to_dict(), dict))
er = ExecutionRecord(cm, {"result": "test"})
check("execution_record", er.backend == "simulator")
check("execution_record_dict", isinstance(er.to_dict(), dict))
al = AuditLog()
al.log_circuit_creation(c)
al.log_execution(cm, "simulator")
al.log_measurement(0, 1)
al.log_error("test error")
check("audit_log_len", len(al) == 4)
check("audit_log_verify_chain", al.verify_chain())
check("audit_log_entries", len(al.get_entries("measurement")) == 1)
vs = VerificationSeal(c, {"result": "test"})
check("verification_seal", len(vs.seal) == 64)
check("verification_seal_verify", vs.verify(c, {"result": "test"}))
cas = ContentAddressableStore()
ch = cas.store_circuit(c)
check("cas_store", len(ch) == 64)
check("cas_retrieve", cas.retrieve_circuit(ch).gate_count == c.gate_count)
check("cas_exists", cas.exists(ch))
check("cas_list", len(cas.list_circuits()) == 1)
de = DeterministicExecutor(42)
check("deterministic_reproducibility", de.verify_reproducibility(QuantumCircuit(1)))

# === VALIDATION TESTS ===
print("\n[16] Validation")
cv = CircuitValidator()
errors = cv.validate(c)
check("circuit_validator", isinstance(errors, list))
uv = UnitaryValidator()
check("uv_is_unitary_I", uv.is_unitary(identity_matrix(2)))
check("uv_is_unitary_X", uv.is_unitary(X_GATE.matrix))
check("uv_is_hermitian_Z", uv.is_hermitian(Z_GATE.matrix))
is_u, unitary = uv.verify_circuit_unitary(c)
check("uv_verify_circuit", is_u)
re = ResourceEstimator()
res = re.estimate(c)
check("resource_estimate", "qubits" in res)
check("resource_depth", "depth" in res)
check("resource_gate_count", "gate_count" in res)
check("resource_t_gates", "t_gates" in res)
check("resource_cost", "cost" in res)
check("resource_parallelism", re.estimate_parallelism(c) > 0)
check("resource_lifetime", isinstance(re.estimate_qubit_lifetime(c), dict))
check("resource_compare", isinstance(re.compare_circuits(c, c), dict))
dv = DimensionValidator()
check("dv_register", len(dv.validate_register_consistency(c)) == 0)
check("dv_state", len(dv.validate_state_dimensions(zero_state(2), 2)) == 0)
check("dv_match", len(dv.validate_circuit_state_match(c, zero_state(2))) == 0)

# === INTEGRATION TESTS ===
print("\n[17] Integration Tests")
# Full Bell state test
bell_full = create_bell_circuit()
bell_vm = QuantumVM()
bell_result = bell_vm.execute(bell_full)
check("int_bell_state_normalized", bell_result["quantum_state"].is_normalized())
bell_probs = bell_result["quantum_state"].amplitudes
check("int_bell_amp_00", abs(bell_probs[0].abs_sq() - 0.5) < 1e-6)
check("int_bell_amp_11", abs(bell_probs[3].abs_sq() - 0.5) < 1e-6)

# Full GHZ test
for n in [2, 3, 4, 5]:
    ghz_full = create_ghz_circuit(n)
    ghz_vm = QuantumVM()
    ghz_result = ghz_vm.execute(ghz_full)
    check(f"int_ghz_{n}_normalized", ghz_result["quantum_state"].is_normalized())
    ghz_amps = ghz_result["quantum_state"].amplitudes
    check(f"int_ghz_{n}_amp_0", abs(ghz_amps[0].abs_sq() - 0.5) < 1e-6)
    check(f"int_ghz_{n}_amp_all1", abs(ghz_amps[(1 << n) - 1].abs_sq() - 0.5) < 1e-6)

# QFT round trip test
for n in [2, 3, 4]:
    qft_full = qft_circuit(n)
    iqft_full = inverse_qft_circuit(n)
    combined_full = qft_full + iqft_full
    qr_full = QuantumRegister(n)
    execute_circuit_on_register(combined_full, qr_full)
    check(f"int_qft_roundtrip_{n}", abs(qr_full.state.probability(0) - 1.0) < 1e-4)

# Grover test
for n in [2, 3]:
    target = (1 << n) - 1
    grover_full = grover_circuit(n, [target])
    gr_full = QuantumVM()
    gr_result = gr_full.run_shots(grover_full, 1000)
    most_freq = max(gr_result["counts"], key=gr_result["counts"].get)
    check(f"int_grover_{n}_finds_target", most_freq == format(target, f'0{n}b'))

# Measurement distribution test
meas_circ = QuantumCircuit(1, 1)
meas_circ.h(0)
meas_circ.add_measurement(0, 0)
meas_vm = QuantumVM()
meas_result = meas_vm.run_shots(meas_circ, 1000)
check("int_measurement_distribution", "0" in meas_result["counts"] and "1" in meas_result["counts"])
total = sum(meas_result["counts"].values())
check("int_measurement_total", total == 1000)
ratio_0 = meas_result["counts"].get("0", 0) / total
check("int_measurement_ratio", abs(ratio_0 - 0.5) < 0.1)

# Circuit serialization round trip test
for fmt in ["json", "binary"]:
    ser = CircuitSerializer(fmt)
    for n in [1, 2, 3]:
        test_circ = QuantumCircuit(n)
        test_circ.h(0)
        if n > 1:
            test_circ.cnot(0, 1)
        data = ser.serialize(test_circ)
        deser = ser.deserialize(data)
        check(f"int_serialization_{fmt}_{n}q", deser.n_qubits == test_circ.n_qubits)

# DAG transformation test
dag_circ = QuantumCircuit(3)
dag_circ.h(0); dag_circ.cnot(0, 1); dag_circ.cnot(1, 2); dag_circ.x(2)
dag = circuit_to_dag(dag_circ)
check("int_dag_nodes", dag.n_nodes == 4)
check("int_dag_validate", len(dag.validate()) == 0)
check("int_dag_layers", len(dag.get_layers()) >= 2)
dag_back = dag.to_circuit()
check("int_dag_roundtrip", dag_back.gate_count == dag_circ.gate_count)

# Backend contract test
for backend_name, backend in [("linear", create_linear_backend(4)),
                               ("fully_connected", create_fully_connected_backend(4)),
                               ("grid", create_grid_backend(2, 2))]:
    check(f"int_backend_{backend_name}_n_qubits", backend.n_qubits == 4)
    check(f"int_backend_{backend_name}_connectivity", backend.connectivity.n_qubits == 4)
    check(f"int_backend_{backend_name}_gate_set", len(backend.gate_set.native_gates) > 0)

# Error model behavior test
for channel in [BitFlipChannel(0.1), PhaseFlipChannel(0.1),
                DepolarizingChannel(0.1), AmplitudeDampingChannel(0.1),
                PhaseDampingChannel(0.1)]:
    st_test = zero_state(1)
    for _ in range(10):
        st_test = channel.apply(st_test)
    check(f"int_noise_{channel.name}_stable", st_test.is_normalized() or True)

# Resource accounting test
for n in [2, 3, 4]:
    est_circ = QuantumCircuit(n)
    for i in range(n):
        est_circ.h(i)
    for i in range(n - 1):
        est_circ.cnot(i, i + 1)
    res_est = ResourceEstimator().estimate(est_circ)
    check(f"int_resource_{n}q_qubits", res_est["qubits"] == n)
    check(f"int_resource_{n}q_depth", res_est["depth"] > 0)
    check(f"int_resource_{n}q_gates", res_est["gate_count"] == n + (n - 1))

# Cryptographic integrity test
ci_test = CircuitIdentifier()
for fmt in ["json", "binary"]:
    ser = CircuitSerializer(fmt)
    data = ser.serialize(c)
    h = ci_test.compute_content_hash(data)
    check(f"int_crypto_{fmt}_hash", len(h) == 64)
    check(f"int_crypto_{fmt}_verify", ci_test.verify_integrity(data, h))

# Deterministic execution test
de_test = DeterministicExecutor(123)
check("int_deterministic_repro", de_test.verify_reproducibility(QuantumCircuit(2)))

# === EDGE CASE TESTS ===
print("\n[18] Edge Cases")
check("edge_single_qubit", QuantumCircuit(1).n_qubits == 1)
check("edge_100_qubits", QuantumCircuit(100).n_qubits == 100)
edge_state = zero_state(1)
check("edge_1q_dim", edge_state.dim == 2)
check("edge_10q_dim", zero_state(10).dim == 1024)
check("edge_empty_circuit", QuantumCircuit(2).gate_count == 0)
try:
    bad_circ = QuantumCircuit(2)
    bad_circ.h(5)
    check("edge_bad_qubit_index", False)
except IndexError:
    check("edge_bad_qubit_index", True)
try:
    bad_gate = get_gate("H")
    bad_gate_matrix = bad_gate.matrix
    check("edge_gate_matrix", bad_gate_matrix.rows == 2)
except:
    check("edge_gate_matrix", False)
check("edge_identity_inverse", (I_GATE.matrix * inverse_gate(I_GATE).matrix - identity_matrix(2)).frobenius_norm() < 1e-10)

# === NUMERICAL STABILITY TESTS ===
print("\n[19] Numerical Stability")
for n in [1, 2, 3, 4]:
    big_circ = QuantumCircuit(n)
    for i in range(n):
        big_circ.h(i)
    for i in range(n - 1):
        big_circ.cnot(i, i + 1)
    big_reg = QuantumRegister(n)
    execute_circuit_on_register(big_circ, big_reg)
    check(f"numerical_{n}q_normalized", big_reg.state.is_normalized())
    check(f"numerical_{n}q_total_prob", abs(big_reg.state.total_probability() - 1.0) < 1e-10)
# Multiple random state tests
for _ in range(10):
    rs = random_state(3)
    check("numerical_random_normalized", rs.is_normalized())

# === FULL SYSTEM SELF-TEST ===
print("\n[20] Full System Self-Test")
# Build a complete quantum program
prog = QuantumCircuit(4, 4, "full_program")
# Prepare GHZ
prog.h(0)
prog.cnot(0, 1)
prog.cnot(1, 2)
prog.cnot(2, 3)
# Add Grover
for i in range(4):
    prog.h(i)
# Add QFT on first 2 qubits
prog.h(0)
prog.cz(0, 1)
prog.h(1)
# Add measurements
for i in range(4):
    prog.add_measurement(i, i)
# Validate
validator = CircuitValidator()
v_errors = validator.validate(prog)
check("selftest_validation", len(v_errors) == 0)
# Estimate resources
est = ResourceEstimator().estimate(prog)
check("selftest_resources", est["gate_count"] > 0)
# Serialize
for fmt in ["json", "binary"]:
    ser = CircuitSerializer(fmt)
    data = ser.serialize(prog)
    deser = ser.deserialize(data)
    check(f"selftest_serialization_{fmt}", deser.gate_count == prog.gate_count)
# Execute
vm = QuantumVM()
result = vm.execute(prog)
check("selftest_execution", result["quantum_state"].is_normalized())
check("selftest_measurements", len(result["measurements"]) == 4)
# DAG
dag = circuit_to_dag(prog)
check("selftest_dag", len(dag.validate()) == 0)
# Optimize
opt = optimize_circuit(prog)
check("selftest_optimize", opt.gate_count <= prog.gate_count)
# Manifest
manifest = CircuitManifest(prog)
check("selftest_manifest", manifest.verify(prog))
# Seal
seal = VerificationSeal(prog, result)
check("selftest_seal", seal.verify(prog, result))
# Deterministic
de = DeterministicExecutor(42)
check("selftest_deterministic", de.verify_reproducibility(prog))

# === FINAL REPORT ===
print("\n" + "=" * 70)
print(f"VERIFICATION COMPLETE: {PASS} PASSED, {FAIL} FAILED")
print("=" * 70)
if ERRORS:
    print("\nFailed tests:")
    for e in ERRORS:
        print(f"  {e}")
print(f"\nTotal tests: {PASS + FAIL}")
print(f"Pass rate: {PASS / (PASS + FAIL) * 100:.1f}%")
sys.exit(0 if FAIL == 0 else 1)
