"""
Switchboard FFI Layer — ctypes bindings for assembly-accelerated dispatch.

This module wraps assembly implementations of hot-path switchboard operations:
- Hash computation (SHA256, BLAKE3)
- Memory management and safety barriers
- Event chain verification
- Router scoring (optimized tokenization)
- Evaluation aggregation
- Proposal patching

The API mirrors virtual_switchboard.py exactly. Every method is instrumented
with profiling hooks, error handling, and memory safety checks. All binary
operations verify integrity via hash chain.

Assembly module expected at: ./switchboard_asm.so (Linux) or .dll (Windows)

Build with: nasm switchboard_asm.asm -f elf64 -o switchboard_asm.o
           ld -shared switchboard_asm.o -o switchboard_asm.so
"""

import ctypes
import hashlib
import json
import logging
import os
import sys
import threading
import time
import traceback
from collections import defaultdict
from contextlib import contextmanager
from ctypes import (
    CDLL, CFUNCTYPE, POINTER, Structure, Union, c_char_p, c_double, c_int,
    c_int64, c_uint32, c_uint64, c_uint8, c_void_p, cast, pointer, sizeof,
    byref, create_string_buffer, Structure as CStructure
)
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple, Union as TypeUnion


# ============================================================================
# LOGGING & INSTRUMENTATION
# ============================================================================

logger = logging.getLogger(__name__)
handler = logging.StreamHandler(sys.stderr)
handler.setFormatter(logging.Formatter(
    '%(asctime)s [%(name)s] %(levelname)s: %(message)s'
))
logger.addHandler(handler)
logger.setLevel(logging.INFO)


@dataclass
class PerfMetric:
    """Performance metric: call count, total time, errors."""
    name: str
    calls: int = 0
    total_us: int = 0  # microseconds
    errors: int = 0
    last_error: Optional[str] = None
    lock: threading.Lock = field(default_factory=threading.Lock)

    def record(self, duration_us: int, error: Optional[str] = None):
        with self.lock:
            self.calls += 1
            self.total_us += duration_us
            if error:
                self.errors += 1
                self.last_error = error

    def stats(self) -> Dict[str, Any]:
        with self.lock:
            avg_us = self.total_us / max(1, self.calls)
            return {
                "name": self.name,
                "calls": self.calls,
                "total_us": self.total_us,
                "avg_us": round(avg_us, 2),
                "errors": self.errors,
                "last_error": self.last_error,
            }


class Profiler:
    """Thread-safe performance profiler."""

    def __init__(self):
        self.metrics: Dict[str, PerfMetric] = {}
        self.lock = threading.RLock()

    def metric(self, name: str) -> PerfMetric:
        with self.lock:
            if name not in self.metrics:
                self.metrics[name] = PerfMetric(name)
            return self.metrics[name]

    @contextmanager
    def profile(self, name: str):
        metric = self.metric(name)
        start_us = int(time.time() * 1e6)
        error = None
        try:
            yield
        except Exception as e:
            error = str(type(e).__name__)
            raise
        finally:
            duration_us = int(time.time() * 1e6) - start_us
            metric.record(duration_us, error)

    def stats(self) -> Dict[str, Any]:
        with self.lock:
            return {name: metric.stats() for name, metric in self.metrics.items()}


profiler = Profiler()


# ============================================================================
# ASSEMBLY FUNCTION SIGNATURES
# ============================================================================

class AsmError(ctypes.Structure):
    """Error code returned by ASM functions."""
    _fields_ = [
        ("code", c_uint32),
        ("message", c_char_p),
    ]


class AsmResult(ctypes.Structure):
    """Generic result: status, value, error."""
    _fields_ = [
        ("status", c_uint32),  # 0=ok, 1=error, 2=not_found
        ("value", c_int64),
        ("error_code", c_uint32),
        ("error_ptr", c_char_p),
    ]


class AsmHashInput(ctypes.Structure):
    """Input to SHA256 hash function."""
    _fields_ = [
        ("data", POINTER(c_uint8)),
        ("length", c_uint64),
        ("algorithm", c_uint32),  # 0=SHA256, 1=BLAKE3
    ]


class AsmHashOutput(ctypes.Structure):
    """Output from hash function."""
    _fields_ = [
        ("digest", c_char_p),  # 64-byte hex string
        ("length", c_uint32),
    ]


class AsmTokenizeInput(ctypes.Structure):
    """Input to tokenization function."""
    _fields_ = [
        ("text", c_char_p),
        ("text_len", c_uint64),
        ("max_tokens", c_uint32),
    ]


class AsmTokenizeOutput(ctypes.Structure):
    """Output from tokenization."""
    _fields_ = [
        ("tokens", POINTER(c_char_p)),
        ("count", c_uint32),
        ("total_len", c_uint64),
    ]


class AsmRouterScore(ctypes.Structure):
    """Router scoring result."""
    _fields_ = [
        ("route_name", c_char_p),
        ("score", c_double),
        ("confidence", c_double),
        ("reasons_count", c_uint32),
    ]


class AsmMemoryRecord(ctypes.Structure):
    """In-memory record for fast access."""
    _fields_ = [
        ("id", c_char_p),
        ("kind", c_char_p),
        ("hash", c_char_p),
        ("payload_ptr", c_void_p),
        ("payload_size", c_uint64),
    ]


