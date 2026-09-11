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

#!/usr/bin/env python3
# simulate_gate_list.py
# Simple state-vector simulator for the gate list format used by KrausExtractor fallback.
# Requires numpy.

import sys, json, math
import numpy as np

def parse_gatefile(path):
    gates = []
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            gates.append(parts)
    return gates

def apply_single_qubit_gate(state, q, G, n_qubits):
    new = np.zeros_like(state)
    for idx in range(len(state)):
        bit = (idx >> (n_qubits - 1 - q)) & 1
        partner = idx ^ (1 << (n_qubits - 1 - q))
        if bit == 0:
            new[idx]     += G[0,0] * state[idx] + G[0,1] * state[partner]
            new[partner] += G[1,0] * state[idx] + G[1,1] * state[partner]
    return new

def apply_ry(state, q, theta, n_qubits):
    c = math.cos(theta/2.0)
    s = math.sin(theta/2.0)
    R = np.array([[c, -s],[s, c]], dtype=complex)
    return apply_single_qubit_gate(state, q, R, n_qubits)

def apply_controlled_ry(state, control, target, theta, n_qubits):
    new = state.copy()
    c = math.cos(theta/2.0)
    s = math.sin(theta/2.0)
    for idx in range(len(state)):
        if ((idx >> (n_qubits - 1 - control)) & 1) == 1:
            bit = (idx >> (n_qubits - 1 - target)) & 1
            partner = idx ^ (1 << (n_qubits - 1 - target))
            a = state[idx]
            b = state[partner]
            if bit == 0:
                new[idx]     = c * a - s * b
                new[partner] = s * a + c * b
    return new

def main():
    if len(sys.argv) < 2:
        print("Usage: simulate_gate_list.py gatefile", file=sys.stderr)
        sys.exit(2)
    gates = parse_gatefile(sys.argv[1])
    maxq = -1
    inits = {}
    for g in gates:
        if g[0] == "INIT":
            q = int(g[1]); b = int(g[2])
            inits[q] = b
            if q > maxq: maxq = q
        elif g[0] == "C_RY":
            q1 = int(g[1]); q2 = int(g[2])
            maxq = max(maxq, q1, q2)
        elif g[0] == "RY":
            q = int(g[1]); maxq = max(maxq, q)
    n_qubits = maxq + 1
    dim = 2 ** n_qubits
    init_index = 0
    for q in range(n_qubits):
        bit = inits.get(q, 0)
        init_index = (init_index << 1) | (bit & 1)
    state = np.zeros(dim, dtype=complex)
    state[init_index] = 1.0 + 0j
    for g in gates:
        if g[0] == "INIT":
            continue
        elif g[0] == "RY":
            q = int(g[1]); theta = float(g[2])
            state = apply_ry(state, q, theta, n_qubits)
        elif g[0] == "C_RY":
            control = int(g[1]); target = int(g[2]); theta = float(g[3])
            state = apply_controlled_ry(state, control, target, theta, n_qubits)
        else:
            print("Unknown gate:", g, file=sys.stderr)
            sys.exit(2)
    out = [(float(np.real(a)), float(np.imag(a))) for a in state.tolist()]
    print(json.dumps(out))

if __name__ == "__main__":
    main()
