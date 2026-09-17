package ledger

import (
	"bufio"
	"fmt"
	"io"
	"os"
)

// FileWriter handles ledger file operations
type FileWriter struct {
	filepath string
	format   SerializationFormat
}

// NewFileWriter creates file writer
func NewFileWriter(filepath string, format SerializationFormat) *FileWriter {
	return &FileWriter{
		filepath: filepath,
		format:   format,
	}
}

// Write writes ledger to file
func (fw *FileWriter) Write(ledger *Ledger) error {
	data, err := SerializeLedger(ledger, fw.format)
	if err != nil {
		return fmt.Errorf("serialize failed: %w", err)
	}

	file, err := os.Create(fw.filepath)
	if err != nil {
		return fmt.Errorf("create file failed: %w", err)
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	if _, err := writer.Write(data); err != nil {
		return fmt.Errorf("write failed: %w", err)
	}

	if err := writer.Flush(); err != nil {
		return fmt.Errorf("flush failed: %w", err)
	}

	return nil
}

// FileReader handles ledger file read operations
type FileReader struct {
	filepath string
	format   SerializationFormat
}

// NewFileReader creates file reader
func NewFileReader(filepath string, format SerializationFormat) *FileReader {
	return &FileReader{
		filepath: filepath,
		format:   format,
	}
}

// Read reads ledger from file
func (fr *FileReader) Read(sessionID string) (*Ledger, error) {
	file, err := os.Open(fr.filepath)
	if err != nil {
		return nil, fmt.Errorf("open file failed: %w", err)
	}
	defer file.Close()

	reader := bufio.NewReader(file)
	data, err := io.ReadAll(reader)
	if err != nil {
		return nil, fmt.Errorf("read failed: %w", err)
	}

	return DeserializeLedger(data, fr.format, sessionID)
}

// StreamWriter streams ledger events to writer
type StreamWriter struct {
	writer    io.Writer
	format    SerializationFormat
	bufferSize int
}

// NewStreamWriter creates stream writer
func NewStreamWriter(writer io.Writer, format SerializationFormat) *StreamWriter {
	return &StreamWriter{
		writer:     writer,
		format:     format,
		bufferSize: 4096,
	}
}

// WriteEvent writes single event
func (sw *StreamWriter) WriteEvent(event Event) error {
	serializer := &JSONSerializer{}
	data, err := serializer.Serialize(event)
	if err != nil {
		return fmt.Errorf("serialize event failed: %w", err)
	}

	data = append(data, '\n')
	if _, err := sw.writer.Write(data); err != nil {
		return fmt.Errorf("write event failed: %w", err)
	}

	return nil
}

// StreamReader reads ledger events from reader
type StreamReader struct {
	reader io.Reader
	format SerializationFormat
}

// NewStreamReader creates stream reader
func NewStreamReader(reader io.Reader, format SerializationFormat) *StreamReader {
	return &StreamReader{
		reader: reader,
		format: format,
	}
}

// ReadEvent reads next event
func (sr *StreamReader) ReadEvent() (*Event, error) {
	scanner := bufio.NewScanner(sr.reader)
	if !scanner.Scan() {
		return nil, fmt.Errorf("no more events")
	}

	line := scanner.Bytes()
	serializer := &JSONSerializer{}

	var event Event
	if err := serializer.Deserialize(line, &event); err != nil {
		return nil, fmt.Errorf("deserialize event failed: %w", err)
	}

	return &event, nil
}

// EventLogWriter writes events to log file
type EventLogWriter struct {
	filepath string
	file     *os.File
	writer   *bufio.Writer
}

// NewEventLogWriter creates event log writer
func NewEventLogWriter(filepath string) (*EventLogWriter, error) {
	file, err := os.OpenFile(filepath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return nil, fmt.Errorf("open log file failed: %w", err)
	}

	return &EventLogWriter{
		filepath: filepath,
		file:     file,
		writer:   bufio.NewWriter(file),
	}, nil
}

// LogEvent writes event to log
func (elw *EventLogWriter) LogEvent(event Event) error {
	serializer := &JSONSerializer{}
	data, err := serializer.Serialize(event)
	if err != nil {
		return fmt.Errorf("serialize failed: %w", err)
	}

	data = append(data, '\n')
	if _, err := elw.writer.Write(data); err != nil {
		return fmt.Errorf("write failed: %w", err)
	}

	return nil
}

// Flush flushes writer buffer
func (elw *EventLogWriter) Flush() error {
	return elw.writer.Flush()
}

// Close closes log file
func (elw *EventLogWriter) Close() error {
	if err := elw.Flush(); err != nil {
		return err
	}
	return elw.file.Close()
}

// CheckpointManager manages ledger checkpoints
type CheckpointManager struct {
	directory string
}

// NewCheckpointManager creates checkpoint manager
func NewCheckpointManager(directory string) *CheckpointManager {
	return &CheckpointManager{
		directory: directory,
	}
}

// CreateCheckpoint creates ledger checkpoint
func (cm *CheckpointManager) CreateCheckpoint(ledger *Ledger) (string, error) {
	snapshot := ledger.CreateSnapshot()

	filepath := fmt.Sprintf("%s/checkpoint_%d.json", cm.directory, snapshot.SnapshotTime)

	writer := NewFileWriter(filepath, FormatJSON)
	if err := writer.Write(ledger); err != nil {
		return "", fmt.Errorf("checkpoint failed: %w", err)
	}

	return filepath, nil
}

// RecoveryManager manages ledger recovery
type RecoveryManager struct {
	directory string
}

// NewRecoveryManager creates recovery manager
func NewRecoveryManager(directory string) *RecoveryManager {
	return &RecoveryManager{
		directory: directory,
	}
}

// RecoverLatest recovers latest checkpoint
func (rm *RecoveryManager) RecoverLatest(sessionID string) (*Ledger, error) {
	entries, err := os.ReadDir(rm.directory)
	if err != nil {
		return nil, fmt.Errorf("read directory failed: %w", err)
	}

	if len(entries) == 0 {
		return nil, fmt.Errorf("no checkpoints found")
	}

	// Get latest checkpoint
	latestEntry := entries[len(entries)-1]
	filepath := fmt.Sprintf("%s/%s", rm.directory, latestEntry.Name())

	reader := NewFileReader(filepath, FormatJSON)
	return reader.Read(sessionID)
}

// DeltaWriter writes incremental ledger changes
type DeltaWriter struct {
	filepath      string
	lastChecksum  string
}

// NewDeltaWriter creates delta writer
func NewDeltaWriter(filepath string) *DeltaWriter {
	return &DeltaWriter{
		filepath: filepath,
	}
}

// WriteDelta writes delta events since last checkpoint
func (dw *DeltaWriter) WriteDelta(events []Event) error {
	data := map[string]interface{}{
		"event_count": len(events),
		"events":      events,
	}

	serializer := &JSONSerializer{}
	jsonData, err := serializer.Serialize(data)
	if err != nil {
		return fmt.Errorf("serialize failed: %w", err)
	}

	if err := os.WriteFile(dw.filepath, jsonData, 0644); err != nil {
		return fmt.Errorf("write file failed: %w", err)
	}

	return nil
}

// SnapshotStore manages multiple snapshots
type SnapshotStore struct {
	directory string
	snapshots map[string]LedgerSnapshot
}

// NewSnapshotStore creates snapshot store
func NewSnapshotStore(directory string) *SnapshotStore {
	return &SnapshotStore{
		directory: directory,
		snapshots: make(map[string]LedgerSnapshot),
	}
}

// StoreSnapshot stores snapshot
func (ss *SnapshotStore) StoreSnapshot(sessionID string, snapshot LedgerSnapshot) error {
	serializer := NewSnapshotSerializer(FormatJSON)
	data, err := serializer.SerializeSnapshot(snapshot)
	if err != nil {
		return fmt.Errorf("serialize failed: %w", err)
	}

	filepath := fmt.Sprintf("%s/%s.json", ss.directory, sessionID)
	if err := os.WriteFile(filepath, data, 0644); err != nil {
		return fmt.Errorf("write file failed: %w", err)
	}

	ss.snapshots[sessionID] = snapshot
	return nil
}

// RetrieveSnapshot retrieves snapshot
func (ss *SnapshotStore) RetrieveSnapshot(sessionID string) (LedgerSnapshot, error) {
	if snapshot, ok := ss.snapshots[sessionID]; ok {
		return snapshot, nil
	}

	filepath := fmt.Sprintf("%s/%s.json", ss.directory, sessionID)
	data, err := os.ReadFile(filepath)
	if err != nil {
		return LedgerSnapshot{}, fmt.Errorf("read file failed: %w", err)
	}

	serializer := NewSnapshotSerializer(FormatJSON)
	return serializer.DeserializeSnapshot(data)
}

// ReplicationWriter handles ledger replication
type ReplicationWriter struct {
	destinations []string
}

// NewReplicationWriter creates replication writer
func NewReplicationWriter(destinations []string) *ReplicationWriter {
	return &ReplicationWriter{
		destinations: destinations,
	}
}

// Replicate replicates ledger to destinations
func (rw *ReplicationWriter) Replicate(ledger *Ledger) error {
	data, err := ledger.Export()
	if err != nil {
		return fmt.Errorf("export failed: %w", err)
	}

	for _, dest := range rw.destinations {
		if err := os.WriteFile(dest, data, 0644); err != nil {
			return fmt.Errorf("replicate to %s failed: %w", dest, err)
		}
	}

	return nil
}

// VerificationWriter writes ledger verification proofs
type VerificationWriter struct {
	filepath string
}

// NewVerificationWriter creates verification writer
func NewVerificationWriter(filepath string) *VerificationWriter {
	return &VerificationWriter{
		filepath: filepath,
	}
}

// WriteProof writes merkle proof
func (vw *VerificationWriter) WriteProof(index int, proof []string) error {
	data := map[string]interface{}{
		"index": index,
		"proof": proof,
	}

	serializer := &JSONSerializer{}
	jsonData, err := serializer.Serialize(data)
	if err != nil {
		return fmt.Errorf("serialize failed: %w", err)
	}

	if err := os.WriteFile(vw.filepath, jsonData, 0644); err != nil {
		return fmt.Errorf("write file failed: %w", err)
	}

	return nil
}