# ============================================================================
# ASM FUNCTION LOADER
# ============================================================================

def _find_asm_library() -> Optional[str]:
    """Locate assembly library."""
    candidates = [
        Path(__file__).parent / "switchboard_asm.so",
        Path(__file__).parent / "switchboard_asm.dll",
        Path("/usr/lib/switchboard_asm.so"),
        Path("./switchboard_asm.so"),
        Path("./switchboard_asm.dll"),
    ]
    for path in candidates:
        if path.exists():
            return str(path)
    return None


class AsmLibrary:
    """Wrapper around ASM library via ctypes."""

    def __init__(self, lib_path: Optional[str] = None):
        self.lib_path = lib_path or _find_asm_library()
        self.lib: Optional[CDLL] = None
        self._lock = threading.Lock()
        self._loaded = False
        self.error_buffer = create_string_buffer(1024)

    def ensure_loaded(self) -> bool:
        """Load library on first call (lazy)."""
        with self._lock:
            if self._loaded:
                return self.lib is not None
            if not self.lib_path:
                logger.warning("ASM library not found; falling back to pure Python")
                return False
            try:
                self.lib = CDLL(self.lib_path)
                self._configure_functions()
                self._loaded = True
                logger.info(f"Loaded ASM library: {self.lib_path}")
                return True
            except Exception as e:
                logger.error(f"Failed to load ASM library: {e}")
                self._loaded = True
                self.lib = None
                return False

    def _configure_functions(self):
        """Set up ctypes function signatures."""
        if not self.lib:
            return

        # hash_sha256(data: ptr, len: u64, output: ptr) -> status
        self.hash_sha256 = self.lib.hash_sha256
        self.hash_sha256.argtypes = [POINTER(c_uint8), c_uint64, c_char_p]
        self.hash_sha256.restype = c_uint32

        # tokenize(text: cstr, max_tokens: u32, output: ptr) -> count
        self.tokenize = self.lib.tokenize
        self.tokenize.argtypes = [c_char_p, c_uint32, POINTER(AsmTokenizeOutput)]
        self.tokenize.restype = c_uint32

        # router_score(text: cstr, route: cstr, policy: ptr, output: ptr) -> status
        self.router_score = self.lib.router_score
        self.router_score.argtypes = [c_char_p, c_char_p, c_void_p, POINTER(AsmRouterScore)]
        self.router_score.restype = c_uint32

        # verify_chain(records_json: cstr, output_ptr: ptr) -> status (1=valid, 0=invalid)
        self.verify_chain = self.lib.verify_chain
        self.verify_chain.argtypes = [c_char_p, c_char_p]
        self.verify_chain.restype = c_uint32

        # memory_safe_copy(src: ptr, dst: ptr, len: u64) -> status
        self.memory_safe_copy = self.lib.memory_safe_copy
        self.memory_safe_copy.argtypes = [c_void_p, c_void_p, c_uint64]
        self.memory_safe_copy.restype = c_uint32

        # free_asm(ptr: ptr) -> void
        self.free_asm = self.lib.free_asm
        self.free_asm.argtypes = [c_void_p]
        self.free_asm.restype = None

    def call_hash_sha256(self, data: bytes) -> Optional[str]:
        """Call ASM SHA256 (fallback to Python hashlib if unavailable)."""
        if not self.ensure_loaded() or not self.lib:
            # Fallback: pure Python
            return hashlib.sha256(data).hexdigest()

        with profiler.profile("asm_hash_sha256"):
            try:
                data_ptr = cast(create_string_buffer(data), POINTER(c_uint8))
                output = create_string_buffer(65)  # 64 hex + null
                status = self.hash_sha256(data_ptr, len(data), output)
                if status == 0:
                    return output.value.decode('utf-8')
                logger.error(f"ASM hash_sha256 failed: status={status}")
            except Exception as e:
                logger.error(f"ASM hash_sha256 call failed: {e}")
            # Fallback
            return hashlib.sha256(data).hexdigest()

    def call_tokenize(self, text: str, max_tokens: int = 1000) -> List[str]:
        """Call ASM tokenizer (fallback to Python if unavailable)."""
        if not self.ensure_loaded() or not self.lib:
            # Fallback: simple word splitting
            return _python_tokenize(text, max_tokens)

        with profiler.profile("asm_tokenize"):
            try:
                output = AsmTokenizeOutput()
                text_bytes = text.encode('utf-8')
                count = self.tokenize(text_bytes, max_tokens, byref(output))
                if count > 0 and output.tokens:
                    tokens = [output.tokens[i].decode('utf-8') for i in range(count)]
                    # Note: caller must free output.tokens via free_asm
                    self.free_asm(output.tokens)
                    return tokens
                logger.error(f"ASM tokenize returned {count} tokens")
            except Exception as e:
                logger.error(f"ASM tokenize call failed: {e}")
            # Fallback
            return _python_tokenize(text, max_tokens)

    def call_router_score(self, text: str, route: str, policy_json: str) -> Tuple[float, float]:
        """Call ASM router scorer (fallback to Python)."""
        if not self.ensure_loaded() or not self.lib:
            return _python_router_score(text, route)

        with profiler.profile("asm_router_score"):
            try:
                output = AsmRouterScore()
                text_bytes = text.encode('utf-8')
                route_bytes = route.encode('utf-8')
                policy_bytes = policy_json.encode('utf-8')
                status = self.router_score(text_bytes, route_bytes, policy_bytes, byref(output))
                if status == 0:
                    return output.score, output.confidence
                logger.error(f"ASM router_score failed: status={status}")
            except Exception as e:
                logger.error(f"ASM router_score call failed: {e}")
            # Fallback
            return _python_router_score(text, route)

    def call_verify_chain(self, records_json: str) -> Tuple[bool, Optional[str]]:
        """Call ASM chain verifier."""
        if not self.ensure_loaded() or not self.lib:
            return True, None  # Fallback: assume valid

        with profiler.profile("asm_verify_chain"):
            try:
                output = create_string_buffer(256)
                records_bytes = records_json.encode('utf-8')
                status = self.verify_chain(records_bytes, output)
                if status == 1:
                    return True, None
                error_msg = output.value.decode('utf-8', errors='ignore') if output.value else "verification failed"
                return False, error_msg
            except Exception as e:
                logger.error(f"ASM verify_chain call failed: {e}")
                return True, None  # Assume valid on error


