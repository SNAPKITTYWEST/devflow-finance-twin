package ledger

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sync"
	"time"
)

// Ledger: hash-chained, immutable ledger for events
type Ledger struct {
	sessionID        string
	events           []Event
	lastHash         string
	verified         bool
	merkleTree       *EventMerkleTree
	stats            *EventStats
	auditLog         []EventAuditLog
	mu               sync.RWMutex
	sealed           bool
	sealTime         int64
	creationTime     int64
	lastModified     int64
	compressionLevel int
	maxEvents        int
}

// LedgerConfig configuration for ledger
type LedgerConfig struct {
	SessionID        string
	MaxEvents        int
	CompressionLevel int
	AutoVerify       bool
}

// NewLedger creates a new ledger with session ID
func NewLedger(sessionID string) *Ledger {
	now := time.Now().UnixMilli()
	return &Ledger{
		sessionID:        sessionID,
		events:           make([]Event, 0, 1000),
		lastHash:         "",
		verified:         false,
		merkleTree:       nil,
		stats:            NewEventStats(),
		auditLog:         make([]EventAuditLog, 0),
		sealed:           false,
		creationTime:     now,
		lastModified:     now,
		compressionLevel: 6,
		maxEvents:        1000000,
	}
}

// NewLedgerWithConfig creates a ledger with configuration
func NewLedgerWithConfig(config LedgerConfig) *Ledger {
	ledger := NewLedger(config.SessionID)
	if config.MaxEvents > 0 {
		ledger.maxEvents = config.MaxEvents
	}
	if config.CompressionLevel > 0 {
		ledger.compressionLevel = config.CompressionLevel
	}
	return ledger
}

// AppendEvent adds event to ledger with hash chaining
func (l *Ledger) AppendEvent(event Event) error {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.verified {
		return fmt.Errorf("cannot append to verified ledger")
	}
	if l.sealed {
		return fmt.Errorf("cannot append to sealed ledger")
	}
	if len(l.events) >= l.maxEvents {
		return fmt.Errorf("ledger max events reached: %d", l.maxEvents)
	}

	// Validate event
	if event.EventID == "" {
		return fmt.Errorf("event ID cannot be empty")
	}
	if event.RawContentHash == "" {
		event.RawContentHash = computeContentHash(event.RawContent)
	}
	if event.NormalizedContentHash == "" && event.NormalizedContent != "" {
		event.NormalizedContentHash = computeContentHash(event.NormalizedContent)
	}

	event.SequenceNumber = uint64(len(l.events) + 1)
	event.PreviousEventHash = l.lastHash
	event.Timestamp = time.Now().UnixMilli()

	// Compute current event hash
	currentHash := computeEventHash(event)
	event.CurrentEventHash = currentHash

	l.events = append(l.events, event)
	l.lastHash = currentHash
	l.lastModified = time.Now().UnixMilli()

	// Update stats
	l.stats.TotalEvents++
	l.stats.EventsByType[event.EventType]++
	l.stats.EventsBySpeaker[event.Speaker]++

	// Log audit
	l.addAuditLog("APPEND", event.EventID, map[string]interface{}{
		"sequence_number": event.SequenceNumber,
	}, "system")

	return nil
}

// Verify checks ledger integrity with hash chain validation
func (l *Ledger) Verify() error {
	l.mu.Lock()
	defer l.mu.Unlock()

	if len(l.events) == 0 {
		l.verified = true
		return nil
	}

	prevHash := ""

	for i, event := range l.events {
		if event.PreviousEventHash != prevHash {
			l.stats.VerificationFailures++
			return fmt.Errorf("ledger integrity broken at event %d (%s): hash chain mismatch", i, event.EventID)
		}

		currentHash := computeEventHash(event)
		if currentHash != event.CurrentEventHash {
			l.stats.VerificationFailures++
			return fmt.Errorf("ledger integrity broken at event %d (%s): current hash mismatch", i, event.EventID)
		}

		prevHash = event.CurrentEventHash
	}

	l.verified = true
	l.stats.VerificationSuccesses++
	l.addAuditLog("VERIFY", "ledger", map[string]interface{}{
		"events_verified": len(l.events),
		"root_hash":       l.lastHash,
	}, "system")

	return nil
}

