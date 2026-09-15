package audit

import (
	"bufio"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"strings"
	"time"
)

// DecisionSeal represents a cryptographic seal for an audit decision
type DecisionSeal struct {
	OperationID   string    `json:"operation_id"`
	OperationType string    `json:"operation_type"`
	Timestamp     time.Time `json:"timestamp"`
	ResourceURI   string    `json:"resource_uri"`
	Decision      string    `json:"decision"`
	Reason        string    `json:"reason"`
	Hash          string    `json:"hash"`
	PreviousHash  string    `json:"previous_hash,omitempty"`
}

// GenerateHash computes a cryptographic hash of the seal for integrity verification
func (ds *DecisionSeal) GenerateHash() error {
	// Create deterministic string representation
	data := fmt.Sprintf("%s:%s:%d:%s:%s:%s:%s",
		ds.OperationID,
		ds.OperationType,
		ds.Timestamp.Unix(),
		ds.ResourceURI,
		ds.Decision,
		ds.Reason,
		ds.PreviousHash,
	)

	// Compute SHA256 hash
	hash := sha256.Sum256([]byte(data))
	ds.Hash = fmt.Sprintf("%x", hash)

	return nil
}

// AuditLedger is a file-based ledger for audit events
type AuditLedger struct {
	Filename      string
	lastHash      string
	recordCount   int
	sealed        bool
	sealTimestamp time.Time
}

// Initialize creates or opens the ledger file
func (al *AuditLedger) Initialize() error {
	// Create or open file
	f, err := os.OpenFile(al.Filename, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return fmt.Errorf("failed to open ledger file: %w", err)
	}
	defer f.Close()

	// If file is empty, write header
	fileInfo, err := os.Stat(al.Filename)
	if err != nil {
		return fmt.Errorf("failed to stat ledger file: %w", err)
	}

	if fileInfo.Size() == 0 {
		header := map[string]interface{}{
			"ledger_version": "1.0",
			"created_at":     time.Now(),
			"type":           "audit_ledger",
		}

		headerJSON, err := json.Marshal(header)
		if err != nil {
			return fmt.Errorf("failed to marshal header: %w", err)
		}

		if _, err := f.WriteString(string(headerJSON) + "\n"); err != nil {
			return fmt.Errorf("failed to write header: %w", err)
		}

		al.lastHash = ""
	} else {
		// Read last hash from existing ledger
		lines, err := al.readAllLines()
		if err == nil && len(lines) > 0 {
			// Parse last entry to get hash
			lastLine := lines[len(lines)-1]
			var lastEntry map[string]interface{}
			if err := json.Unmarshal([]byte(lastLine), &lastEntry); err == nil {
				if hash, ok := lastEntry["hash"].(string); ok {
					al.lastHash = hash
				}
			}
		}
	}

	return nil
}

// AppendSeal adds a new seal record to the ledger
func (al *AuditLedger) AppendSeal(seal *DecisionSeal) error {
	if seal == nil {
		return fmt.Errorf("seal cannot be nil")
	}

	// Set previous hash for chain integrity
	seal.PreviousHash = al.lastHash

	// Regenerate hash with previous hash
	if err := seal.GenerateHash(); err != nil {
		return fmt.Errorf("failed to generate hash: %w", err)
	}

	// Marshal seal to JSON
	sealJSON, err := json.Marshal(seal)
	if err != nil {
		return fmt.Errorf("failed to marshal seal: %w", err)
	}

	// Append to file
	f, err := os.OpenFile(al.Filename, os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return fmt.Errorf("failed to open ledger file: %w", err)
	}
	defer f.Close()

	if _, err := f.WriteString(string(sealJSON) + "\n"); err != nil {
		return fmt.Errorf("failed to write seal: %w", err)
	}

	// Update tracking
	al.lastHash = seal.Hash
	al.recordCount++

	return nil
}

// LogEvent creates and appends a simple event log entry
func (al *AuditLedger) LogEvent(eventType, operationID, message string) error {
	seal := &DecisionSeal{
		OperationID:   operationID,
		OperationType: eventType,
		Timestamp:     time.Now(),
		ResourceURI:   "",
		Decision:      "LOGGED",
		Reason:        message,
	}

	return al.AppendSeal(seal)
}

// ListEntries returns all entries from the ledger
func (al *AuditLedger) ListEntries() ([]string, error) {
	lines, err := al.readAllLines()
	if err != nil {
		return nil, err
	}

	// Skip header line
	if len(lines) > 0 {
		return lines[1:], nil
	}

	return []string{}, nil
}

