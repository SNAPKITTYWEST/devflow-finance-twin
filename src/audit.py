import hashlib
import json
import logging
from decimal import Decimal
from typing import Any, Dict, Optional

logger = logging.getLogger("devflow.audit")

# Seal version for forward-compatible verification
SEAL_VERSION = "1.0.0"
HASH_ALGORITHM = "sha256"


class CryptographicAuditLayer:
    """
    Production-grade cryptographic Decision Seal generation and verification.
    Every financial operation and state transition produces an immutable,
    hash-linked seal with versioned structure for forward compatibility.
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
        """
        Generate a deterministic Decision Seal for a financial event.
        The seal is a SHA-256 digest of all event fields (excluding the digest itself).
        """
        if not event_id:
            raise ValueError("event_id is required for seal generation.")
        if not actor:
            raise ValueError("actor is required for seal generation.")

        seal_data = {
            "seal_version": SEAL_VERSION,
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

        logger.debug("Generated seal for event %s — digest %s", event_id, digest[:16])

        return {
            **seal_data,
            "cryptographic_digest": digest
        }

    @staticmethod
    def verify_seal(seal: Dict[str, Any]) -> bool:
        """
        Verify the integrity of a Decision Seal by recomputing its digest.
        Returns True if the seal is valid, False if tampered.
        """
        if not seal or not isinstance(seal, dict):
            logger.warning("verify_seal called with invalid input")
            return False

        stored_digest = seal.get("cryptographic_digest")
        if not stored_digest:
            logger.warning("Seal missing cryptographic_digest")
            return False

        check_data = {k: v for k, v in seal.items() if k != "cryptographic_digest"}
        canonical = json.dumps(check_data, sort_keys=True, separators=(',', ':'), default=str)
        computed_digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

        is_valid = stored_digest == computed_digest
        if not is_valid:
            logger.warning(
                "Seal verification FAILED for event %s: stored %s, computed %s",
                seal.get("event_id", "unknown"), stored_digest[:16], computed_digest[:16]
            )
        return is_valid

    @staticmethod
    def chain_verify(seals: list) -> tuple:
        """
        Verify a chain of Decision Seals.
        Returns (is_valid, error_message_or_none).
        """
        for idx, seal in enumerate(seals):
            if not CryptographicAuditLayer.verify_seal(seal):
                return False, f"Seal at index {idx} failed integrity check (event: {seal.get('event_id')})"

            if idx > 0:
                prev_seal = seals[idx - 1]
                expected_parent = prev_seal.get("cryptographic_digest", "0" * 64)
                actual_parent = seal.get("parent_event_hash", "")
                if expected_parent != actual_parent:
                    return False, (
                        f"Seal chain break at index {idx}: "
                        f"expected parent {expected_parent[:16]}, got {actual_parent[:16]}"
                    )

        logger.info("Seal chain verified: %d seals, all valid", len(seals))
        return True, None
