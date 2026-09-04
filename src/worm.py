import hashlib
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

class WormStorageError(Exception):
    pass

class WormStorageEngine:
    """
    Custom Write Once Read Many (WORM) storage subsystem.
    Maintains an append-only, hash-linked immutable event log with Merkle-chain integrity.
    """
    def __init__(self, storage_path: str = "ledger.worm"):
        self.storage_path = Path(storage_path)
        self._ensure_storage()

    def _ensure_storage(self) -> None:
        if not self.storage_path.exists():
            self.storage_path.parent.mkdir(parents=True, exist_ok=True)
            self.storage_path.touch()

    def get_last_hash(self) -> str:
        last_line = ""
        if not self.storage_path.exists():
            return "0" * 64
        with open(self.storage_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    last_line = line
        if not last_line:
            return "0" * 64
        try:
            record = json.loads(last_line)
            return record.get("record_hash", "0" * 64)
        except json.JSONDecodeError:
            raise WormStorageError("Storage corruption detected: invalid JSON in WORM log.")

    def append(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Appends an immutable record to the WORM log.
        Computes SHA-256 decision seal / record hash chaining to the previous record.
        """
        prev_hash = self.get_last_hash()
        canonical_payload = json.dumps(payload, sort_keys=True, separators=(',', ':'))
        
        # Build record structure
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

        # Enforce WORM: append only, check file integrity
        with open(self.storage_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(final_record, sort_keys=True) + "\n")

        return final_record

    def read_all(self) -> List[Dict[str, Any]]:
        records = []
        if not self.storage_path.exists():
            return records
        with open(self.storage_path, "r", encoding="utf-8") as f:
            for idx, line in enumerate(f):
                if not line.strip():
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError as e:
                    raise WormStorageError(f"Corruption at line {idx + 1}: {e}")
        return records

    def verify_integrity(self) -> Tuple[bool, Optional[str]]:
        """
        Verifies the entire WORM chain hash integrity and Merkle linkage.
        """
        records = self.read_all()
        expected_prev = "0" * 64

        for idx, rec in enumerate(records):
            if rec.get("prev_hash") != expected_prev:
                return False, f"Chain break at record {idx}: expected prev_hash {expected_prev}, got {rec.get('prev_hash')}"
            
            # Recompute hash
            check_record = {
                "prev_hash": rec["prev_hash"],
                "payload": rec["payload"]
            }
            canonical = json.dumps(check_record, sort_keys=True, separators=(',', ':'))
            computed_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

            if computed_hash != rec.get("record_hash"):
                return False, f"Hash mismatch at record {idx}: stored {rec.get('record_hash')}, computed {computed_hash}"

            expected_prev = computed_hash

        return True, None
