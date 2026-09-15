package audit

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"sync"
	"time"
)

// DecisionSeal cryptographically binds operation outcome to policy decision
type DecisionSeal struct {
	OperationID       string            `json:"operation_id"`
	ParentID          string            `json:"parent_id,omitempty"`
	Sequence          int64             `json:"sequence"`
	UserRequest       string            `json:"user_request"`
	NormalizedTask    string            `json:"normalized_task"`
	PolicyDecision    string            `json:"policy_decision"`
	ExecutionResult   string            `json:"execution_result"`
	VerificationResult string            `json:"verification_result"`
	InputDigest       string            `json:"input_digest"`
	OutputDigest      string            `json:"output_digest"`
	Timestamp         time.Time         `json:"timestamp"`
	SealHash          string            `json:"seal_hash"`
	Metadata          map[string]string `json:"metadata,omitempty"`
}

// ComputeSealHash generates deterministic SHA-256 over normalized record
func (d *DecisionSeal) ComputeSealHash() (string, error) {
	// Normalize record for deterministic hashing
	normalized := map[string]interface{}{
		"operation_id":       d.OperationID,
		"parent_id":          d.ParentID,
		"sequence":           d.Sequence,
		"user_request":       d.UserRequest,
		"normalized_task":    d.NormalizedTask,
		"policy_decision":    d.PolicyDecision,
		"execution_result":   d.ExecutionResult,
		"verification_result": d.VerificationResult,
		"input_digest":       d.InputDigest,
		"output_digest":      d.OutputDigest,
		"timestamp":          d.Timestamp.Unix(),
	}

	// Sort keys for deterministic ordering
	data, err := json.Marshal(normalized)
	if err != nil {
		return "", err
	}

	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:]), nil
}

// SignSeal computes and stores seal hash
func (d *DecisionSeal) SignSeal() error {
	hash, err := d.ComputeSealHash()
	if err != nil {
		return err
	}
	d.SealHash = hash
	return nil
}

// AuditLedger records all operations with decision seals
type AuditLedger struct {
	Records  []*DecisionSeal
	Filename string
	mu       sync.RWMutex
	sequence int64
}

// NewAuditLedger creates new ledger
func NewAuditLedger(filename string) *AuditLedger {
	return &AuditLedger{
		Records:  make([]*DecisionSeal, 0),
		Filename: filename,
		sequence: 0,
	}
}

// AppendRecord adds decision seal to ledger
func (a *AuditLedger) AppendRecord(seal *DecisionSeal) error {
	a.mu.Lock()
	defer a.mu.Unlock()

	// Increment sequence
	a.sequence++
	seal.Sequence = a.sequence

	// Set parent to previous record if exists
	if len(a.Records) > 0 {
		seal.ParentID = a.Records[len(a.Records)-1].OperationID
	}

	// Sign seal
	err := seal.SignSeal()
	if err != nil {
		return fmt.Errorf("cannot sign seal: %w", err)
	}

	// Append to in-memory records
	a.Records = append(a.Records, seal)

	// Write to file
	err = a.persistRecord(seal)
	if err != nil {
		return fmt.Errorf("cannot persist record: %w", err)
	}

	return nil
}