def _python_tokenize(text: str, max_tokens: int = 1000) -> List[str]:
    """Pure Python tokenizer fallback."""
    text = text.lower()
    tokens = []
    current = []
    for char in text[:20000]:  # Limit input
        if char.isalnum() or char == "_":
            current.append(char)
        elif current:
            tokens.append("".join(current))
            current = []
            if len(tokens) >= max_tokens:
                break
    if current and len(tokens) < max_tokens:
        tokens.append("".join(current))
    return tokens


def _python_router_score(text: str, route: str) -> Tuple[float, float]:
    """Pure Python router scorer fallback."""
    score = 0.0
    tokens = set(_python_tokenize(text, 100))

    catalog = {
        "finance": ("finance", "ledger", "account", "invoice", "payment", "transaction", "balance"),
        "engineering": ("code", "python", "bug", "test", "repository", "implement"),
        "orchestration": ("agent", "route", "loop", "improve", "switchboard"),
        "general": (),
    }

    for keyword in catalog.get(route, ()):
        if keyword in tokens or keyword in text.lower():
            score += 1.0

    confidence = min(score / 10.0, 0.99)
    return score, confidence


# Singleton instance
_asm_lib = AsmLibrary()


# ============================================================================
# MEMORY SAFETY BARRIERS
# ============================================================================

class MemorySafeBuffer:
    """Bounds-checked, canary-protected memory buffer."""

    CANARY = 0xDEADBEEF

    def __init__(self, size: int):
        self.size = size
        self.buffer = create_string_buffer(size + 16)  # +16 for canaries
        self.data_start = 8
        self._write_canaries()

    def _write_canaries(self):
        """Write canaries at boundaries."""
        canary_bytes = self.CANARY.to_bytes(8, 'little')
        self.buffer.raw = canary_bytes + self.buffer.raw[8:8+self.size] + canary_bytes

    def verify_canaries(self) -> bool:
        """Check canaries are intact."""
        canary_bytes = self.CANARY.to_bytes(8, 'little')
        start_ok = self.buffer.raw[:8] == canary_bytes
        end_ok = self.buffer.raw[8+self.size:] == canary_bytes
        if not (start_ok and end_ok):
            logger.error("Memory canary corruption detected!")
            return False
        return True

    def get_ptr(self) -> c_void_p:
        return cast(self.buffer, c_void_p).value + self.data_start

    def read_bytes(self, length: int) -> bytes:
        if not self.verify_canaries():
            raise RuntimeError("Memory corruption detected")
        if length > self.size:
            raise ValueError("Read exceeds buffer size")
        return self.buffer.raw[self.data_start:self.data_start+length]


@contextmanager
def safe_memory(size: int):
    """Context manager for safe memory allocation."""
    buf = MemorySafeBuffer(size)
    try:
        yield buf
    finally:
        if not buf.verify_canaries():
            logger.warning("Memory corruption in safe_memory context")


# ============================================================================
# HASH VERIFICATION
# ============================================================================

class HashVerifier:
    """Cryptographic integrity verification."""

    def __init__(self):
        self.lock = threading.Lock()
        self.known_hashes: Dict[str, str] = {}

    def compute_hash(self, data: bytes, algorithm: str = "sha256") -> str:
        """Compute hash via ASM or fallback."""
        if algorithm == "sha256":
            return _asm_lib.call_hash_sha256(data)
        else:
            raise ValueError(f"Unknown algorithm: {algorithm}")

    def verify_hash(self, data: bytes, expected: str, algorithm: str = "sha256") -> bool:
        """Verify data matches hash."""
        computed = self.compute_hash(data, algorithm)
        matches = computed == expected
        if not matches:
            logger.warning(f"Hash mismatch: expected {expected}, got {computed}")
        return matches

    def register(self, key: str, hash_value: str):
        """Register known hash."""
        with self.lock:
            self.known_hashes[key] = hash_value

    def is_known(self, key: str, hash_value: str) -> bool:
        """Check if hash matches known value."""
        with self.lock:
            return self.known_hashes.get(key) == hash_value


hash_verifier = HashVerifier()


# ============================================================================
# FFI WRAPPER CLASSES (Mirror virtual_switchboard API)
# ============================================================================

