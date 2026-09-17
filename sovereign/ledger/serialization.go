package ledger

import (
	"bytes"
	"encoding/gob"
	"encoding/json"
	"fmt"
	"time"
)

// Serializer handles event and ledger serialization
type Serializer interface {
	Serialize(v interface{}) ([]byte, error)
	Deserialize(data []byte, v interface{}) error
	Format() string
}

// JSONSerializer implements JSON serialization
type JSONSerializer struct{}

// Serialize serializes to JSON
func (js *JSONSerializer) Serialize(v interface{}) ([]byte, error) {
	return json.MarshalIndent(v, "", "  ")
}

// Deserialize deserializes from JSON
func (js *JSONSerializer) Deserialize(data []byte, v interface{}) error {
	return json.Unmarshal(data, v)
}

// Format returns format name
func (js *JSONSerializer) Format() string {
	return "json"
}

// GobSerializer implements Gob serialization
type GobSerializer struct{}

// Serialize serializes to Gob
func (gs *GobSerializer) Serialize(v interface{}) ([]byte, error) {
	var buf bytes.Buffer
	encoder := gob.NewEncoder(&buf)
	if err := encoder.Encode(v); err != nil {
		return nil, fmt.Errorf("gob encode failed: %w", err)
	}
	return buf.Bytes(), nil
}

// Deserialize deserializes from Gob
func (gs *GobSerializer) Deserialize(data []byte, v interface{}) error {
	decoder := gob.NewDecoder(bytes.NewReader(data))
	return decoder.Decode(v)
}

// Format returns format name
func (gs *GobSerializer) Format() string {
	return "gob"
}

// SerializationFormat enumeration
type SerializationFormat string

const (
	FormatJSON SerializationFormat = "json"
	FormatGob  SerializationFormat = "gob"
)

// SerializerFactory creates serializers
type SerializerFactory struct{}

// CreateSerializer creates appropriate serializer
func (sf *SerializerFactory) CreateSerializer(format SerializationFormat) (Serializer, error) {
	switch format {
	case FormatJSON:
		return &JSONSerializer{}, nil
	case FormatGob:
		return &GobSerializer{}, nil
	default:
		return nil, fmt.Errorf("unknown format: %s", format)
	}
}

// EventExport represents exportable event
type EventExport struct {
	EventID               string                 `json:"event_id"`
	SequenceNumber        uint64                 `json:"sequence_number"`
	Timestamp             int64                  `json:"timestamp"`
	Speaker               string                 `json:"speaker"`
	EventType             string                 `json:"event_type"`
	RawContentHash        string                 `json:"raw_content_hash"`
	NormalizedContentHash string                 `json:"normalized_content_hash"`
	PreviousEventHash     string                 `json:"previous_event_hash"`
	CurrentEventHash      string                 `json:"current_event_hash"`
	EvaluationVersion     string                 `json:"evaluation_version"`
	ConstraintVersion     string                 `json:"constraint_version"`
	MetadataHash          string                 `json:"metadata_hash,omitempty"`
}

// ToExport converts event to export format
func (e *Event) ToExport() EventExport {
	metadataHash := ""
	if len(e.Metadata) > 0 {
		if data, err := json.Marshal(e.Metadata); err == nil {
			metadataHash = computeContentHash(string(data))
		}
	}

	return EventExport{
		EventID:               e.EventID,
		SequenceNumber:        e.SequenceNumber,
		Timestamp:             e.Timestamp,
		Speaker:               e.Speaker,
		EventType:             e.EventType,
		RawContentHash:        e.RawContentHash,
		NormalizedContentHash: e.NormalizedContentHash,
		PreviousEventHash:     e.PreviousEventHash,
		CurrentEventHash:      e.CurrentEventHash,
		EvaluationVersion:     e.EvaluationVersion,
		ConstraintVersion:     e.ConstraintVersion,
		MetadataHash:          metadataHash,
	}
}

// LedgerExport represents exportable ledger
type LedgerExport struct {
	SessionID        string        `json:"session_id"`
	CreationTime     int64         `json:"creation_time"`
	LastModified     int64         `json:"last_modified"`
	Sealed           bool          `json:"sealed"`
	SealTime         int64         `json:"seal_time,omitempty"`
	Verified         bool          `json:"verified"`
	EventCount       int           `json:"event_count"`
	RootHash         string        `json:"root_hash"`
	MerkleRoot       string        `json:"merkle_root"`
	Events           []EventExport `json:"events"`
	Statistics       *EventStats   `json:"statistics,omitempty"`
	ExportTime       int64         `json:"export_time"`
	ExportFormat     string        `json:"export_format"`
}

// SerializeLedger serializes ledger with specified format
func SerializeLedger(ledger *Ledger, format SerializationFormat) ([]byte, error) {
	data, err := ledger.Export()
	if err != nil {
		return nil, fmt.Errorf("export failed: %w", err)
	}

	// Parse exported data
	var exportMap map[string]interface{}
	if err := json.Unmarshal(data, &exportMap); err != nil {
		return nil, fmt.Errorf("parse export failed: %w", err)
	}

	factory := &SerializerFactory{}
	serializer, err := factory.CreateSerializer(format)
	if err != nil {
		return nil, err
	}

	return serializer.Serialize(exportMap)
}

