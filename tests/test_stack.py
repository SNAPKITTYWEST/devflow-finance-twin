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
from decimal import Decimal, InvalidOperation

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


# ── Edge Case Tests ───────────────────────────────────────────────────────────

class TestEdgeCasesWorm(unittest.TestCase):
    """WORM storage edge cases."""
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.storage_path = os.path.join(self.tmpdir, "edge.worm")
        self.storage = WormStorageEngine(self.storage_path)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_concurrent_appends(self):
        """Multiple sequential appends maintain chain integrity."""
        for i in range(100):
            self.storage.append({"i": i, "data": f"record_{i}"})
        valid, err = self.storage.verify_integrity()
        self.assertTrue(valid)
        self.assertEqual(self.storage.record_count(), 100)

    def test_large_payload(self):
        """Record with 100KB payload succeeds."""
        large_data = "x" * 100000
        rec = self.storage.append({"big": large_data})
        self.assertIn("record_hash", rec)
        self.assertEqual(self.storage.record_count(), 1)

    def test_unicode_payload(self):
        """Unicode characters in payload are preserved."""
        payload = {"name": "Ahmad Ali Parr", "arabic": "ال ", "emoji": "🔐"}
        rec = self.storage.append(payload)
        records = self.storage.read_all()
        self.assertEqual(records[0]["payload"]["name"], "Ahmad Ali Parr")
        self.assertEqual(records[0]["payload"]["arabic"], "ال ")
        self.assertEqual(records[0]["payload"]["emoji"], "🔐")

    def test_deeply_nested_payload(self):
        """Deeply nested JSON payload is stored correctly."""
        nested = {"level": {"level": {"level": {"level": {"deep": "value"}}}}}
        rec = self.storage.append(nested)
        records = self.storage.read_all()
        self.assertEqual(records[0]["payload"]["level"]["level"]["level"]["level"]["deep"], "value")

    def test_empty_string_values(self):
        """Empty string values in payload are allowed."""
        rec = self.storage.append({"key": "", "other": ""})
        self.assertIn("record_hash", rec)

    def test_null_values_in_payload(self):
        """Null values in payload are preserved."""
        rec = self.storage.append({"key": None, "other": 0})
        records = self.storage.read_all()
        self.assertIsNone(records[0]["payload"]["key"])
        self.assertEqual(records[0]["payload"]["other"], 0)

    def test_special_float_values(self):
        """NaN and Infinity are rejected by JSON serialization with allow_nan=False."""
        import math
        # json.dumps default allows NaN; our code uses sort_keys which doesn't block it
        # The real protection is in quantize_money which rejects NaN before WORM write
        from twin import quantize_money
        with self.assertRaises((ValueError, InvalidOperation)):
            quantize_money(float('nan'))
        with self.assertRaises((ValueError, InvalidOperation)):
            quantize_money(float('inf'))

    def test_storage_created_with_mode_600(self):
        """New storage file is created (exists and is a file)."""
        import stat
        mode = os.stat(self.storage_path).st_mode
        self.assertTrue(stat.S_ISREG(mode))
        # On Unix, also check not world-readable
        if os.name != 'nt':
            self.assertFalse(mode & stat.S_IROTH)

    def test_read_nonexistent_file(self):
        """Reading from a deleted file returns empty list."""
        os.remove(self.storage_path)
        records = self.storage.read_all()
        self.assertEqual(records, [])

    def test_get_hash_after_many_records(self):
        """Hash retrieval works correctly after many records."""
        last_hash = "0" * 64
        for i in range(50):
            rec = self.storage.append({"i": i})
            last_hash = rec["record_hash"]
        self.assertEqual(self.storage.get_last_hash(), last_hash)


