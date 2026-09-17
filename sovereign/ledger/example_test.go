package ledger

import (
	"fmt"
	"testing"
)

// ExampleLedger demonstrates ledger usage
func ExampleLedger(t *testing.T) {
	// Create ledger
	ledger := NewLedger("example-session")

	// Build and append events
	event1 := NewEventBuilder("txn-001").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("Transfer 100 USD from Alice to Bob").
		WithNormalizedContent("Transfer 100 USD from Alice to Bob").
		WithEvaluationVersion("1.0").
		WithConstraintVersion("1.0").
		WithMetadata("amount", 100).
		WithMetadata("currency", "USD").
		WithMetadata("recipient", "Bob").
		Build()

	event2 := NewEventBuilder("txn-002").
		WithSpeaker("Bob").
		WithEventType("transaction").
		WithRawContent("Transfer 50 USD from Bob to Charlie").
		WithNormalizedContent("Transfer 50 USD from Bob to Charlie").
		WithEvaluationVersion("1.0").
		WithConstraintVersion("1.0").
		WithMetadata("amount", 50).
		WithMetadata("currency", "USD").
		WithMetadata("recipient", "Charlie").
		Build()

	event3 := NewEventBuilder("audit-001").
		WithSpeaker("Auditor").
		WithEventType("audit").
		WithRawContent("Ledger audit check passed").
		WithNormalizedContent("Ledger audit check passed").
		WithEvaluationVersion("1.0").
		WithConstraintVersion("1.0").
		WithMetadata("audit_level", "high").
		Build()

	// Append all events
	ledger.AppendEvent(event1)
	ledger.AppendEvent(event2)
	ledger.AppendEvent(event3)

	fmt.Println("=== Event Appending ===")
	fmt.Printf("Appended %d events\n", ledger.GetEventCount())

	// Verify ledger integrity
	if err := ledger.Verify(); err != nil {
		t.Fatalf("Verification failed: %v", err)
	}

	fmt.Println("\n=== Ledger Verification ===")
	fmt.Printf("Ledger verified: %v\n", ledger.IsVerified())
	fmt.Printf("Root hash: %s\n", ledger.GetRootHash()[:16]+"...")

	// Get statistics
	stats := ledger.GetStats()

	fmt.Println("\n=== Statistics ===")
	fmt.Printf("Total events: %d\n", stats.TotalEvents)
	fmt.Printf("Event types: %v\n", stats.EventsByType)
	fmt.Printf("Speakers: %v\n", stats.EventsBySpeaker)

	// Query events by type
	txns, _ := ledger.EventsByType("transaction")
	fmt.Printf("\nTransaction count: %d\n", len(txns))

	// Query events by speaker
	aliceEvents, _ := ledger.EventsBySpeaker("Alice")
	fmt.Printf("Events from Alice: %d\n", len(aliceEvents))

	// Get specific event
	event, _ := ledger.GetEvent(1)
	fmt.Printf("\nFirst event: %s by %s\n", event.EventID, event.Speaker)

	// Replay ledger
	replay, _ := ledger.Replay()
	fmt.Printf("Replayed events: %d\n", len(replay))

	// Create snapshot
	snapshot := ledger.CreateSnapshot()
	fmt.Printf("\nSnapshot created at: %d\n", snapshot.SnapshotTime)
	fmt.Printf("Snapshot - Sealed: %v, Verified: %v\n", snapshot.Sealed, snapshot.Verified)

	// Seal ledger
	if err := ledger.Seal(); err != nil {
		t.Fatalf("Seal failed: %v", err)
	}

	fmt.Printf("\nLedger sealed: %v\n", ledger.IsSealed())

	// Export ledger
	exportData, _ := ledger.Export()
	fmt.Printf("Export size: %d bytes\n", len(exportData))

	// Tamper detection
	isTampered := ledger.TamperDetection()
	fmt.Printf("Tampered: %v\n", isTampered)

	// Audit log
	auditLog := ledger.GetAuditLog()
	fmt.Printf("\nAudit log entries: %d\n", len(auditLog))
}

// ExampleMerkleTree demonstrates Merkle tree usage
func ExampleMerkleTree(t *testing.T) {
	fmt.Println("\n=== Merkle Tree Example ===")

	// Create event hashes
	hashes := []string{"hash1", "hash2", "hash3", "hash4"}
	tree := NewEventMerkleTree(hashes)

	fmt.Printf("Merkle root: %s\n", tree.Root()[:16]+"...")

	// Generate and verify proof for event 0
	proof := tree.Proof(0)
	fmt.Printf("Proof length for event 0: %d\n", len(proof))

	verified := tree.VerifyProof(0, proof, hashes[0])
	fmt.Printf("Proof verification: %v\n", verified)
}

