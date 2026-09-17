# Immutable Event Ledger Package

## Overview

The `sovereign/ledger/` package provides a complete, production-ready implementation of an immutable, hash-chained event ledger in Go. It implements cryptographic verification, integrity checking, deterministic replay, and comprehensive event management.

## Key Features

### Core Functionality
- **Hash-Chained Events**: Each event is cryptographically linked to the previous one using SHA-256
- **Immutable Ledger**: Once appended and verified, events cannot be modified without detection
- **Integrity Verification**: Complete hash chain validation to detect tampering
- **Merkle Tree Support**: Efficient verification of event sets via Merkle proofs
- **Deterministic Replay**: Reproducible ledger state from events
- **Event Sealing**: Permanent ledger closure for audit trails

### Advanced Features
- **Event Builder**: Fluent interface for constructing complex events
- **Query System**: Search events by ID, speaker, type, timestamp, or sequence
- **Statistics Tracking**: Automatic aggregation of ledger metrics
- **Audit Logging**: Complete operation history
- **Snapshot Creation**: Point-in-time ledger snapshots
- **Serialization**: JSON and Gob format support
- **File I/O**: Checkpoint, recovery, and replication support
- **Thread-Safe**: RWMutex-protected operations

## Package Structure

```
sovereign/ledger/
├── event.go              # Event types, builders, queries (401 LOC)
├── ledger.go             # Core ledger implementation (497 LOC)
├── ledger_test.go        # Comprehensive tests (525 LOC)
├── serialization.go      # Serialization support (358 LOC)
├── io.go                 # File I/O and persistence (389 LOC)
├── example_test.go       # Usage examples
└── go.mod                # Module definition
```

**Total: 2,170+ LOC**

## Core Types

### Event
Represents an immutable ledger entry with:
- EventID, SequenceNumber, Timestamp
- Speaker, EventType, Content
- Raw and normalized content hashes
- Hash chain references
- Evaluation and constraint versions
- Flexible metadata

### Ledger
Main ledger container with:
- Hash-chained events
- Verification state
- Statistics and audit log
- Sealing capability
- Thread-safe operations

### EventBuilder
Fluent builder for event construction:
```go
event := NewEventBuilder("evt-001").
    WithSpeaker("Alice").
    WithEventType("transaction").
    WithRawContent("content").
    WithMetadata("key", "value").
    Build()
```

## Usage Examples

### Create and Populate Ledger

```go
// Create ledger
ledger := NewLedger("session-001")

// Build event
event := NewEventBuilder("evt-001").
    WithSpeaker("Alice").
    WithEventType("transaction").
    WithRawContent("Transfer 100 USD").
    WithNormalizedContent("Transfer 100 USD").
    WithEvaluationVersion("1.0").
    WithConstraintVersion("1.0").
    Build()

// Append event
if err := ledger.AppendEvent(event); err != nil {
    log.Fatal(err)
}
```

### Verify Ledger Integrity

```go
// Verify hash chain
if err := ledger.Verify(); err != nil {
    log.Fatal("Verification failed:", err)
}

// Check for tampering
if ledger.TamperDetection() {
    log.Fatal("Ledger has been tampered with")
}
```

### Query Events

```go
// Get by sequence number
event, err := ledger.GetEvent(1)

// Get by event ID
event, err := ledger.GetEventByID("evt-001")

// Query by speaker
events, err := ledger.EventsBySpeaker("Alice")

// Query by type
events, err := ledger.EventsByType("transaction")

// Range query
events, err := ledger.GetRange(1, 100)
```

### Export and Serialize

```go
// Full export with statistics
data, err := ledger.Export()

// Canonical form for hashing
data, err := ledger.ExportCanonical()

// Custom serialization options
opts := SerializationOptions{
    Format:          FormatJSON,
    IncludeMetadata: true,
    IncludeStats:    true,
}
data, err := ledger.SerializeWithOptions(opts)
```

### Replay and Snapshots

```go
// Replay verified ledger
events, err := ledger.Replay()

// Create snapshot
snapshot := ledger.CreateSnapshot()

// Seal for audit trail
if err := ledger.Seal(); err != nil {
    log.Fatal(err)
}
```