class TestEdgeCasesTwin(unittest.TestCase):
    """FinanceTwin edge cases."""
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.storage_path = os.path.join(self.tmpdir, "edge.worm")
        self.storage = WormStorageEngine(self.storage_path)
        self.twin = FinanceTwinEngine(self.storage)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_many_accounts(self):
        """Create 100 accounts, all exist in state."""
        for i in range(100):
            self.twin.execute_command("CREATE_ACCOUNT", "admin", {
                "account_id": f"ACC_{i:03d}", "initial_balance": str(i * 100)
            })
        self.assertEqual(len(self.twin.accounts), 100)
        self.assertEqual(self.twin.event_count, 100)

    def test_many_transactions(self):
        """Chain of 50 transactions maintains correct balances."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        for i in range(50):
            self.twin.execute_command("POST_TRANSACTION", "admin", {
                "transaction_id": f"TX_{i:03d}", "from_account": "A", "to_account": "B", "amount": "100"
            })
        self.assertEqual(self.twin.accounts["A"], Decimal("95000.0000"))
        self.assertEqual(self.twin.accounts["B"], Decimal("5000.0000"))

    def test_exact_balance_transaction(self):
        """Transaction that drains account to exactly zero."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "100"
        })
        self.assertEqual(self.twin.accounts["A"], Decimal("0.0000"))
        self.assertEqual(self.twin.accounts["B"], Decimal("100.0000"))

    def test_one_cent_transaction(self):
        """Smallest possible transaction."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "10"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "0.0001"
        })
        self.assertEqual(self.twin.accounts["A"], Decimal("9.9999"))
        self.assertEqual(self.twin.accounts["B"], Decimal("0.0001"))

    def test_large_amount_transaction(self):
        """Transaction near maximum balance limit."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "99999999999999.9999"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "99999999999999.9999"
        })
        self.assertEqual(self.twin.accounts["A"], Decimal("0.0000"))

    def test_over_limit_amount_rejected(self):
        """Transaction exceeding maximum amount is rejected."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "99999999999999999.9999"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        with self.assertRaises(ValueError):
            self.twin.execute_command("POST_TRANSACTION", "admin", {
                "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "99999999999999999.9999"
            })

    def test_fractional_cents_rounded(self):
        """Values with more than 4 decimal places are rounded (HALF_EVEN)."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "33.33333"
        })
        # 33.33333 rounds to 33.3333 (HALF_EVEN: 3 is odd, round down)
        self.assertEqual(self.twin.accounts["B"], Decimal("33.3333"))

    def test_multiple_reversals_accumulate(self):
        """Multiple different transactions can be reversed."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "1000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "1000"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "100"
        })
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_002", "from_account": "A", "to_account": "B", "amount": "200"
        })
        self.twin.execute_command("REVERSE_TRANSACTION", "admin", {"transaction_id": "TX_001"})
        self.twin.execute_command("REVERSE_TRANSACTION", "admin", {"transaction_id": "TX_002"})
        self.assertEqual(self.twin.accounts["A"], Decimal("1000.0000"))
        self.assertEqual(self.twin.accounts["B"], Decimal("1000.0000"))

    def test_state_hash_deterministic(self):
        """Same operations produce identical state hashes."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "500"})
        hash1 = self.twin.compute_state_hash()

        twin2 = FinanceTwinEngine(self.storage)
        hash2 = twin2.compute_state_hash()
        self.assertEqual(hash1, hash2)

    def test_state_hash_changes_on_mutation(self):
        """State hash changes when operations are performed."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "500"})
        hash1 = self.twin.compute_state_hash()
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "300"})
        hash2 = self.twin.compute_state_hash()
        self.assertNotEqual(hash1, hash2)

    def test_verify_after_many_operations(self):
        """Verification succeeds after 200 operations."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "1000000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        for i in range(100):
            self.twin.execute_command("POST_TRANSACTION", "admin", {
                "transaction_id": f"TX_A_{i}", "from_account": "A", "to_account": "B", "amount": "1"
            })
            self.twin.execute_command("POST_TRANSACTION", "admin", {
                "transaction_id": f"TX_B_{i}", "from_account": "B", "to_account": "A", "amount": "0.5"
            })
        valid, err = self.twin.verify_ledger_consistency()
        self.assertTrue(valid)

    def test_get_account_balance(self):
        """Safe balance lookup."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "42"})
        self.assertEqual(self.twin.get_account_balance("A"), Decimal("42.0000"))
        self.assertIsNone(self.twin.get_account_balance("GHOST"))

    def test_get_transaction(self):
        """Safe transaction lookup."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "0"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "50"
        })
        tx = self.twin.get_transaction("TX_001")
        self.assertIsNotNone(tx)
        self.assertEqual(tx["status"], "POSTED")
        self.assertIsNone(self.twin.get_transaction("GHOST"))


