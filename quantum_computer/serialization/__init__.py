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

"""Circuit serialization: JSON, binary, cryptographic integrity."""
import json
import hashlib
import struct
import time
import base64
from typing import List, Optional, Dict, Any, Tuple
from quantum_computer.circuit.circuit import QuantumCircuit, Instruction, Measurement
from quantum_computer.gates import Gate, get_gate, GATE_SET, PARAMETERIZED_GATES

class CircuitSerializer:
    __slots__ = ('_format',)
    def __init__(self, fmt: str = "json"):
        if fmt not in ("json", "binary"):
            raise ValueError(f"Unknown format: {fmt}")
        self._format = fmt
    def serialize(self, circuit: QuantumCircuit) -> bytes:
        if self._format == "json":
            return self._serialize_json(circuit)
        return self._serialize_binary(circuit)
    def deserialize(self, data: bytes) -> QuantumCircuit:
        if self._format == "json":
            return self._deserialize_json(data)
        return self._deserialize_binary(data)
    def _serialize_json(self, circuit: QuantumCircuit) -> bytes:
        d = circuit.to_dict()
        return json.dumps(d, indent=2).encode("utf-8")
    def _deserialize_json(self, data: bytes) -> QuantumCircuit:
        d = json.loads(data.decode("utf-8"))
        return QuantumCircuit.from_dict(d)
    def _serialize_binary(self, circuit: QuantumCircuit) -> bytes:
        parts = []
        parts.append(struct.pack(">HH", circuit.n_qubits, circuit.n_classical))
        name_bytes = circuit.name.encode("utf-8")
        parts.append(struct.pack(">H", len(name_bytes)))
        parts.append(name_bytes)
        parts.append(struct.pack(">I", len(circuit.instructions)))
        for inst in circuit.instructions:
            gate_name = inst.gate.name.encode("utf-8")
            parts.append(struct.pack(">H", len(gate_name)))
            parts.append(gate_name)
            parts.append(struct.pack(">H", len(inst.qubits)))
            for q in inst.qubits:
                parts.append(struct.pack(">H", q))
            params = inst.gate.params
            parts.append(struct.pack(">H", len(params)))
            for k, v in params.items():
                key_bytes = k.encode("utf-8")
                parts.append(struct.pack(">H", len(key_bytes)))
                parts.append(key_bytes)
                parts.append(struct.pack(">d", v))
        parts.append(struct.pack(">I", len(circuit.measurements)))
        for meas in circuit.measurements:
            parts.append(struct.pack(">HH", meas.qubit, meas.classical_bit))
        return b"".join(parts)
    def _deserialize_binary(self, data: bytes) -> QuantumCircuit:
        offset = 0
        n_qubits, n_classical = struct.unpack_from(">HH", data, offset)
        offset += 4
        name_len = struct.unpack_from(">H", data, offset)[0]
        offset += 2
        name = data[offset:offset + name_len].decode("utf-8")
        offset += name_len
        n_insts = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        circ = QuantumCircuit(n_qubits, n_classical, name)
        for _ in range(n_insts):
            gname_len = struct.unpack_from(">H", data, offset)[0]
            offset += 2
            gate_name = data[offset:offset + gname_len].decode("utf-8")
            offset += gname_len
            n_q = struct.unpack_from(">H", data, offset)[0]
            offset += 2
            qubits = []
            for _ in range(n_q):
                q = struct.unpack_from(">H", data, offset)[0]
                offset += 2
                qubits.append(q)
            n_params = struct.unpack_from(">H", data, offset)[0]
            offset += 2
            params = {}
            for _ in range(n_params):
                klen = struct.unpack_from(">H", data, offset)[0]
                offset += 2
                k = data[offset:offset + klen].decode("utf-8")
                offset += klen
                v = struct.unpack_from(">d", data, offset)[0]
                offset += 8
                params[k] = v
            if gate_name in PARAMETERIZED_GATES and params:
                gate = PARAMETERIZED_GATES[gate_name].bind(**params)
            else:
                gate = get_gate(gate_name)
            circ.add_instruction(gate, qubits)
        n_meas = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        for _ in range(n_meas):
            q, c = struct.unpack_from(">HH", data, offset)
            offset += 4
            circ._measurements.append(Measurement(q, c))
        return circ

