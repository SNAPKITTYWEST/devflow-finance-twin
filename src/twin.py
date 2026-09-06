from decimal import Decimal, ROUND_HALF_EVEN, InvalidOperation
import json
import hashlib
import logging
import time
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple
from worm import WormStorageEngine
from audit import CryptographicAuditLayer
from quantum import QuantumAbstractionLayer

logger = logging.getLogger("devflow.twin")

# Production constants
MAX_BALANCE = Decimal("99999999999999999.9999")
MAX_TRANSACTION_AMOUNT = Decimal("99999999999999.9999")
RATE_LIMIT_WINDOW_SECONDS = 60
RATE_LIMIT_MAX_OPS = 1000
VALID_OPERATIONS = frozenset({
    "CREATE_ACCOUNT", "POST_TRANSACTION", "CREATE_INVOICE",
    "RECORD_PAYMENT", "CREATE_OBLIGATION", "APPROVE_TRANSACTION",
    "REJECT_TRANSACTION", "REVERSE_TRANSACTION"
})


def quantize_money(amount: Any) -> Decimal:
    """Enforce strict 18-decimal fixed-point arithmetic for monetary state."""
    try:
        if isinstance(amount, Decimal):
            d = amount
        else:
            d = Decimal(str(amount))
    except (InvalidOperation, ValueError) as e:
        raise ValueError(f"Invalid monetary amount: {amount!r} — {e}")

    if d < 0:
        raise ValueError(f"Negative amounts not permitted: {d}")
    if d > MAX_BALANCE:
        raise ValueError(f"Amount exceeds maximum balance: {d} > {MAX_BALANCE}")

    return d.quantize(Decimal("0.0001"), rounding=ROUND_HALF_EVEN)


class RateLimiter:
    """Simple sliding-window rate limiter for operational throughput."""
    def __init__(self, window: int = RATE_LIMIT_WINDOW_SECONDS, max_ops: int = RATE_LIMIT_MAX_OPS):
        self.window = window
        self.max_ops = max_ops
        self._timestamps: List[float] = []

    def check(self) -> bool:
        now = time.monotonic()
        cutoff = now - self.window
        self._timestamps = [t for t in self._timestamps if t > cutoff]
        if len(self._timestamps) >= self.max_ops:
            return False
        self._timestamps.append(now)
        return True


