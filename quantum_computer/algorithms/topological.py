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

"""Quantum annealing abstractions and topological qubit representations."""
import math
from typing import List, Optional, Tuple, Dict
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix
from quantum_computer.core.state import QuantumState, zero_state
from quantum_computer.circuit.circuit import QuantumCircuit
from quantum_computer.gates import Gate, get_gate

class IsingModel:
    __slots__ = ('_n_qubits', '_J', '_h', '_coupling_map')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        self._J: Dict[Tuple[int, int], float] = {}
        self._h: Dict[int, float] = {}
        self._coupling_map: List[Tuple[int, int]] = []
    @property
    def n_qubits(self) -> int:
        return self._n_qubits
    def set_coupling(self, i: int, j: int, value: float):
        if i < 0 or i >= self._n_qubits or j < 0 or j >= self._n_qubits:
            raise IndexError("Qubit index out of range")
        self._J[(i, j)] = value
        self._J[(j, i)] = value
        if (i, j) not in self._coupling_map and (j, i) not in self._coupling_map:
            self._coupling_map.append((i, j))
    def set_bias(self, i: int, value: float):
        if i < 0 or i >= self._n_qubits:
            raise IndexError("Qubit index out of range")
        self._h[i] = value
    def energy(self, spin_config: List[int]) -> float:
        e = 0.0
        for (i, j), J_val in self._J.items():
            e += J_val * spin_config[i] * spin_config[j]
        for i, h_val in self._h.items():
            e += h_val * spin_config[i]
        return e / 2.0
    def ground_state_brute_force(self) -> Tuple[List[int], float]:
        best_config = [1] * self._n_qubits
        best_energy = float('inf')
        for config_int in range(1 << self._n_qubits):
            config = [((config_int >> i) & 1) * 2 - 1 for i in range(self._n_qubits)]
            e = self.energy(config)
            if e < best_energy:
                best_energy = e
                best_config = config[:]
        return best_config, best_energy
    def to_qubo(self) -> Dict[Tuple[int, int], float]:
        qubo = {}
        for (i, j), J_val in self._J.items():
            if i < j:
                qubo[(i, j)] = J_val
        for i, h_val in self._h.items():
            qubo[(i, i)] = h_val
        return qubo
    def from_qubo(self, qubo: Dict[Tuple[int, int], float]):
        self._J.clear()
        self._h.clear()
        for (i, j), val in qubo.items():
            if i == j:
                self._h[i] = val
            else:
                self._J[(i, j)] = val
                self._J[(j, i)] = val
    def __repr__(self):
        return f"IsingModel(n_qubits={self._n_qubits}, couplings={len(self._J)}, biases={len(self._h)})"

class AnnealingSchedule:
    __slots__ = ('_total_time', '_n_steps', '_s_schedule', '_t_schedule')
    def __init__(self, total_time: float = 100.0, n_steps: int = 100):
        self._total_time = total_time
        self._n_steps = n_steps
        self._s_schedule = [i / n_steps for i in range(n_steps + 1)]
        self._t_schedule = [1.0 - i / n_steps for i in range(n_steps + 1)]
    @property
    def total_time(self) -> float:
        return self._total_time
    @property
    def n_steps(self) -> int:
        return self._n_steps
    def get_s(self, step: int) -> float:
        if step < 0 or step > self._n_steps:
            raise IndexError("Step out of range")
        return self._s_schedule[step]
    def get_t(self, step: int) -> float:
        if step < 0 or step > self._n_steps:
            raise IndexError("Step out of range")
        return self._t_schedule[step]
    def set_custom_schedule(self, s_values: List[float], t_values: List[float]):
        if len(s_values) != len(t_values):
            raise ValueError("Schedule length mismatch")
        self._s_schedule = s_values[:]
        self._t_schedule = t_values[:]
        self._n_steps = len(s_values) - 1
    def __repr__(self):
        return f"AnnealingSchedule(total_time={self._total_time}, steps={self._n_steps})"

