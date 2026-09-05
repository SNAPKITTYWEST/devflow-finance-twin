"""
Devflow Finance Twin — Production Test Suite
Tests for WORM storage, FinanceTwin, Audit layer, Quantum layer, and integration.
"""
import sys
import os
import json
import unittest
import tempfile
import shutil
from pathlib import Path
from decimal import Decimal

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from worm import WormStorageEngine, WormStorageError, WormIntegrityError, WormRecordError
from twin import FinanceTwinEngine, quantize_money, RateLimiter, VALID_OPERATIONS
from audit import CryptographicAuditLayer, SEAL_VERSION
from quantum import QuantumAbstractionLayer


# ── WORM Storage Tests ────────────────────────────────────────────────────────

class TestWormStorage(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.storage_path = os.path.join(self.tmpdir, "test.worm")
        self.storage = WormStorageEngine(self.storage_path)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_empty_storage_returns_zero_hash(self):
        self.assertEqual(self.storage.get_last_hash(), "0" * 64)

    def test_append_and_read(self):
        rec = self.storage.append({"op": "test", "val": 42})
        self.assertIn("record_hash", rec)
        self.assertIn("prev_hash", rec)
        self.assertEqual(rec["payload"]["op"], "test")

        all_records = self.storage.read_all()
        self.assertEqual(len(all_records), 1)

    def test_hash_chaining(self):
        r1 = self.storage.append({"op": "first"})
        r2 = self.storage.append({"op": "second"})
        self.assertEqual(r2["prev_hash"], r1["record_hash"])

    def test_integrity_valid_chain(self):
        self.storage.append({"op": "a"})
        self.storage.append({"op": "b"})
        valid, err = self.storage.verify_integrity()
        self.assertTrue(valid)
        self.assertIsNone(err)

    def test_tamper_detection(self):
        self.storage.append({"op": "legit"})
        self.storage.append({"op": "also_legit"})

        # Tamper with the file
        with open(self.storage_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        record = json.loads(lines[0])
        record["payload"]["op"] = "TAMPERED"
        lines[0] = json.dumps(record) + "\n"

        with open(self.storage_path, "w", encoding="utf-8") as f:
            f.writelines(lines)

        valid, err = self.storage.verify_integrity()
        self.assertFalse(valid)
        self.assertIn("Hash mismatch", err)

    def test_empty_payload_rejected(self):
        with self.assertRaises(WormRecordError):
            self.storage.append({})

    def test_non_dict_payload_rejected(self):
        with self.assertRaises(WormRecordError):
            self.storage.append("not a dict")

    def test_record_count(self):
        self.assertEqual(self.storage.record_count(), 0)
        self.storage.append({"op": "x"})
        self.storage.append({"op": "y"})
        self.assertEqual(self.storage.record_count(), 2)

    def test_tail(self):
        for i in range(20):
            self.storage.append({"i": i})
        tail = self.storage.tail(5)
        self.assertEqual(len(tail), 5)
        self.assertEqual(tail[0]["payload"]["i"], 15)

    def test_corrupt_json_detected(self):
        with open(self.storage_path, "w", encoding="utf-8") as f:
            f.write("NOT VALID JSON\n")
        with self.assertRaises(WormStorageError):
            self.storage.read_all()


# ── FinanceTwin Tests ─────────────────────────────────────────────────────────

class TestFinanceTwin(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.storage_path = os.path.join(self.tmpdir, "test.worm")
        self.storage = WormStorageEngine(self.storage_path)
        self.twin = FinanceTwinEngine(self.storage)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_create_account(self):
        res = self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_001", "initial_balance": "1000.0000"
        })
        self.assertEqual(self.twin.accounts["ACC_001"], Decimal("1000.0000"))
        self.assertEqual(self.twin.event_count, 1)
        self.assertIn("decision_seal", res)

    def test_create_duplicate_account_rejected(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_001", "initial_balance": "0"
        })
        with self.assertRaises(ValueError):
            self.twin.execute_command("CREATE_ACCOUNT", "admin", {
                "account_id": "ACC_001", "initial_balance": "0"
            })

    def test_post_transaction(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "1000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "500"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "250.5000"
        })
        self.assertEqual(self.twin.accounts["A"], Decimal("749.5000"))
        self.assertEqual(self.twin.accounts["B"], Decimal("750.5000"))

    def test_insufficient_funds_rejected(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})
        with self.assertRaises(ValueError):
            self.twin.execute_command("POST_TRANSACTION", "admin", {
                "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "200"
            })

    def test_self_transaction_rejected(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})
        with self.assertRaises(ValueError):
            self.twin.execute_command("POST_TRANSACTION", "admin", {
                "transaction_id": "TX_001", "from_account": "A", "to_account": "A", "amount": "50"
            })

    def test_unknown_account_rejected(self):
        with self.assertRaises(ValueError):
            self.twin.execute_command("POST_TRANSACTION", "admin", {
                "transaction_id": "TX_001", "from_account": "GHOST", "to_account": "B", "amount": "10"
            })

    def test_state_rebuild(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "500"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "200"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "100"
        })
        # Rebuild from WORM
        twin2 = FinanceTwinEngine(self.storage)
        self.assertEqual(twin2.accounts.get("A"), Decimal("400.0000"))
        self.assertEqual(twin2.accounts.get("B"), Decimal("300.0000"))
        self.assertEqual(twin2.event_count, self.twin.event_count)

    def test_verify_consistency(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "X", "initial_balance": "1000"})
        valid, err = self.twin.verify_ledger_consistency()
        self.assertTrue(valid)
        self.assertIsNone(err)

    def test_invalid_operation_rejected(self):
        with self.assertRaises(ValueError):
            self.twin.execute_command("HACK_DATABASE", "admin", {})

    def test_empty_actor_rejected(self):
        with self.assertRaises(ValueError):
            self.twin.execute_command("CREATE_ACCOUNT", "", {"account_id": "A"})

    def test_negative_balance_rejected(self):
        with self.assertRaises(ValueError):
            self.twin.execute_command("CREATE_ACCOUNT", "admin", {
                "account_id": "A", "initial_balance": "-100"
            })

    def test_decision_seal_generated(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})
        self.assertIsNotNone(self.twin.latest_decision_seal)
        self.assertIn("cryptographic_digest", self.twin.latest_decision_seal)
        self.assertEqual(self.twin.latest_decision_seal["seal_version"], SEAL_VERSION)

    def test_list_accounts(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "200"})
        accounts = self.twin.list_accounts()
        self.assertEqual(len(accounts), 2)
        self.assertIn("A", accounts)
        self.assertIn("B", accounts)

    def test_reverse_transaction(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "1000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "500"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "100"
        })
        bal_a_before = self.twin.accounts["A"]
        bal_b_before = self.twin.accounts["B"]

        self.twin.execute_command("REVERSE_TRANSACTION", "admin", {
            "transaction_id": "TX_001"
        })
        self.assertEqual(self.twin.transactions["TX_001"]["status"], "REVERSED")
        self.assertEqual(self.twin.accounts["A"], bal_a_before + Decimal("100"))
        self.assertEqual(self.twin.accounts["B"], bal_b_before - Decimal("100"))

    def test_double_reverse_rejected(self):
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "1000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "500"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "100"
        })
        self.twin.execute_command("REVERSE_TRANSACTION", "admin", {"transaction_id": "TX_001"})
        with self.assertRaises(ValueError):
            self.twin.execute_command("REVERSE_TRANSACTION", "admin", {"transaction_id": "TX_001"})


