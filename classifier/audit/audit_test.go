package audit

import (
	"testing"
	"time"

	"devflow-finance-twin/classifier/primitives"
)

func TestCanonicalEncode(t *testing.T) {
	envelope := &primitives.DecisionEnvelope{
		Timestamp:    time.Now().UnixNano(),
		ModelID:      "model-123",
		ModelVersion: "1.0.0",
		InputHash:    "input-hash-xyz",
		RouterHash:   "router-hash-abc",
		Disposition:  "CLASS_A",
		Route:        "main",
		RouteChoices: []*primitives.RouteChoice{
			{
				Name:     "route-a",
				Selected: true,
				Probabilities: map[string]float64{
					"CLASS_A": 0.8,
					"CLASS_B": 0.2,
				},
			},
		},
		NoulChoices: []*primitives.NoulChoice{
			{
				Name:        "noul-1",
				Decision:    "CLASS_A",
				Probability: 0.95,
				Logits: map[string]float64{
					"CLASS_A": 2.5,
					"CLASS_B": -1.0,
				},
			},
		},
		Thresholds: map[string]float64{
			"threshold_1": 0.5,
		},
		CalibrationMetadata: map[string]interface{}{
			"temp": 0.7,
		},
	}

	encoded := CanonicalEncode(envelope)
	if len(encoded) == 0 {
		t.Fatal("canonical encoding should not be empty")
	}

	// Encode again and verify same result (determinism)
	encoded2 := CanonicalEncode(envelope)
	if len(encoded) != len(encoded2) {
		t.Fatalf("determinism check failed: lengths differ %d vs %d", len(encoded), len(encoded2))
	}

	// Compare bytes
	for i := range encoded {
		if encoded[i] != encoded2[i] {
			t.Fatal("determinism check failed: byte mismatch at position", i)
		}
	}
}

func TestComputeDecisionHash(t *testing.T) {
	envelope := &primitives.DecisionEnvelope{
		Timestamp:   time.Now().UnixNano(),
		ModelID:     "model-123",
		ModelVersion: "1.0.0",
		InputHash:   "input-xyz",
		Disposition: "CLASS_A",
		Route:       "main",
	}

	hash1 := ComputeDecisionHash(envelope)
	hash2 := ComputeDecisionHash(envelope)

	if hash1 != hash2 {
		t.Fatalf("hash mismatch: %s vs %s", hash1, hash2)
	}

	if len(hash1) != 64 {
		t.Fatalf("SHA-256 hash should be 64 chars, got %d", len(hash1))
	}

	// Change envelope and verify different hash
	envelope.Disposition = "CLASS_B"
	hash3 := ComputeDecisionHash(envelope)

	if hash1 == hash3 {
		t.Fatal("different envelopes should produce different hashes")
	}
}

func TestAuditRecordChaining(t *testing.T) {
	records := make([]*AuditRecord, 3)

	for i := 0; i < 3; i++ {
		records[i] = &AuditRecord{
			InputHash:         "input-" + string(rune(i)),
			ModelHash:         "model-hash",
			ModelVersion:      "1.0.0",
			Timestamp:         time.Now().UnixNano() + int64(i)*1000,
			Disposition:       "CLASS_A",
			Thresholds:        map[string]float64{},
			SelectedClasses:   map[string]string{},
			Scores:            map[string]float64{},
			ExecutionTimeNanos: 1000,
		}

		if i > 0 {
			records[i].PreviousRecordHash = records[i-1].ComputeRecordHash()
		}
		records[i].VerificationChecksum = records[i].ComputeRecordHash()
	}

	// Verify chain
	if records[1].PreviousRecordHash != records[0].VerificationChecksum {
		t.Fatal("record chaining failed")
	}
	if records[2].PreviousRecordHash != records[1].VerificationChecksum {
		t.Fatal("record chaining failed")
	}
}

func TestAuditLogAppend(t *testing.T) {
	al := NewAuditLog("")

	records := make([]*AuditRecord, 5)
	for i := 0; i < 5; i++ {
		records[i] = &AuditRecord{
			InputHash:       "input-" + string(rune(i)),
			ModelVersion:    "1.0.0",
			Timestamp:       time.Now().UnixNano() + int64(i)*1000,
			Disposition:     "CLASS_A",
			Thresholds:      map[string]float64{},
			SelectedClasses: map[string]string{},
			Scores:          map[string]float64{},
		}

		if err := al.Append(records[i]); err != nil {
			t.Fatalf("failed to append record %d: %v", i, err)
		}
	}

	stats := al.GetStats()
	if stats["total_records"] != int64(5) {
		t.Fatalf("expected 5 records, got %v", stats["total_records"])
	}
}

func TestAuditLogVerify(t *testing.T) {
	al := NewAuditLog("")

	// Add records in order
	for i := 0; i < 3; i++ {
		record := &AuditRecord{
			InputHash:       "input-" + string(rune(i)),
			Timestamp:       time.Now().UnixNano() + int64(i)*1000000,
			Disposition:     "CLASS_A",
			Thresholds:      map[string]float64{},
			SelectedClasses: map[string]string{},
			Scores:          map[string]float64{},
		}
		al.Append(record)
	}

	// Verify should pass
	if err := al.Verify(); err != nil {
		t.Fatalf("verification should pass: %v", err)
	}
}