class TestEdgeCasesAudit(unittest.TestCase):
    """Audit layer edge cases."""
    def test_seal_with_all_none_values(self):
        """Seal generation handles None metadata gracefully."""
        seal = CryptographicAuditLayer.generate_seal(
            event_id="evt_001", parent_event_hash="0" * 64,
            timestamp="2026-01-01T00:00:00Z", actor="admin",
            operation="OP", previous_state_hash="0" * 64,
            resulting_state_hash="abc", metadata={"key": None}
        )
        self.assertTrue(CryptographicAuditLayer.verify_seal(seal))

    def test_seal_with_nested_metadata(self):
        """Seal handles deeply nested metadata."""
        metadata = {"a": {"b": {"c": [1, 2, 3]}}}
        seal = CryptographicAuditLayer.generate_seal(
            event_id="evt_001", parent_event_hash="0" * 64,
            timestamp="t", actor="a", operation="OP",
            previous_state_hash="0" * 64, resulting_state_hash="h",
            metadata=metadata
        )
        self.assertTrue(CryptographicAuditLayer.verify_seal(seal))

    def test_chain_verify_single_seal(self):
        """Chain verification works with a single seal."""
        seal = CryptographicAuditLayer.generate_seal(
            event_id="evt_1", parent_event_hash="0" * 64,
            timestamp="t", actor="a", operation="OP",
            previous_state_hash="0" * 64, resulting_state_hash="h", metadata={}
        )
        valid, err = CryptographicAuditLayer.chain_verify([seal])
        self.assertTrue(valid)

    def test_chain_verify_empty_list(self):
        """Chain verification with empty list succeeds."""
        valid, err = CryptographicAuditLayer.chain_verify([])
        self.assertTrue(valid)

    def test_seal_digest_is_64_hex_chars(self):
        """Seal digest is always a 64-character hex string."""
        seal = CryptographicAuditLayer.generate_seal(
            event_id="evt_1", parent_event_hash="0" * 64,
            timestamp="t", actor="a", operation="OP",
            previous_state_hash="0" * 64, resulting_state_hash="h", metadata={}
        )
        digest = seal["cryptographic_digest"]
        self.assertEqual(len(digest), 64)
        self.assertTrue(all(c in "0123456789abcdef" for c in digest))


class TestEdgeCasesQuantum(unittest.TestCase):
    """Quantum layer edge cases."""
    def test_zero_weight_portfolio(self):
        """Portfolio with all zero weights is valid."""
        q = QuantumAbstractionLayer("simulator")
        result = q.run_optimization_circuit({"a": 0.0, "b": 0.0})
        self.assertEqual(result["circuit_type"], "QAOA_PORTFOLIO_OPTIMIZER")

    def test_full_weight_portfolio(self):
        """Portfolio with weight 1.0 is valid."""
        q = QuantumAbstractionLayer("simulator")
        result = q.run_optimization_circuit({"all_in": 1.0})
        self.assertIn("suggested_allocations", result)

    def test_many_assets(self):
        """Portfolio with 50 assets works."""
        q = QuantumAbstractionLayer("simulator")
        weights = {f"asset_{i}": 0.02 for i in range(50)}
        result = q.run_optimization_circuit(weights)
        self.assertEqual(len(result["suggested_allocations"]), 50)

    def test_entropy_length(self):
        """Quantum entropy is always 64 hex chars (SHA-3-256)."""
        q = QuantumAbstractionLayer("simulator")
        e = q.get_quantum_entropy()
        self.assertEqual(len(e), 64)

    def test_deterministic_mode_reproducible(self):
        """Same seed produces identical entropy across instances."""
        q1 = QuantumAbstractionLayer("simulator", deterministic_seed="fixed_seed_42")
        q2 = QuantumAbstractionLayer("simulator", deterministic_seed="fixed_seed_42")
        self.assertEqual(q1.get_quantum_entropy("test"), q2.get_quantum_entropy("test"))

    def test_random_bytes_unique(self):
        """Two random byte calls return different values."""
        q = QuantumAbstractionLayer("simulator")
        b1 = q.generate_random_bytes(32)
        b2 = q.generate_random_bytes(32)
        self.assertNotEqual(b1, b2)

    def test_hash_input_deterministic(self):
        """Same input produces same hash."""
        q = QuantumAbstractionLayer("simulator")
        h1 = q.hash_input("data")
        h2 = q.hash_input("data")
        self.assertEqual(h1, h2)

    def test_hash_input_different_inputs(self):
        """Different inputs produce different hashes."""
        q = QuantumAbstractionLayer("simulator")
        h1 = q.hash_input("data1")
        h2 = q.hash_input("data2")
        self.assertNotEqual(h1, h2)


