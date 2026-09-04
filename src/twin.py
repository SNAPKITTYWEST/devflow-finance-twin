from decimal import Decimal, ROUND_HALF_EVEN
import json
import hashlib
from typing import Any, Dict, List, Optional, Tuple

try:
    from worm import WormStorageEngine
    from audit import CryptographicAuditLayer
    from quantum import QuantumAbstractionLayer
except ImportError:
    from src.worm import WormStorageEngine
    from src.audit import CryptographicAuditLayer
    from src.quantum import QuantumAbstractionLayer

def quantize_money(amount: Any) -> Decimal:
    """Enforces strict decimal fixed-point arithmetic for monetary state."""
    if isinstance(amount, Decimal):
        d = amount
    else:
        d = Decimal(str(amount))
    return d.quantize(Decimal("0.0001"), rounding=ROUND_HALF_EVEN)

class FinanceTwinEngine:
    """
    Digital twin of financial operations using event sourcing and WORM storage.
    The twin does not trust its current state; it reconstructs it from provable history.
    """
    def __init__(self, storage_engine: WormStorageEngine, quantum_layer: Optional[QuantumAbstractionLayer] = None):
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
        self.rebuild_state()

    def compute_state_hash(self) -> str:
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
        """Reconstructs the entire financial state from historical WORM events."""
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
            self._apply_event_to_memory(payload, record.get("record_hash"))
            self.event_count += 1

    def _apply_event_to_memory(self, event: Dict[str, Any], record_hash: str) -> None:
        op = event.get("operation")
        data = event.get("data", {})

        if op == "CREATE_ACCOUNT":
            acc_id = data["account_id"]
            self.accounts[acc_id] = quantize_money(data.get("initial_balance", "0.0000"))
        
        elif op == "POST_TRANSACTION":
            tx_id = data["transaction_id"]
            from_acc = data["from_account"]
            to_acc = data["to_account"]
            amount = quantize_money(data["amount"])
            
            if from_acc in self.accounts and self.accounts[from_acc] < amount:
                raise ValueError(f"Insufficient funds in account {from_acc} for transaction {tx_id}")

            if from_acc in self.accounts:
                self.accounts[from_acc] -= amount
            if to_acc in self.accounts:
                self.accounts[to_acc] += amount
            
            self.transactions[tx_id] = {**data, "status": "POSTED"}

        elif op == "CREATE_INVOICE":
            inv_id = data["invoice_id"]
            self.invoices[inv_id] = {**data, "status": "ISSUED"}

        elif op == "RECORD_PAYMENT":
            pay_id = data["payment_id"]
            inv_id = data["invoice_id"]
            if inv_id in self.invoices:
                self.invoices[inv_id]["status"] = "PAID"

        elif op == "CREATE_OBLIGATION":
            obl_id = data["obligation_id"]
            self.liabilities[obl_id] = {**data, "status": "ACTIVE"}

        elif op == "APPROVE_TRANSACTION":
            tx_id = data["transaction_id"]
            self.approvals[tx_id] = True

        elif op == "REJECT_TRANSACTION":
            tx_id = data["transaction_id"]
            self.approvals[tx_id] = False

        elif op == "REVERSE_TRANSACTION":
            tx_id = data["transaction_id"]
            if tx_id in self.transactions and self.transactions[tx_id]["status"] != "REVERSED":
                original = self.transactions[tx_id]
                from_acc = original["to_account"] # Swap direction for reversal
                to_acc = original["from_account"]
                amount = quantize_money(original["amount"])
                
                if from_acc in self.accounts:
                    self.accounts[from_acc] -= amount
                if to_acc in self.accounts:
                    self.accounts[to_acc] += amount
                
                self.transactions[tx_id]["status"] = "REVERSED"

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
        Executes a financial command, creates an immutable event, records to WORM,
        and generates a cryptographic Decision Seal.
        """
        import uuid
        from datetime import datetime, timezone

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

        # Validate business logic preconditions before committing
        if operation == "POST_TRANSACTION":
            from_acc = data["from_account"]
            amount = quantize_money(data["amount"])
            if from_acc not in self.accounts:
                raise ValueError(f"Account {from_acc} does not exist.")
            if self.accounts[from_acc] < amount:
                raise ValueError(f"Insufficient balance in {from_acc}.")

        # Append to WORM storage
        worm_record = self.storage.append(event_payload)
        
        # Apply locally and update seal
        self._apply_event_to_memory(event_payload, worm_record["record_hash"])
        self.event_count += 1

        return {
            "event_id": event_id,
            "worm_record_hash": worm_record["record_hash"],
            "decision_seal": self.latest_decision_seal,
            "current_state_hash": self.compute_state_hash()
        }

    def verify_ledger_consistency(self) -> Tuple[bool, Optional[str]]:
        """
        Independent verification: rebuilds state from scratch and verifies WORM integrity.
        """
        is_valid, err = self.storage.verify_integrity()
        if not is_valid:
            return False, f"WORM Integrity Failure: {err}"
        
        # Rebuild and compare
        current_hash_in_memory = self.compute_state_hash()
        self.rebuild_state()
        rebuilt_hash = self.compute_state_hash()

        if current_hash_in_memory != rebuilt_hash:
            return False, "State inconsistency detected between active memory and historical replay."

        return True, None