### File I/O

```go
// Write ledger to file
writer := NewFileWriter("ledger.json", FormatJSON)
if err := writer.Write(ledger); err != nil {
    log.Fatal(err)
}

// Read ledger from file
reader := NewFileReader("ledger.json", FormatJSON)
ledger, err := reader.Read("session-001")

// Create checkpoint
cm := NewCheckpointManager("./checkpoints")
filepath, err := cm.CreateCheckpoint(ledger)

// Recover from checkpoint
rm := NewRecoveryManager("./checkpoints")
ledger, err := rm.RecoverLatest("session-001")
```

### Merkle Trees

```go
// Create Merkle tree from event hashes
hashes := []string{"hash1", "hash2", "hash3", "hash4"}
tree := NewEventMerkleTree(hashes)

// Get Merkle root
root := tree.Root()

// Generate proof for event
proof := tree.Proof(0)

// Verify proof
verified := tree.VerifyProof(0, proof, hashes[0])
```

## API Reference

### Ledger Methods

| Method | Purpose |
|--------|---------|
| `AppendEvent(event Event)` | Add event to ledger |
| `Verify()` | Verify ledger integrity |
| `Seal()` | Permanently close ledger |
| `GetEvent(seq uint64)` | Retrieve event by sequence |
| `GetEventByID(id string)` | Retrieve event by ID |
| `Query(query EventQuery)` | Search events |
| `Replay()` | Get ordered event list |
| `Export()` | Serialize full ledger |
| `TamperDetection()` | Check for modifications |
| `CreateSnapshot()` | Create point-in-time snapshot |
| `GetStats()` | Get ledger statistics |
| `IsVerified()` | Check verification state |
| `IsSealed()` | Check seal state |

### Statistics

The ledger automatically tracks:
- Total event count
- Events by type
- Events by speaker
- First/last event times
- Average time per event
- Verification success/failure counts
- Sequence gaps
- Content hash collisions

## Thread Safety

All Ledger methods use RWMutex protection:
- **Read operations** use RLock for concurrent access
- **Write operations** use Lock for exclusive access
- **Safe for concurrent access** from multiple goroutines

## Testing

The package includes 20+ comprehensive tests:

```bash
go test -v
go test -bench=.  # Run benchmarks
```

Test coverage includes:
- Event creation and building
- Hash chaining verification
- Ledger sealing
- Query operations
- Serialization/deserialization
- Concurrent operations
- Merkle tree operations
- File I/O operations

## Performance

Benchmarks (1000 events):
- AppendEvent: ~1-2µs per operation
- Verify: ~100-200µs per ledger
- Export: ~200-300µs per ledger
- Merkle tree operations: O(log n)

## Design Patterns

### Hash Chaining
Each event includes a hash of the previous event, creating an immutable chain. Modifying any event invalidates all subsequent hashes.

### Canonical Form
Events are hashed using a deterministic canonical JSON representation to ensure reproducible hashing across serialization formats.

### Merkle Trees
Optional Merkle tree construction enables efficient proof generation and verification for event subsets.

### Event Builder
Fluent interface reduces boilerplate and ensures proper event construction.

### Snapshot Semantics
Snapshots capture ledger state without deep copying, enabling efficient point-in-time analysis.

## Security Considerations

1. **Hash Function**: Uses SHA-256 for collision resistance
2. **Deterministic Hashing**: Canonical JSON ensures reproducible hashes
3. **Immutability**: Sealed ledgers cannot accept new events
4. **Verification**: Hash chain verification detects any modifications
5. **Audit Trail**: Complete operation logging for compliance

## Limitations

- Ledger must be verified before replaying
- Sealed ledgers cannot accept new events
- Events must have unique IDs for deterministic behavior
- Large ledgers (>1M events) may have memory implications

## Future Enhancements

- [ ] Compression support for large event payloads
- [ ] Distributed ledger synchronization
- [ ] Event pruning for archived data
- [ ] Real-time change notification
- [ ] Event encryption support
- [ ] Batch operation optimization

## License

See LICENSE file in repository
