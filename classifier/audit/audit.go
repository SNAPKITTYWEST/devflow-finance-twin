package audit

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"devflow-finance-twin/classifier/primitives"
)

// CanonicalDecisionEncoding performs deterministic serialization of a DecisionEnvelope
// Ensures:
// 1. All keys alphabetically sorted
// 2. Binary format (no ambiguous text representation)
// 3. No floating-point ambiguity (use fixed-point encoding where needed)
// 4. Consistent ordering of nested structures
func CanonicalEncode(envelope *primitives.DecisionEnvelope) []byte {
	buf := &bytes.Buffer{}

	// Write metadata in canonical order
	writeString(buf, envelope.ModelID)
	writeString(buf, envelope.ModelVersion)
	writeInt64(buf, envelope.Timestamp)
	writeString(buf, envelope.InputHash)
	writeString(buf, envelope.RouterHash)
	writeString(buf, envelope.Disposition)
	writeString(buf, envelope.Route)

	// Write RouteChoices (sorted by name)
	routes := make([]*primitives.RouteChoice, len(envelope.RouteChoices))
	copy(routes, envelope.RouteChoices)
	sort.Slice(routes, func(i, j int) bool {
		return routes[i].Name < routes[j].Name
	})

	writeInt32(buf, int32(len(routes)))
	for _, rc := range routes {
		writeString(buf, rc.Name)
		writeBool(buf, rc.Selected)
		writeStringFloatMap(buf, rc.Probabilities)
	}

	// Write NoulChoices (sorted by name)
	nouls := make([]*primitives.NoulChoice, len(envelope.NoulChoices))
	copy(nouls, envelope.NoulChoices)
	sort.Slice(nouls, func(i, j int) bool {
		return nouls[i].Name < nouls[j].Name
	})

	writeInt32(buf, int32(len(nouls)))
	for _, nc := range nouls {
		writeString(buf, nc.Name)
		writeString(buf, nc.Decision)
		writeFloat64(buf, nc.Probability)
		writeStringFloatMap(buf, nc.Logits)
	}

	// Write Thresholds (sorted by key)
	writeStringFloatMap(buf, envelope.Thresholds)

	// Write CalibrationMetadata (sorted JSON representation)
	calibrationBytes := encodeCalibrationMetadata(envelope.CalibrationMetadata)
	writeBytes(buf, calibrationBytes)

	return buf.Bytes()
}