// ExampleSerialization demonstrates serialization
func ExampleSerialization(t *testing.T) {
	fmt.Println("\n=== Serialization Example ===")

	ledger := NewLedger("serialization-test")

	event := NewEventBuilder("evt-001").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("Test event").
		Build()

	ledger.AppendEvent(event)
	ledger.Verify()

	// JSON serialization
	opts := SerializationOptions{
		Format:          FormatJSON,
		IncludeMetadata: true,
		IncludeStats:    true,
	}

	jsonData, _ := ledger.SerializeWithOptions(opts)
	fmt.Printf("JSON serialization: %d bytes\n", len(jsonData))

	// Canonical export
	canonical, _ := ledger.ExportCanonical()
	fmt.Printf("Canonical export: %d bytes\n", len(canonical))
}

// ExampleEventQuery demonstrates event querying
func ExampleEventQuery(t *testing.T) {
	fmt.Println("\n=== Event Query Example ===")

	ledger := NewLedger("query-test")

	// Add diverse events
	for i := 0; i < 5; i++ {
		speaker := "Alice"
		if i%2 == 0 {
			speaker = "Bob"
		}

		event := NewEventBuilder(fmt.Sprintf("evt-%d", i)).
			WithSpeaker(speaker).
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("Event %d", i)).
			Build()

		ledger.AppendEvent(event)
	}

	// Query by speaker
	aliceEvents, _ := ledger.EventsBySpeaker("Alice")
	fmt.Printf("Alice events: %d\n", len(aliceEvents))

	bobEvents, _ := ledger.EventsBySpeaker("Bob")
	fmt.Printf("Bob events: %d\n", len(bobEvents))

	// Query by type
	txns, _ := ledger.EventsByType("transaction")
	fmt.Printf("Transaction events: %d\n", len(txns))

	// Get range
	rangeEvents, _ := ledger.GetRange(1, 3)
	fmt.Printf("Events in range [1,3]: %d\n", len(rangeEvents))
}

// TestCompleteWorkflow tests complete ledger workflow
func TestCompleteWorkflow(t *testing.T) {
	// Initialize ledger
	config := LedgerConfig{
		SessionID:        "workflow-test",
		MaxEvents:        10000,
		CompressionLevel: 6,
	}
	ledger := NewLedgerWithConfig(config)

	// Phase 1: Build event batch
	eventBatch := []Event{}
	for i := 0; i < 100; i++ {
		speaker := "Alice"
		if i%3 == 0 {
			speaker = "Bob"
		} else if i%3 == 1 {
			speaker = "Charlie"
		}

		event := NewEventBuilder(fmt.Sprintf("evt-%04d", i)).
			WithSpeaker(speaker).
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("Transaction %d", i)).
			WithNormalizedContent(fmt.Sprintf("Transaction %d", i)).
			WithEvaluationVersion("1.0").
			WithConstraintVersion("1.0").
			Build()

		eventBatch = append(eventBatch, event)
	}

	// Phase 2: Append events
	for _, event := range eventBatch {
		if err := ledger.AppendEvent(event); err != nil {
			t.Fatalf("Failed to append event: %v", err)
		}
	}

	if ledger.GetEventCount() != 100 {
		t.Fatalf("Expected 100 events, got %d", ledger.GetEventCount())
	}

	// Phase 3: Verify integrity
	if err := ledger.Verify(); err != nil {
		t.Fatalf("Verification failed: %v", err)
	}

	// Phase 4: Query and analyze
	stats := ledger.GetStats()
	if stats.TotalEvents != 100 {
		t.Fatalf("Stats mismatch: %d vs 100", stats.TotalEvents)
	}

	// Phase 5: Export and serialize
	exportData, err := ledger.Export()
	if err != nil || len(exportData) == 0 {
		t.Fatal("Export failed")
	}

	// Phase 6: Seal and finalize
	if err := ledger.Seal(); err != nil {
		t.Fatalf("Seal failed: %v", err)
	}

	if !ledger.IsSealed() {
		t.Fatal("Ledger not sealed")
	}

	// Phase 7: Final verification
	if ledger.TamperDetection() {
		t.Fatal("Tamper detected in sealed ledger")
	}

	fmt.Printf("\n✓ Complete workflow test passed\n")
	fmt.Printf("  - Events processed: %d\n", ledger.GetEventCount())
	fmt.Printf("  - Root hash: %s...\n", ledger.GetRootHash()[:16])
	fmt.Printf("  - Verified: %v\n", ledger.IsVerified())
	fmt.Printf("  - Sealed: %v\n", ledger.IsSealed())
}