class QuantumAnnealer:
    __slots__ = ('_ising_model', '_schedule', '_n_reads')
    def __init__(self, ising_model: IsingModel, schedule: Optional[AnnealingSchedule] = None):
        self._ising_model = ising_model
        self._schedule = schedule or AnnealingSchedule()
        self._n_reads = 100
    @property
    def ising_model(self) -> IsingModel:
        return self._ising_model
    @property
    def schedule(self) -> AnnealingSchedule:
        return self._schedule
    def set_n_reads(self, n: int):
        self._n_reads = n
    def anneal(self) -> Tuple[List[int], float]:
        best_config = [1] * self._ising_model.n_qubits
        best_energy = float('inf')
        for _ in range(self._n_reads):
            config = self._single_anneal()
            energy = self._ising_model.energy(config)
            if energy < best_energy:
                best_energy = energy
                best_config = config[:]
        return best_config, best_energy
    def _single_anneal(self) -> List[int]:
        n = self._ising_model.n_qubits
        config = [1] * n
        import random
        for step in range(self._schedule.n_steps):
            s = self._schedule.get_s(step)
            t = self._schedule.get_t(step)
            for i in range(n):
                delta_e = self._compute_delta_energy(config, i)
                if delta_e < 0 or (t > 0 and random.random() < math.exp(-delta_e / t)):
                    config[i] *= -1
        return config
    def _compute_delta_energy(self, config: List[int], flip_qubit: int) -> float:
        delta_e = 0.0
        for (i, j), J_val in self._ising_model._J.items():
            if i == flip_qubit or j == flip_qubit:
                other = j if i == flip_qubit else i
                delta_e += 2 * J_val * config[flip_qubit] * config[other]
        if flip_qubit in self._ising_model._h:
            delta_e += 2 * self._ising_model._h[flip_qubit] * config[flip_qubit]
        return delta_e
    def quantum_anneal_circuit(self) -> QuantumCircuit:
        n = self._ising_model.n_qubits
        circ = QuantumCircuit(n)
        for q in range(n):
            circ.h(q)
        for step in range(self._schedule.n_steps):
            s = self._schedule.get_s(step)
            for (i, j), J_val in self._ising_model._J.items():
                if i < j:
                    angle = 2 * J_val * s * self._schedule.total_time / self._schedule.n_steps
                    circ.cnot(i, j)
                    circ.rz(j, angle)
                    circ.cnot(i, j)
            for i, h_val in self._ising_model._h.items():
                angle = 2 * h_val * s * self._schedule.total_time / self._schedule.n_steps
                circ.rz(i, angle)
        for q in range(n):
            circ.h(q)
        return circ
    def __repr__(self):
        return f"QuantumAnnealer(model={self._ising_model}, schedule={self._schedule})"

class Anyon:
    __slots__ = ('_position', '_type', '_charge')
    def __init__(self, position: Tuple[float, float], anyon_type: str = "e", charge: int = 1):
        self._position = position
        self._type = anyon_type
        self._charge = charge
    @property
    def position(self) -> Tuple[float, float]:
        return self._position
    @property
    def type(self) -> str:
        return self._type
    @property
    def charge(self) -> int:
        return self._charge
    def move(self, new_position: Tuple[float, float]):
        self._position = new_position
    def __repr__(self):
        return f"Anyon(pos={self._position}, type={self._type}, charge={self._charge})"

class Worldline:
    __slots__ = ('_anyon', '_trajectory')
    def __init__(self, anyon: Anyon):
        self._anyon = anyon
        self._trajectory = [anyon.position]
    @property
    def anyon(self) -> Anyon:
        return self._anyon
    @property
    def trajectory(self) -> List[Tuple[float, float]]:
        return self._trajectory[:]
    def add_position(self, position: Tuple[float, float]):
        self._trajectory.append(position)
        self._anyon.move(position)
    def length(self) -> float:
        total = 0.0
        for i in range(1, len(self._trajectory)):
            dx = self._trajectory[i][0] - self._trajectory[i-1][0]
            dy = self._trajectory[i][1] - self._trajectory[i-1][1]
            total += math.sqrt(dx*dx + dy*dy)
        return total
    def intersects(self, other: 'Worldline') -> bool:
        for i in range(len(self._trajectory) - 1):
            for j in range(len(other._trajectory) - 1):
                if self._segments_intersect(self._trajectory[i], self._trajectory[i+1],
                                             other._trajectory[j], other._trajectory[j+1]):
                    return True
        return False
    def _segments_intersect(self, p1, p2, p3, p4) -> bool:
        def cross(o, a, b):
            return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
        d1 = cross(p3, p4, p1)
        d2 = cross(p3, p4, p2)
        d3 = cross(p1, p2, p3)
        d4 = cross(p1, p2, p4)
        if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and \
           ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
            return True
        return False
    def __repr__(self):
        return f"Worldline(anyon={self._anyon}, positions={len(self._trajectory)})"

class Braid:
    __slots__ = ('_anyon_indices', '_direction')
    def __init__(self, anyon_indices: Tuple[int, int], direction: int = 1):
        self._anyon_indices = anyon_indices
        self._direction = direction
    @property
    def anyon_indices(self) -> Tuple[int, int]:
        return self._anyon_indices
    @property
    def direction(self) -> int:
        return self._direction
    def __repr__(self):
        return f"Braid({self._anyon_indices}, dir={self._direction})"

