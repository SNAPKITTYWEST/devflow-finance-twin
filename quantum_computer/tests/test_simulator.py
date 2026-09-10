"""Test suite for simulator backends and density matrix operations."""
import math
import sys
import os
import random
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from quantum_computer.core.complex import Complex, ZERO, ONE, I
from quantum_computer.core.matrix import Matrix, identity_matrix
from quantum_computer.core.state import QuantumState, zero_state, computational_basis_state, random_state
from quantum_computer.core.register import QuantumRegister
from quantum_computer.circuit.circuit import QuantumCircuit
from quantum_computer.gates import (I_GATE, X_GATE, Y_GATE, Z_GATE, H_GATE, S_GATE, T_GATE,
                                     CNOT_GATE, CZ_GATE, SWAP_GATE, TOFFOLI_GATE,
                                     RX_GATE, RY_GATE, RZ_GATE, get_gate)
from quantum_computer.algorithms import (create_bell_circuit, create_ghz_circuit,
                                          execute_circuit_on_register, qft_circuit, inverse_qft_circuit,
                                          grover_circuit)
from quantum_computer.vm.simulator import (DensityMatrix, StateSnapshot, DeterministicSimulator,
                                            NoisySimulator, StatevectorSimulator, UnitarySimulator,
                                            MatrixProductState)
from quantum_computer.noise import BitFlipChannel, DepolarizingChannel

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
print("SIMULATOR BACKEND TEST SUITE")
print("=" * 70)

# === DENSITY MATRIX TESTS ===
print("\n[1] Density Matrix Operations")
rho = DensityMatrix(1)
check("dm_init", rho.n_qubits == 1)
check("dm_trace", rho.trace() == ONE)
check("dm_purity", abs(rho.purity() - 1.0) < 1e-10)
check("dm_is_pure", rho.is_pure())

rho_x = DensityMatrix(1)
rho_x.apply_gate(X_GATE.matrix)
check("dm_apply_gate", rho_x.trace() == ONE)

rho_bell = DensityMatrix.from_state(zero_state(2))
check("dm_from_state", rho_bell.n_qubits == 2)
check("dm_bell_trace", rho_bell.trace() == ONE)

rho_mixed = DensityMatrix(1)
rho_mixed.apply_gate(H_GATE.matrix)
rho_mixed.apply_channel([
    Complex(math.sqrt(0.9)) * identity_matrix(2),
    Complex(math.sqrt(0.1)) * X_GATE.matrix
])
check("dm_channel_apply", rho_mixed.trace().re > 0.9)

rho_partial = DensityMatrix(2)
rho_partial.apply_gate(H_GATE.matrix, [0])
rho_partial.apply_gate(CNOT_GATE.matrix, [0, 1])
rho_trace = rho_partial.partial_trace([1])
check("dm_partial_trace", rho_trace.n_qubits == 1)

rho_exp = DensityMatrix(1)
exp_val = rho_exp.expectation(Z_GATE.matrix)
check("dm_expectation", exp_val == ONE)

entropy = rho_mixed.von_neumann_entropy()
check("dm_entropy", entropy >= 0)

# === STATE VECTOR SIMULATOR TESTS ===
print("\n[2] Statevector Simulator")
sv_sim = StatevectorSimulator(2)
bell_circ = create_bell_circuit()
amps = sv_sim.simulate(bell_circ)
check("sv_bell_amps", len(amps) == 4)
check("sv_bell_prob_00", abs(amps[0].abs_sq() - 0.5) < 1e-6)
check("sv_bell_prob_11", abs(amps[3].abs_sq() - 0.5) < 1e-6)

probs = sv_sim.probabilities(bell_circ)
check("sv_bell_probs", abs(sum(probs) - 1.0) < 1e-10)

bitstring = sv_sim.measure(bell_circ)
check("sv_bell_measure", bitstring in ["00", "01", "10", "11"])

for n in [2, 3]:
    ghz_circ = create_ghz_circuit(n)
    sv = StatevectorSimulator(n)
    amps = sv.simulate(ghz_circ)
    check(f"sv_ghz_{n}_len", len(amps) == (1 << n))
    total = sum(a.abs_sq() for a in amps)
    check(f"sv_ghz_{n}_normalized", abs(total - 1.0) < 1e-10)

# === UNITARY SIMULATOR TESTS ===
print("\n[3] Unitary Simulator")
usim = UnitarySimulator(1)
circ_h = QuantumCircuit(1)
circ_h.h(0)
u = usim.simulate(circ_h)
check("usim_h_unitary", u.is_unitary())

circ_x = QuantumCircuit(1)
circ_x.x(0)
u_x = usim.simulate(circ_x)
check("usim_x_unitary", u_x.is_unitary())

usim2 = UnitarySimulator(2)
bell_circ2 = create_bell_circuit()
u_bell = usim2.simulate(bell_circ2)
check("usim_bell_unitary", u_bell.is_unitary())
check("usim_bell_det", abs(u_bell.determinant().abs_val() - 1.0) < 1e-10)

check("usim_h_is_unitary", usim.is_unitary(circ_h))

circ_not = QuantumCircuit(2)
circ_not.cnot(0, 1)
u_not = usim2.simulate(circ_not)
check("usim_cnot_unitary", u_not.is_unitary())