// readAllLines reads all lines from the ledger file
func (al *AuditLedger) readAllLines() ([]string, error) {
	data, err := ioutil.ReadFile(al.Filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read ledger file: %w", err)
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) == 1 && lines[0] == "" {
		return []string{}, nil
	}

	return lines, nil
}

// VerifyIntegrity checks the chain of hashes for integrity
func (al *AuditLedger) VerifyIntegrity() (bool, error) {
	lines, err := al.readAllLines()
	if err != nil {
		return false, err
	}

	if len(lines) <= 1 {
		return true, nil // Empty ledger is valid
	}

	var previousHash string

	// Skip header
	for i := 1; i < len(lines); i++ {
		if lines[i] == "" {
			continue
		}

		var seal DecisionSeal
		if err := json.Unmarshal([]byte(lines[i]), &seal); err != nil {
			return false, fmt.Errorf("failed to unmarshal seal at line %d: %w", i, err)
		}

		// Verify chain
		if i > 1 && seal.PreviousHash != previousHash {
			return false, fmt.Errorf("chain integrity broken at line %d", i)
		}

		// Recompute hash and verify
		expectedPreviousHash := seal.PreviousHash
		seal.PreviousHash = "" // Clear for hash computation

		// Verify the seal hash
		expectedHash := seal.Hash
		seal.Hash = ""

		seal.PreviousHash = expectedPreviousHash
		if err := seal.GenerateHash(); err != nil {
			return false, fmt.Errorf("failed to regenerate hash at line %d: %w", i, err)
		}

		if seal.Hash != expectedHash {
			return false, fmt.Errorf("hash mismatch at line %d", i)
		}

		previousHash = seal.Hash
	}

	return true, nil
}

// Seal finalizes the ledger and generates a final seal
func (al *AuditLedger) Seal() error {
	al.sealTimestamp = time.Now()
	al.sealed = true

	seal := &DecisionSeal{
		OperationID:   "LEDGER_SEAL",
		OperationType: "LEDGER_FINALIZATION",
		Timestamp:     al.sealTimestamp,
		ResourceURI:   al.Filename,
		Decision:      "SEALED",
		Reason:        fmt.Sprintf("Ledger sealed with %d records", al.recordCount),
	}

	return al.AppendSeal(seal)
}

// PrintLedger outputs the entire ledger to stdout
func (al *AuditLedger) PrintLedger() error {
	lines, err := al.readAllLines()
	if err != nil {
		return err
	}

	for i, line := range lines {
		if line != "" {
			fmt.Printf("[%d] %s\n", i, line)
		}
	}

	return nil
}

// GetStatistics returns statistics about the ledger
func (al *AuditLedger) GetStatistics() map[string]interface{} {
	stats := make(map[string]interface{})

	lines, err := al.readAllLines()
	if err != nil {
		stats["error"] = err.Error()
		return stats
	}

	stats["total_entries"] = len(lines) - 1 // Subtract header
	stats["sealed"] = al.sealed
	stats["last_record_hash"] = al.lastHash

	// Count operations by type
	operationCounts := make(map[string]int)
	for i := 1; i < len(lines); i++ {
		if lines[i] == "" {
			continue
		}

		var seal DecisionSeal
		if err := json.Unmarshal([]byte(lines[i]), &seal); err != nil {
			continue
		}

		operationCounts[seal.OperationType]++
	}

	stats["operations"] = operationCounts

	// Verify integrity
	valid, _ := al.VerifyIntegrity()
	stats["chain_valid"] = valid

	return stats
}

// ExportJSON exports the entire ledger as JSON
func (al *AuditLedger) ExportJSON() (string, error) {
	lines, err := al.readAllLines()
	if err != nil {
		return "", err
	}

	var entries []interface{}

	for i := 1; i < len(lines); i++ {
		if lines[i] == "" {
			continue
		}

		var seal DecisionSeal
		if err := json.Unmarshal([]byte(lines[i]), &seal); err != nil {
			continue
		}

		entries = append(entries, seal)
	}

	export := map[string]interface{}{
		"ledger_file": al.Filename,
		"exported_at": time.Now(),
		"entry_count": len(entries),
		"entries":     entries,
	}

	data, err := json.MarshalIndent(export, "", "  ")
	if err != nil {
		return "", fmt.Errorf("failed to marshal export: %w", err)
	}

	return string(data), nil
}
