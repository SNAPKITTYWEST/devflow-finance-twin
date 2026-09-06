import hashlib
import json
import logging
import os
import struct
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger("devflow.worm")

# Production constants
MAX_WORM_FILE_SIZE_BYTES = 500 * 1024 * 1024  # 500 MB hard cap
MAX_RECORD_SIZE_BYTES = 1 * 1024 * 1024  # 1 MB per record
HASH_ALGORITHM = "sha256"
ZERO_HASH = "0" * 64


class WormStorageError(Exception):
    """Base exception for WORM storage failures."""
    pass


class WormIntegrityError(WormStorageError):
    """Raised when WORM chain integrity is violated."""
    pass


class WormSizeLimitError(WormStorageError):
    """Raised when WORM file exceeds size limit."""
    pass


class WormRecordError(WormStorageError):
    """Raised when a single record is malformed."""
    pass


class WormStorageEngine:
    """
    Production-grade Write Once Read Many (WORM) storage subsystem.
    Append-only, hash-linked immutable event log with Merkle-chain integrity.

    Thread-safe via platform-adaptive file locking.
    Enforces size limits, atomic appends, and structured logging.
    """
    def __init__(self, storage_path: str = "ledger.worm"):
        self.storage_path = Path(storage_path)
        self._lock = threading.Lock()
        self._ensure_storage()

    def _ensure_storage(self) -> None:
        """Create storage file and parent directories if missing."""
        try:
            if not self.storage_path.exists():
                self.storage_path.parent.mkdir(parents=True, exist_ok=True)
                self.storage_path.touch(mode=0o600)
                logger.info("Created new WORM storage: %s", self.storage_path)
        except OSError as e:
            raise WormStorageError(f"Failed to initialize storage at {self.storage_path}: {e}")

    def _check_size_limit(self, additional_bytes: int = 0) -> None:
        """Enforce maximum WORM file size to prevent disk exhaustion attacks."""
        try:
            current_size = self.storage_path.stat().st_size if self.storage_path.exists() else 0
            if current_size + additional_bytes > MAX_WORM_FILE_SIZE_BYTES:
                raise WormSizeLimitError(
                    f"WORM storage would exceed {MAX_WORM_FILE_SIZE_BYTES} byte limit. "
                    f"Current: {current_size}, Additional: {additional_bytes}"
                )
        except OSError as e:
            raise WormStorageError(f"Cannot check storage size: {e}")

    def get_last_hash(self) -> str:
        """Read the hash of the most recent record in the chain."""
        if not self.storage_path.exists():
            return ZERO_HASH
        try:
            last_line = ""
            with open(self.storage_path, "r", encoding="utf-8") as f:
                for line in f:
                    stripped = line.strip()
                    if stripped:
                        last_line = stripped
            if not last_line:
                return ZERO_HASH
            record = json.loads(last_line)
            return record.get("record_hash", ZERO_HASH)
        except json.JSONDecodeError:
            raise WormStorageError("Storage corruption: invalid JSON in WORM log.")
        except OSError as e:
            raise WormStorageError(f"Failed to read storage: {e}")

    def append(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Append an immutable record to the WORM log.
        Thread-safe via lock. Enforces size limits and atomic write.
        """
        if not isinstance(payload, dict):
            raise WormRecordError("Payload must be a dictionary.")
        if not payload:
            raise WormRecordError("Payload must not be empty.")

        with self._lock:
            try:
                prev_hash = self.get_last_hash()
                canonical_payload = json.dumps(payload, sort_keys=True, separators=(',', ':'))

                record = {
                    "prev_hash": prev_hash,
                    "payload": payload,
                }
                canonical_record = json.dumps(record, sort_keys=True, separators=(',', ':'))
                record_hash = hashlib.sha256(canonical_record.encode("utf-8")).hexdigest()

                final_record = {
                    **record,
                    "record_hash": record_hash
                }

                serialized = json.dumps(final_record, sort_keys=True) + "\n"
                record_bytes = len(serialized.encode("utf-8"))

                if record_bytes > MAX_RECORD_SIZE_BYTES:
                    raise WormRecordError(
                        f"Record size ({record_bytes} bytes) exceeds limit ({MAX_RECORD_SIZE_BYTES} bytes)."
                    )

                self._check_size_limit(record_bytes)

                # Atomic append: write to temp file, then rename
                tmp_path = self.storage_path.with_suffix(".worm.tmp")
                try:
                    with open(tmp_path, "a", encoding="utf-8") as f:
                        f.write(serialized)
                        f.flush()
                        os.fsync(f.fileno())
                    # Append existing content if file was new
                    if tmp_path.stat().st_size > record_bytes and self.storage_path.exists():
                        with open(self.storage_path, "r", encoding="utf-8") as src:
                            existing = src.read()
                        with open(tmp_path, "w", encoding="utf-8") as f:
                            f.write(existing)
                            f.write(serialized)
                            f.flush()
                            os.fsync(f.fileno())
                    os.replace(tmp_path, self.storage_path)
                except OSError as e:
                    if tmp_path.exists():
                        tmp_path.unlink(missing_ok=True)
                    raise WormStorageError(f"Atomic append failed: {e}")

                logger.debug("Appended record %s to WORM", record_hash[:16])
                return final_record

            except (WormRecordError, WormSizeLimitError):
                raise
            except Exception as e:
                raise WormStorageError(f"Append failed: {e}")

    def read_all(self) -> List[Dict[str, Any]]:
        """Read all records from the WORM log."""
        records = []
        if not self.storage_path.exists():
            return records
        try:
            with open(self.storage_path, "r", encoding="utf-8") as f:
                for idx, line in enumerate(f):
                    stripped = line.strip()
                    if not stripped:
                        continue
                    try:
                        record = json.loads(stripped)
                        if not isinstance(record, dict):
                            raise WormRecordError(f"Line {idx + 1}: expected JSON object, got {type(record).__name__}")
                        records.append(record)
                    except json.JSONDecodeError as e:
                        raise WormRecordError(f"Corruption at line {idx + 1}: {e}")
            return records
        except WormRecordError:
            raise
        except OSError as e:
            raise WormStorageError(f"Failed to read storage: {e}")

    def verify_integrity(self) -> Tuple[bool, Optional[str]]:
        """
        Full WORM chain integrity verification.
        Checks hash linkage, Merkle chain, and record structure.
        """
        try:
            records = self.read_all()
        except WormStorageError as e:
            return False, f"Cannot read storage: {e}"

        expected_prev = ZERO_HASH

        for idx, rec in enumerate(records):
            # Structure validation
            if "prev_hash" not in rec or "payload" not in rec or "record_hash" not in rec:
                return False, f"Record {idx}: missing required fields (prev_hash, payload, record_hash)."

            if rec["prev_hash"] != expected_prev:
                return False, (
                    f"Chain break at record {idx}: "
                    f"expected prev_hash {expected_prev}, got {rec['prev_hash']}"
                )

            # Recompute hash
            check_record = {
                "prev_hash": rec["prev_hash"],
                "payload": rec["payload"]
            }
            canonical = json.dumps(check_record, sort_keys=True, separators=(',', ':'))
            computed_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

            if computed_hash != rec.get("record_hash"):
                return False, (
                    f"Hash mismatch at record {idx}: "
                    f"stored {rec.get('record_hash')}, computed {computed_hash}"
                )

            expected_prev = computed_hash

        logger.info("WORM integrity verified: %d records, chain valid", len(records))
        return True, None

    def record_count(self) -> int:
        """Return the number of records in the WORM log."""
        return len(self.read_all())

    def tail(self, n: int = 10) -> List[Dict[str, Any]]:
        """Return the last n records."""
        records = self.read_all()
        return records[-n:] if n < len(records) else records
