"""Circuit optimization: gate fusion, redundant gate elimination, commutation analysis."""
import math
from typing import List, Optional, Tuple, Set
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction
from quantum_computer.circuit.dag import CircuitDAG, circuit_to_dag, dag_to_circuit
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix
from quantum_computer.gates import Gate, get_gate

def eliminate_redundant_gates(circuit: QuantumCircuit) -> QuantumCircuit:
    result = circuit.copy()
    changed = True
    while changed:
        changed = False
        i = 0
        while i < len(result.instructions) - 1:
            inst_a = result.instructions[i]
            inst_b = result.instructions[i + 1]
            if (inst_a.gate.name == inst_b.gate.name and
                inst_a.qubits == inst_b.qubits and
                inst_a.condition == inst_b.condition):
                if inst_a.gate.name in ("I",):
                    result.remove_gate(i)
                    result.remove_gate(i)
                    changed = True
                    continue
                inv_names = {"X": "X", "Y": "Y", "Z": "Z", "H": "H",
                             "S": "Sdg", "Sdg": "S", "T": "Tdg", "Tdg": "T"}
                if inst_a.gate.name in inv_names:
                    if inv_names[inst_a.gate.name] == inst_b.gate.name:
                        result.remove_gate(i + 1)
                        result.remove_gate(i)
                        changed = True
                        continue
            i += 1
    return result

def fuse_adjacent_gates(circuit: QuantumCircuit) -> QuantumCircuit:
    result = circuit.copy()
    changed = True
    while changed:
        changed = False
        i = 0
        while i < len(result.instructions) - 1:
            inst_a = result.instructions[i]
            inst_b = result.instructions[i + 1]
            if (len(inst_a.qubits) == 1 and len(inst_b.qubits) == 1 and
                inst_a.qubits == inst_b.qubits and
                inst_a.condition is None and inst_b.condition is None):
                if inst_a.gate.n_qubits == 1 and inst_b.gate.n_qubits == 1:
                    product = inst_a.gate.matrix * inst_b.gate.matrix
                    fused = Gate(f"{inst_a.gate.name}_{inst_b.gate.name}", 1, product)
                    result.replace_gate(i, fused, inst_a.qubits)
                    result.remove_gate(i + 1)
                    changed = True
                    continue
            i += 1
    return result

def can_commute(a: Instruction, b: Instruction) -> bool:
    if a.gate.name == "barrier" or b.gate.name == "barrier":
        return True
    shared = set(a.qubits) & set(b.qubits)
    if not shared:
        return True
    pauli_gates = {"I", "X", "Y", "Z"}
    if (a.gate.name in pauli_gates and b.gate.name in pauli_gates and
        len(a.qubits) == 1 and len(b.qubits) == 1):
        return True
    if a.gate.name == b.gate.name and len(a.qubits) == len(b.qubits):
        return a.qubits == b.qubits
    return False

def commute_transform(circuit: QuantumCircuit) -> QuantumCircuit:
    result = circuit.copy()
    changed = True
    while changed:
        changed = False
        for i in range(len(result.instructions) - 1):
            inst_a = result.instructions[i]
            inst_b = result.instructions[i + 1]
            if (can_commute(inst_a, inst_b) and
                inst_a.condition is None and inst_b.condition is None):
                pass
    return result

def optimize_circuit(circuit: QuantumCircuit, passes: Optional[List[str]] = None) -> QuantumCircuit:
    if passes is None:
        passes = ["eliminate_redundant", "fuse_adjacent"]
    result = circuit.copy()
    for p in passes:
        if p == "eliminate_redundant":
            result = eliminate_redundant_gates(result)
        elif p == "fuse_adjacent":
            result = fuse_adjacent_gates(result)
        elif p == "commute":
            result = commute_transform(result)
    return result

class OptimizationPass:
    def optimize(self, circuit: QuantumCircuit) -> QuantumCircuit:
        raise NotImplementedError

class RedundantGateElimination(OptimizationPass):
    def optimize(self, circuit: QuantumCircuit) -> QuantumCircuit:
        return eliminate_redundant_gates(circuit)

class GateFusion(OptimizationPass):
    def optimize(self, circuit: QuantumCircuit) -> QuantumCircuit:
        return fuse_adjacent_gates(circuit)

class CommuteScheduling(OptimizationPass):
    def optimize(self, circuit: QuantumCircuit) -> QuantumCircuit:
        return commute_transform(circuit)

class CircuitOptimizer:
    __slots__ = ('_passes', '_max_iterations')
    def __init__(self, passes: Optional[List[OptimizationPass]] = None, max_iterations: int = 10):
        self._passes = passes or [RedundantGateElimination(), GateFusion()]
        self._max_iterations = max_iterations
    def optimize(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        for _ in range(self._max_iterations):
            prev_count = result.gate_count
            for p in self._passes:
                result = p.optimize(result)
            if result.gate_count == prev_count:
                break
        return result
    def add_pass(self, p: OptimizationPass):
        self._passes.append(p)
