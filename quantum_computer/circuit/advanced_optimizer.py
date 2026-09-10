"""Advanced circuit optimization: peephole, template matching, commutation-based optimization."""
import math
from typing import List, Optional, Tuple, Dict, Set
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction
from quantum_computer.circuit.dag import CircuitDAG, circuit_to_dag
from quantum_computer.gates import Gate, get_gate, GATE_SET
from quantum_computer.core.complex import Complex, ZERO, ONE
from quantum_computer.core.matrix import Matrix, identity_matrix

class CommutationAnalyzer:
    __slots__ = ('_commutation_table')
    def __init__(self):
        self._commutation_table = self._build_table()
    def _build_table(self) -> Dict[Tuple[str, str], bool]:
        table = {}
        commuting_pairs = [
            ("I", "X"), ("I", "Y"), ("I", "Z"), ("I", "H"), ("I", "S"), ("I", "T"),
            ("X", "X"), ("X", "Z"), ("X", "T"), ("X", "S"),
            ("Y", "Y"), ("Y", "T"),
            ("Z", "Z"), ("Z", "H"), ("Z", "S"), ("Z", "T"),
            ("S", "S"), ("S", "T"), ("T", "T"),
        ]
        for a, b in commuting_pairs:
            table[(a, b)] = True
            table[(b, a)] = True
        return table
    def commute(self, gate_a: str, gate_b: str) -> bool:
        return self._commutation_table.get((gate_a, gate_b), False)
    def analyze_circuit(self, circuit: QuantumCircuit) -> List[Tuple[int, int]]:
        pairs = []
        for i in range(len(circuit.instructions)):
            for j in range(i + 1, len(circuit.instructions)):
                inst_a = circuit.instructions[i]
                inst_b = circuit.instructions[j]
                if self._gates_commute(inst_a, inst_b):
                    pairs.append((i, j))
        return pairs
    def _gates_commute(self, a: Instruction, b: Instruction) -> bool:
        if a.gate.name == "barrier" or b.gate.name == "barrier":
            return True
        shared = set(a.qubits) & set(b.qubits)
        if not shared:
            return True
        if len(shared) == 1 and a.gate.n_qubits == 1 and b.gate.n_qubits == 1:
            return self.commute(a.gate.name, b.gate.name)
        return False

class TemplateMatcher:
    __slots__ = ('_templates')
    def __init__(self):
        self._templates = self._build_templates()
    def _build_templates(self) -> List[Tuple[List[str], List[str]]]:
        templates = []
        templates.append((["H", "H"], []))
        templates.append((["X", "X"], []))
        templates.append((["Z", "Z"], []))
        templates.append((["S", "Sdg"], []))
        templates.append((["T", "Tdg"], []))
        templates.append((["Sdg", "S"], []))
        templates.append((["Tdg", "T"], []))
        templates.append((["CNOT", "CNOT"], []))
        templates.append((["H", "CNOT", "H"], ["CZ"]))
        templates.append((["CZ", "CZ"], []))
        templates.append((["Rx", "Rx"], ["Rx"]))
        templates.append((["Ry", "Ry"], ["Ry"]))
        templates.append((["Rz", "Rz"], ["Rz"]))
        return templates
    def match(self, circuit: QuantumCircuit) -> List[Tuple[int, List[str]]]:
        matches = []
        for template_in, template_out in self._templates:
            for i in range(len(circuit.instructions) - len(template_in) + 1):
                if self._match_at(circuit, i, template_in):
                    matches.append((i, template_out))
        return matches
    def _match_at(self, circuit: QuantumCircuit, start: int, pattern: List[str]) -> bool:
        for k, gate_name in enumerate(pattern):
            idx = start + k
            if idx >= len(circuit.instructions):
                return False
            if circuit.instructions[idx].gate.name != gate_name:
                return False
            if k > 0:
                prev_qubits = set(circuit.instructions[start + k - 1].qubits)
                curr_qubits = set(circuit.instructions[idx].qubits)
                if not (prev_qubits & curr_qubits):
                    return False
        return True
    def apply_match(self, circuit: QuantumCircuit, match_pos: int,
                     replacement: List[str]) -> QuantumCircuit:
        result = circuit.copy()
        n_match = len(replacement)
        if n_match == 0:
            for _ in range(match_pos, match_pos + n_match):
                if match_pos < len(result.instructions):
                    result.remove_gate(match_pos)
        else:
            original = result.instructions[match_pos]
            if replacement:
                new_gate = get_gate(replacement[0])
                result.replace_gate(match_pos, new_gate, original.qubits)
        return result