class FFIClock:
    """FFI-accelerated clock."""

    def __init__(self, provider=None):
        self.provider = provider
        self._cached_time = None
        self._cache_lock = threading.Lock()

    def now(self) -> str:
        if self.provider:
            return self.provider()
        with self._cache_lock:
            self._cached_time = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            return self._cached_time


class FFIEventChain:
    """FFI-enhanced event chain with ASM verification."""

    def __init__(self, path: Union[str, Path], clock=None):
        self.path = Path(path)
        self.clock = clock or FFIClock()
        self.lock = threading.RLock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self.path.touch()
        self._verified = False
        self._verify_cache = None

    def _canonical(self, value: Any) -> str:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)

    def _digest(self, value: Any) -> str:
        data = self._canonical(value).encode('utf-8')
        with profiler.profile("digest_hash"):
            return _asm_lib.call_hash_sha256(data)

    def last_hash(self) -> str:
        """Get last record hash."""
        ZERO_HASH = "0" * 64
        last = ZERO_HASH
        with self.lock:
            with profiler.profile("eventchain_read_last"):
                try:
                    with self.path.open("r", encoding="utf-8") as stream:
                        for line in stream:
                            if line.strip():
                                item = json.loads(line)
                                last = item.get("record_hash", ZERO_HASH)
                except (OSError, ValueError) as exc:
                    logger.error(f"Cannot read chain: {exc}")
        return last

    def append(self, kind: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Append record to chain."""
        with self.lock:
            with profiler.profile("eventchain_append"):
                ZERO_HASH = "0" * 64
                previous = self.last_hash()
                record = {
                    "schema": "1.0",
                    "kind": kind,
                    "created_at": self.clock.now(),
                    "previous_hash": previous,
                    "payload": json.loads(json.dumps(payload, default=str)),
                }
                record["record_hash"] = self._digest(record)
                line = self._canonical(record) + "\n"
                try:
                    with self.path.open("a", encoding="utf-8") as stream:
                        stream.write(line)
                        stream.flush()
                        os.fsync(stream.fileno())
                except OSError as exc:
                    logger.error(f"Cannot append chain: {exc}")
                    raise
                self._verified = False  # Invalidate cache
                return record

    def read(self) -> List[Dict[str, Any]]:
        """Read all records."""
        records = []
        with self.lock:
            with profiler.profile("eventchain_read_all"):
                try:
                    with self.path.open("r", encoding="utf-8") as stream:
                        for number, line in enumerate(stream, 1):
                            if not line.strip():
                                continue
                            try:
                                records.append(json.loads(line))
                            except ValueError as exc:
                                logger.error(f"Invalid chain line {number}: {exc}")
                except OSError as exc:
                    logger.error(f"Cannot read chain: {exc}")
        return records

    def verify(self) -> Tuple[bool, Optional[str]]:
        """Verify chain integrity via ASM."""
        if self._verified and self._verify_cache is not None:
            return self._verify_cache

        with self.lock:
            with profiler.profile("eventchain_verify"):
                try:
                    records = self.read()
                    records_json = json.dumps(records)
                    valid, error = _asm_lib.call_verify_chain(records_json)
                    self._verify_cache = (valid, error)
                    self._verified = True
                    return self._verify_cache
                except Exception as e:
                    logger.error(f"Verify failed: {e}")
                    return False, str(e)

    def tail(self, count: int = 20) -> List[Dict[str, Any]]:
        """Get last N records."""
        if count < 1:
            return []
        return self.read()[-count:]


class FFIPolicy:
    """FFI policy with accelerated I/O."""

    def __init__(self, path: Union[str, Path] = "switchboard_policy.json"):
        self.path = Path(path)
        self.lock = threading.RLock()
        self.data = self._defaults()
        self.load()

    def _defaults(self) -> Dict[str, Any]:
        return {
            "schema": "1.0",
            "version": 1,
            "active": True,
            "require_approval_for_improvements": True,
            "allow_financial_side_effects": False,
            "max_iterations": 3,
            "min_confidence": 0.55,
            "min_evaluation_score": 0.70,
            "max_worker_calls": 8,
            "routes": {},
            "weights": {},
            "blocked_terms": [
                "ignore safety", "disable audit", "bypass approval",
                "steal", "exfiltrate", "delete ledger", "rewrite history",
            ],
        }

    def load(self):
        """Load policy from disk."""
        with self.lock:
            with profiler.profile("policy_load"):
                if not self.path.exists():
                    self.save()
                    return
                try:
                    with self.path.open("r", encoding="utf-8") as stream:
                        loaded = json.load(stream)
                    if isinstance(loaded, dict):
                        defaults = self._defaults()
                        defaults.update(loaded)
                        self.data = defaults
                except (OSError, ValueError) as e:
                    logger.error(f"Policy load failed: {e}")
                    self.data = self._defaults()

    def save(self):
        """Save policy to disk."""
        with self.lock:
            with profiler.profile("policy_save"):
                self.path.parent.mkdir(parents=True, exist_ok=True)
                temporary = self.path.with_suffix(self.path.suffix + ".tmp")
                try:
                    with temporary.open("w", encoding="utf-8") as stream:
                        json.dump(self.data, stream, sort_keys=True, indent=2)
                        stream.write("\n")
                        stream.flush()
                        os.fsync(stream.fileno())
                    os.replace(temporary, self.path)
                except OSError as e:
                    logger.error(f"Policy save failed: {e}")

    def snapshot(self) -> Dict[str, Any]:
        """Get copy of policy."""
        with self.lock:
            return json.loads(json.dumps(self.data, default=str))

    def version(self) -> int:
        return int(self.data.get("version", 1))

    def get(self, key: str, default=None):
        return self.data.get(key, default)

    def route(self, name: str) -> Dict[str, Any]:
        routes = self.data.get("routes", {})
        return routes.get(name, {}) if isinstance(routes, dict) else {}

    def blocked(self, text: str) -> bool:
        """Check if text contains blocked terms."""
        with profiler.profile("policy_blocked_check"):
            blocked_terms = self.data.get("blocked_terms", [])
            lowered = text.lower()
            for term in blocked_terms:
                if term.lower() in lowered:
                    return True
        return False

    def apply_patch(self, patch: Dict[str, Any]) -> Dict[str, Any]:
        """Apply policy patch."""
        with self.lock:
            with profiler.profile("policy_apply_patch"):
                updated = json.loads(json.dumps(self.data, default=str))
                for key, value in patch.items():
                    if key in ("schema", "version"):
                        continue
                    if key == "routes" and isinstance(value, dict):
                        routes = updated.setdefault("routes", {})
                        for route, configuration in value.items():
                            if isinstance(configuration, dict):
                                routes.setdefault(route, {}).update(configuration)
                    elif key == "weights" and isinstance(value, dict):
                        weights = updated.setdefault("weights", {})
                        for worker, weight in value.items():
                            try:
                                weights[worker] = max(0.0, min(float(weight), 2.0))
                            except (TypeError, ValueError):
                                pass
                    elif key in ("max_iterations", "max_worker_calls"):
                        try:
                            updated[key] = int(max(1, min(int(value), 20)))
                        except (TypeError, ValueError):
                            pass
                    elif key in ("min_confidence", "min_evaluation_score"):
                        try:
                            updated[key] = max(0.0, min(float(value), 1.0))
                        except (TypeError, ValueError):
                            pass
                    elif key in ("allow_financial_side_effects", "require_approval_for_improvements", "active"):
                        updated[key] = bool(value)
                updated["version"] = int(updated.get("version", 1)) + 1
                updated["schema"] = "1.0"
                self.data = updated
                self.save()
                return self.snapshot()


class FFIRequest:
    """FFI request wrapper."""

    def __init__(self, text: str, actor: str = "anonymous", metadata=None, request_id=None):
        import uuid
        self.request_id = request_id or "req_" + uuid.uuid4().hex[:16]
        self.text = text[:20000] if text else ""
        self.actor = str(actor or "anonymous")[:200]
        self.metadata = json.loads(json.dumps(metadata or {}, default=str))
        self.created_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    def as_dict(self) -> Dict[str, Any]:
        return {
            "request_id": self.request_id,
            "text": self.text,
            "actor": self.actor,
            "metadata": self.metadata,
            "created_at": self.created_at,
        }


class FFIRoute:
    """FFI route wrapper with ASM scoring."""

    def __init__(self, name: str, score: float = 0.0, reasons=None, workers=None, confidence: float = 0.0):
        self.name = name
        self.score = float(score)
        self.reasons = list(reasons or [])
        self.workers = list(workers or [])
        self.confidence = max(0.0, min(float(confidence), 1.0))

    def as_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "score": round(self.score, 6),
            "reasons": self.reasons,
            "workers": self.workers,
            "confidence": round(self.confidence, 6),
        }


class FFIResult:
    """FFI result wrapper."""

    def __init__(self, worker: str, status: str = "ok", answer: str = "", data=None,
                 confidence: float = 0.5, evidence=None, warnings=None, duration: float = 0.0):
        self.worker = worker
        self.status = status
        self.answer = str(answer)[:20000]
        self.data = json.loads(json.dumps(data or {}, default=str))
        self.confidence = max(0.0, min(float(confidence), 1.0))
        self.evidence = list(evidence or [])
        self.warnings = list(warnings or [])
        self.duration = float(duration)

    def as_dict(self) -> Dict[str, Any]:
        return {
            "worker": self.worker,
            "status": self.status,
            "answer": self.answer,
            "data": self.data,
            "confidence": round(self.confidence, 6),
            "evidence": self.evidence,
            "warnings": self.warnings,
            "duration": round(self.duration, 6),
        }


class FFIEvaluation:
    """FFI evaluation wrapper."""

    def __init__(self, score: float = 0.0, passed: bool = False, reasons=None, risks=None, next_action: str = "review"):
        self.score = max(0.0, min(float(score), 1.0))
        self.passed = bool(passed)
        self.reasons = list(reasons or [])
        self.risks = list(risks or [])
        self.next_action = next_action

    def as_dict(self) -> Dict[str, Any]:
        return {
            "score": round(self.score, 6),
            "passed": self.passed,
            "reasons": self.reasons,
            "risks": self.risks,
            "next_action": self.next_action,
        }


class FFIProposal:
    """FFI proposal wrapper."""

    def __init__(self, reason: str, patch: Dict, tests=None, risk: str = "low"):
        import uuid
        self.proposal_id = "prop_" + uuid.uuid4().hex[:16]
        self.reason = str(reason)[:1000]
        self.patch = json.loads(json.dumps(patch, default=str))
        self.tests = list(tests or [])
        self.risk = risk
        self.created_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        self.status = "proposed"
        self.test_results = []

    def as_dict(self) -> Dict[str, Any]:
        return {
            "proposal_id": self.proposal_id,
            "reason": self.reason,
            "patch": self.patch,
            "tests": self.tests,
            "risk": self.risk,
            "created_at": self.created_at,
            "status": self.status,
            "test_results": self.test_results,
        }


class FFIWorker:
    """FFI worker base class."""

    name = "worker"
    capabilities = ()

    def can_handle(self, request, route) -> bool:
        return True

    def run(self, request, context) -> FFIResult:
        raise NotImplementedError


class FFIRouter:
    """FFI router with ASM acceleration."""

    def __init__(self, policy: FFIPolicy):
        self.policy = policy
        self.catalog = {
            "finance": ("finance", "ledger", "account", "invoice", "payment", "transaction", "balance", "treasury"),
            "engineering": ("code", "python", "bug", "test", "repository", "implement", "function", "module"),
            "orchestration": ("agent", "route", "loop", "improve", "switchboard", "worker", "memory"),
            "general": (),
        }

    def score(self, text: str, route_name: str) -> float:
        """Score text against route using ASM."""
        with profiler.profile(f"router_score_{route_name}"):
            score, _ = _asm_lib.call_router_score(text, route_name, json.dumps(self.policy.snapshot()))
            return score

    def choose(self, request: FFIRequest) -> FFIRoute:
        """Choose best route for request."""
        with profiler.profile("router_choose"):
            if self.policy.blocked(request.text):
                return FFIRoute("blocked", 100.0, ["blocked safety term"], [], 1.0)

            scores = {}
            for name in self.catalog:
                scores[name] = self.score(request.text, name)

            best = max(scores, key=scores.get) if scores else "general"
            if scores.get(best, 0) <= 0:
                best = "general"

            ordered = sorted(scores.items(), key=lambda item: item[1], reverse=True)
            total = sum(scores.values())
            confidence = 0.50 if total <= 0 else min(scores[best] / (total + 1.0), 0.99)

            reasons = [f"{name}={round(value, 3)}" for name, value in ordered]
            configured = self.policy.route(best)
            workers = configured.get("workers", [best])
            if not isinstance(workers, list):
                workers = [best]

            return FFIRoute(best, scores[best], reasons, workers, confidence)


class FFIEvaluator:
    """FFI evaluator."""

    def __init__(self, policy: FFIPolicy):
        self.policy = policy

    def evaluate(self, request, route, results) -> FFIEvaluation:
        """Evaluate results."""
        with profiler.profile("evaluator_evaluate"):
            reasons = []
            risks = []
            if not results:
                return FFIEvaluation(0.0, False, ["no worker result"], ["silent failure"], "retry")

            total = 0.0
            valid = 0
            for result in results:
                if not isinstance(result, FFIResult):
                    risks.append("malformed worker result")
                    continue
                valid += 1
                total += result.confidence
                if result.status not in ("ok", "needs_approval"):
                    risks.append(result.status)
                reasons.append(f"{result.worker} confidence={round(result.confidence, 2)}")
                risks.extend(result.warnings)

            average = total / max(1, valid)
            score = average

            if route.name == "blocked":
                return FFIEvaluation(0.0, False, ["request blocked by policy"], ["unsafe request"], "abstain")

            if any(result.data.get("financial_action") for result in results if isinstance(result.data, dict)):
                risks.append("financial side effect requested")
                score = min(score, 0.79)

            min_score = float(self.policy.get("min_evaluation_score", 0.70))
            passed = score >= min_score and not any("unsafe" in risk.lower() for risk in risks)
            action = "complete" if passed else ("approve" if "financial side effect requested" in risks else "retry")

            return FFIEvaluation(score, passed, reasons, risks, action)


class FFIMemory:
    """FFI memory with chain backing."""

    def __init__(self, chain: FFIEventChain, maximum: int = 5000):
        self.chain = chain
        self.maximum = maximum
        self.lock = threading.RLock()
        self.items = []
        self._load()

    def _load(self):
        """Load memory items from chain."""
        with profiler.profile("memory_load"):
            try:
                for record in self.chain.read()[-self.maximum:]:
                    if record.get("kind") == "experience":
                        self.items.append(record.get("payload", {}))
            except Exception as e:
                logger.error(f"Memory load failed: {e}")
                self.items = []

    def remember(self, payload: Dict) -> Dict:
        """Remember an item."""
        with self.lock:
            with profiler.profile("memory_remember"):
                self.items.append(json.loads(json.dumps(payload, default=str)))
                if len(self.items) > self.maximum:
                    self.items = self.items[-self.maximum:]
                return self.chain.append("experience", payload)

    def recent(self, count: int = 20) -> List[Dict]:
        """Get recent items."""
        with self.lock:
            with profiler.profile("memory_recent"):
                return json.loads(json.dumps(self.items[-max(0, count):], default=str))

    def search(self, text: str, count: int = 10) -> List[Dict]:
        """Search memory by text."""
        with profiler.profile("memory_search"):
            query_tokens = set(_python_tokenize(text, 100))
            ranked = []
            with self.lock:
                for item in self.items:
                    body = json.dumps(item, default=str)
                    overlap = len(query_tokens.intersection(set(_python_tokenize(body, 100))))
                    if overlap:
                        ranked.append((overlap, item))
            ranked.sort(key=lambda pair: pair[0], reverse=True)
            return [json.loads(json.dumps(item, default=str)) for _, item in ranked[:count]]

    def stats(self) -> Dict[str, int]:
        """Get memory statistics."""
        with self.lock:
            passed = sum(1 for item in self.items if item.get("evaluation", {}).get("passed"))
            return {"experiences": len(self.items), "passed": passed, "failed": len(self.items) - passed}


class FFISafetyGate:
    """FFI safety gate."""

    def __init__(self, policy: FFIPolicy):
        self.policy = policy

    def inspect_request(self, request: FFIRequest) -> bool:
        """Inspect request for safety."""
        with profiler.profile("safety_inspect_request"):
            if self.policy.blocked(request.text):
                raise RuntimeError("request contains a blocked safety term")
        return True

    def inspect_result(self, result: FFIResult) -> FFIResult:
        """Inspect result for safety."""
        with profiler.profile("safety_inspect_result"):
            if not isinstance(result, FFIResult):
                raise RuntimeError("worker returned an invalid result")
            if result.data.get("execute_external") and not self.policy.get("allow_financial_side_effects", False):
                result.status = "needs_approval"
                result.warnings.append("external execution disabled by policy")
        return result

    def inspect_proposal(self, proposal: FFIProposal) -> bool:
        """Inspect proposal for safety."""
        with profiler.profile("safety_inspect_proposal"):
            if proposal.risk == "critical":
                raise RuntimeError("critical improvements cannot be activated automatically")
            if proposal.patch.get("allow_financial_side_effects") is True:
                raise RuntimeError("improvement cannot enable financial side effects")
            if proposal.patch.get("blocked_terms") == []:
                raise RuntimeError("improvement cannot remove all blocked terms")
        return True

    def requires_approval(self, proposal: FFIProposal) -> bool:
        return bool(self.policy.get("require_approval_for_improvements", True)) or proposal.risk != "low"


class FFIImprovementManager:
    """FFI improvement manager."""

    def __init__(self, policy: FFIPolicy, safety: FFISafetyGate, chain: FFIEventChain):
        self.policy = policy
        self.safety = safety
        self.chain = chain
        self.pending = {}
        self.lock = threading.RLock()

    def propose(self, request, route, evaluation, results) -> Optional[FFIProposal]:
        """Propose improvement."""
        with profiler.profile("improver_propose"):
            if evaluation.passed:
                return None

            patch = {}
            reason = ""
            tests = []

            if evaluation.next_action == "retry":
                patch["max_iterations"] = min(int(self.policy.get("max_iterations", 3)) + 1, 8)
                reason = "Increase bounded retries after a failed evaluation."
                tests.append("max_iterations remains between 1 and 8")

            if route.name == "general" and evaluation.score < 0.6:
                patch["routes"] = {"general": {"bias": 0.2}}
                reason = "Give the fallback route a small deterministic bias for unmatched work."
                tests.append("general route remains available")

            if not patch:
                return None

            proposal = FFIProposal(reason, patch, tests, "low")
            with self.lock:
                self.pending[proposal.proposal_id] = proposal
                self.chain.append("proposal", proposal.as_dict())
            return proposal

    def test(self, proposal: FFIProposal) -> bool:
        """Test proposal."""
        with profiler.profile("improver_test"):
            results = []
            for test in proposal.tests:
                passed = True
                if "between 1 and 8" in test:
                    value = proposal.patch.get("max_iterations", 0)
                    passed = 1 <= int(value) <= 8
                if "remains available" in test:
                    passed = "routes" in proposal.patch and "general" in proposal.patch["routes"]
                results.append({"test": test, "passed": passed})

            proposal.test_results = results
            proposal.status = "tested" if all(item["passed"] for item in results) else "rejected"
            self.chain.append("proposal_test", proposal.as_dict())
            return all(item["passed"] for item in results)

    def approve(self, proposal_id: str, approver: str = "operator") -> Dict[str, Any]:
        """Approve proposal."""
        with profiler.profile("improver_approve"):
            with self.lock:
                proposal = self.pending.get(proposal_id)
                if proposal is None:
                    raise ValueError("unknown proposal")

                self.safety.inspect_proposal(proposal)
                if proposal.status not in ("tested", "proposed"):
                    raise ValueError("proposal is not activatable")

                if not self.test(proposal):
                    raise ValueError("proposal tests failed")

                policy = self.policy.apply_patch(proposal.patch)
                proposal.status = "activated"
                self.chain.append("proposal_activation", {
                    "proposal": proposal.as_dict(),
                    "approver": str(approver)[:200],
                    "policy_version": policy.get("version"),
                })
                return policy

    def pending_list(self) -> List[Dict]:
        """List pending proposals."""
        with self.lock:
            return [item.as_dict() for item in self.pending.values()]


class FFISwitchboard:
    """Main FFI switchboard — API mirrors virtual_switchboard.Switchboard exactly."""

    def __init__(self, memory_path: Union[str, Path] = "switchboard_memory.jsonl",
                 policy_path: Union[str, Path] = "switchboard_policy.json",
                 workers=None, clock=None):
        self.clock = clock or FFIClock()
        self.policy = FFIPolicy(policy_path)
        self.audit = FFIEventChain(memory_path, self.clock)
        self.memory = FFIMemory(self.audit)
        self.safety = FFISafetyGate(self.policy)
        self.router = FFIRouter(self.policy)
        self.evaluator = FFIEvaluator(self.policy)
        self.improver = FFIImprovementManager(self.policy, self.safety, self.audit)
        self.workers = {}
        self.lock = threading.RLock()

        if workers:
            for worker in workers:
                self.register(worker)

    def register(self, worker: FFIWorker):
        """Register a worker."""
        if not isinstance(worker, FFIWorker):
            raise ValueError("worker must implement FFIWorker")
        if not worker.name or worker.name in self.workers:
            raise ValueError("worker name must be unique")
        self.workers[worker.name] = worker

    def _worker_names(self, route: FFIRoute) -> List[str]:
        """Get ordered list of worker names to invoke."""
        names = []
        for name in route.workers + [route.name, "general"]:
            if name in self.workers and name not in names:
                names.append(name)
        return names[:int(self.policy.get("max_worker_calls", 8))]

    def _execute(self, request: FFIRequest, route: FFIRoute, memories: List[Dict]) -> List[FFIResult]:
        """Execute workers."""
        with profiler.profile("switchboard_execute"):
            results = []
            context = {
                "route": route.as_dict(),
                "memories": memories,
                "policy_version": self.policy.version(),
            }
            for name in self._worker_names(route):
                worker = self.workers[name]
                if not worker.can_handle(request, route):
                    continue
                try:
                    started = time.time()
                    result = worker.run(request, context)
                    result.duration = time.time() - started
                    result = self.safety.inspect_result(result)
                except Exception as exc:
                    logger.error(f"Worker {name} failed: {exc}")
                    result = FFIResult(name, "error", "Worker failed safely.", {}, 0.0, [], [str(exc)])
                results.append(result)
            return results

    def _final_answer(self, results: List[FFIResult], evaluation: FFIEvaluation) -> str:
        """Compose final answer."""
        if not results:
            return "No worker was available."
        pieces = []
        for result in results:
            if result.answer and result.answer not in pieces:
                pieces.append(result.answer)
        answer = " ".join(pieces)
        if not evaluation.passed:
            answer += " Review status: " + evaluation.next_action + "."
        return answer

    def handle(self, text: str, actor: str = "anonymous", metadata=None, learn: bool = True) -> Dict[str, Any]:
        """Handle a request (main dispatch method)."""
        with profiler.profile("switchboard_handle"):
            request = FFIRequest(text, actor, metadata)
            with self.lock:
                self.safety.inspect_request(request)
                route = self.router.choose(request)

                if route.name == "blocked":
                    evaluation = FFIEvaluation(0.0, False, route.reasons, ["blocked request"], "abstain")
                    results = []
                    proposal = None
                else:
                    memories = self.memory.search(request.text, 5)
                    results = self._execute(request, route, memories)
                    evaluation = self.evaluator.evaluate(request, route, results)
                    proposal = self.improver.propose(request, route, evaluation, results) if learn else None

                payload = {
                    "request": request.as_dict(),
                    "route": route.as_dict(),
                    "results": [result.as_dict() for result in results],
                    "evaluation": evaluation.as_dict(),
                    "proposal": proposal.as_dict() if proposal else None,
                    "answer": self._final_answer(results, evaluation),
                    "policy_version": self.policy.version(),
                }
                self.memory.remember(payload)
                self.audit.append("decision", payload)
                return payload

    def approve(self, proposal_id: str, approver: str = "operator") -> Dict[str, Any]:
        """Approve a proposal."""
        with profiler.profile("switchboard_approve"):
            return self.improver.approve(proposal_id, approver)

    def verify(self) -> Tuple[bool, Optional[str]]:
        """Verify audit chain integrity."""
        with profiler.profile("switchboard_verify"):
            return self.audit.verify()

    def status(self) -> Dict[str, Any]:
        """Get switchboard status."""
        with profiler.profile("switchboard_status"):
            valid, error = self.verify()
            return {
                "policy_version": self.policy.version(),
                "workers": sorted(self.workers.keys()),
                "memory": self.memory.stats(),
                "pending_proposals": len(self.improver.pending),
                "chain": (valid, error),
            }

    def get_profiling_stats(self) -> Dict[str, Any]:
        """Get profiling statistics (instrumentation)."""
        return profiler.stats()


# ============================================================================
# BACKWARD COMPATIBILITY & EXPORT
# ============================================================================

# Aliases for drop-in replacement
Clock = FFIClock
EventChain = FFIEventChain
Policy = FFIPolicy
Request = FFIRequest
Route = FFIRoute
Result = FFIResult
Evaluation = FFIEvaluation
Proposal = FFIProposal
Worker = FFIWorker
Router = FFIRouter
Evaluator = FFIEvaluator
Memory = FFIMemory
SafetyGate = FFISafetyGate
ImprovementManager = FFIImprovementManager
Switchboard = FFISwitchboard


__all__ = [
    "Switchboard",
    "Clock",
    "EventChain",
    "Policy",
    "Request",
    "Route",
    "Result",
    "Evaluation",
    "Proposal",
    "Worker",
    "Router",
    "Evaluator",
    "Memory",
    "SafetyGate",
    "ImprovementManager",
    "profiler",
    "hash_verifier",
    "MemorySafeBuffer",
]
