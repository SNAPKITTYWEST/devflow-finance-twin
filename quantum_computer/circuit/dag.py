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

"""DAG representation for quantum circuits."""
from typing import List, Set, Dict, Optional
from quantum_computer.circuit.circuit import Instruction, QuantumCircuit

class DAGNode:
    __slots__ = ('_instruction', '_index', '_successors', '_predecessors', '_depth')
    def __init__(self, instruction: Instruction, index: int):
        self._instruction = instruction
        self._index = index
        self._successors: List[int] = []
        self._predecessors: List[int] = []
        self._depth = 0
    @property
    def instruction(self) -> Instruction:
        return self._instruction
    @property
    def index(self) -> int:
        return self._index
    @property
    def successors(self) -> List[int]:
        return self._successors[:]
    @property
    def predecessors(self) -> List[int]:
        return self._predecessors[:]
    @property
    def depth(self) -> int:
        return self._depth
    @depth.setter
    def depth(self, d: int):
        self._depth = d
    def add_successor(self, idx: int):
        if idx not in self._successors:
            self._successors.append(idx)
    def add_predecessor(self, idx: int):
        if idx not in self._predecessors:
            self._predecessors.append(idx)
    def __repr__(self):
        return f"DAGNode({self._instruction}, depth={self._depth})"

class CircuitDAG:
    __slots__ = ('_nodes', '_n_qubits', '_qubit_owners', '_topological_order', '_built')
    def __init__(self, n_qubits: int):
        self._n_qubits = n_qubits
        self._nodes: List[DAGNode] = []
        self._qubit_owners: Dict[int, List[int]] = {q: [] for q in range(n_qubits)}
        self._topological_order: List[int] = []
        self._built = False
    @property
    def nodes(self) -> List[DAGNode]:
        return self._nodes[:]
    @property
    def n_nodes(self) -> int:
        return len(self._nodes)
    @property
    def topological_order(self) -> List[int]:
        if not self._built:
            self.build()
        return self._topological_order[:]
    def add_node(self, instruction: Instruction) -> int:
        idx = len(self._nodes)
        node = DAGNode(instruction, idx)
        self._nodes.append(node)
        for q in instruction.qubits:
            if self._qubit_owners[q]:
                last_idx = self._qubit_owners[q][-1]
                node.add_predecessor(last_idx)
                self._nodes[last_idx].add_successor(idx)
            self._qubit_owners[q].append(idx)
        if instruction.condition:
            cbit = instruction.condition[0]
            for owner_list in self._qubit_owners.values():
                if owner_list:
                    last = owner_list[-1]
                    if last != idx and idx not in self._nodes[last].successors:
                        node.add_predecessor(last)
                        self._nodes[last].add_successor(idx)
        self._built = False
        return idx
    def build(self):
        in_degree = [0] * len(self._nodes)
        for node in self._nodes:
            for s in node.successors:
                in_degree[s] += 1
        queue = []
        for i, deg in enumerate(in_degree):
            if deg == 0:
                queue.append(i)
        order = []
        depth_map = {}
        while queue:
            idx = queue.pop(0)
            order.append(idx)
            node = self._nodes[idx]
            max_pred_depth = 0
            for pred in node.predecessors:
                max_pred_depth = max(max_pred_depth, depth_map.get(pred, 0) + 1)
            depth_map[idx] = max_pred_depth
            node.depth = max_pred_depth
            for s in node.successors:
                in_degree[s] -= 1
                if in_degree[s] == 0:
                    queue.append(s)
        if len(order) != len(self._nodes):
            raise ValueError("DAG has a cycle")
        self._topological_order = order
        self._built = True
    def validate(self) -> List[str]:
        errors = []
        if not self._built:
            self.build()
        for i, node in enumerate(self._nodes):
            if i not in self._topological_order:
                errors.append(f"Node {i} not in topological order")
            for pred in node.predecessors:
                if pred not in self._topological_order:
                    errors.append(f"Predecessor {pred} of node {i} not in topological order")
                elif self._topological_order.index(pred) >= self._topological_order.index(i):
                    errors.append(f"Predecessor {pred} comes after node {i} in topological order")
        return errors
    def get_qubit_depth(self, qubit: int) -> int:
        if not self._built:
            self.build()
        max_d = 0
        for idx in self._topological_order:
            node = self._nodes[idx]
            if qubit in node.instruction.qubits:
                max_d = max(max_d, node.depth + 1)
        return max_d
    def get_layers(self) -> List[List[Instruction]]:
        if not self._built:
            self.build()
        layers = {}
        for idx in self._topological_order:
            node = self._nodes[idx]
            d = node.depth
            if d not in layers:
                layers[d] = []
            layers[d].append(node.instruction)
        return [layers[d] for d in sorted(layers.keys())]
    def to_circuit(self) -> QuantumCircuit:
        if not self._built:
            self.build()
        circ = QuantumCircuit(self._n_qubits)
        for idx in self._topological_order:
            node = self._nodes[idx]
            inst = node.instruction
            if inst.gate.name != "barrier":
                circ.add_instruction(inst.gate, inst.qubits,
                                     inst.classical_bits, inst.condition)
        return circ
    def __repr__(self):
        return f"CircuitDAG(nodes={len(self._nodes)}, qubits={self._n_qubits})"

def circuit_to_dag(circuit: QuantumCircuit) -> CircuitDAG:
    dag = CircuitDAG(circuit.n_qubits)
    for inst in circuit.instructions:
        dag.add_node(inst)
    dag.build()
    return dag

def dag_to_circuit(dag: CircuitDAG) -> QuantumCircuit:
    return dag.to_circuit()