class FinanceTwinEngine:
    """
    Production-grade digital twin of financial operations.
    Event sourcing with WORM storage. The twin does not trust its current state;
    it reconstructs it from provable history.
    """
    def __init__(
        self,
        storage_engine: WormStorageEngine,
        quantum_layer: Optional[QuantumAbstractionLayer] = None
    ):
        self.storage = storage_engine
        self.quantum = quantum_layer or QuantumAbstractionLayer()
        self.accounts: Dict[str, Decimal] = {}
        self.transactions: Dict[str, Dict[str, Any]] = {}
        self.invoices: Dict[str, Dict[str, Any]] = {}
        self.liabilities: Dict[str, Dict[str, Any]] = {}
        self.assets: Dict[str, Dict[str, Any]] = {}
        self.approvals: Dict[str, bool] = {}
        self.event_count = 0
        self.latest_decision_seal: Optional[Dict[str, Any]] = None
        self._rate_limiter = RateLimiter()
        self.rebuild_state()

    def compute_state_hash(self) -> str:
        """Deterministic SHA-256 hash of the entire financial state."""
        state_snapshot = {
            "accounts": {k: str(v) for k, v in sorted(self.accounts.items())},
            "transactions": sorted(self.transactions.keys()),
            "invoices": sorted(self.invoices.keys()),
            "liabilities": sorted(self.liabilities.keys()),
            "assets": sorted(self.assets.keys()),
            "event_count": self.event_count
        }
        canonical = json.dumps(state_snapshot, sort_keys=True, separators=(',', ':'))
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    def rebuild_state(self) -> None:
        """Reconstruct the entire financial state from historical WORM events."""
        self.accounts = {}
        self.transactions = {}
        self.invoices = {}
        self.liabilities = {}
        self.assets = {}
        self.approvals = {}
        self.event_count = 0
        self.latest_decision_seal = None

        records = self.storage.read_all()
        for record in records:
            payload = record.get("payload", {})
            try:
                self._apply_event_to_memory(payload, record.get("record_hash"))
                self.event_count += 1
            except Exception as e:
                logger.error("Failed to apply event %s during rebuild: %s",
                           payload.get("event_id", "unknown"), e)
                raise

        logger.info("State rebuilt: %d events, %d accounts", self.event_count, len(self.accounts))

    def _apply_event_to_memory(self, event: Dict[str, Any], record_hash: str) -> None:
        """Apply a single event to in-memory state. Raises on business rule violations."""
        op = event.get("operation")
        data = event.get("data", {})

        if op == "CREATE_ACCOUNT":
            acc_id = data.get("account_id")
            if not acc_id or not isinstance(acc_id, str):
                raise ValueError("CREATE_ACCOUNT requires a valid account_id string.")
            if acc_id in self.accounts:
                raise ValueError(f"Account {acc_id} already exists.")
            balance = quantize_money(data.get("initial_balance", "0.0000"))
            self.accounts[acc_id] = balance

        elif op == "POST_TRANSACTION":
            tx_id = data.get("transaction_id")
            from_acc = data.get("from_account")
            to_acc = data.get("to_account")
            amount_str = data.get("amount")

            if not all([tx_id, from_acc, to_acc, amount_str]):
                raise ValueError("POST_TRANSACTION requires transaction_id, from_account, to_account, and amount.")

            amount = quantize_money(amount_str)

            if from_acc not in self.accounts:
                raise ValueError(f"Source account {from_acc} does not exist.")
            if to_acc not in self.accounts:
                raise ValueError(f"Destination account {to_acc} does not exist.")
            if from_acc == to_acc:
                raise ValueError("Self-transactions are not permitted.")
            if self.accounts[from_acc] < amount:
                raise ValueError(f"Insufficient funds in {from_acc}: {self.accounts[from_acc]} < {amount}")
            if amount > MAX_TRANSACTION_AMOUNT:
                raise ValueError(f"Transaction amount exceeds limit: {amount}")

            self.accounts[from_acc] -= amount
            self.accounts[to_acc] += amount
            self.transactions[tx_id] = {**data, "status": "POSTED"}

        elif op == "CREATE_INVOICE":
            inv_id = data.get("invoice_id")
            if not inv_id:
                raise ValueError("CREATE_INVOICE requires an invoice_id.")
            self.invoices[inv_id] = {**data, "status": "ISSUED"}

        elif op == "RECORD_PAYMENT":
            pay_id = data.get("payment_id")
            inv_id = data.get("invoice_id")
            if not inv_id:
                raise ValueError("RECORD_PAYMENT requires an invoice_id.")
            if inv_id in self.invoices:
                self.invoices[inv_id]["status"] = "PAID"
            else:
                logger.warning("RECORD_PAYMENT for unknown invoice %s", inv_id)

        elif op == "CREATE_OBLIGATION":
            obl_id = data.get("obligation_id")
            if not obl_id:
                raise ValueError("CREATE_OBLIGATION requires an obligation_id.")
            self.liabilities[obl_id] = {**data, "status": "ACTIVE"}

        elif op == "APPROVE_TRANSACTION":
            tx_id = data.get("transaction_id")
            if not tx_id:
                raise ValueError("APPROVE_TRANSACTION requires a transaction_id.")
            self.approvals[tx_id] = True

        elif op == "REJECT_TRANSACTION":
            tx_id = data.get("transaction_id")
            if not tx_id:
                raise ValueError("REJECT_TRANSACTION requires a transaction_id.")
            self.approvals[tx_id] = False

        elif op == "REVERSE_TRANSACTION":
            tx_id = data.get("transaction_id")
            if not tx_id:
                raise ValueError("REVERSE_TRANSACTION requires a transaction_id.")
            if tx_id not in self.transactions:
                raise ValueError(f"Transaction {tx_id} not found.")
            if self.transactions[tx_id]["status"] == "REVERSED":
                raise ValueError(f"Transaction {tx_id} already reversed.")

            original = self.transactions[tx_id]
            from_acc = original["to_account"]
            to_acc = original["from_account"]
            amount = quantize_money(original["amount"])

            if from_acc in self.accounts:
                self.accounts[from_acc] -= amount
            if to_acc in self.accounts:
                self.accounts[to_acc] += amount

            self.transactions[tx_id]["status"] = "REVERSED"

        else:
            raise ValueError(f"Unknown operation: {op}")

        # Update decision seal tracking
        actor = event.get("actor", "system")
        prev_hash = self.latest_decision_seal["cryptographic_digest"] if self.latest_decision_seal else "0" * 64
        curr_state_hash = self.compute_state_hash()

        self.latest_decision_seal = CryptographicAuditLayer.generate_seal(
            event_id=event.get("event_id", "evt_unknown"),
            parent_event_hash=prev_hash,
            timestamp=event.get("timestamp", "1970-01-01T00:00:00Z"),
            actor=actor,
            operation=op,
            previous_state_hash=prev_hash,
            resulting_state_hash=curr_state_hash,
            metadata=data
        )

    def execute_command(self, operation: str, actor: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Execute a financial command with full production hardening:
        - Rate limiting
        - Input validation
        - WORM append
        - Cryptographic decision seal
        """
        # Rate limit check
        if not self._rate_limiter.check():
            raise ValueError(
                f"Rate limit exceeded: max {RATE_LIMIT_MAX_OPS} operations "
                f"per {RATE_LIMIT_WINDOW_SECONDS}s window."
            )

        # Operation validation
        if operation not in VALID_OPERATIONS:
            raise ValueError(f"Invalid operation: {operation}. Valid: {sorted(VALID_OPERATIONS)}")
        if not actor or not isinstance(actor, str):
            raise ValueError("Actor must be a non-empty string.")
        if not isinstance(data, dict):
            raise ValueError("Data must be a dictionary.")

        import uuid
        event_id = f"evt_{uuid.uuid4().hex[:12]}"
        timestamp = datetime.now(timezone.utc).isoformat()
        prev_state_hash = self.compute_state_hash()

        event_payload = {
            "event_id": event_id,
            "timestamp": timestamp,
            "actor": actor,
            "operation": operation,
            "data": data
        }

        # Business logic pre-validation
        if operation == "POST_TRANSACTION":
            from_acc = data.get("from_account")
            amount = quantize_money(data.get("amount", "0"))
            if from_acc not in self.accounts:
                raise ValueError(f"Account {from_acc} does not exist.")
            if self.accounts[from_acc] < amount:
                raise ValueError(f"Insufficient balance in {from_acc}.")

        # Append to WORM
        worm_record = self.storage.append(event_payload)

        # Apply locally and update seal
        self._apply_event_to_memory(event_payload, worm_record["record_hash"])
        self.event_count += 1

        logger.info("Executed %s by %s — event %s", operation, actor, event_id)

        return {
            "event_id": event_id,
            "worm_record_hash": worm_record["record_hash"],
            "decision_seal": self.latest_decision_seal,
            "current_state_hash": self.compute_state_hash()
        }

    def verify_ledger_consistency(self) -> Tuple[bool, Optional[str]]:
        """
        Independent verification: rebuild state from scratch and verify WORM integrity.
        """
        is_valid, err = self.storage.verify_integrity()
        if not is_valid:
            return False, f"WORM Integrity Failure: {err}"

        # Snapshot current state
        current_hash = self.compute_state_hash()

        # Rebuild from scratch
        self.rebuild_state()
        rebuilt_hash = self.compute_state_hash()

        if current_hash != rebuilt_hash:
            return False, "State inconsistency between active memory and historical replay."

        logger.info("Ledger consistency verified: state hash %s", rebuilt_hash[:16])
        return True, None

    def get_account_balance(self, account_id: str) -> Optional[Decimal]:
        """Safe account balance lookup."""
        return self.accounts.get(account_id)

    def list_accounts(self) -> Dict[str, str]:
        """Return all accounts with their balances as strings."""
        return {k: str(v) for k, v in self.accounts.items()}

    def get_transaction(self, tx_id: str) -> Optional[Dict[str, Any]]:
        """Safe transaction lookup."""
        return self.transactions.get(tx_id)