class CircuitIdentifier:
    __slots__ = ('_hash_algo',)
    def __init__(self, hash_algo: str = "sha256"):
        self._hash_algo = hash_algo
    def compute_hash(self, circuit: QuantumCircuit) -> str:
        serializer = CircuitSerializer("binary")
        data = serializer.serialize(circuit)
        h = hashlib.new(self._hash_algo)
        h.update(data)
        return h.hexdigest()
    def compute_content_hash(self, data: bytes) -> str:
        h = hashlib.new(self._hash_algo)
        h.update(data)
        return h.hexdigest()
    def verify_integrity(self, data: bytes, expected_hash: str) -> bool:
        actual = self.compute_content_hash(data)
        return actual == expected_hash

class CircuitManifest:
    __slots__ = ('_circuit_hash', '_name', '_created_at', '_metadata',
                 '_version', '_execution_id')
    def __init__(self, circuit: QuantumCircuit, execution_id: Optional[str] = None):
        identifier = CircuitIdentifier()
        self._circuit_hash = identifier.compute_hash(circuit)
        self._name = circuit.name
        self._created_at = time.time()
        self._metadata = circuit.metadata
        self._version = "1.0"
        self._execution_id = execution_id or self._generate_id()
    @property
    def circuit_hash(self) -> str:
        return self._circuit_hash
    @property
    def name(self) -> str:
        return self._name
    @property
    def created_at(self) -> float:
        return self._created_at
    @property
    def execution_id(self) -> str:
        return self._execution_id
    def _generate_id(self) -> str:
        return hashlib.sha256(f"{self._circuit_hash}{self._created_at}".encode()).hexdigest()[:16]
    def to_dict(self) -> dict:
        return {
            "circuit_hash": self._circuit_hash,
            "name": self._name,
            "created_at": self._created_at,
            "execution_id": self._execution_id,
            "version": self._version,
            "metadata": self._metadata
        }
    @staticmethod
    def from_dict(d: dict) -> 'CircuitManifest':
        m = CircuitManifest.__new__(CircuitManifest)
        m._circuit_hash = d["circuit_hash"]
        m._name = d["name"]
        m._created_at = d["created_at"]
        m._execution_id = d["execution_id"]
        m._version = d.get("version", "1.0")
        m._metadata = d.get("metadata", {})
        return m
    def verify(self, circuit: QuantumCircuit) -> bool:
        identifier = CircuitIdentifier()
        return identifier.compute_hash(circuit) == self._circuit_hash
    def __repr__(self):
        return f"CircuitManifest(hash={self._circuit_hash[:8]}..., id={self._execution_id})"

class ExecutionRecord:
    __slots__ = ('_manifest', '_results', '_timestamp', '_duration', '_backend')
    def __init__(self, manifest: CircuitManifest, results: dict,
                 backend: str = "simulator"):
        self._manifest = manifest
        self._results = results
        self._timestamp = time.time()
        self._duration = 0.0
        self._backend = backend
    @property
    def manifest(self) -> CircuitManifest:
        return self._manifest
    @property
    def results(self) -> dict:
        return self._results
    @property
    def timestamp(self) -> float:
        return self._timestamp
    @property
    def backend(self) -> str:
        return self._backend
    def set_duration(self, duration: float):
        self._duration = duration
    def to_dict(self) -> dict:
        return {
            "manifest": self._manifest.to_dict(),
            "results": self._serialize_results(),
            "timestamp": self._timestamp,
            "duration": self._duration,
            "backend": self._backend
        }
    def _serialize_results(self) -> dict:
        r = {}
        for k, v in self._results.items():
            if k == "quantum_state":
                r[k] = {"amplitudes": [(a.re, a.im) for a in v.amplitudes]}
            elif k == "classical_registers":
                r[k] = v
            elif k == "counts":
                r[k] = v
            elif k == "measurements":
                r[k] = v
            else:
                r[k] = str(v)
        return r
    @staticmethod
    def from_dict(d: dict) -> 'ExecutionRecord':
        manifest = CircuitManifest.from_dict(d["manifest"])
        return ExecutionRecord(manifest, d["results"], d.get("backend", "simulator"))

class AuditLog:
    __slots__ = ('_entries',)
    def __init__(self):
        self._entries: List[Dict[str, Any]] = []
    def log(self, event_type: str, details: dict, severity: str = "info"):
        entry = {
            "timestamp": time.time(),
            "event_type": event_type,
            "details": details,
            "severity": severity
        }
        self._entries.append(entry)
    def log_circuit_creation(self, circuit: QuantumCircuit):
        self.log("circuit_created", {
            "name": circuit.name,
            "n_qubits": circuit.n_qubits,
            "gate_count": circuit.gate_count
        })
    def log_execution(self, manifest: CircuitManifest, backend: str):
        self.log("circuit_executed", {
            "circuit_hash": manifest.circuit_hash,
            "execution_id": manifest.execution_id,
            "backend": backend
        })
    def log_measurement(self, qubit: int, outcome: int):
        self.log("measurement", {"qubit": qubit, "outcome": outcome})
    def log_error(self, error: str):
        self.log("error", {"error": error}, severity="error")
    def get_entries(self, event_type: Optional[str] = None) -> List[Dict[str, Any]]:
        if event_type is None:
            return self._entries[:]
        return [e for e in self._entries if e["event_type"] == event_type]
    def verify_chain(self) -> bool:
        for i in range(1, len(self._entries)):
            if self._entries[i]["timestamp"] < self._entries[i - 1]["timestamp"]:
                return False
        return True
    def __len__(self):
        return len(self._entries)
    def __repr__(self):
        return f"AuditLog(entries={len(self._entries)})"