# ── Audit Layer Tests ─────────────────────────────────────────────────────────

class TestAuditLayer(unittest.TestCase):
    def test_generate_and_verify_seal(self):
        seal = CryptographicAuditLayer.generate_seal(
            event_id="evt_001",
            parent_event_hash="0" * 64,
            timestamp="2026-01-01T00:00:00Z",
            actor="admin",
            operation="CREATE_ACCOUNT",
            previous_state_hash="0" * 64,
            resulting_state_hash="abc123",
            metadata={"account_id": "ACC_001"}
        )
        self.assertTrue(CryptographicAuditLayer.verify_seal(seal))
        self.assertEqual(seal["seal_version"], SEAL_VERSION)

    def test_tampered_seal_detected(self):
        seal = CryptographicAuditLayer.generate_seal(
            event_id="evt_002",
            parent_event_hash="0" * 64,
            timestamp="2026-01-01T00:00:00Z",
            actor="admin",
            operation="CREATE_ACCOUNT",
            previous_state_hash="0" * 64,
            resulting_state_hash="abc",
            metadata={}
        )
        seal["actor"] = "TAMPERED"
        self.assertFalse(CryptographicAuditLayer.verify_seal(seal))

    def test_chain_verify(self):
        seal1 = CryptographicAuditLayer.generate_seal(
            event_id="evt_1", parent_event_hash="0" * 64,
            timestamp="t1", actor="a", operation="OP1",
            previous_state_hash="0" * 64, resulting_state_hash="h1", metadata={}
        )
        seal2 = CryptographicAuditLayer.generate_seal(
            event_id="evt_2", parent_event_hash=seal1["cryptographic_digest"],
            timestamp="t2", actor="a", operation="OP2",
            previous_state_hash="h1", resulting_state_hash="h2", metadata={}
        )
        valid, err = CryptographicAuditLayer.chain_verify([seal1, seal2])
        self.assertTrue(valid)

    def test_chain_verify_break(self):
        seal1 = CryptographicAuditLayer.generate_seal(
            event_id="evt_1", parent_event_hash="0" * 64,
            timestamp="t1", actor="a", operation="OP1",
            previous_state_hash="0" * 64, resulting_state_hash="h1", metadata={}
        )
        seal2 = CryptographicAuditLayer.generate_seal(
            event_id="evt_2", parent_event_hash="WRONG_HASH",
            timestamp="t2", actor="a", operation="OP2",
            previous_state_hash="h1", resulting_state_hash="h2", metadata={}
        )
        valid, err = CryptographicAuditLayer.chain_verify([seal1, seal2])
        self.assertFalse(valid)
        self.assertIn("chain break", err.lower())

    def test_verify_empty_seal(self):
        self.assertFalse(CryptographicAuditLayer.verify_seal({}))
        self.assertFalse(CryptographicAuditLayer.verify_seal(None))


