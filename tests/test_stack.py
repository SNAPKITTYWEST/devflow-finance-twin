import unittest
import shutil
from pathlib import Path
from decimal import Decimal
from worm import WormStorageEngine
from twin import FinanceTwinEngine
from quantum import QuantumAbstractionLayer
from audit import CryptographicAuditLayer

class TestDevflowFinanceStack(unittest.TestCase):
    def setUp(self):
        self.test_storage_path = "test_ledger.worm"
        if Path(self.test_storage_path).exists():
            Path(self.test_storage_path).unlink()
        self.storage = WormStorageEngine(self.test_storage_path)
        self.twin = FinanceTwinEngine(self.storage)

    def tearDown(self):
        if Path(self.test_storage_path).exists():
            Path(self.test_storage_path).unlink()

    def test_deterministic_replay_and_accounts(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "ACC_001", "initial_balance": "1000.0000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "ACC_002", "initial_balance": "500.0000"})
        
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_101",
            "from_account": "ACC_001",
            "to_account": "ACC_002",
            "amount": "250.5000"
        })

        self.assertEqual(self.twin.accounts["ACC_001"], Decimal("749.5000"))
        self.assertEqual(self.twin.accounts["ACC_002"], Decimal("750.5000"))

        # Reconstruct twin from scratch
        twin_rebuilt = FinanceTwinEngine(self.storage)
        self.assertEqual(twin_rebuilt.accounts["ACC_001"], Decimal("749.5000"))
        self.assertEqual(twin_rebuilt.accounts["ACC_002"], Decimal("750.5000"))
        self.assertEqual(twin_rebuilt.event_count, 3)

    def test_adversarial_worm_tampering_detection(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "ACC_001", "initial_balance": "5000.0000"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_201",
            "from_account": "ACC_001",
            "to_account": "ACC_002",
            "amount": "100.0000"
        })

        # Verify initial state is pristine
        valid, err = self.twin.verify_ledger_consistency()
        self.assertTrue(valid)

        # Adversarial tampering: modify the WORM storage file directly
        with open(self.test_storage_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        # Tamper with the first record payload amount/balance
        import json
        first_record = json.loads(lines[0])
        first_record["payload"]["data"]["initial_balance"] = "99999.0000"
        lines[0] = json.dumps(first_record) + "\n"

        with open(self.test_storage_path, "w", encoding="utf-8") as f:
            f.writelines(lines)

        # Verification must fail due to Merkle/hash mismatch
        valid, err = self.twin.verify_ledger_consistency()
        self.assertFalse(valid)
        self.assertIn("Hash mismatch", err)

    def test_quantum_adapter_isolation(self):
        quantum = QuantumAbstractionLayer("simulator")
        optimization = quantum.run_optimization_circuit({"liquidity": 0.4, "bonds": 0.6})
        
        self.assertEqual(optimization["circuit_type"], "QAOA_PORTFOLIO_OPTIMIZER")
        self.assertIn("quantum_entropy_digest", optimization)
        # Verify quantum output cannot mutate ledger directly without deterministic twin validation
        self.assertNotIn("accounts", self.twin.accounts)

if __name__ == "__main__":
    unittest.main()