// persistRecord writes single record to ledger file
func (a *AuditLedger) persistRecord(seal *DecisionSeal) error {
	file, err := os.OpenFile(a.Filename, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer file.Close()

	data, err := json.Marshal(seal)
	if err != nil {
		return err
	}

	_, err = file.Write(append(data, '\n'))
	return err
}

// VerifyChain verifies seal chain integrity
func (a *AuditLedger) VerifyChain() error {
	a.mu.RLock()
	records := a.Records
	a.mu.RUnlock()

	if len(records) == 0 {
		return nil
	}

	// Verify first record has no parent
	if records[0].ParentID != "" {
		return fmt.Errorf("first record has invalid parent: %s", records[0].ParentID)
	}

	// Verify chain integrity
	for i := 1; i < len(records); i++ {
		curr := records[i]
		prev := records[i-1]

		// Verify parent matches previous
		if curr.ParentID != prev.OperationID {
			return fmt.Errorf("chain broken at record %d: parent mismatch", i)
		}

		// Verify sequence increments
		if curr.Sequence != prev.Sequence+1 {
			return fmt.Errorf("sequence break at record %d: expected %d got %d", i, prev.Sequence+1, curr.Sequence)
		}

		// Verify seal hash
		hash, err := curr.ComputeSealHash()
		if err != nil {
			return fmt.Errorf("cannot compute hash for record %d: %w", i, err)
		}

		if hash != curr.SealHash {
			return fmt.Errorf("seal hash mismatch at record %d", i)
		}
	}

	return nil
}

// LoadLedger loads ledger from file
func (a *AuditLedger) LoadLedger() error {
	a.mu.Lock()
	defer a.mu.Unlock()

	file, err := os.Open(a.Filename)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	for {
		var seal DecisionSeal
		err := decoder.Decode(&seal)
		if err != nil {
			break
		}
		a.Records = append(a.Records, &seal)
		if seal.Sequence > a.sequence {
			a.sequence = seal.Sequence
		}
	}

	return nil
}

// GetRecords returns all records
func (a *AuditLedger) GetRecords() []*DecisionSeal {
	a.mu.RLock()
	defer a.mu.RUnlock()

	// Return copy
	records := make([]*DecisionSeal, len(a.Records))
	copy(records, a.Records)
	return records
}

// SearchByOperationID finds record by operation ID
func (a *AuditLedger) SearchByOperationID(operationID string) *DecisionSeal {
	a.mu.RLock()
	defer a.mu.RUnlock()

	for _, record := range a.Records {
		if record.OperationID == operationID {
			return record
		}
	}
	return nil
}

// SearchByTimeRange finds records in time range
func (a *AuditLedger) SearchByTimeRange(startTime, endTime time.Time) []*DecisionSeal {
	a.mu.RLock()
	defer a.mu.RUnlock()

	var results []*DecisionSeal
	for _, record := range a.Records {
		if record.Timestamp.After(startTime) && record.Timestamp.Before(endTime) {
			results = append(results, record)
		}
	}
	return results
}

// ExportJSON exports all records as JSON
func (a *AuditLedger) ExportJSON(filename string) error {
	a.mu.RLock()
	records := a.Records
	a.mu.RUnlock()

	data, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(filename, data, 0600)
}

// ComputeLedgerHash computes hash of entire ledger for verification
func (a *AuditLedger) ComputeLedgerHash() (string, error) {
	a.mu.RLock()
	defer a.mu.RUnlock()

	if len(a.Records) == 0 {
		return "", fmt.Errorf("empty ledger")
	}

	// Hash all seal hashes in order
	hash := sha256.New()
	for _, record := range a.Records {
		hash.Write([]byte(record.SealHash))
	}

	return hex.EncodeToString(hash.Sum(nil)), nil
}

// DetectTampering detects if ledger was modified
func (a *AuditLedger) DetectTampering() (bool, error) {
	a.mu.RLock()
	records := a.Records
	a.mu.RUnlock()

	for i, record := range records {
		hash, err := record.ComputeSealHash()
		if err != nil {
			return true, fmt.Errorf("cannot verify record %d: %w", i, err)
		}

		if hash != record.SealHash {
			return true, fmt.Errorf("tampering detected at record %d", i)
		}
	}

	return false, nil
}

// StatSummary returns statistics about ledger
type StatSummary struct {
	TotalRecords      int64
	TimeRange         [2]time.Time
	SuccessfulOps     int64
	FailedOps         int64
	VerifiedOps       int64
	AverageLatency    float64
	LastSealHash      string
}

// GetStatSummary computes statistics
func (a *AuditLedger) GetStatSummary() *StatSummary {
	a.mu.RLock()
	defer a.mu.RUnlock()

	if len(a.Records) == 0 {
		return &StatSummary{}
	}

	stats := &StatSummary{
		TotalRecords: int64(len(a.Records)),
		TimeRange:    [2]time.Time{a.Records[0].Timestamp, a.Records[len(a.Records)-1].Timestamp},
	}

	var totalLatency time.Duration

	for _, record := range a.Records {
		switch record.ExecutionResult {
		case "SUCCESS":
			stats.SuccessfulOps++
		case "FAILED":
			stats.FailedOps++
		}

		if record.VerificationResult == "VERIFIED" {
			stats.VerifiedOps++
		}

		if len(a.Records) > 1 {
			totalLatency += record.Timestamp.Sub(a.Records[0].Timestamp)
		}
	}

	if len(a.Records) > 0 {
		stats.AverageLatency = totalLatency.Seconds() / float64(len(a.Records))
		stats.LastSealHash = a.Records[len(a.Records)-1].SealHash
	}

	return stats
}

// ExportProvenanceReport generates human-readable provenance report
func (a *AuditLedger) ExportProvenanceReport(filename string) error {
	a.mu.RLock()
	records := a.Records
	a.mu.RUnlock()

	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	fmt.Fprintf(file, "=== AUDIT LEDGER PROVENANCE REPORT ===\n")
	fmt.Fprintf(file, "Generated: %s\n", time.Now().Format(time.RFC3339))
	fmt.Fprintf(file, "Total Records: %d\n\n", len(records))

	// Sort by sequence
	sorted := make([]*DecisionSeal, len(records))
	copy(sorted, records)
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i].Sequence < sorted[j].Sequence
	})

	for _, record := range sorted {
		fmt.Fprintf(file, "--- Record %d ---\n", record.Sequence)
		fmt.Fprintf(file, "Operation ID: %s\n", record.OperationID)
		fmt.Fprintf(file, "Parent ID: %s\n", record.ParentID)
		fmt.Fprintf(file, "Timestamp: %s\n", record.Timestamp.Format(time.RFC3339))
		fmt.Fprintf(file, "User Request: %s\n", record.UserRequest)
		fmt.Fprintf(file, "Policy Decision: %s\n", record.PolicyDecision)
		fmt.Fprintf(file, "Execution Result: %s\n", record.ExecutionResult)
		fmt.Fprintf(file, "Verification Result: %s\n", record.VerificationResult)
		fmt.Fprintf(file, "Seal Hash: %s\n", record.SealHash)
		fmt.Fprintf(file, "\n")
	}

	return nil
}
