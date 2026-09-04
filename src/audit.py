import hashlib
import json
from decimal import Decimal
from typing import Any, Dict, Optional

class CryptographicAuditLayer:
    """
    Generates deterministic Decision Seals for every financial operation and state transition.
    """
    @staticmethod
    def generate_seal(
        event_id: str,
        parent_event_hash: str,
        timestamp: str,
        actor: str,
        operation: str,
        previous_state_hash: str,
        resulting_state_hash: str,
        metadata: Dict[str, Any]
    ) -> Dict[str, Any]:
        seal_data = {
            "event_id": event_id,
            "parent_event_hash": parent_event_hash,
            "timestamp": timestamp,
            "actor": actor,
            "operation": operation,
            "previous_state_hash": previous_state_hash,
            "resulting_state_hash": resulting_state_hash,
            "metadata": metadata
        }
        canonical = json.dumps(seal_data, sort_keys=True, separators=(',', ':'), default=str)
        digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        
        return {
            **seal_data,
            "cryptographic_digest": digest
        }

    @staticmethod
    def verify_seal(seal: Dict[str, Any]) -> bool:
        stored_digest = seal.get("cryptographic_digest")
        check_data = {k: v for k, v in seal.items() if k != "cryptographic_digest"}
        canonical = json.dumps(check_data, sort_keys=True, separators=(',', ':'), default=str)
        computed_digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        return stored_digest == computed_digest
