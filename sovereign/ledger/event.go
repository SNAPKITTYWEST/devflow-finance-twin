package ledger

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"time"
)

// Event: immutable ledger entry with comprehensive audit trail
type Event struct {
	EventID               string                 `json:"event_id"`
	SequenceNumber        uint64                 `json:"sequence_number"`
	Timestamp             int64                  `json:"timestamp"`
	Speaker               string                 `json:"speaker"`
	EventType             string                 `json:"event_type"`
	RawContent            string                 `json:"raw_content"`
	RawContentHash        string                 `json:"raw_content_hash"`
	NormalizedContent     string                 `json:"normalized_content"`
	NormalizedContentHash string                 `json:"normalized_content_hash"`
	PreviousEventHash     string                 `json:"previous_event_hash"`
	CurrentEventHash      string                 `json:"current_event_hash"`
	EvaluationVersion     string                 `json:"evaluation_version"`
	ConstraintVersion     string                 `json:"constraint_version"`
	Metadata              map[string]interface{} `json:"metadata,omitempty"`
}

// EventBuilder fluent interface for creating events
type EventBuilder struct {
	event Event
}

// NewEventBuilder creates a new event builder
func NewEventBuilder(eventID string) *EventBuilder {
	return &EventBuilder{
		event: Event{
			EventID:   eventID,
			Timestamp: time.Now().UnixMilli(),
			Metadata:  make(map[string]interface{}),
		},
	}
}

// WithSpeaker sets the speaker
func (eb *EventBuilder) WithSpeaker(speaker string) *EventBuilder {
	eb.event.Speaker = speaker
	return eb
}

// WithEventType sets the event type
func (eb *EventBuilder) WithEventType(eventType string) *EventBuilder {
	eb.event.EventType = eventType
	return eb
}

// WithRawContent sets raw content and computes hash
func (eb *EventBuilder) WithRawContent(content string) *EventBuilder {
	eb.event.RawContent = content
	eb.event.RawContentHash = computeContentHash(content)
	return eb
}

// WithNormalizedContent sets normalized content and computes hash
func (eb *EventBuilder) WithNormalizedContent(content string) *EventBuilder {
	eb.event.NormalizedContent = content
	eb.event.NormalizedContentHash = computeContentHash(content)
	return eb
}

// WithEvaluationVersion sets evaluation version
func (eb *EventBuilder) WithEvaluationVersion(version string) *EventBuilder {
	eb.event.EvaluationVersion = version
	return eb
}

// WithConstraintVersion sets constraint version
func (eb *EventBuilder) WithConstraintVersion(version string) *EventBuilder {
	eb.event.ConstraintVersion = version
	return eb
}

// WithMetadata adds metadata key-value pair
func (eb *EventBuilder) WithMetadata(key string, value interface{}) *EventBuilder {
	eb.event.Metadata[key] = value
	return eb
}

// WithTimestamp sets custom timestamp
func (eb *EventBuilder) WithTimestamp(ts int64) *EventBuilder {
	eb.event.Timestamp = ts
	return eb
}

// Build returns the constructed event
func (eb *EventBuilder) Build() Event {
	return eb.event
}

// computeContentHash computes SHA-256 hash of content
func computeContentHash(content string) string {
	hash := sha256.Sum256([]byte(content))
	return hex.EncodeToString(hash[:])
}

// ToJSON serializes event to JSON
func (e *Event) ToJSON() ([]byte, error) {
	return json.MarshalIndent(e, "", "  ")
}

// FromJSON deserializes event from JSON
func (e *Event) FromJSON(data []byte) error {
	return json.Unmarshal(data, e)
}

// EventCanonical creates canonical form for hashing
type EventCanonical struct {
	EventID               string `json:"event_id"`
	SequenceNumber        uint64 `json:"sequence_number"`
	RawContentHash        string `json:"raw_content_hash"`
	NormalizedContentHash string `json:"normalized_content_hash"`
	EvaluationVersion     string `json:"evaluation_version"`
	ConstraintVersion     string `json:"constraint_version"`
	PreviousEventHash     string `json:"previous_event_hash"`
}

// Canonical returns canonical form for deterministic hashing
func (e *Event) Canonical() EventCanonical {
	return EventCanonical{
		EventID:               e.EventID,
		SequenceNumber:        e.SequenceNumber,
		RawContentHash:        e.RawContentHash,
		NormalizedContentHash: e.NormalizedContentHash,
		EvaluationVersion:     e.EvaluationVersion,
		ConstraintVersion:     e.ConstraintVersion,
		PreviousEventHash:     e.PreviousEventHash,
	}
}

// EventQuery represents a query for searching events
type EventQuery struct {
	EventID       string
	Speaker       string
	EventType     string
	TimeStart     int64
	TimeEnd       int64
	SequenceStart uint64
	SequenceEnd   uint64
}

// EventFilter checks if event matches query
func (e *Event) Matches(q EventQuery) bool {
	if q.EventID != "" && e.EventID != q.EventID {
		return false
	}
	if q.Speaker != "" && e.Speaker != q.Speaker {
		return false
	}
	if q.EventType != "" && e.EventType != q.EventType {
		return false
	}
	if q.TimeStart > 0 && e.Timestamp < q.TimeStart {
		return false
	}
	if q.TimeEnd > 0 && e.Timestamp > q.TimeEnd {
		return false
	}
	if q.SequenceStart > 0 && e.SequenceNumber < q.SequenceStart {
		return false
	}
	if q.SequenceEnd > 0 && e.SequenceNumber > q.SequenceEnd {
		return false
	}
	return true
}

// EventSnapshot immutable snapshot of event
type EventSnapshot struct {
	Event       Event
	CaptureTime int64
}