// DeserializeLedger deserializes ledger from data
func DeserializeLedger(data []byte, format SerializationFormat, sessionID string) (*Ledger, error) {
	factory := &SerializerFactory{}
	serializer, err := factory.CreateSerializer(format)
	if err != nil {
		return nil, err
	}

	var exportMap map[string]interface{}
	if err := serializer.Deserialize(data, &exportMap); err != nil {
		return nil, fmt.Errorf("deserialize failed: %w", err)
	}

	// Reconstruct ledger
	ledger := NewLedger(sessionID)

	// Reconstruct events
	if eventsRaw, ok := exportMap["events"]; ok {
		if eventsArray, ok := eventsRaw.([]interface{}); ok {
			for _, eventRaw := range eventsArray {
				eventJSON, _ := json.Marshal(eventRaw)
				var event Event
				if err := json.Unmarshal(eventJSON, &event); err != nil {
					return nil, fmt.Errorf("event deserialize failed: %w", err)
				}
				ledger.AppendEvent(event)
			}
		}
	}

	return ledger, nil
}

// SnapshotSerializer handles snapshot serialization
type SnapshotSerializer struct {
	format SerializationFormat
}

// NewSnapshotSerializer creates snapshot serializer
func NewSnapshotSerializer(format SerializationFormat) *SnapshotSerializer {
	return &SnapshotSerializer{
		format: format,
	}
}

// SerializeSnapshot serializes snapshot
func (ss *SnapshotSerializer) SerializeSnapshot(snapshot LedgerSnapshot) ([]byte, error) {
	factory := &SerializerFactory{}
	serializer, err := factory.CreateSerializer(ss.format)
	if err != nil {
		return nil, err
	}

	return serializer.Serialize(snapshot)
}

// DeserializeSnapshot deserializes snapshot
func (ss *SnapshotSerializer) DeserializeSnapshot(data []byte) (LedgerSnapshot, error) {
	factory := &SerializerFactory{}
	serializer, err := factory.CreateSerializer(ss.format)
	if err != nil {
		return LedgerSnapshot{}, err
	}

	var snapshot LedgerSnapshot
	if err := serializer.Deserialize(data, &snapshot); err != nil {
		return LedgerSnapshot{}, fmt.Errorf("deserialize failed: %w", err)
	}

	return snapshot, nil
}

// SerializationOptions configuration for serialization
type SerializationOptions struct {
	IncludeMetadata bool
	IncludeContent  bool
	IncludeStats    bool
	Format          SerializationFormat
	Timestamp       int64
}

// SerializeWithOptions serializes with custom options
func (l *Ledger) SerializeWithOptions(opts SerializationOptions) ([]byte, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	events := make([]EventExport, len(l.events))
	for i := range l.events {
		events[i] = l.events[i].ToExport()
	}

	export := map[string]interface{}{
		"session_id":     l.sessionID,
		"creation_time":  l.creationTime,
		"last_modified":  l.lastModified,
		"sealed":         l.sealed,
		"verified":       l.verified,
		"event_count":    len(l.events),
		"root_hash":      l.lastHash,
		"export_time":    opts.Timestamp,
		"export_format":  opts.Format,
		"events":         events,
	}

	if opts.IncludeStats {
		export["statistics"] = l.stats
	}

	factory := &SerializerFactory{}
	serializer, err := factory.CreateSerializer(opts.Format)
	if err != nil {
		return nil, err
	}

	return serializer.Serialize(export)
}

// BatchSerializer handles batch serialization of multiple ledgers
type BatchSerializer struct {
	ledgers map[string]*Ledger
}

// NewBatchSerializer creates batch serializer
func NewBatchSerializer() *BatchSerializer {
	return &BatchSerializer{
		ledgers: make(map[string]*Ledger),
	}
}

// AddLedger adds ledger to batch
func (bs *BatchSerializer) AddLedger(sessionID string, ledger *Ledger) {
	bs.ledgers[sessionID] = ledger
}

// SerializeBatch serializes all ledgers
func (bs *BatchSerializer) SerializeBatch(format SerializationFormat) ([]byte, error) {
	batch := make(map[string]interface{})
	batch["timestamp"] = time.Now().UnixMilli()
	batch["ledger_count"] = len(bs.ledgers)

	ledgerData := make(map[string]interface{})
	for sessionID, ledger := range bs.ledgers {
		data, err := ledger.Export()
		if err != nil {
			return nil, fmt.Errorf("export failed for %s: %w", sessionID, err)
		}

		var ledgerMap map[string]interface{}
		if err := json.Unmarshal(data, &ledgerMap); err != nil {
			return nil, fmt.Errorf("parse failed for %s: %w", sessionID, err)
		}

		ledgerData[sessionID] = ledgerMap
	}
	batch["ledgers"] = ledgerData

	factory := &SerializerFactory{}
	serializer, err := factory.CreateSerializer(format)
	if err != nil {
		return nil, err
	}

	return serializer.Serialize(batch)
}

// ArchiveSerializer handles archival serialization
type ArchiveSerializer struct {
	compressionLevel int
}

// NewArchiveSerializer creates archive serializer
func NewArchiveSerializer(level int) *ArchiveSerializer {
	return &ArchiveSerializer{
		compressionLevel: level,
	}
}

// Archive creates archive of ledger with metadata
func (as *ArchiveSerializer) Archive(ledger *Ledger) (map[string]interface{}, error) {
	data, err := ledger.Export()
	if err != nil {
		return nil, fmt.Errorf("export failed: %w", err)
	}

	return map[string]interface{}{
		"timestamp":           time.Now().UnixMilli(),
		"session_id":          ledger.GetSessionID(),
		"event_count":         ledger.GetEventCount(),
		"root_hash":           ledger.GetRootHash(),
		"verified":            ledger.IsVerified(),
		"sealed":              ledger.IsSealed(),
		"data":                data,
		"compression_level":   as.compressionLevel,
		"archive_version":     "1.0",
	}, nil
}