class PeepholeOptimizer:
    __slots__ = ('_commutation_analyzer', '_template_matcher', '_max_passes')
    def __init__(self, max_passes: int = 5):
        self._commutation_analyzer = CommutationAnalyzer()
        self._template_matcher = TemplateMatcher()
        self._max_passes = max_passes
    def optimize(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        for _ in range(self._max_passes):
            prev_count = result.gate_count
            result = self._eliminate_identity_pairs(result)
            result = self._merge_parameterized_gates(result)
            result = self._remove_trivial_gates(result)
            if result.gate_count == prev_count:
                break
        return result
    def _eliminate_identity_pairs(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        changed = True
        while changed:
            changed = False
            for i in range(len(result.instructions) - 1):
                inst_a = result.instructions[i]
                inst_b = result.instructions[i + 1]
                if (inst_a.gate.name == inst_b.gate.name and
                    inst_a.qubits == inst_b.qubits):
                    if inst_a.gate.name in ("X", "Y", "Z", "H", "S", "T", "Sdg", "Tdg"):
                        inv_map = {"X": "X", "Y": "Y", "Z": "Z", "H": "H",
                                   "S": "Sdg", "Sdg": "S", "T": "Tdg", "Tdg": "T"}
                        if inv_map.get(inst_a.gate.name) == inst_b.gate.name:
                            result.remove_gate(i + 1)
                            result.remove_gate(i)
                            changed = True
                            break
        return result
    def _merge_parameterized_gates(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        changed = True
        while changed:
            changed = False
            for i in range(len(result.instructions) - 1):
                inst_a = result.instructions[i]
                inst_b = result.instructions[i + 1]
                if (inst_a.qubits == inst_b.qubits and
                    inst_a.gate.name in ("Rx", "Ry", "Rz") and
                    inst_b.gate.name in ("Rx", "Ry", "Rz") and
                    inst_a.gate.name == inst_b.gate.name):
                    theta_a = inst_a.gate.params.get("theta", 0)
                    theta_b = inst_b.gate.params.get("theta", 0)
                    merged = get_gate(inst_a.gate.name).with_params(theta_a + theta_b)
                    result.replace_gate(i, merged, inst_a.qubits)
                    result.remove_gate(i + 1)
                    changed = True
                    break
        return result
    def _remove_trivial_gates(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        changed = True
        while changed:
            changed = False
            for i in range(len(result.instructions)):
                inst = result.instructions[i]
                if inst.gate.name == "I":
                    result.remove_gate(i)
                    changed = True
                    break
                if inst.gate.name in ("Rx", "Ry", "Rz"):
                    theta = inst.gate.params.get("theta", 0)
                    if abs(theta % (2 * math.pi)) < 1e-10:
                        result.remove_gate(i)
                        changed = True
                        break
        return result

class CircuitRewriter:
    __slots__ = ('_rules')
    def __init__(self):
        self._rules = self._build_rules()
    def _build_rules(self) -> List[Dict]:
        return [
            {"name": "double_cnot_elimination", "pattern": ["CNOT", "CNOT"], "condition": "same_qubits"},
            {"name": "hadamard_cancellation", "pattern": ["H", "H"], "condition": "same_qubit"},
            {"name": "phase_merge", "pattern": ["S", "S"], "condition": "same_qubit"},
            {"name": "t_merge", "pattern": ["T", "T"], "condition": "same_qubit"},
            {"name": "cnot_to_swap", "pattern": ["CNOT", "CNOT", "CNOT"], "condition": "swap_pattern"},
        ]
    def rewrite(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        for rule in self._rules:
            result = self._apply_rule(result, rule)
        return result
    def _apply_rule(self, circuit: QuantumCircuit, rule: Dict) -> QuantumCircuit:
        result = circuit.copy()
        pattern = rule["pattern"]
        i = 0
        while i <= len(result.instructions) - len(pattern):
            match = True
            for k, gate_name in enumerate(pattern):
                if result.instructions[i + k].gate.name != gate_name:
                    match = False
                    break
            if match and self._check_condition(result, i, rule["condition"]):
                result = self._transform(result, i, len(pattern), rule["name"])
            else:
                i += 1
        return result
    def _check_condition(self, circuit: QuantumCircuit, start: int, condition: str) -> bool:
        if condition == "same_qubits":
            qubits = circuit.instructions[start].qubits
            for k in range(1, len(circuit.instructions) - start):
                if circuit.instructions[start + k].qubits != qubits:
                    return False
            return True
        elif condition == "same_qubit":
            qubits = circuit.instructions[start].qubits
            for k in range(1, len(circuit.instructions) - start):
                if circuit.instructions[start + k].qubits != qubits:
                    return False
            return True
        elif condition == "swap_pattern":
            if len(circuit.instructions) - start < 3:
                return False
            q0, q1 = circuit.instructions[start].qubits
            if circuit.instructions[start + 1].qubits != [q1, q0]:
                return False
            if circuit.instructions[start + 2].qubits != [q0, q1]:
                return False
            return True
        return False
    def _transform(self, circuit: QuantumCircuit, start: int,
                    n_match: int, rule_name: str) -> QuantumCircuit:
        result = circuit.copy()
        if rule_name in ("double_cnot_elimination", "hadamard_cancellation",
                          "phase_merge", "t_merge"):
            for _ in range(n_match):
                if start < len(result.instructions):
                    result.remove_gate(start)
        elif rule_name == "cnot_to_swap":
            qubits = result.instructions[start].qubits
            for _ in range(n_match):
                if start < len(result.instructions):
                    result.remove_gate(start)
            result.add_instruction(get_gate("SWAP"), qubits)
        return result

class NoiseAwareOptimizer:
    __slots__ = ('_noise_model', '_gate_costs')
    def __init__(self, noise_model=None):
        self._noise_model = noise_model
        self._gate_costs = {"CNOT": 10, "SWAP": 30, "H": 1, "X": 1, "Z": 1, "T": 5, "S": 2}
    def optimize(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        if self._noise_model:
            result = self._reduce_cnot_count(result)
        result = self._reduce_depth(result)
        return result
    def _reduce_cnot_count(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        changed = True
        while changed:
            changed = False
            for i in range(len(result.instructions) - 1):
                inst_a = result.instructions[i]
                inst_b = result.instructions[i + 1]
                if (inst_a.gate.name == "CNOT" and inst_b.gate.name == "CNOT" and
                    inst_a.qubits == inst_b.qubits):
                    result.remove_gate(i + 1)
                    result.remove_gate(i)
                    changed = True
                    break
        return result
    def _reduce_depth(self, circuit: QuantumCircuit) -> QuantumCircuit:
        return circuit
    def estimate_cost(self, circuit: QuantumCircuit) -> float:
        total = 0.0
        for inst in circuit.instructions:
            total += self._gate_costs.get(inst.gate.name, 1)
        return total

class LayoutOptimizer:
    __slots__ = ('_n_qubits', '_initial_layout', '_final_layout')
    def __init__(self, n_qubits: int, initial_layout: Optional[Dict[int, int]] = None):
        self._n_qubits = n_qubits
        self._initial_layout = initial_layout or {i: i for i in range(n_qubits)}
        self._final_layout = {i: i for i in range(n_qubits)}
    def optimize(self, circuit: QuantumCircuit) -> Tuple[QuantumCircuit, Dict[int, int]]:
        layout = dict(self._initial_layout)
        result = QuantumCircuit(circuit.n_qubits, circuit.n_classical, circuit.name)
        for inst in circuit.instructions:
            mapped_qubits = [layout.get(q, q) for q in inst.qubits]
            result.add_instruction(inst.gate, mapped_qubits, inst.classical_bits, inst.condition)
        return result, layout
    def update_layout(self, swap_qubits: Tuple[int, int]):
        q0, q1 = swap_qubits
        for k, v in self._initial_layout.items():
            if v == q0:
                self._initial_layout[k] = q1
            elif v == q1:
                self._initial_layout[k] = q0
    def __repr__(self):
        return f"LayoutOptimizer(n_qubits={self._n_qubits})"

class CircuitCompactor:
    __slots__ = ('_max_iterations')
    def __init__(self, max_iterations: int = 10):
        self._max_iterations = max_iterations
    def compact(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        for _ in range(self._max_iterations):
            prev_count = result.gate_count
            result = self._remove_identity_gates(result)
            result = self._merge_adjacent_rotations(result)
            result = self._eliminate_redundant_cnots(result)
            if result.gate_count == prev_count:
                break
        return result
    def _remove_identity_gates(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        changed = True
        while changed:
            changed = False
            for i in range(len(result.instructions)):
                inst = result.instructions[i]
                if inst.gate.name == "I":
                    result.remove_gate(i)
                    changed = True
                    break
                if inst.gate.name in ("Rx", "Ry", "Rz"):
                    theta = inst.gate.params.get("theta", 0)
                    if abs(theta % (2 * math.pi)) < 1e-10:
                        result.remove_gate(i)
                        changed = True
                        break
        return result
    def _merge_adjacent_rotations(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        changed = True
        while changed:
            changed = False
            for i in range(len(result.instructions) - 1):
                inst_a = result.instructions[i]
                inst_b = result.instructions[i + 1]
                if (inst_a.qubits == inst_b.qubits and
                    inst_a.gate.name == inst_b.gate.name and
                    inst_a.gate.name in ("Rx", "Ry", "Rz")):
                    theta_a = inst_a.gate.params.get("theta", 0)
                    theta_b = inst_b.gate.params.get("theta", 0)
                    merged = get_gate(inst_a.gate.name).with_params(theta_a + theta_b)
                    result.replace_gate(i, merged, inst_a.qubits)
                    result.remove_gate(i + 1)
                    changed = True
                    break
        return result
    def _eliminate_redundant_cnots(self, circuit: QuantumCircuit) -> QuantumCircuit:
        result = circuit.copy()
        changed = True
        while changed:
            changed = False
            for i in range(len(result.instructions) - 1):
                inst_a = result.instructions[i]
                inst_b = result.instructions[i + 1]
                if (inst_a.gate.name == "CNOT" and inst_b.gate.name == "CNOT" and
                    inst_a.qubits == inst_b.qubits):
                    result.remove_gate(i + 1)
                    result.remove_gate(i)
                    changed = True
                    break
        return result

class AdvancedCircuitOptimizer:
    __slots__ = ('_peephole', '_rewriter', '_compactor', '_layout_optimizer', '_max_passes')
    def __init__(self, max_passes: int = 10):
        self._peephole = PeepholeOptimizer(max_passes=5)
        self._rewriter = CircuitRewriter()
        self._compactor = CircuitCompactor(max_iterations=5)
        self._layout_optimizer = None
        self._max_passes = max_passes
    def optimize(self, circuit: QuantumCircuit, passes: Optional[List[str]] = None) -> QuantumCircuit:
        if passes is None:
            passes = ["peephole", "rewriter", "compactor"]
        result = circuit.copy()
        for _ in range(self._max_passes):
            prev_count = result.gate_count
            if "peephole" in passes:
                result = self._peephole.optimize(result)
            if "rewriter" in passes:
                result = self._rewriter.rewrite(result)
            if "compactor" in passes:
                result = self._compactor.compact(result)
            if result.gate_count == prev_count:
                break
        return result
    def optimize_with_layout(self, circuit: QuantumCircuit,
                              initial_layout: Optional[Dict[int, int]] = None) -> Tuple[QuantumCircuit, Dict[int, int]]:
        if initial_layout:
            self._layout_optimizer = LayoutOptimizer(circuit.n_qubits, initial_layout)
            circuit, layout = self._layout_optimizer.optimize(circuit)
        optimized = self.optimize(circuit)
        return optimized, layout if initial_layout else {}
    def compare_circuits(self, original: QuantumCircuit, optimized: QuantumCircuit) -> Dict[str, float]:
        return {
            "gate_reduction": (original.gate_count - optimized.gate_count) / original.gate_count if original.gate_count > 0 else 0,
            "depth_reduction": (original.depth - optimized.depth) / original.depth if original.depth > 0 else 0,
            "original_gates": original.gate_count,
            "optimized_gates": optimized.gate_count,
            "original_depth": original.depth,
            "optimized_depth": optimized.depth
        }