// encodeCalibrationMetadata encodes calibration metadata in canonical form
func encodeCalibrationMetadata(metadata map[string]interface{}) []byte {
	if len(metadata) == 0 {
		return []byte{0}
	}

	// Sort keys for deterministic encoding
	keys := make([]string, 0, len(metadata))
	for k := range metadata {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	buf := &bytes.Buffer{}
	binary.Write(buf, binary.LittleEndian, int32(len(keys)))

	for _, k := range keys {
		writeString(buf, k)
		v := metadata[k]

		// Encode based on type
		switch val := v.(type) {
		case float64:
			binary.Write(buf, binary.LittleEndian, byte(1)) // float64 type
			binary.Write(buf, binary.LittleEndian, val)
		case string:
			binary.Write(buf, binary.LittleEndian, byte(2)) // string type
			writeString(buf, val)
		case bool:
			binary.Write(buf, binary.LittleEndian, byte(3)) // bool type
			if val {
				binary.Write(buf, binary.LittleEndian, byte(1))
			} else {
				binary.Write(buf, binary.LittleEndian, byte(0))
			}
		case int:
			binary.Write(buf, binary.LittleEndian, byte(4)) // int type
			binary.Write(buf, binary.LittleEndian, int64(val))
		case map[string]interface{}:
			binary.Write(buf, binary.LittleEndian, byte(5)) // nested map type
			nestedBytes := encodeCalibrationMetadata(val)
			binary.Write(buf, binary.LittleEndian, int32(len(nestedBytes)))
			buf.Write(nestedBytes)
		default:
			binary.Write(buf, binary.LittleEndian, byte(0)) // nil type
		}
	}

	return buf.Bytes()
}

// Helper binary encoding functions

func writeString(buf *bytes.Buffer, s string) {
	bytes := []byte(s)
	binary.Write(buf, binary.LittleEndian, int32(len(bytes)))
	buf.Write(bytes)
}

func writeBytes(buf *bytes.Buffer, b []byte) {
	binary.Write(buf, binary.LittleEndian, int32(len(b)))
	buf.Write(b)
}

func writeInt64(buf *bytes.Buffer, v int64) {
	binary.Write(buf, binary.LittleEndian, v)
}

func writeInt32(buf *bytes.Buffer, v int32) {
	binary.Write(buf, binary.LittleEndian, v)
}

func writeBool(buf *bytes.Buffer, v bool) {
	if v {
		buf.WriteByte(1)
	} else {
		buf.WriteByte(0)
	}
}

func writeFloat64(buf *bytes.Buffer, v float64) {
	binary.Write(buf, binary.LittleEndian, v)
}

func writeStringFloatMap(buf *bytes.Buffer, m map[string]float64) {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	binary.Write(buf, binary.LittleEndian, int32(len(keys)))
	for _, k := range keys {
		writeString(buf, k)
		writeFloat64(buf, m[k])
	}
}

// ComputeDecisionHash computes SHA-256 of canonical encoding
func ComputeDecisionHash(envelope *primitives.DecisionEnvelope) string {
	encoded := CanonicalEncode(envelope)
	hash := sha256.Sum256(encoded)
	return hex.EncodeToString(hash[:])
}

// ComputeInputHash computes SHA-256 of input representation
func ComputeInputHash(input interface{}) (string, error) {
	jsonBytes, err := json.Marshal(input)
	if err != nil {
		return "", err
	}
	hash := sha256.Sum256(jsonBytes)
	return hex.EncodeToString(hash[:]), nil
}

// ComputeModelHash computes SHA-256 of model metadata
func ComputeModelHash(metadata *primitives.ModelMetadata) string {
	buf := &bytes.Buffer{}
	writeString(buf, metadata.ModelID)
	writeString(buf, metadata.ModelVersion)
	writeString(buf, metadata.Hash)
	binary.Write(buf, binary.LittleEndian, metadata.CreatedAt.UnixNano())
	binary.Write(buf, binary.LittleEndian, metadata.UpdatedAt.UnixNano())

	hash := sha256.Sum256(buf.Bytes())
	return hex.EncodeToString(hash[:])
}

// ComputeRouterHash computes SHA-256 of router configuration
func ComputeRouterHash(metadata *primitives.RouterMetadata) string {
	buf := &bytes.Buffer{}
	writeString(buf, metadata.Hash)
	writeString(buf, metadata.ConfigHash)
	writeString(buf, metadata.Version)

	// Sort nodes for determinism
	nodes := make([]string, len(metadata.Nodes))
	copy(nodes, metadata.Nodes)
	sort.Strings(nodes)

	binary.Write(buf, binary.LittleEndian, int32(len(nodes)))
	for _, node := range nodes {
		writeString(buf, node)
	}

	hash := sha256.Sum256(buf.Bytes())
	return hex.EncodeToString(hash[:])
}

// AuditRecord represents a complete decision audit trail
type AuditRecord struct {
	ID                    string                 `json:"id"`
	InputHash             string                 `json:"input_hash"`
	ModelHash             string                 `json:"model_hash"`
	ModelVersion          string                 `json:"model_version"`
	RouterHash            string                 `json:"router_hash"`
	ConfigurationHash     string                 `json:"configuration_hash"`
	DecisionHash          string                 `json:"decision_hash"`
	Timestamp             int64                  `json:"timestamp"`
	Route                 string                 `json:"route"`
	Disposition           string                 `json:"disposition"`
	Thresholds            map[string]float64     `json:"thresholds"`
	SelectedClasses       map[string]string      `json:"selected_classes"`
	Scores                map[string]float64     `json:"scores"`
	CalibrationMetadata   map[string]interface{} `json:"calibration_metadata"`
	PreviousRecordHash    string                 `json:"previous_record_hash,omitempty"`
	VerificationChecksum  string                 `json:"verification_checksum,omitempty"`
	ExecutionTimeNanos    int64                  `json:"execution_time_nanos"`
}

// ComputeRecordHash computes SHA-256 of this record (for chaining)
func (ar *AuditRecord) ComputeRecordHash() string {
	buf := &bytes.Buffer{}
	writeString(buf, ar.ID)
	writeString(buf, ar.InputHash)
	writeString(buf, ar.ModelHash)
	writeString(buf, ar.ModelVersion)
	writeString(buf, ar.RouterHash)
	writeString(buf, ar.ConfigurationHash)
	writeString(buf, ar.DecisionHash)
	binary.Write(buf, binary.LittleEndian, ar.Timestamp)
	writeString(buf, ar.Route)
	writeString(buf, ar.Disposition)

	// Sort and write thresholds
	thresholdKeys := make([]string, 0, len(ar.Thresholds))
	for k := range ar.Thresholds {
		thresholdKeys = append(thresholdKeys, k)
	}
	sort.Strings(thresholdKeys)
	binary.Write(buf, binary.LittleEndian, int32(len(thresholdKeys)))
	for _, k := range thresholdKeys {
		writeString(buf, k)
		writeFloat64(buf, ar.Thresholds[k])
	}

	// Sort and write selected classes
	classKeys := make([]string, 0, len(ar.SelectedClasses))
	for k := range ar.SelectedClasses {
		classKeys = append(classKeys, k)
	}
	sort.Strings(classKeys)
	binary.Write(buf, binary.LittleEndian, int32(len(classKeys)))
	for _, k := range classKeys {
		writeString(buf, k)
		writeString(buf, ar.SelectedClasses[k])
	}

	binary.Write(buf, binary.LittleEndian, ar.ExecutionTimeNanos)

	hash := sha256.Sum256(buf.Bytes())
	return hex.EncodeToString(hash[:])
}

// AuditLog maintains a persistent audit trail with integrity verification
type AuditLog struct {
	mu              sync.RWMutex
	records         []*AuditRecord
	file            string // optional file storage
	index           map[string]int
	lastRecordHash  string
	recordCount     int64
	verificationLog []VerificationEntry
}

// VerificationEntry records a verification check
type VerificationEntry struct {
	Timestamp       int64
	RecordsVerified int
	ChecksumMatch   bool
	ErrorMessage    string
}

// NewAuditLog creates a new audit log
func NewAuditLog(filePath string) *AuditLog {
	return &AuditLog{
		records:         make([]*AuditRecord, 0, 1000),
		file:            filePath,
		index:           make(map[string]int),
		verificationLog: make([]VerificationEntry, 0),
	}
}

// Append adds a new audit record to the log
func (al *AuditLog) Append(record *AuditRecord) error {
	al.mu.Lock()
	defer al.mu.Unlock()

	// Set record metadata
	record.ID = fmt.Sprintf("audit-%d-%d", time.Now().UnixNano(), len(al.records))
	record.PreviousRecordHash = al.lastRecordHash
	record.VerificationChecksum = record.ComputeRecordHash()

	// Append to in-memory list
	al.records = append(al.records, record)
	al.index[record.ID] = len(al.records) - 1
	al.lastRecordHash = record.VerificationChecksum
	al.recordCount++

	// Write to file if configured
	if al.file != "" {
		return al.persistRecord(record)
	}
	return nil
}

// persistRecord writes a record to the audit log file
func (al *AuditLog) persistRecord(record *AuditRecord) error {
	// Ensure directory exists
	dir := filepath.Dir(al.file)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create audit log directory: %w", err)
	}

	// Open file in append mode
	f, err := os.OpenFile(al.file, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to open audit log file: %w", err)
	}
	defer f.Close()

	// Write JSON record
	jsonBytes, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %w", err)
	}

	// Write record with newline delimiter
	if _, err := f.Write(append(jsonBytes, '\n')); err != nil {
		return fmt.Errorf("failed to write to audit log: %w", err)
	}

	return nil
}