// NewEventSnapshot creates a snapshot of an event
func NewEventSnapshot(e Event) EventSnapshot {
	// Deep copy metadata
	metaCopy := make(map[string]interface{})
	for k, v := range e.Metadata {
		metaCopy[k] = v
	}
	e.Metadata = metaCopy

	return EventSnapshot{
		Event:       e,
		CaptureTime: time.Now().UnixMilli(),
	}
}

// EventStats aggregates statistics for events
type EventStats struct {
	TotalEvents            int64
	EventsByType           map[string]int64
	EventsBySpeaker        map[string]int64
	FirstEventTime         int64
	LastEventTime          int64
	AverageTimePerEvent    int64
	ContentHashCollisions  int64
	SequenceGaps           int64
	VerificationSuccesses  int64
	VerificationFailures   int64
}

// NewEventStats creates empty event statistics
func NewEventStats() *EventStats {
	return &EventStats{
		EventsByType:    make(map[string]int64),
		EventsBySpeaker: make(map[string]int64),
	}
}

// EventMerkleTree represents a Merkle tree of events for efficient verification
type EventMerkleTree struct {
	leaves []string // hashes of events
	tree   [][]string
}

// NewEventMerkleTree creates a new Merkle tree
func NewEventMerkleTree(eventHashes []string) *EventMerkleTree {
	mt := &EventMerkleTree{
		leaves: make([]string, len(eventHashes)),
		tree:   make([][]string, 0),
	}
	copy(mt.leaves, eventHashes)
	mt.buildTree()
	return mt
}

// buildTree constructs the Merkle tree
func (mt *EventMerkleTree) buildTree() {
	if len(mt.leaves) == 0 {
		return
	}

	currentLevel := make([]string, len(mt.leaves))
	copy(currentLevel, mt.leaves)
	mt.tree = append(mt.tree, currentLevel)

	for len(currentLevel) > 1 {
		nextLevel := make([]string, 0)
		for i := 0; i < len(currentLevel); i += 2 {
			left := currentLevel[i]
			right := left
			if i+1 < len(currentLevel) {
				right = currentLevel[i+1]
			}
			combined := left + right
			hash := sha256.Sum256([]byte(combined))
			nextLevel = append(nextLevel, hex.EncodeToString(hash[:]))
		}
		mt.tree = append(mt.tree, nextLevel)
		currentLevel = nextLevel
	}
}

// Root returns the Merkle root hash
func (mt *EventMerkleTree) Root() string {
	if len(mt.tree) == 0 {
		return ""
	}
	level := mt.tree[len(mt.tree)-1]
	if len(level) > 0 {
		return level[0]
	}
	return ""
}

// Proof generates a Merkle proof for event at index
func (mt *EventMerkleTree) Proof(index int) []string {
	if index < 0 || index >= len(mt.leaves) {
		return nil
	}

	proof := make([]string, 0)
	pos := index
	for level := 0; level < len(mt.tree)-1; level++ {
		sibling := pos ^ 1
		if sibling < len(mt.tree[level]) {
			proof = append(proof, mt.tree[level][sibling])
		}
		pos = pos / 2
	}
	return proof
}

// VerifyProof verifies a Merkle proof
func (mt *EventMerkleTree) VerifyProof(index int, proof []string, leaf string) bool {
	if index < 0 || index >= len(mt.leaves) {
		return false
	}

	current := leaf
	pos := index

	for i := 0; i < len(proof); i++ {
		if pos%2 == 0 {
			combined := current + proof[i]
			hash := sha256.Sum256([]byte(combined))
			current = hex.EncodeToString(hash[:])
		} else {
			combined := proof[i] + current
			hash := sha256.Sum256([]byte(combined))
			current = hex.EncodeToString(hash[:])
		}
		pos = pos / 2
	}

	return current == mt.Root()
}

// EventAuditLog tracks all operations on events
type EventAuditLog struct {
	timestamp  int64
	operation  string
	eventID    string
	details    map[string]interface{}
	actor      string
}

// EventFilter represents filtering criteria
type EventFilter struct {
	Criteria map[string]interface{}
}

// NewEventFilter creates a new filter
func NewEventFilter() *EventFilter {
	return &EventFilter{
		Criteria: make(map[string]interface{}),
	}
}

// AddCriteria adds filtering criteria
func (ef *EventFilter) AddCriteria(key string, value interface{}) *EventFilter {
	ef.Criteria[key] = value
	return ef
}

// EventComparator compares two events for sorting
type EventComparator struct {
	sortKey string
	desc    bool
}

// NewEventComparator creates event comparator
func NewEventComparator(sortKey string, desc bool) *EventComparator {
	return &EventComparator{
		sortKey: sortKey,
		desc:    desc,
	}
}

// SortEvents sorts events by comparator
func (ec *EventComparator) SortEvents(events []Event) {
	sort.Slice(events, func(i, j int) bool {
		cmp := ec.compareEvents(&events[i], &events[j])
		if ec.desc {
			return cmp > 0
		}
		return cmp < 0
	})
}

// compareEvents compares two events
func (ec *EventComparator) compareEvents(a, b *Event) int {
	switch ec.sortKey {
	case "sequence":
		if a.SequenceNumber < b.SequenceNumber {
			return -1
		} else if a.SequenceNumber > b.SequenceNumber {
			return 1
		}
	case "timestamp":
		if a.Timestamp < b.Timestamp {
			return -1
		} else if a.Timestamp > b.Timestamp {
			return 1
		}
	case "speaker":
		if a.Speaker < b.Speaker {
			return -1
		} else if a.Speaker > b.Speaker {
			return 1
		}
	case "type":
		if a.EventType < b.EventType {
			return -1
		} else if a.EventType > b.EventType {
			return 1
		}
	}
	return 0
}