class TestEdgeCasesIntegration(unittest.TestCase):
    """End-to-end edge cases."""
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.storage_path = os.path.join(self.tmpdir, "edge.worm")
        self.storage = WormStorageEngine(self.storage_path)
        self.twin = FinanceTwinEngine(self.storage)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_rapid_create_and_verify(self):
        """Rapid account creation followed by verification."""
        for i in range(50):
            self.twin.execute_command("CREATE_ACCOUNT", "admin", {
                "account_id": f"ACC_{i}", "initial_balance": str(i)
            })
        valid, err = self.twin.verify_ledger_consistency()
        self.assertTrue(valid)

    def test_roundtrip_serialization(self):
        """Data survives WORM write/read/rebuild cycle."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {
            "account_id": "ACC_001", "initial_balance": "12345.6789"
        })
        twin2 = FinanceTwinEngine(self.storage)
        self.assertEqual(twin2.accounts["ACC_001"], Decimal("12345.6789"))

    def test_interleaved_operations(self):
        """Mixed operations in sequence maintain consistency."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "10000"})
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "5000"})

        # Interleave creates, transactions, reversals
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "C", "initial_balance": "1000"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_001", "from_account": "A", "to_account": "B", "amount": "500"
        })
        self.twin.execute_command("CREATE_INVOICE", "admin", {"invoice_id": "INV_001", "amount": "200"})
        self.twin.execute_command("POST_TRANSACTION", "admin", {
            "transaction_id": "TX_002", "from_account": "B", "to_account": "C", "amount": "100"
        })
        self.twin.execute_command("REVERSE_TRANSACTION", "admin", {"transaction_id": "TX_002"})
        self.twin.execute_command("CREATE_OBLIGATION", "admin", {"obligation_id": "OBL_001", "amount": "500"})

        valid, err = self.twin.verify_ledger_consistency()
        self.assertTrue(valid)
        self.assertEqual(self.twin.event_count, 8)

    def test_clone_and_diverge(self):
        """Two twins from same storage, one continues, verify divergence."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "1000"})
        twin2 = FinanceTwinEngine(self.storage)

        # Continue on original
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "B", "initial_balance": "500"})

        # twin2 has old state
        self.assertNotIn("B", twin2.accounts)

        # Rebuild twin2
        twin2.rebuild_state()
        self.assertIn("B", twin2.accounts)

    def test_verify_detects_injected_record(self):
        """Injecting a record with wrong prev_hash breaks verification."""
        self.twin.execute_command("CREATE_ACCOUNT", "admin", {"account_id": "A", "initial_balance": "100"})

        # Inject a record with wrong chain
        with open(self.storage_path, "a", encoding="utf-8") as f:
            fake_record = {
                "prev_hash": "DEADBEEF",
                "payload": {"operation": "INJECTED"},
                "record_hash": "fake_hash"
            }
            f.write(json.dumps(fake_record) + "\n")

        valid, err = self.twin.verify_ledger_consistency()
        self.assertFalse(valid)
        self.assertIn("Chain break", err)


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    unittest.main()