# === DETERMINISTIC SIMULATOR TESTS ===
print("\n[4] Deterministic Simulator")
dsim = DeterministicSimulator(2, record_snapshots=True)
bell_circ = create_bell_circuit()
state = dsim.simulate(bell_circ)
check("dsim_bell_normalized", state.is_normalized())
check("dsim_bell_prob_00", abs(state.probability(0) - 0.5) < 1e-6)
check("dsim_snapshots", len(dsim.snapshots) > 0)

dsim2 = DeterministicSimulator(3)
ghz_circ = create_ghz_circuit(3)
state3 = dsim2.simulate(ghz_circ)
check("dsim_ghz_normalized", state3.is_normalized())
check("dsim_ghz_prob_000", abs(state3.probability(0) - 0.5) < 1e-6)
check("dsim_ghz_prob_111", abs(state3.probability(7) - 0.5) < 1e-6)

dm = dsim.simulate_density_matrix(bell_circ)
check("dsim_density_matrix", dm.n_qubits == 2)

fidelity = dsim.compute_fidelity(create_bell_circuit(), create_bell_circuit())
check("dsim_self_fidelity", abs(fidelity - 1.0) < 1e-10)

# === NOISY SIMULATOR TESTS ===
print("\n[5] Noisy Simulator")
nsim = NoisySimulator(1, n_shots=100)
circ = QuantumCircuit(1)
circ.h(0)
state = nsim.simulate(circ)
check("nsim_h_normalized", state.is_normalized())

counts = nsim.run_shots(circ)
check("nsim_shots", sum(counts.values()) == 100)

noise = BitFlipChannel(0.1, 1)
nsim_noisy = NoisySimulator(1, noise_model=noise, n_shots=100)
state_noisy = nsim_noisy.simulate(circ)
check("nsim_noisy_normalized", state_noisy.is_normalized())

counts_noisy = nsim_noisy.run_shots(circ)
check("nsim_noisy_shots", sum(counts_noisy.values()) == 100)

# === SNAPSHOT TESTS ===
print("\n[6] State Snapshots")
snap = StateSnapshot(0, zero_state(1))
check("snapshot_step", snap.step == 0)
check("snapshot_state", snap.state.n_qubits == 1)
check("snapshot_dm", snap.density_matrix.n_qubits == 1)
check("snapshot_metadata", isinstance(snap.metadata, dict))

# === MPS TESTS ===
print("\n[7] Matrix Product State")
mps = MatrixProductState(2)
check("mps_n_qubits", mps.n_qubits == 2)
mps2 = MatrixProductState(3)
check("mps_3_qubits", mps2.n_qubits == 3)
norm = mps.norm()
check("mps_norm", norm > 0)

# === INTEGRATION: BACKEND CONTRACTS ===
print("\n[8] Backend Contracts")
for n in [1, 2, 3]:
    sv = StatevectorSimulator(n)
    us = UnitarySimulator(n)
    ds = DeterministicSimulator(n)
    circ = QuantumCircuit(n)
    for i in range(n):
        circ.h(i)
    sv_state = sv.simulate(circ)
    us_matrix = us.simulate(circ)
    ds_state = ds.simulate(circ)
    check(f"contract_sv_{n}q", len(sv_state) == (1 << n))
    check(f"contract_us_{n}q", us_matrix.rows == (1 << n))
    check(f"contract_ds_{n}q", ds_state.n_qubits == n)

# === MEASUREMENT DISTRIBUTION TESTS ===
print("\n[9] Measurement Distribution Tests")
for n in [1, 2]:
    circ = QuantumCircuit(n)
    for i in range(n):
        circ.h(i)
    sv = StatevectorSimulator(n)
    counts = {}
    for _ in range(1000):
        bits = sv.measure(circ)
        bitstring = "".join(str(b) for b in bits)
        counts[bitstring] = counts.get(bitstring, 0) + 1
    check(f"meas_dist_{n}q_all_outcomes", len(counts) == (1 << n))
    for key, count in counts.items():
        check(f"meas_dist_{n}q_{key}_balanced", abs(count / 1000 - 1.0 / (1 << n)) < 0.1)

# === EDGE CASE TESTS ===
print("\n[10] Edge Cases")
check("edge_dm_1q", DensityMatrix(1).n_qubits == 1)
check("edge_dm_trace", DensityMatrix(1).trace() == ONE)
check("edge_sv_1q", StatevectorSimulator(1).n_qubits == 1)
check("edge_us_1q", UnitarySimulator(1).n_qubits == 1)
check("edge_ds_1q", DeterministicSimulator(1).n_qubits == 1)

circ_empty = QuantumCircuit(2)
sv = StatevectorSimulator(2)
amps = sv.simulate(circ_empty)
check("edge_empty_circuit", len(amps) == 4)
check("edge_empty_prob_00", abs(amps[0].abs_sq() - 1.0) < 1e-10)

# === FINAL REPORT ===
print("\n" + "=" * 70)
print(f"SIMULATOR TEST COMPLETE: {PASS} PASSED, {FAIL} FAILED")
print("=" * 70)
if ERRORS:
    print("\nFailed tests:")
    for e in ERRORS:
        print(f"  {e}")
print(f"\nTotal tests: {PASS + FAIL}")
print(f"Pass rate: {PASS / (PASS + FAIL) * 100:.1f}%")
sys.exit(0 if FAIL == 0 else 1)
