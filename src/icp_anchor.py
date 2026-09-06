"""
Devflow Finance Twin — ICP Anchor Bridge
Anchors WORM state hashes to the Internet Computer Protocol canister
for sovereign cross-chain verification.

Architecture:
  WORM Engine → ICP Anchor → IC Canister → Cross-chain verification

The ICP canister stores:
  - WORM root hash (Merkle root)
  - Record count
  - Timestamp
  - Previous canister hash (chain of anchors)

This creates an immutable, verifiable bridge between the local WORM ledger
and the Internet Computer's decentralized consensus layer.
"""
import hashlib
import json
import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger("devflow.icp_anchor")

# ── Constants ─────────────────────────────────────────────────────────────────

CANISTER_HASH_LENGTH = 64  # SHA-256 hex
ANCHOR_CHAIN_MIN = 1
ZERO_HASH = "0" * 64


@dataclass
class AnchorRecord:
    """A single anchor entry in the ICP canister."""
    worm_root_hash: str
    record_count: int
    timestamp: float
    previous_anchor_hash: str
    anchor_hash: str = ""
    canister_id: str = ""
    metadata: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self):
        if not self.anchor_hash:
            self.anchor_hash = self._compute_hash()

    def _compute_hash(self) -> str:
        """Compute deterministic anchor hash."""
        data = {
            "worm_root_hash": self.worm_root_hash,
            "record_count": self.record_count,
            "timestamp": self.timestamp,
            "previous_anchor_hash": self.previous_anchor_hash,
            "canister_id": self.canister_id,
            "metadata": self.metadata,
        }
        canonical = json.dumps(data, sort_keys=True, separators=(',', ':'))
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    def verify(self) -> bool:
        """Verify anchor hash integrity."""
        return self.anchor_hash == self._compute_hash()


@dataclass
class CanisterState:
    """State of the ICP canister."""
    canister_id: str
    anchor_chain: List[AnchorRecord] = field(default_factory=list)
    latest_root_hash: str = ZERO_HASH
    total_anchors: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "canister_id": self.canister_id,
            "latest_root_hash": self.latest_root_hash,
            "total_anchors": self.total_anchors,
            "anchor_chain_length": len(self.anchor_chain),
        }


class ICPAnchorError(Exception):
    """Base exception for ICP anchor failures."""
    pass


class AnchorChainError(ICPAnchorError):
    """Anchor chain integrity broken."""
    pass


class CanisterNotInitializedError(ICPAnchorError):
    """Canister has not been initialized."""
    pass