# ── Quantum Layer Tests ───────────────────────────────────────────────────────

class TestQuantumLayer(unittest.TestCase):
    def setUp(self):
        self.q = QuantumAbstractionLayer("simulator")

    def test_entropy_is_deterministic_with_seed(self):
        q_det = QuantumAbstractionLayer("simulator", deterministic_seed="test_seed")
        e1 = q_det.get_quantum_entropy("mod")
        e2 = q_det.get_quantum_entropy("mod")
        self.assertEqual(e1, e2)

    def test_entropy_changes_per_seed(self):
        q1 = QuantumAbstractionLayer("simulator", deterministic_seed="seed_a")
        q2 = QuantumAbstractionLayer("simulator", deterministic_seed="seed_b")
        self.assertNotEqual(q1.get_quantum_entropy(), q2.get_quantum_entropy())

    def test_optimization_circuit(self):
        result = self.q.run_optimization_circuit({"stocks": 0.6, "bonds": 0.4})
        self.assertEqual(result["circuit_type"], "QAOA_PORTFOLIO_OPTIMIZER")
        self.assertIn("quantum_entropy_digest", result)
        self.assertEqual(result["status"], "VALIDATED_PENDING_DETERMINISTIC_APPROVAL")

    def test_optimization_empty_weights_rejected(self):
        with self.assertRaises(ValueError):
            self.q.run_optimization_circuit({})

    def test_optimization_invalid_weight_rejected(self):
        with self.assertRaises(ValueError):
            self.q.run_optimization_circuit({"stocks": -0.5})
        with self.assertRaises(ValueError):
            self.q.run_optimization_circuit({"stocks": 1.5})

    def test_generate_random_bytes(self):
        b = self.q.generate_random_bytes(32)
        self.assertEqual(len(b), 32)

    def test_random_bytes_invalid_length(self):
        with self.assertRaises(ValueError):
            self.q.generate_random_bytes(0)
        with self.assertRaises(ValueError):
            self.q.generate_random_bytes(2048)

    def test_hash_input(self):
        h = self.q.hash_input("hello world")
        self.assertEqual(len(h), 64)  # SHA-3-256 hex digest

    def test_hash_input_sha256(self):
        h = self.q.hash_input("test", algorithm="sha256")
        self.assertEqual(len(h), 64)

    def test_hash_input_unsupported_algorithm(self):
        with self.assertRaises(ValueError):
            self.q.hash_input("x", algorithm="md5")