func TestComputeModelHash(t *testing.T) {
	metadata := &primitives.ModelMetadata{
		ModelID:      "model-123",
		ModelVersion: "1.0.0",
		Hash:         "abc123",
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	hash1 := ComputeModelHash(metadata)
	hash2 := ComputeModelHash(metadata)

	if hash1 != hash2 {
		t.Fatal("model hash should be deterministic")
	}

	if len(hash1) != 64 {
		t.Fatalf("SHA-256 hash should be 64 chars, got %d", len(hash1))
	}
}

func TestComputeRouterHash(t *testing.T) {
	metadata := &primitives.RouterMetadata{
		Hash:       "router-hash",
		ConfigHash: "config-hash",
		Version:    "1.0",
		Nodes:      []string{"node-a", "node-b", "node-c"},
	}

	hash1 := ComputeRouterHash(metadata)
	hash2 := ComputeRouterHash(metadata)

	if hash1 != hash2 {
		t.Fatal("router hash should be deterministic")
	}

	// Change node order - should produce same hash (sorted internally)
	metadata2 := &primitives.RouterMetadata{
		Hash:       "router-hash",
		ConfigHash: "config-hash",
		Version:    "1.0",
		Nodes:      []string{"node-c", "node-a", "node-b"},
	}

	hash3 := ComputeRouterHash(metadata2)
	if hash1 != hash3 {
		t.Fatal("router hash should be same regardless of node order")
	}
}

func TestGetRecordsByTimeRange(t *testing.T) {
	al := NewAuditLog("")

	now := time.Now().UnixNano()
	for i := 0; i < 5; i++ {
		record := &AuditRecord{
			InputHash:       "input-" + string(rune(i)),
			Timestamp:       now + int64(i)*1000000000, // 1 second apart
			Disposition:     "CLASS_A",
			Thresholds:      map[string]float64{},
			SelectedClasses: map[string]string{},
			Scores:          map[string]float64{},
		}
		al.Append(record)
	}

	// Query range that includes 2nd and 3rd records
	results := al.GetRecordsByTimeRange(
		now+500000000,
		now+2500000000,
	)

	if len(results) < 2 {
		t.Fatalf("expected at least 2 records in range, got %d", len(results))
	}
}

func TestGetRecordsByDisposition(t *testing.T) {
	al := NewAuditLog("")

	dispositions := []string{"CLASS_A", "CLASS_B", "CLASS_A", "CLASS_C", "CLASS_A"}
	for i, disp := range dispositions {
		record := &AuditRecord{
			InputHash:       "input-" + string(rune(i)),
			Timestamp:       time.Now().UnixNano() + int64(i)*1000,
			Disposition:     disp,
			Thresholds:      map[string]float64{},
			SelectedClasses: map[string]string{},
			Scores:          map[string]float64{},
		}
		al.Append(record)
	}

	results := al.GetRecordsByDisposition("CLASS_A")
	if len(results) != 3 {
		t.Fatalf("expected 3 CLASS_A records, got %d", len(results))
	}
}

func TestGetRecordsByRoute(t *testing.T) {
	al := NewAuditLog("")

	routes := []string{"route_a", "route_b", "route_a", "route_c"}
	for i, route := range routes {
		record := &AuditRecord{
			InputHash:       "input-" + string(rune(i)),
			Timestamp:       time.Now().UnixNano() + int64(i)*1000,
			Route:           route,
			Thresholds:      map[string]float64{},
			SelectedClasses: map[string]string{},
			Scores:          map[string]float64{},
		}
		al.Append(record)
	}

	results := al.GetRecordsByRoute("route_a")
	if len(results) != 2 {
		t.Fatalf("expected 2 route_a records, got %d", len(results))
	}
}

func TestGetStats(t *testing.T) {
	al := NewAuditLog("")

	for i := 0; i < 10; i++ {
		record := &AuditRecord{
			InputHash:         "input-" + string(rune(i)),
			Timestamp:         time.Now().UnixNano() + int64(i)*1000,
			Disposition:       "CLASS_" + string(rune('A'+(i%2))),
			Route:             "route_" + string(rune('A'+(i%3))),
			Thresholds:        map[string]float64{},
			SelectedClasses:   map[string]string{},
			Scores:            map[string]float64{},
			ExecutionTimeNanos: 1000 * int64(i+1),
		}
		al.Append(record)
	}

	stats := al.GetStats()

	if totalRecords, ok := stats["total_records"].(int64); !ok || totalRecords != 10 {
		t.Fatalf("expected 10 total records, got %v", stats["total_records"])
	}

	if _, ok := stats["disposition_counts"].(map[string]int64); !ok {
		t.Fatal("disposition_counts should be map[string]int64")
	}
}