class BraidGroup:
    __slots__ = ('_n_anyons', '_braids')
    def __init__(self, n_anyons: int):
        self._n_anyons = n_anyons
        self._braids: List[Braid] = []
    @property
    def n_anyons(self) -> int:
        return self._n_anyons
    @property
    def braids(self) -> List[Braid]:
        return self._braids[:]
    def add_braid(self, braid: Braid):
        if braid.anyon_indices[0] < 0 or braid.anyon_indices[0] >= self._n_anyons:
            raise IndexError("Anyon index out of range")
        if braid.anyon_indices[1] < 0 or braid.anyon_indices[1] >= self._n_anyons:
            raise IndexError("Anyon index out of range")
        self._braids.append(braid)
    def compose(self, other: 'BraidGroup') -> 'BraidGroup':
        if self._n_anyons != other._n_anyons:
            raise ValueError("Anyon count mismatch")
        result = BraidGroup(self._n_anyons)
        result._braids = self._braids + other._braids
        return result
    def inverse(self) -> 'BraidGroup':
        result = BraidGroup(self._n_anyons)
        for braid in reversed(self._braids):
            result._braids.append(Braid(braid.anyon_indices, -braid.direction))
        return result
    def apply_to_positions(self, positions: List[Tuple[float, float]]) -> List[Tuple[float, float]]:
        result = [p for p in positions]
        for braid in self._braids:
            i, j = braid.anyon_indices
            result[i], result[j] = result[j], result[i]
        return result
    def __len__(self):
        return len(self._braids)
    def __repr__(self):
        return f"BraidGroup(n_anyons={self._n_anyons}, braids={len(self._braids)})"

class TopologicalQubit:
    __slots__ = ('_n_anyons', '_anyons', '_worldlines', '_braid_group')
    def __init__(self, n_anyons: int = 4):
        self._n_anyons = n_anyons
        self._anyons = [Anyon((i * 1.0, 0.0)) for i in range(n_anyons)]
        self._worldlines = [Worldline(a) for a in self._anyons]
        self._braid_group = BraidGroup(n_anyons)
    @property
    def n_anyons(self) -> int:
        return self._n_anyons
    @property
    def anyons(self) -> List[Anyon]:
        return self._anyons[:]
    @property
    def worldlines(self) -> List[Worldline]:
        return self._worldlines[:]
    def apply_braid(self, braid: Braid):
        self._braid_group.add_braid(braid)
        i, j = braid.anyon_indices
        self._anyons[i].move(self._anyons[j].position)
        self._anyons[j].move(self._anyons[i].position)
    def braid_sigma(self, i: int, direction: int = 1):
        if i < 0 or i >= self._n_anyons - 1:
            raise IndexError("Braid index out of range")
        braid = Braid((i, i + 1), direction)
        self.apply_braid(braid)
    def fusion_rules(self) -> Dict[Tuple[str, str], str]:
        return {
            ("e", "e"): "1",
            ("e", "m"): "eps",
            ("m", "e"): "eps",
            ("m", "m"): "1",
            ("1", "e"): "e",
            ("e", "1"): "e",
            ("1", "m"): "m",
            ("m", "1"): "m",
            ("1", "1"): "1",
            ("eps", "eps"): "1",
        }
    def measure_fusion(self, i: int, j: int) -> str:
        rules = self.fusion_rules()
        t1 = self._anyons[i].type
        t2 = self._anyons[j].type
        return rules.get((t1, t2), "unknown")
    def encode_logical_zero(self):
        if self._n_anyons >= 4:
            self._anyons[0] = Anyon((0, 0), "e", 1)
            self._anyons[1] = Anyon((1, 0), "e", -1)
            self._anyons[2] = Anyon((2, 0), "e", 1)
            self._anyons[3] = Anyon((3, 0), "e", -1)
    def encode_logical_one(self):
        if self._n_anyons >= 4:
            self.encode_logical_zero()
            self.braid_sigma(1, 1)
    def __repr__(self):
        return f"TopologicalQubit(n_anyons={self._n_anyons})"

class TopologicalOperationValidator:
    __slots__ = ('_topological_qubit')
    def __init__(self, topological_qubit: TopologicalQubit):
        self._topological_qubit = topological_qubit
    def validate_braid(self, braid: Braid) -> bool:
        i, j = braid.anyon_indices
        if i < 0 or i >= self._topological_qubit.n_anyons:
            return False
        if j < 0 or j >= self._topological_qubit.n_anyons:
            return False
        if abs(i - j) != 1:
            return False
        return True
    def validate_sequence(self, braids: List[Braid]) -> List[str]:
        errors = []
        for i, braid in enumerate(braids):
            if not self.validate_braid(braid):
                errors.append(f"Invalid braid at position {i}: {braid}")
        return errors
    def verify_fusion_consistency(self) -> bool:
        n = self._topological_qubit.n_anyons
        if n < 2:
            return True
        total_charge = 0
        for anyon in self._topological_qubit.anyons:
            total_charge += anyon.charge
        return total_charge == 0
    def __repr__(self):
        return f"TopologicalOperationValidator(qubit={self._topological_qubit})"