class VerificationSeal:
    __slots__ = ('_circuit_hash', '_execution_hash', '_timestamp', '_seal')
    def __init__(self, circuit: QuantumCircuit, results: dict):
        identifier = CircuitIdentifier()
        self._circuit_hash = identifier.compute_hash(circuit)
        result_str = json.dumps(str(results), sort_keys=True)
        self._execution_hash = hashlib.sha256(result_str.encode()).hexdigest()
        self._timestamp = time.time()
        self._seal = hashlib.sha256(
            f"{self._circuit_hash}{self._execution_hash}{self._timestamp}".encode()
        ).hexdigest()
    @property
    def seal(self) -> str:
        return self._seal
    @property
    def circuit_hash(self) -> str:
        return self._circuit_hash
    @property
    def execution_hash(self) -> str:
        return self._execution_hash
    def verify(self, circuit: QuantumCircuit, results: dict) -> bool:
        identifier = CircuitIdentifier()
        actual_hash = identifier.compute_hash(circuit)
        if actual_hash != self._circuit_hash:
            return False
        result_str = json.dumps(str(results), sort_keys=True)
        actual_exec = hashlib.sha256(result_str.encode()).hexdigest()
        return actual_exec == self._execution_hash
    def to_dict(self) -> dict:
        return {
            "circuit_hash": self._circuit_hash,
            "execution_hash": self._execution_hash,
            "timestamp": self._timestamp,
            "seal": self._seal
        }
    def __repr__(self):
        return f"VerificationSeal(seal={self._seal[:16]}...)"

class ContentAddressableStore:
    __slots__ = ('_store', '_index')
    def __init__(self):
        self._store: Dict[str, bytes] = {}
        self._index: Dict[str, str] = {}
    def store_circuit(self, circuit: QuantumCircuit) -> str:
        serializer = CircuitSerializer("binary")
        data = serializer.serialize(circuit)
        identifier = CircuitIdentifier()
        content_hash = identifier.compute_content_hash(data)
        self._store[content_hash] = data
        self._index[circuit.name] = content_hash
        return content_hash
    def retrieve_circuit(self, content_hash: str) -> Optional[QuantumCircuit]:
        if content_hash not in self._store:
            return None
        serializer = CircuitSerializer("binary")
        return serializer.deserialize(self._store[content_hash])
    def retrieve_by_name(self, name: str) -> Optional[QuantumCircuit]:
        if name not in self._index:
            return None
        return self.retrieve_circuit(self._index[name])
    def exists(self, content_hash: str) -> bool:
        return content_hash in self._store
    def list_circuits(self) -> List[str]:
        return list(self._index.keys())
    def __len__(self):
        return len(self._store)
    def __repr__(self):
        return f"ContentAddressableStore(circuits={len(self._store)})"

class DeterministicExecutor:
    __slots__ = ('_seed',)
    def __init__(self, seed: int = 42):
        self._seed = seed
    def execute(self, circuit: QuantumCircuit) -> Dict[str, Any]:
        import random
        random.seed(self._seed)
        from quantum_computer.vm import QuantumVM
        vm = QuantumVM()
        return vm.execute(circuit)
    def run_shots(self, circuit: QuantumCircuit, n_shots: int) -> Dict[str, Any]:
        import random
        random.seed(self._seed)
        from quantum_computer.vm import QuantumVM
        vm = QuantumVM()
        return vm.run_shots(circuit, n_shots)
    def verify_reproducibility(self, circuit: QuantumCircuit, n_runs: int = 3) -> bool:
        results = []
        for _ in range(n_runs):
            r = self.execute(circuit)
            state = r["quantum_state"]
            results.append([a.re for a in state.amplitudes])
        for i in range(1, len(results)):
            for j in range(len(results[0])):
                if abs(results[0][j] - results[i][j]) > 1e-10:
                    return False
        return True