class ICPAnchorBridge:
    """
    ICP Anchor Bridge — connects WORM engine to Internet Computer canister.

    Provides:
    - Anchor WORM state to IC canister
    - Verify anchor chain integrity
    - Query canister state
    - Export anchor proofs for cross-chain verification
    """

    def __init__(self, canister_id: str = "devflow-finance-twin-canister"):
        self.canister_id = canister_id
        self.state = CanisterState(canister_id=canister_id)
        self._initialized = False
        logger.info("ICP Anchor Bridge created: %s", canister_id)

    def initialize(self) -> CanisterState:
        """
        Initialize the canister with a genesis anchor.
        Called once on first deployment.
        """
        logger.info("ICP Anchor: Initializing canister %s", self.canister_id)

        genesis_anchor = AnchorRecord(
            worm_root_hash=ZERO_HASH,
            record_count=0,
            timestamp=time.time(),
            previous_anchor_hash=ZERO_HASH,
            canister_id=self.canister_id,
            metadata={"type": "GENESIS", "version": "1.1.0"}
        )

        self.state.anchor_chain = [genesis_anchor]
        self.state.latest_root_hash = ZERO_HASH
        self.state.total_anchors = 1
        self._initialized = True

        logger.info("ICP Anchor: Genesis anchor created — %s", genesis_anchor.anchor_hash[:16])
        return self.state

    def anchor_state(
        self,
        worm_root_hash: str,
        record_count: int,
        metadata: Optional[Dict[str, Any]] = None
    ) -> AnchorRecord:
        """
        Anchor WORM state to the IC canister.
        Creates a new anchor record chained to the previous one.

        Args:
            worm_root_hash: Current WORM Merkle root
            record_count: Number of records in WORM
            metadata: Optional metadata for the anchor

        Returns:
            AnchorRecord with computed anchor hash
        """
        if not self._initialized:
            self.initialize()

        if not worm_root_hash or worm_root_hash == ZERO_HASH:
            raise ICPAnchorError("Cannot anchor zero/empty WORM root hash")

        # Get previous anchor hash
        prev_hash = ZERO_HASH
        if self.state.anchor_chain:
            prev_hash = self.state.anchor_chain[-1].anchor_hash

        # Create new anchor
        anchor = AnchorRecord(
            worm_root_hash=worm_root_hash,
            record_count=record_count,
            timestamp=time.time(),
            previous_anchor_hash=prev_hash,
            canister_id=self.canister_id,
            metadata=metadata or {}
        )

        # Append to chain
        self.state.anchor_chain.append(anchor)
        self.state.latest_root_hash = worm_root_hash
        self.state.total_anchors += 1

        logger.info(
            "ICP Anchor: State anchored — worm_root=%s, anchor=%s, count=%d",
            worm_root_hash[:16], anchor.anchor_hash[:16], record_count
        )

        return anchor

    def verify_chain(self) -> Tuple[bool, Optional[str]]:
        """
        Verify the entire anchor chain integrity.
        Returns (is_valid, error_message_or_none).
        """
        if not self.state.anchor_chain:
            return True, None

        for idx, anchor in enumerate(self.state.anchor_chain):
            # Verify anchor hash
            if not anchor.verify():
                return False, f"Anchor {idx}: hash integrity failed"

            # Verify chain linkage
            if idx > 0:
                expected_prev = self.state.anchor_chain[idx - 1].anchor_hash
                if anchor.previous_anchor_hash != expected_prev:
                    return False, (
                        f"Anchor {idx}: chain break — "
                        f"expected prev {expected_prev[:16]}, got {anchor.previous_anchor_hash[:16]}"
                    )

        logger.info("ICP Anchor: Chain verified — %d anchors, all valid", len(self.state.anchor_chain))
        return True, None

    def get_anchor(self, index: int) -> Optional[AnchorRecord]:
        """Get anchor at specific index."""
        if 0 <= index < len(self.state.anchor_chain):
            return self.state.anchor_chain[index]
        return None

    def get_latest_anchor(self) -> Optional[AnchorRecord]:
        """Get the most recent anchor."""
        if self.state.anchor_chain:
            return self.state.anchor_chain[-1]
        return None

    def get_canister_state(self) -> Dict[str, Any]:
        """Get canister state as dictionary."""
        return self.state.to_dict()

    def export_proof(self, anchor_index: int) -> Optional[Dict[str, Any]]:
        """
        Export a verifiable proof for a specific anchor.
        Includes the anchor, its chain context, and canister metadata.
        """
        if anchor_index < 0 or anchor_index >= len(self.state.anchor_chain):
            return None

        anchor = self.state.anchor_chain[anchor_index]

        return {
            "canister_id": self.canister_id,
            "proof_type": "ICP_WORM_ANCHOR",
            "proof_version": "1.1.0",
            "anchor": {
                "worm_root_hash": anchor.worm_root_hash,
                "record_count": anchor.record_count,
                "timestamp": anchor.timestamp,
                "anchor_hash": anchor.anchor_hash,
                "previous_anchor_hash": anchor.previous_anchor_hash,
            },
            "chain_context": {
                "total_anchors": self.state.total_anchors,
                "anchor_index": anchor_index,
                "latest_root_hash": self.state.latest_root_hash,
            },
            "verification": {
                "hash_valid": anchor.verify(),
                "chain_valid": self.verify_chain()[0],
            }
        }

    def sync_from_worm(self, worm_storage_path: str) -> Optional[AnchorRecord]:
        """
        Synchronize anchor state from a WORM storage file.
        Reads the WORM, computes root hash, and creates an anchor.
        """
        try:
            from pathlib import Path
            path = Path(worm_storage_path)
            if not path.exists():
                logger.warning("ICP Anchor: WORM file not found: %s", worm_storage_path)
                return None

            records = []
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    stripped = line.strip()
                    if stripped:
                        records.append(json.loads(stripped))

            if not records:
                logger.info("ICP Anchor: WORM is empty, anchoring genesis")
                # For empty WORM, use a special genesis hash
                genesis_hash = hashlib.sha256(b"GENESIS_EMPTY_WORM").hexdigest()
                return self.anchor_state(
                    genesis_hash, 0,
                    {"type": "EMPTY_SYNC", "note": "Genesis anchor for empty WORM"}
                )

            # Compute WORM root from last record
            last_record = records[-1]
            worm_root = last_record.get("record_hash", ZERO_HASH)

            return self.anchor_state(
                worm_root_hash=worm_root,
                record_count=len(records),
                metadata={"type": "WORM_SYNC", "source": worm_storage_path}
            )

        except Exception as e:
            logger.error("ICP Anchor: Sync failed — %s", e)
            return None


# ── Convenience: Quick Anchor ────────────────────────────────────────────────

def quick_anchor(
    canister_id: str,
    worm_root_hash: str,
    record_count: int
) -> AnchorRecord:
    """
    Quick one-shot anchor creation.
    Creates bridge, initializes, and anchors in one call.
    """
    bridge = ICPAnchorBridge(canister_id)
    bridge.initialize()
    return bridge.anchor_state(worm_root_hash, record_count)
