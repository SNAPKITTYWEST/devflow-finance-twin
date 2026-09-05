"""
Devflow Finance Twin — Cold Boot + ICP Anchor Integration Tests
"""
import sys
import os
import json
import unittest
import tempfile
import shutil
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from cold_boot import (
    ColdBootProtocol, ColdBootError, Phase1Error, Phase2Error,
    WORMFullError, SealFailError, WORMMetadata, WORMRecord,
    RecordType, GENESIS_ROOT, ZERO_HASH, cold_boot
)
from icp_anchor import (
    ICPAnchorBridge, ICPAnchorError, AnchorChainError,
    AnchorRecord, CanisterState, quick_anchor
)


# ── Cold Boot Phase 1 Tests ──────────────────────────────────────────────────

class TestColdBootPhase1(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.worm_path = os.path.join(self.tmpdir, "test.worm")

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_phase1_returns_sha256_hash(self):
        protocol = ColdBootProtocol(self.worm_path)
        root_hash = protocol.phase1_rom_anchor()
        self.assertEqual(len(root_hash), 64)
        self.assertTrue(all(c in "0123456789abcdef" for c in root_hash))

    def test_phase1_deterministic(self):
        protocol = ColdBootProtocol(self.worm_path)
        h1 = protocol.phase1_rom_anchor(b"firmware_data")
        h2 = protocol.phase1_rom_anchor(b"firmware_data")
        self.assertEqual(h1, h2)

    def test_phase1_different_inputs(self):
        protocol = ColdBootProtocol(self.worm_path)
        h1 = protocol.phase1_rom_anchor(b"firmware_a")
        h2 = protocol.phase1_rom_anchor(b"firmware_b")
        self.assertNotEqual(h1, h2)

    def test_phase1_stores_rom_hash(self):
        protocol = ColdBootProtocol(self.worm_path)
        root_hash = protocol.phase1_rom_anchor(b"test")
        self.assertEqual(protocol._rom_hash, root_hash)


# ── Cold Boot Phase 2 Tests ──────────────────────────────────────────────────

class TestColdBootPhase2(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.worm_path = os.path.join(self.tmpdir, "test.worm")

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_phase2_initializes_metadata(self):
        protocol = ColdBootProtocol(self.worm_path)
        metadata = protocol.phase2_bridge_init()
        self.assertEqual(metadata.head, 0)
        self.assertEqual(metadata.tail, 0)
        self.assertEqual(metadata.root_slot, GENESIS_ROOT)

    def test_phase2_creates_storage_file(self):
        protocol = ColdBootProtocol(self.worm_path)
        protocol.phase2_bridge_init()
        self.assertTrue(Path(self.worm_path).exists())

    def test_phase2_loads_existing_state(self):
        # Pre-populate WORM
        with open(self.worm_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({"prev_hash": ZERO_HASH, "payload": {"op": "test"}, "record_hash": "abc123"}) + "\n")
            f.write(json.dumps({"prev_hash": "abc123", "payload": {"op": "test2"}, "record_hash": "def456"}) + "\n")

        protocol = ColdBootProtocol(self.worm_path)
        metadata = protocol.phase2_bridge_init()
        self.assertEqual(metadata.record_count, 2)

    def test_phase2_registers_svc_handlers(self):
        protocol = ColdBootProtocol(self.worm_path)
        protocol.phase2_bridge_init()
        self.assertIn(254, protocol._svc_handlers)
        self.assertIn(255, protocol._svc_handlers)
        self.assertIn(253, protocol._svc_handlers)


# ── Cold Boot Phase 3 Tests ──────────────────────────────────────────────────

class TestColdBootPhase3(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.worm_path = os.path.join(self.tmpdir, "test.worm")

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_phase3_requires_phase2(self):
        protocol = ColdBootProtocol(self.worm_path)
        with self.assertRaises(Phase2Error):
            protocol.phase3_treasury_driver()

    def test_phase3_completes_cold_boot(self):
        protocol = ColdBootProtocol(self.worm_path)
        protocol.phase1_rom_anchor()
        protocol.phase2_bridge_init()
        protocol.phase3_treasury_driver()  # Should not raise
        self.assertTrue(protocol._initialized)


# ── Cold Boot Full Sequence Tests ────────────────────────────────────────────

class TestColdBootFull(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.worm_path = os.path.join(self.tmpdir, "test.worm")

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_full_cold_boot(self):
        protocol = cold_boot(self.worm_path)
        self.assertTrue(protocol._initialized)
        # Root is ZERO_HASH until records are written (no genesis record in WORM yet)
        self.assertIsNotNone(protocol.get_root_hash())
        self.assertEqual(len(protocol.get_root_hash()), 64)

    def test_cold_boot_write_read_verify(self):
        protocol = cold_boot(self.worm_path)

        # Write a record
        record_hash = protocol.write_once({"op": "CREATE_ACCOUNT", "id": "ACC_001"})
        self.assertEqual(len(record_hash), 64)

        # Read it back
        record = protocol.read_many(0)
        self.assertEqual(record["payload"]["op"], "CREATE_ACCOUNT")

        # Verify chain
        valid, err = protocol.verify_chain()
        self.assertTrue(valid)


# ── WORM Record Serialization Tests ──────────────────────────────────────────

class TestWORMRecord(unittest.TestCase):
    def test_serialize_deserialize_roundtrip(self):
        rec = WORMRecord(
            record_type=RecordType.ANCHOR,
            length=100,
            timestamp=1234567890,
            prev_hash="a" * 64,
            record_hash="b" * 64,
            payload={"op": "test", "value": 42}
        )
        data = rec.serialize()
        rec2 = WORMRecord.deserialize(data)
        self.assertEqual(rec2.payload, rec.payload)
        self.assertEqual(rec2.record_type, RecordType.ANCHOR)

    def test_deserialize_short_data(self):
        with self.assertRaises(ColdBootError):
            WORMRecord.deserialize(b"short")

    def test_deserialize_bad_magic(self):
        with self.assertRaises(ColdBootError):
            WORMRecord.deserialize(b"BAD_MAGIC" + b"\x00" * 60)


# ── ICP Anchor Tests ─────────────────────────────────────────────────────────

class TestICPAnchor(unittest.TestCase):
    def setUp(self):
        self.bridge = ICPAnchorBridge("test-canister-001")

    def test_initialize_creates_genesis(self):
        state = self.bridge.initialize()
        self.assertEqual(state.total_anchors, 1)
        self.assertEqual(state.latest_root_hash, ZERO_HASH)

    def test_anchor_state(self):
        self.bridge.initialize()
        anchor = self.bridge.anchor_state("a" * 64, 10)
        self.assertEqual(anchor.worm_root_hash, "a" * 64)
        self.assertEqual(anchor.record_count, 10)
        self.assertEqual(len(self.bridge.state.anchor_chain), 2)

    def test_anchor_chain_linkage(self):
        self.bridge.initialize()
        a1 = self.bridge.anchor_state("a" * 64, 5)
        a2 = self.bridge.anchor_state("b" * 64, 10)
        self.assertEqual(a2.previous_anchor_hash, a1.anchor_hash)

    def test_verify_chain_valid(self):
        self.bridge.initialize()
        self.bridge.anchor_state("a" * 64, 5)
        self.bridge.anchor_state("b" * 64, 10)
        valid, err = self.bridge.verify_chain()
        self.assertTrue(valid)
        self.assertIsNone(err)

    def test_verify_chain_tampered(self):
        self.bridge.initialize()
        self.bridge.anchor_state("a" * 64, 5)
        # Tamper with anchor
        self.bridge.state.anchor_chain[1].worm_root_hash = "TAMPERED"
        valid, err = self.bridge.verify_chain()
        self.assertFalse(valid)
        self.assertIn("integrity", err.lower())

    def test_anchor_rejects_zero_hash(self):
        self.bridge.initialize()
        with self.assertRaises(ICPAnchorError):
            self.bridge.anchor_state(ZERO_HASH, 5)

    def test_export_proof(self):
        self.bridge.initialize()
        self.bridge.anchor_state("a" * 64, 5)
        proof = self.bridge.export_proof(1)
        self.assertIsNotNone(proof)
        self.assertEqual(proof["canister_id"], "test-canister-001")
        self.assertTrue(proof["verification"]["hash_valid"])

    def test_export_proof_invalid_index(self):
        self.bridge.initialize()
        self.assertIsNone(self.bridge.export_proof(99))

    def test_get_canister_state(self):
        self.bridge.initialize()
        state = self.bridge.get_canister_state()
        self.assertEqual(state["total_anchors"], 1)
        self.assertEqual(state["canister_id"], "test-canister-001")

    def test_quick_anchor(self):
        anchor = quick_anchor("quick-canister", "a" * 64, 100)
        self.assertEqual(anchor.worm_root_hash, "a" * 64)
        self.assertEqual(anchor.record_count, 100)


class TestICPAnchorSync(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.worm_path = os.path.join(self.tmpdir, "sync.worm")
        self.bridge = ICPAnchorBridge("sync-canister")

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_sync_from_worm(self):
        # Create WORM with records
        with open(self.worm_path, "w", encoding="utf-8") as f:
            f.write(json.dumps({"prev_hash": ZERO_HASH, "payload": {"op": "a"}, "record_hash": "h1"}) + "\n")
            f.write(json.dumps({"prev_hash": "h1", "payload": {"op": "b"}, "record_hash": "h2"}) + "\n")

        self.bridge.initialize()
        anchor = self.bridge.sync_from_worm(self.worm_path)
        self.assertIsNotNone(anchor)
        self.assertEqual(anchor.worm_root_hash, "h2")
        self.assertEqual(anchor.record_count, 2)

    def test_sync_empty_worm(self):
        with open(self.worm_path, "w") as f:
            pass

        self.bridge.initialize()
        anchor = self.bridge.sync_from_worm(self.worm_path)
        self.assertIsNotNone(anchor)
        # Empty WORM gets a genesis hash, not ZERO_HASH
        self.assertEqual(len(anchor.worm_root_hash), 64)
        self.assertEqual(anchor.record_count, 0)

    def test_sync_nonexistent_file(self):
        self.bridge.initialize()
        anchor = self.bridge.sync_from_worm("/nonexistent/path.worm")
        self.assertIsNone(anchor)


# ── Integration: Cold Boot + ICP Anchor ──────────────────────────────────────

class TestColdBootICPIntegration(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.worm_path = os.path.join(self.tmpdir, "integ.worm")

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_cold_boot_then_anchor(self):
        """Full flow: cold boot → write records → anchor to ICP."""
        # 1. Cold boot
        protocol = cold_boot(self.worm_path)

        # 2. Write records
        protocol.write_once({"op": "CREATE_ACCOUNT", "id": "ACC_001", "balance": "1000"})
        protocol.write_once({"op": "CREATE_ACCOUNT", "id": "ACC_002", "balance": "500"})
        protocol.write_once({"op": "POST_TRANSACTION", "id": "TX_001", "amount": "100"})

        # 3. Verify WORM chain
        valid, err = protocol.verify_chain()
        self.assertTrue(valid)

        # 4. Anchor to ICP
        bridge = ICPAnchorBridge("integ-canister")
        bridge.initialize()
        anchor = bridge.sync_from_worm(self.worm_path)

        self.assertIsNotNone(anchor)
        self.assertEqual(anchor.record_count, 3)
        self.assertEqual(anchor.worm_root_hash, protocol.get_root_hash())

        # 5. Verify ICP chain
        valid, err = bridge.verify_chain()
        self.assertTrue(valid)

    def test_multiple_anchors(self):
        """Multiple anchor cycles maintain chain integrity."""
        protocol = cold_boot(self.worm_path)
        bridge = ICPAnchorBridge("multi-canister")
        bridge.initialize()

        # Write and anchor in cycles
        for cycle in range(5):
            protocol.write_once({"op": "CYCLE", "cycle": cycle})
            anchor = bridge.sync_from_worm(self.worm_path)
            self.assertIsNotNone(anchor)

        # Verify full chain
        valid, err = bridge.verify_chain()
        self.assertTrue(valid)
        self.assertEqual(bridge.state.total_anchors, 6)  # genesis + 5

    def test_proof_export_roundtrip(self):
        """Export proof, verify it contains correct data."""
        protocol = cold_boot(self.worm_path)
        protocol.write_once({"op": "TEST"})

        bridge = ICPAnchorBridge("proof-canister")
        bridge.initialize()
        bridge.sync_from_worm(self.worm_path)

        proof = bridge.export_proof(1)  # First real anchor (index 1, after genesis)
        self.assertIsNotNone(proof)
        self.assertTrue(proof["verification"]["hash_valid"])
        self.assertTrue(proof["verification"]["chain_valid"])
        self.assertEqual(proof["anchor"]["record_count"], 1)


if __name__ == "__main__":
    unittest.main()
