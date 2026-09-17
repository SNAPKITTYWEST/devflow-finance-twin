package ledger

import (
	"fmt"
	"testing"
	"time"
)

// TestNewLedger tests ledger creation
func TestNewLedger(t *testing.T) {
	ledger := NewLedger("test-session")
	if ledger.sessionID != "test-session" {
		t.Errorf("expected session ID 'test-session', got %s", ledger.sessionID)
	}
	if ledger.GetEventCount() != 0 {
		t.Errorf("expected 0 events, got %d", ledger.GetEventCount())
	}
	if ledger.IsVerified() {
		t.Error("new ledger should not be verified")
	}
}

// TestAppendEvent tests adding events to ledger
func TestAppendEvent(t *testing.T) {
	ledger := NewLedger("test-session")

	event := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("transfer 100 units").
		WithNormalizedContent("transfer 100 units").
		WithEvaluationVersion("1.0").
		WithConstraintVersion("1.0").
		Build()

	if err := ledger.AppendEvent(event); err != nil {
		t.Errorf("failed to append event: %v", err)
	}

	if ledger.GetEventCount() != 1 {
		t.Errorf("expected 1 event, got %d", ledger.GetEventCount())
	}

	if ledger.GetRootHash() == "" {
		t.Error("expected non-empty root hash")
	}
}

// TestHashChaining tests hash chain integrity
func TestHashChaining(t *testing.T) {
	ledger := NewLedger("test-session")

	event1 := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("content1").
		Build()

	event2 := NewEventBuilder("event-2").
		WithSpeaker("Bob").
		WithEventType("transaction").
		WithRawContent("content2").
		Build()

	ledger.AppendEvent(event1)
	ledger.AppendEvent(event2)

	retrieved, _ := ledger.GetEvent(2)
	if retrieved.PreviousEventHash == "" {
		t.Error("event 2 should have previous hash")
	}

	if retrieved.SequenceNumber != 2 {
		t.Errorf("expected sequence 2, got %d", retrieved.SequenceNumber)
	}
}

// TestVerify tests ledger verification
func TestVerify(t *testing.T) {
	ledger := NewLedger("test-session")

	for i := 0; i < 5; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	if err := ledger.Verify(); err != nil {
		t.Errorf("verification failed: %v", err)
	}

	if !ledger.IsVerified() {
		t.Error("ledger should be verified")
	}
}

// TestExport tests ledger export
func TestExport(t *testing.T) {
	ledger := NewLedger("test-session")

	event := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("content").
		Build()

	ledger.AppendEvent(event)
	ledger.Verify()

	data, err := ledger.Export()
	if err != nil {
		t.Errorf("export failed: %v", err)
	}

	if len(data) == 0 {
		t.Error("exported data should not be empty")
	}
}

// TestReplay tests ledger replay
func TestReplay(t *testing.T) {
	ledger := NewLedger("test-session")

	for i := 0; i < 3; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	ledger.Verify()

	replay, err := ledger.Replay()
	if err != nil {
		t.Errorf("replay failed: %v", err)
	}

	if len(replay) != 3 {
		t.Errorf("expected 3 events in replay, got %d", len(replay))
	}
}

// TestTamperDetection tests tamper detection
func TestTamperDetection(t *testing.T) {
	ledger := NewLedger("test-session")

	event := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("content").
		Build()

	ledger.AppendEvent(event)
	ledger.Verify()

	isTampered := ledger.TamperDetection()
	if isTampered {
		t.Error("verified ledger should not be detected as tampered")
	}
}

// TestSeal tests ledger sealing
func TestSeal(t *testing.T) {
	ledger := NewLedger("test-session")

	event := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("content").
		Build()

	ledger.AppendEvent(event)
	ledger.Verify()

	if err := ledger.Seal(); err != nil {
		t.Errorf("seal failed: %v", err)
	}

	if !ledger.IsSealed() {
		t.Error("ledger should be sealed")
	}

	// Try to append after seal
	event2 := NewEventBuilder("event-2").
		WithSpeaker("Bob").
		WithEventType("transaction").
		WithRawContent("content2").
		Build()

	if err := ledger.AppendEvent(event2); err == nil {
		t.Error("should not allow append to sealed ledger")
	}
}