# ── Quantize Money Tests ──────────────────────────────────────────────────────

class TestQuantizeMoney(unittest.TestCase):
    def test_string_input(self):
        # ROUND_HALF_EVEN: 100.12345 rounds to 100.1234 (round to even digit)
        self.assertEqual(quantize_money("100.12345"), Decimal("100.1234"))

    def test_decimal_input(self):
        # ROUND_HALF_EVEN: 50.00005 rounds to 50.0000 (round to even digit)
        self.assertEqual(quantize_money(Decimal("50.00005")), Decimal("50.0000"))

    def test_integer_input(self):
        self.assertEqual(quantize_money(100), Decimal("100.0000"))

    def test_negative_rejected(self):
        with self.assertRaises(ValueError):
            quantize_money("-100")

    def test_zero_allowed(self):
        self.assertEqual(quantize_money("0"), Decimal("0.0000"))


# ── Rate Limiter Tests ────────────────────────────────────────────────────────

class TestRateLimiter(unittest.TestCase):
    def test_allows_within_limit(self):
        rl = RateLimiter(window=60, max_ops=5)
        for _ in range(5):
            self.assertTrue(rl.check())

    def test_blocks_over_limit(self):
        rl = RateLimiter(window=60, max_ops=3)
        for _ in range(3):
            rl.check()
        self.assertFalse(rl.check())


# ── Integration Tests ─────────────────────────────────────────────────────────

class TestIntegration(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.storage_path = os.path.join(self.tmpdir, "ledger.worm")
        self.storage = WormStorageEngine(self.storage_path)
        self.twin = FinanceTwinEngine(self.storage)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_full_lifecycle(self):
        """End-to-end: create accounts, transact, verify, rebuild."""
        # Create accounts
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_001", "initial_balance": "10000.0000"
        })
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_002", "initial_balance": "5000.0000"
        })

        # Transactions
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "ACC_001",
            "to_account": "ACC_002", "amount": "2500.0000"
        })
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_002", "from_account": "ACC_002",
            "to_account": "ACC_001", "amount": "1000.0000"
        })

        # Verify
        self.assertEqual(self.twin.accounts["ACC_001"], Decimal("8500.0000"))
        self.assertEqual(self.twin.accounts["ACC_002"], Decimal("6500.0000"))
        self.assertEqual(self.twin.event_count, 4)

        # Verify WORM integrity
        valid, err = self.twin.verify_ledger_consistency()
        self.assertTrue(valid)

        # Rebuild from scratch
        twin_rebuilt = FinanceTwinEngine(self.storage)
        self.assertEqual(twin_rebuilt.accounts["ACC_001"], Decimal("8500.0000"))
        self.assertEqual(twin_rebuilt.accounts["ACC_002"], Decimal("6500.0000"))
        self.assertEqual(twin_rebuilt.event_count, 4)

    def test_adversarial_tampering_detection(self):
        """Simulate file-level tampering and verify detection."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_001", "initial_balance": "5000.0000"
        })
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_002", "initial_balance": "1000.0000"
        })
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_201", "from_account": "ACC_001",
            "to_account": "ACC_002", "amount": "100.0000"
        })

        valid, err = self.twin.verify_ledger_consistency()
        self.assertTrue(valid)

        # Tamper with file
        with open(self.storage_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        record = json.loads(lines[0])
        record["payload"]["data"]["initial_balance"] = "99999.0000"
        lines[0] = json.dumps(record) + "\n"
        with open(self.storage_path, "w", encoding="utf-8") as f:
            f.writelines(lines)

        valid, err = self.twin.verify_ledger_consistency()
        self.assertFalse(valid)
        self.assertIn("Hash mismatch", err)

    def test_quantum_isolation(self):
        """Quantum output cannot mutate ledger directly."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_001", "initial_balance": "1000"
        })
        quantum = QuantumAbstractionLayer("simulator")
        result = quantum.run_optimization_circuit({"stocks": 0.6, "bonds": 0.4})
        # Quantum output is advisory only
        self.assertNotIn("accounts", result)
        self.assertEqual(result["status"], "VALIDATED_PENDING_DETERMINISTIC_APPROVAL")
        # Ledger unchanged
        self.assertEqual(self.twin.accounts["ACC_001"], Decimal("1000.0000"))


if __name__ == "__main__":
    unittest.main()