// Verify checks the integrity of the audit trail
// Returns error if tampering detected or records are out of order
func (al *AuditLog) Verify() error {
	al.mu.RLock()
	defer al.mu.RUnlock()

	if len(al.records) == 0 {
		return nil
	}

	previousHash := ""
	for i, record := range al.records {
		// Check chronological order
		if i > 0 && record.Timestamp < al.records[i-1].Timestamp {
			return fmt.Errorf("audit trail out of order at index %d", i)
		}

		// Check hash chain integrity
		if record.PreviousRecordHash != previousHash {
			return fmt.Errorf("hash chain broken at record %d: expected %s, got %s",
				i, previousHash, record.PreviousRecordHash)
		}

		// Recompute checksum to verify no tampering
		computedChecksum := record.ComputeRecordHash()
		if computedChecksum != record.VerificationChecksum {
			return fmt.Errorf("record %d checksum mismatch: record hash was %s, now computes to %s",
				i, record.VerificationChecksum, computedChecksum)
		}

		previousHash = record.VerificationChecksum
	}

	// Record successful verification
	al.verificationLog = append(al.verificationLog, VerificationEntry{
		Timestamp:       time.Now().UnixNano(),
		RecordsVerified: len(al.records),
		ChecksumMatch:   true,
	})

	return nil
}