// TestQuery tests event querying
func TestQuery(t *testing.T) {
	ledger := NewLedger("test-session")

	for i := 0; i < 5; i++ {
		speaker := "Alice"
		if i%2 == 0 {
			speaker = "Bob"
		}
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker(speaker).
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	results, _ := ledger.EventsBySpeaker("Alice")
	if len(results) != 2 {
		t.Errorf("expected 2 events from Alice, got %d", len(results))
	}

	results, _ = ledger.EventsBySpeaker("Bob")
	if len(results) != 3 {
		t.Errorf("expected 3 events from Bob, got %d", len(results))
	}
}

// TestEventBuilder tests event builder fluent interface
func TestEventBuilder(t *testing.T) {
	event := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("transfer 100").
		WithNormalizedContent("transfer 100").
		WithEvaluationVersion("1.0").
		WithConstraintVersion("1.0").
		WithMetadata("amount", 100).
		WithMetadata("currency", "USD").
		Build()

	if event.EventID != "event-1" {
		t.Errorf("expected ID 'event-1', got %s", event.EventID)
	}
	if event.Speaker != "Alice" {
		t.Errorf("expected speaker 'Alice', got %s", event.Speaker)
	}
	if event.EventType != "transaction" {
		t.Errorf("expected type 'transaction', got %s", event.EventType)
	}
	if len(event.Metadata) != 2 {
		t.Errorf("expected 2 metadata entries, got %d", len(event.Metadata))
	}
}

// TestMerkleTree tests Merkle tree construction
func TestMerkleTree(t *testing.T) {
	hashes := []string{
		"hash1",
		"hash2",
		"hash3",
		"hash4",
	}

	mt := NewEventMerkleTree(hashes)
	root := mt.Root()

	if root == "" {
		t.Error("merkle root should not be empty")
	}

	// Test proof verification
	proof := mt.Proof(0)
	if proof == nil {
		t.Error("proof should not be nil")
	}

	verified := mt.VerifyProof(0, proof, hashes[0])
	if !verified {
		t.Error("merkle proof verification failed")
	}
}

// TestEventStats tests statistics collection
func TestEventStats(t *testing.T) {
	ledger := NewLedger("test-session")

	for i := 0; i < 10; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	stats := ledger.GetStats()
	if stats.TotalEvents != 10 {
		t.Errorf("expected 10 events, got %d", stats.TotalEvents)
	}
	if stats.EventsByType["transaction"] != 10 {
		t.Errorf("expected 10 transaction events, got %d", stats.EventsByType["transaction"])
	}
	if stats.EventsBySpeaker["Alice"] != 10 {
		t.Errorf("expected 10 events from Alice, got %d", stats.EventsBySpeaker["Alice"])
	}
}

// TestGetRange tests range retrieval
func TestGetRange(t *testing.T) {
	ledger := NewLedger("test-session")

	for i := 0; i < 10; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	results, err := ledger.GetRange(1, 5)
	if err != nil {
		t.Errorf("GetRange failed: %v", err)
	}
	if len(results) != 5 {
		t.Errorf("expected 5 events, got %d", len(results))
	}
}

// TestLedgerSnapshot tests snapshot creation
func TestLedgerSnapshot(t *testing.T) {
	ledger := NewLedger("test-session")

	event := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("content").
		Build()

	ledger.AppendEvent(event)
	ledger.Verify()

	snapshot := ledger.CreateSnapshot()
	if snapshot.SessionID != "test-session" {
		t.Errorf("expected session 'test-session', got %s", snapshot.SessionID)
	}
	if snapshot.EventCount != 1 {
		t.Errorf("expected 1 event, got %d", snapshot.EventCount)
	}
	if !snapshot.Verified {
		t.Error("snapshot should be verified")
	}
}

// TestConcurrentAppend tests concurrent event appending
func TestConcurrentAppend(t *testing.T) {
	ledger := NewLedger("test-session")

	done := make(chan bool)
	for i := 0; i < 5; i++ {
		go func(id int) {
			event := NewEventBuilder(fmt.Sprintf("event-%d", id)).
				WithSpeaker("Alice").
				WithEventType("transaction").
				WithRawContent(fmt.Sprintf("content-%d", id)).
				Build()
			ledger.AppendEvent(event)
			done <- true
		}(i)
	}

	for i := 0; i < 5; i++ {
		<-done
	}

	if ledger.GetEventCount() != 5 {
		t.Errorf("expected 5 events, got %d", ledger.GetEventCount())
	}
}

// TestEventByID tests event retrieval by ID
func TestEventByID(t *testing.T) {
	ledger := NewLedger("test-session")

	event := NewEventBuilder("unique-event-id").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("content").
		Build()

	ledger.AppendEvent(event)

	retrieved, err := ledger.GetEventByID("unique-event-id")
	if err != nil {
		t.Errorf("failed to retrieve event: %v", err)
	}
	if retrieved.EventID != "unique-event-id" {
		t.Errorf("expected ID 'unique-event-id', got %s", retrieved.EventID)
	}
}

// TestExportCanonical tests canonical export
func TestExportCanonical(t *testing.T) {
	ledger := NewLedger("test-session")

	event := NewEventBuilder("event-1").
		WithSpeaker("Alice").
		WithEventType("transaction").
		WithRawContent("content").
		Build()

	ledger.AppendEvent(event)

	data, err := ledger.ExportCanonical()
	if err != nil {
		t.Errorf("export canonical failed: %v", err)
	}

	if len(data) == 0 {
		t.Error("canonical export should not be empty")
	}
}

// TestEventContentHash tests content hashing
func TestEventContentHash(t *testing.T) {
	content := "test content"
	hash1 := computeContentHash(content)
	hash2 := computeContentHash(content)

	if hash1 != hash2 {
		t.Error("same content should produce same hash")
	}

	hash3 := computeContentHash("different content")
	if hash1 == hash3 {
		t.Error("different content should produce different hash")
	}
}

// TestEventsByType tests event filtering by type
func TestEventsByType(t *testing.T) {
	ledger := NewLedger("test-session")

	for i := 0; i < 3; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	for i := 3; i < 5; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Bob").
			WithEventType("audit").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	txns, _ := ledger.EventsByType("transaction")
	if len(txns) != 3 {
		t.Errorf("expected 3 transactions, got %d", len(txns))
	}

	audits, _ := ledger.EventsByType("audit")
	if len(audits) != 2 {
		t.Errorf("expected 2 audits, got %d", len(audits))
	}
}

// BenchmarkAppendEvent benchmarks event appending
func BenchmarkAppendEvent(b *testing.B) {
	ledger := NewLedger("bench-session")

	for i := 0; i < b.N; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}
}

// BenchmarkVerify benchmarks ledger verification
func BenchmarkVerify(b *testing.B) {
	ledger := NewLedger("bench-session")

	for i := 0; i < 1000; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ledger.Verify()
	}
}

// BenchmarkExport benchmarks ledger export
func BenchmarkExport(b *testing.B) {
	ledger := NewLedger("bench-session")

	for i := 0; i < 1000; i++ {
		event := NewEventBuilder(fmt.Sprintf("event-%d", i)).
			WithSpeaker("Alice").
			WithEventType("transaction").
			WithRawContent(fmt.Sprintf("content-%d", i)).
			Build()
		ledger.AppendEvent(event)
	}

	ledger.Verify()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ledger.Export()
	}
}