// Seal permanently closes the ledger to new events
func (l *Ledger) Seal() error {
	l.mu.Lock()
	defer l.mu.Unlock()

	if err := l.verifyLocked(); err != nil {
		return fmt.Errorf("cannot seal unverified ledger: %w", err)
	}

	l.sealed = true
	l.sealTime = time.Now().UnixMilli()
	l.addAuditLog("SEAL", "ledger", map[string]interface{}{
		"event_count": len(l.events),
		"seal_time":   l.sealTime,
	}, "system")

	return nil
}

// verifyLocked internal verify without locking
func (l *Ledger) verifyLocked() error {
	if len(l.events) == 0 {
		l.verified = true
		return nil
	}

	prevHash := ""
	for i, event := range l.events {
		if event.PreviousEventHash != prevHash {
			return fmt.Errorf("hash chain mismatch at event %d", i)
		}
		currentHash := computeEventHash(event)
		if currentHash != event.CurrentEventHash {
			return fmt.Errorf("current hash mismatch at event %d", i)
		}
		prevHash = event.CurrentEventHash
	}

	l.verified = true
	return nil
}

// GetEvent retrieves event by sequence number
func (l *Ledger) GetEvent(sequenceNumber uint64) (*Event, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	if sequenceNumber == 0 || sequenceNumber > uint64(len(l.events)) {
		return nil, fmt.Errorf("event not found: sequence %d", sequenceNumber)
	}

	return &l.events[sequenceNumber-1], nil
}

// GetEventByID retrieves event by event ID
func (l *Ledger) GetEventByID(eventID string) (*Event, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	for i := range l.events {
		if l.events[i].EventID == eventID {
			return &l.events[i], nil
		}
	}

	return nil, fmt.Errorf("event not found: id %s", eventID)
}

// Query searches events matching criteria
func (l *Ledger) Query(query EventQuery) ([]Event, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	results := make([]Event, 0)
	for _, event := range l.events {
		if event.Matches(query) {
			results = append(results, event)
		}
	}

	return results, nil
}

// Replay deterministic ledger replay for reproducibility
func (l *Ledger) Replay() ([]*Event, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	if !l.verified {
		return nil, fmt.Errorf("cannot replay unverified ledger")
	}

	replay := make([]*Event, len(l.events))
	for i := range l.events {
		replay[i] = &l.events[i]
	}

	l.addAuditLog("REPLAY", "ledger", map[string]interface{}{
		"event_count": len(l.events),
	}, "system")

	return replay, nil
}

// Export serializes ledger to canonical JSON format
func (l *Ledger) Export() ([]byte, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	export := map[string]interface{}{
		"session_id":        l.sessionID,
		"creation_time":     l.creationTime,
		"last_modified":     l.lastModified,
		"sealed":            l.sealed,
		"seal_time":         l.sealTime,
		"verified":          l.verified,
		"event_count":       len(l.events),
		"root_hash":         l.lastHash,
		"merkle_root":       l.getMerkleRoot(),
		"events":            l.events,
		"stats":             l.stats,
	}

	data, err := json.MarshalIndent(export, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("export failed: %w", err)
	}

	l.addAuditLog("EXPORT", "ledger", map[string]interface{}{
		"export_size": len(data),
		"event_count": len(l.events),
	}, "system")

	return data, nil
}

// ExportCanonical exports canonical form for verification
func (l *Ledger) ExportCanonical() ([]byte, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	canonical := make([]EventCanonical, len(l.events))
	for i := range l.events {
		canonical[i] = l.events[i].Canonical()
	}

	export := map[string]interface{}{
		"session_id":  l.sessionID,
		"event_count": len(l.events),
		"events":      canonical,
		"root_hash":   l.lastHash,
	}

	return json.MarshalIndent(export, "", "  ")
}

// TamperDetection checks if ledger was modified (integrity check)
func (l *Ledger) TamperDetection() bool {
	l.mu.RLock()
	defer l.mu.RUnlock()

	if err := l.verifyLocked(); err != nil {
		return true
	}
	return false
}