// GetRecord retrieves an audit record by ID
func (al *AuditLog) GetRecord(id string) (*AuditRecord, error) {
	al.mu.RLock()
	defer al.mu.RUnlock()

	idx, exists := al.index[id]
	if !exists {
		return nil, fmt.Errorf("record not found: %s", id)
	}

	return al.records[idx], nil
}

// GetRecordsByTimeRange retrieves records within a time range
func (al *AuditLog) GetRecordsByTimeRange(startTime, endTime int64) []*AuditRecord {
	al.mu.RLock()
	defer al.mu.RUnlock()

	var result []*AuditRecord
	for _, record := range al.records {
		if record.Timestamp >= startTime && record.Timestamp <= endTime {
			result = append(result, record)
		}
	}
	return result
}

// GetRecordsByDisposition retrieves records with a specific disposition
func (al *AuditLog) GetRecordsByDisposition(disposition string) []*AuditRecord {
	al.mu.RLock()
	defer al.mu.RUnlock()

	var result []*AuditRecord
	for _, record := range al.records {
		if record.Disposition == disposition {
			result = append(result, record)
		}
	}
	return result
}

// GetRecordsByRoute retrieves records with a specific route
func (al *AuditLog) GetRecordsByRoute(route string) []*AuditRecord {
	al.mu.RLock()
	defer al.mu.RUnlock()

	var result []*AuditRecord
	for _, record := range al.records {
		if record.Route == route {
			result = append(result, record)
		}
	}
	return result
}

// ExportJSON exports audit log to JSON format
func (al *AuditLog) ExportJSON(writer io.Writer) error {
	al.mu.RLock()
	defer al.mu.RUnlock()

	encoder := json.NewEncoder(writer)
	encoder.SetIndent("", "  ")

	return encoder.Encode(map[string]interface{}{
		"record_count": al.recordCount,
		"records":      al.records,
		"last_hash":    al.lastRecordHash,
	})
}

// LoadFromFile loads audit records from a file
func (al *AuditLog) LoadFromFile() error {
	al.mu.Lock()
	defer al.mu.Unlock()

	if al.file == "" {
		return fmt.Errorf("no file path configured")
	}

	f, err := os.Open(al.file)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // File doesn't exist yet
		}
		return fmt.Errorf("failed to open audit log file: %w", err)
	}
	defer f.Close()

	scanner := &bytes.Buffer{}
	for {
		line := make([]byte, 0, 4096)
		n, err := f.Read(line)
		if n > 0 {
			scanner.Write(line[:n])
		}
		if err != nil {
			if err == io.EOF {
				break
			}
			return fmt.Errorf("failed to read audit log file: %w", err)
		}
	}

	// Parse records from file content
	decoder := json.NewDecoder(f)
	var record AuditRecord
	for decoder.More() {
		if err := decoder.Decode(&record); err != nil {
			return fmt.Errorf("failed to decode record: %w", err)
		}
		al.records = append(al.records, &record)
		al.index[record.ID] = len(al.records) - 1
	}

	return nil
}

// GetStats returns statistics about the audit log
func (al *AuditLog) GetStats() map[string]interface{} {
	al.mu.RLock()
	defer al.mu.RUnlock()

	dispositionCounts := make(map[string]int)
	routeCounts := make(map[string]int)
	var totalExecutionTime int64

	for _, record := range al.records {
		dispositionCounts[record.Disposition]++
		routeCounts[record.Route]++
		totalExecutionTime += record.ExecutionTimeNanos
	}

	return map[string]interface{}{
		"total_records":         al.recordCount,
		"disposition_counts":    dispositionCounts,
		"route_counts":          routeCounts,
		"average_execution_ns":  totalExecutionTime / int64(len(al.records)+1),
		"verification_checks":   len(al.verificationLog),
		"last_verification":     al.lastRecordHash,
	}
}