// GetStats returns ledger statistics
func (l *Ledger) GetStats() *EventStats {
	l.mu.RLock()
	defer l.mu.RUnlock()

	statsCopy := *l.stats
	return &statsCopy
}

// GetEventCount returns total event count
func (l *Ledger) GetEventCount() int {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return len(l.events)
}

// GetRootHash returns current root hash
func (l *Ledger) GetRootHash() string {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return l.lastHash
}

// GetSessionID returns session ID
func (l *Ledger) GetSessionID() string {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return l.sessionID
}

// IsSealed returns whether ledger is sealed
func (l *Ledger) IsSealed() bool {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return l.sealed
}

// IsVerified returns whether ledger is verified
func (l *Ledger) IsVerified() bool {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return l.verified
}

// GetAuditLog returns audit log entries
func (l *Ledger) GetAuditLog() []EventAuditLog {
	l.mu.RLock()
	defer l.mu.RUnlock()

	logCopy := make([]EventAuditLog, len(l.auditLog))
	copy(logCopy, l.auditLog)
	return logCopy
}

// computeEventHash: deterministic SHA-256 hash
func computeEventHash(e Event) string {
	canonical := e.Canonical()
	jsonBytes, _ := json.Marshal(canonical)
	hash := sha256.Sum256(jsonBytes)
	return hex.EncodeToString(hash[:])
}

// addAuditLog adds entry to audit log
func (l *Ledger) addAuditLog(operation, eventID string, details map[string]interface{}, actor string) {
	entry := EventAuditLog{
		timestamp: time.Now().UnixMilli(),
		operation: operation,
		eventID:   eventID,
		details:   details,
		actor:     actor,
	}
	l.auditLog = append(l.auditLog, entry)
}

// getMerkleRoot computes Merkle root
func (l *Ledger) getMerkleRoot() string {
	if len(l.events) == 0 {
		return ""
	}

	hashes := make([]string, len(l.events))
	for i := range l.events {
		hashes[i] = l.events[i].CurrentEventHash
	}

	tree := NewEventMerkleTree(hashes)
	return tree.Root()
}

// GetRange retrieves events in range
func (l *Ledger) GetRange(start, end uint64) ([]Event, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	if start == 0 || start > uint64(len(l.events)) {
		return nil, fmt.Errorf("invalid start: %d", start)
	}
	if end > uint64(len(l.events)) {
		end = uint64(len(l.events))
	}
	if start > end {
		return nil, fmt.Errorf("start > end: %d > %d", start, end)
	}

	results := make([]Event, end-start+1)
	copy(results, l.events[start-1:end])
	return results, nil
}

// LedgerSnapshot represents immutable snapshot
type LedgerSnapshot struct {
	SessionID    string
	EventCount   int
	RootHash     string
	Verified     bool
	Sealed       bool
	CreationTime int64
	SnapshotTime int64
}

// CreateSnapshot creates ledger snapshot
func (l *Ledger) CreateSnapshot() LedgerSnapshot {
	l.mu.RLock()
	defer l.mu.RUnlock()

	return LedgerSnapshot{
		SessionID:    l.sessionID,
		EventCount:   len(l.events),
		RootHash:     l.lastHash,
		Verified:     l.verified,
		Sealed:       l.sealed,
		CreationTime: l.creationTime,
		SnapshotTime: time.Now().UnixMilli(),
	}
}

// Hash computes ledger hash for verification
func (l *Ledger) Hash() string {
	l.mu.RLock()
	defer l.mu.RUnlock()

	hash := sha256.Sum256([]byte(l.lastHash + l.sessionID))
	return hex.EncodeToString(hash[:])
}

// EventsByType returns events grouped by type
func (l *Ledger) EventsByType(eventType string) ([]Event, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	results := make([]Event, 0)
	for _, event := range l.events {
		if event.EventType == eventType {
			results = append(results, event)
		}
	}

	return results, nil
}

// EventsBySpeaker returns events by speaker
func (l *Ledger) EventsBySpeaker(speaker string) ([]Event, error) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	results := make([]Event, 0)
	for _, event := range l.events {
		if event.Speaker == speaker {
			results = append(results, event)
		}
	}

	return results, nil
}
