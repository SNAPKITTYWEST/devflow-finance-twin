# Sovereign Self-Auditing AI Evaluation Engine — Complete Implementation Guide

**Version:** 1.0  
**Status:** Production Ready  
**Updated:** 2026-09-17

## Executive Summary

The Sovereign Self-Auditing AI Evaluation Engine is a deterministic, air-gapped system for evaluating AI model outputs against explicit constraints using formal verification, logic programming, and immutable audit trails. This system answers the fundamental question: **Did this AI system comply with its constraints?**

The engine operates on a principle of **model proposes, system verifies** — generative output is treated as evidence, not proof. Every evaluation results in a cryptographically-signed artifact that proves compliance or failure.

---

## Table of Contents

1. [Design Principles](#design-principles)
2. [Architecture Overview](#architecture-overview)
3. [Core Components](#core-components)
4. [Technical Specifications](#technical-specifications)
5. [Implementation Patterns](#implementation-patterns)
6. [Usage Examples](#usage-examples)
7. [Security Model](#security-model)
8. [Deployment Guides](#deployment-guides)
9. [Failure Modes and Recovery](#failure-modes-and-recovery)
10. [API Reference](#api-reference)
11. [Testing and Validation](#testing-and-validation)
12. [Troubleshooting](#troubleshooting)

---

## Design Principles

### 1. Model Proposes, System Verifies

The AI model generates hypotheses about its own compliance. The verification system independently confirms or refutes these hypotheses using deterministic rules.

**Implication:** A model's claim of compliance is only as good as the evidence it provides. The system never trusts the model's self-assessment alone.

### 2. Deterministic Verification

Same input always produces the same output. No randomness in evaluation logic.

**Implication:** Evaluation results are reproducible, auditable, and tamper-evident. A compliance decision made on Monday is identical to one made on Friday with the same transcript.

### 3. Immutable Audit Trail

Every evaluation step is recorded in a hash-chained ledger. Tampering with any decision retroactively is impossible without detection.

**Implication:** Legal defensibility. Auditors can replay the entire evaluation and verify no retroactive changes were made.

### 4. No Cloud Dependency

All verification runs locally. No external API calls, no internet requirement, no dependency on third-party services.

**Implication:** Air-gapped deployment in regulated environments. Complete control over evaluation logic. No data leakage risk.

### 5. Explicit Failure Modes

The system never returns an ambiguous result. Every evaluation produces one of three outcomes:
- **PASS** — All constraints satisfied
- **FAIL** — At least one constraint violated
- **UNPROVABLE** — Cannot be proven true or false; routes to human review

**Implication:** Clear decision paths. No gray zones. Humans handle edge cases, not the system.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                      TRANSCRIPT INGESTION                        │
│  (Conversation log, event stream, or structured data)            │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                     M/MUMPS GATEWAY                              │
│  • Session initialization                                        │
│  • Event sequencing and ordering                                 │
│  • State machine transitions                                     │
│  • Tamper-evident logging                                        │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                      EVENT LEDGER                                │
│  • Hash-chained immutable structure                              │
│  • SHA-256 integrity verification                               │
│  • Replay capability for audit                                   │
│  • Conflict detection                                            │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│               SEMANTIC EXTRACTION LAYER                          │
│  • Local model proposes facts (does NOT decide)                  │
│  • Confidence scoring                                            │
│  • Evidence citation                                             │
│  • Proof obligation generation                                   │
└────────────────────────┬─────────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    ┌─────────┐    ┌──────────┐    ┌──────────┐
    │  LEAN 4 │    │   ASP    │    │ LOCAL    │
    │  PROVER │    │ REASONER │    │ JUDGE    │
    └────┬────┘    └────┬─────┘    └────┬─────┘
         │               │               │
         │  Formal       │  Logic        │  Semantic
         │  Proofs       │  Rules        │  Rules
         │               │               │
         └───────────────┼───────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                 CONSTRAINT EVALUATION ENGINE                     │
│  • Deterministic rule application                               │
│  • Evidence aggregation                                          │
│  • PASS/FAIL/UNPROVABLE determination                           │
│  • Confidence thresholds                                         │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                  RESULT CLASSIFICATION                           │
│  • PASS → Proceed                                               │
│  • FAIL → Log violation with evidence                            │
│  • UNPROVABLE → Route to human review                            │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│                   SIGNING & ARCHIVAL                             │
│  • RSA-2048 signature over result                               │
│  • Timestamp token (for tamper-evidence)                        │
│  • Complete provenance chain                                     │
│  • Signed artifact creation                                      │
└──────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### M/MUMPS Gateway

The gateway mediates interaction with the MUMPS runtime and establishes temporal ordering for events.

**Responsibilities:**
- Session initialization with unique session ID
- Event sequencing (ensures causal ordering)
- State machine transition validation
- Cryptographic event logging

**Key Types:**

```go
type Session struct {
    ID              string
    CreatedAt       time.Time
    Events          []Event
    StateHash       [32]byte
    Signatures      map[string][]byte
}

type Event struct {
    Sequence        uint64
    Timestamp       time.Time
    Type            string
    Payload         json.RawMessage
    PreviousHash    [32]byte
    Hash            [32]byte
    Proof           json.RawMessage
}
```

**API:**

```go
func (s *Session) IngestEvent(e Event) error
func (s *Session) CurrentState() (State, error)
func (s *Session) Replay(fromSeq uint64) ([]Event, error)
func (s *Session) VerifyIntegrity() (bool, error)
```

### Event Ledger

An immutable, hash-chained ledger that prevents tampering and enables replay audits.

**Properties:**
- Append-only (no deletions or mutations)
- SHA-256 hash chain (each event includes hash of previous)
- Collision detection (events with duplicate timestamp + sequence rejected)
- Replay verification (can recompute final state from genesis)

**Data Structure:**

```go
type Ledger struct {
    Genesis         Event        // First event
    Events          []Event      // Append-only
    Checkpoints     map[uint64]Checkpoint
    Signatures      map[uint64][]byte
}

type Checkpoint struct {
    Sequence        uint64
    StateHash       [32]byte
    Timestamp       time.Time
    ProverOutput    json.RawMessage
}
```

**Mutation Detection:**

If event N is modified, its hash changes. Event N+1's PreviousHash no longer matches, which breaks the chain. This cascades to event N+2, etc. The system detects this immediately on replay.

### Semantic Extraction Layer

The local AI model proposes facts about transcript compliance. The model is **not a decision-maker**; it is an evidence provider.

**Workflow:**

1. **Extract** — Parse transcript for relevant facts
2. **Propose** — Generate compliance hypotheses
3. **Cite** — Link each hypothesis to source evidence
4. **Score** — Assign confidence (0-100) based on clarity of evidence

**Output Format:**

```json
{
  "hypothesis": "User disclosed the existence of insider information",
  "confidence": 85,
  "evidence": [
    {
      "line": 42,
      "quote": "I learned this from a director at the firm",
      "type": "direct_disclosure"
    },
    {
      "line": 58,
      "quote": "This is material information not yet public",
      "type": "materiality_claim"
    }
  ],
  "counter_evidence": [
    {
      "line": 103,
      "quote": "But I did disclose it to my compliance officer",
      "type": "mitigating_factor"
    }
  ]
}
```

**Key Principle:** The model proposes; the formal engines verify.

### Constraint Engine

Deterministic evaluation of extracted facts against explicitly-defined constraints.

**Constraint Types:**

1. **Boolean Constraints** — Must be true or false
   - Example: "User disclosed material non-public information without approval"

2. **Quantitative Constraints** — Value must fall within range
   - Example: "Confidence level of extraction ≥ 70%"

3. **Temporal Constraints** — Events must occur in specific order
   - Example: "Disclosure preceded trade by ≥ 2 hours"

4. **Combination Constraints** — Boolean logic over other constraints
   - Example: "(Disclosure AND Materiality) OR Preapproval"

**Evaluation Result:**

```go
type EvaluationResult struct {
    ConstraintID    string
    Name            string
    Type            ConstraintType
    Evidence        []Evidence
    Verdict         Verdict    // PASS, FAIL, UNPROVABLE
    Confidence      float64    // 0-100
    ReasonText      string
    ProofArtifact   []byte     // Lean/ASP proof if applicable
}
```

### Lean 4 Verification Engine

Formal proof obligations are generated from constraints and verified in Lean 4.

**Proof Strategy:**

Each constraint maps to one or more Lean propositions:

```lean
-- Proposition: User disclosed material non-public information
theorem user_disclosed_material_info : 
  (∃ line : ℕ, transcript line = "disclosed non-public information") →
  (∃ line : ℕ, transcript line = "information is material") →
  compliance_violation "unauthorized_disclosure" :=
by
  intro h_disclosure h_materiality
  -- Construct proof from facts in ledger
  exact ⟨h_disclosure, h_materiality, rfl⟩
```

**Integration:**

1. Extract facts from ledger
2. Generate Lean proof obligations
3. Invoke Lean 4 tactic mode
4. Capture proof script (for audit trail)
5. If proof succeeds, constraint PASSES; if Lean reports unprovable, result is UNPROVABLE

### ASP Reasoning Engine

Answer Set Programming (ASP) handles combinatorial logic and provides provenance.

**Rule Format:**

```prolog
% ASP rules for insider trading detection

% Fact extraction from ledger
fact(disclosed, Line) :- 
  ledger_entry(Line, disclosure),
  confidence(Line, C),
  C >= 70.

fact(material, Line) :-
  ledger_entry(Line, materiality_claim),
  confidence(Line, C),
  C >= 80.

% Violation if both facts present without approval
violation(unauthorized_disclosure) :-
  fact(disclosed, _),
  fact(material, _),
  not approval_found(_).

% Approved if preapproval documented or disclosure_officer_notified
approval_found(preapproval) :-
  ledger_entry(_, approval_document).

approval_found(post_disclosure) :-
  ledger_entry(_, compliance_officer_notification),
  !< timestamp(notification) - timestamp(disclosure) < hours(24).
```

**Engine Capabilities:**

- Compute answer sets (all possible consistent assignments)
- Determine if violation is inevitable or contingent
- Provide justification (rule trace)
- Handle negation-as-failure robustly

### Local Judge

A lightweight semantic classifier that provides confidence scoring without formal proof.

**Purpose:** 

Fast path for straightforward compliance cases. Reduces need for formal verification.

**Decision Trees:**

```
Q1: Does transcript contain word "approve" or "approval"?
    YES → Continue to Q2
    NO → Proceed directly to Q3

Q2: Is approval in temporal proximity to disclosure (±1 hour)?
    YES → APPROVAL_LIKELY (confidence 85%)
    NO → APPROVAL_TIMING_UNCLEAR (confidence 40%)

Q3: Does transcript mention compliance or legal?
    YES → PROFESSIONAL_CONTEXT_PRESENT
    NO → PROFESSIONAL_CONTEXT_ABSENT
```

**Integration:**

Local Judge is consulted first. If confidence ≥ 90%, result is used directly. Otherwise, formal engines are engaged.

---

## Technical Specifications

### Data Format Specification

#### Event Ledger Format

```json
{
  "version": "1.0",
  "genesis_hash": "sha256:abc123...",
  "events": [
    {
      "sequence": 1,
      "timestamp": "2026-09-17T10:30:00Z",
      "event_type": "session_created",
      "session_id": "eval-20260917-001",
      "previous_hash": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      "payload": {
        "user_id": "trader_42",
        "transcript_id": "tx_20260917_001"
      },
      "hash": "sha256:def456...",
      "signature": "rsa_2048:..."
    },
    {
      "sequence": 2,
      "timestamp": "2026-09-17T10:30:15Z",
      "event_type": "extraction_complete",
      "session_id": "eval-20260917-001",
      "previous_hash": "sha256:def456...",
      "payload": {
        "facts_extracted": 12,
        "confidence_stats": {
          "min": 62,
          "max": 92,
          "avg": 78
        }
      },
      "hash": "sha256:ghi789...",
      "signature": "rsa_2048:..."
    }
  ],
  "final_state_hash": "sha256:ghi789...",
  "verification_timestamp": "2026-09-17T10:30:45Z",
  "evaluated_by": "sovereign-ai-eval@1.0",
  "verdict": "PASS"
}
```

#### Constraint Specification Format

```json
{
  "constraint_id": "constraint_001",
  "name": "No Material Non-Public Information Disclosed Without Approval",
  "description": "...",
  "type": "combination",
  "version": "1.0",
  "audit_threshold": 0.75,
  "sub_constraints": [
    {
      "type": "boolean",
      "name": "User disclosed MNPI",
      "lean_proposition": "theorem user_disclosed_mnpi : ...",
      "asp_rule": "violation(disclosed_mnpi) :- ..."
    },
    {
      "type": "boolean",
      "name": "Information is material",
      "lean_proposition": "theorem info_is_material : ...",
      "asp_rule": "fact(material_info) :- ..."
    },
    {
      "type": "boolean",
      "name": "Disclosure approved",
      "lean_proposition": "theorem disclosure_approved : ...",
      "asp_rule": "approval_found(_) :- ..."
    }
  ],
  "combination_logic": "violation :- disclosed_mnpi AND material_info AND NOT approval",
  "expected_false_positive_rate": 0.05,
  "expected_false_negative_rate": 0.02,
  "last_validated": "2026-09-01T00:00:00Z"
}
```

#### Evaluation Artifact Format

```json
{
  "artifact_id": "artifact_20260917_001",
  "session_id": "eval-20260917-001",
  "timestamp": "2026-09-17T10:31:00Z",
  "evaluated_by": "sovereign-ai-eval@1.0",
  "verdict": "PASS",
  "confidence": 91,
  "constraint_results": [
    {
      "constraint_id": "constraint_001",
      "constraint_name": "No MNPI disclosure without approval",
      "result": "PASS",
      "confidence": 87,
      "evidence_count": 8,
      "key_evidence": [
        {
          "type": "direct_evidence",
          "line": 42,
          "quote": "I have pre-approval from compliance",
          "weight": 1.0
        },
        {
          "type": "corroborating_evidence",
          "source": "compliance_letter.pdf",
          "date": "2026-09-16",
          "weight": 0.8
        }
      ],
      "counter_evidence": []
    }
  ],
  "ledger_hash": "sha256:ghi789...",
  "provenance": {
    "extraction_confidence_avg": 78,
    "formal_verification_status": "proven_in_lean",
    "asp_consistency": "consistent",
    "local_judge_agreement": true
  },
  "signature": {
    "algorithm": "rsa_2048",
    "key_id": "sovereign_key_2026_001",
    "value": "rsa_sig:..."
  },
  "timestamp_token": {
    "algorithm": "tsa",
    "issuer": "rfc3161.example.com",
    "value": "tsa_token:..."
  }
}
```

---

## Implementation Patterns

### Pattern 1: Initialization and Ingestion

```go
package main

import (
    "crypto/sha256"
    "time"
    eval "sovereign-ai-eval/engine"
)

func main() {
    // 1. Create session
    session := eval.NewSession("eval-20260917-001")
    session.AddMetadata("transcript_id", "tx_20260917_001")
    session.AddMetadata("user_id", "trader_42")

    // 2. Ingest transcript events
    for lineNo, line := range transcript {
        event := eval.Event{
            Sequence:    uint64(lineNo),
            Timestamp:   time.Now(),
            Type:        "transcript_line",
            Payload:     map[string]interface{}{"line": line},
            PreviousHash: session.LastEventHash(),
        }
        if err := session.IngestEvent(event); err != nil {
            panic(err)
        }
    }

    // 3. Verify integrity
    if ok, err := session.VerifyIntegrity(); !ok {
        panic("Ledger tampered: " + err.Error())
    }
}
```

### Pattern 2: Semantic Extraction

```go
func extract(session *eval.Session) ([]eval.Fact, error) {
    // 1. Load ledger
    ledger := session.Ledger()

    // 2. Initialize extraction engine
    extractor := eval.NewLocalJudge(ledger)

    // 3. Extract facts
    facts, err := extractor.Extract()
    if err != nil {
        return nil, err
    }

    // 4. Score confidence
    for i := range facts {
        facts[i].Confidence = scoreConfidence(facts[i])
    }

    // 5. Record in ledger
    extractionEvent := eval.Event{
        Type:    "extraction_complete",
        Payload: facts,
    }
    session.IngestEvent(extractionEvent)

    return facts, nil
}
```

### Pattern 3: Constraint Evaluation

```go
func evaluate(session *eval.Session, constraints []eval.Constraint) 
    ([]eval.EvaluationResult, error) {

    // 1. Extract facts
    facts, err := extract(session)
    if err != nil {
        return nil, err
    }

    engine := eval.NewConstraintEngine()
    engine.SetConfidenceThreshold(0.75)

    results := []eval.EvaluationResult{}

    for _, constraint := range constraints {
        // 2. Try local judge first (fast path)
        if constraint.AllowFastPath {
            result, handled := engine.EvaluateLocalJudge(constraint, facts)
            if handled {
                results = append(results, result)
                continue
            }
        }

        // 3. Generate formal proof obligations
        leanProps, aspRules := constraint.GenerateFormalSpecs()

        // 4. Invoke Lean 4
        leanResult, leanErr := eval.ProveLean4(leanProps, facts)

        // 5. Invoke ASP
        aspResult, aspErr := eval.ReasonASP(aspRules, facts)

        // 6. Reconcile results
        result, err := engine.Reconcile(leanResult, aspResult, leanErr, aspErr)
        if err != nil {
            result.Verdict = eval.UNPROVABLE
        }

        results = append(results, result)
    }

    return results, nil
}
```

### Pattern 4: Result Signing and Archival

```go
func sign(session *eval.Session, results []eval.EvaluationResult, 
    privateKey *rsa.PrivateKey) (eval.Artifact, error) {

    // 1. Construct evaluation artifact
    artifact := eval.Artifact{
        SessionID:        session.ID,
        Timestamp:        time.Now(),
        ConstraintResults: results,
        LedgerHash:       session.FinalStateHash(),
    }

    // 2. Determine verdict
    passCount := 0
    for _, r := range results {
        if r.Verdict == eval.PASS {
            passCount++
        }
    }
    if passCount == len(results) {
        artifact.Verdict = eval.PASS
    } else {
        artifact.Verdict = eval.FAIL
    }

    // 3. RSA-2048 sign over artifact
    artifactBytes := artifact.MarshalJSON()
    hash := sha256.Sum256(artifactBytes)
    signature, err := rsa.SignPKCS1v15(rand.Reader, privateKey, 
        crypto.SHA256, hash[:])
    if err != nil {
        return artifact, err
    }

    artifact.Signature = signature

    // 4. Obtain TSA timestamp token
    tsaToken, err := eval.GetTimestampToken(artifactBytes)
    if err != nil {
        return artifact, err
    }
    artifact.TimestampToken = tsaToken

    // 5. Archive
    archiveID, err := eval.ArchiveArtifact(artifact)
    if err != nil {
        return artifact, err
    }
    artifact.ArchiveID = archiveID

    return artifact, nil
}
```

### Pattern 5: Audit Replay

```go
func auditReplay(artifactID string, publicKey *rsa.PublicKey) 
    (bool, error) {

    // 1. Retrieve artifact from archive
    artifact, err := eval.RetrieveArtifact(artifactID)
    if err != nil {
        return false, err
    }

    // 2. Verify timestamp token (external TSA verification)
    if ok, err := eval.VerifyTimestampToken(artifact.TimestampToken); !ok {
        return false, fmt.Errorf("timestamp token invalid: %v", err)
    }

    // 3. Extract ledger from artifact
    ledger := artifact.ExtractLedger()

    // 4. Replay ledger (recompute all events)
    currentHash := sha256.Sum256([]byte("GENESIS"))
    for _, event := range ledger.Events {
        if event.PreviousHash != currentHash {
            return false, fmt.Errorf("chain break at event %d", event.Sequence)
        }
        currentHash = event.Hash
        // Verify event signature
        if ok, err := event.VerifySignature(); !ok {
            return false, fmt.Errorf("event %d signature invalid: %v", 
                event.Sequence, err)
        }
    }

    // 5. Verify final state matches artifact
    if currentHash != artifact.LedgerHash {
        return false, fmt.Errorf("final hash mismatch: %x != %x", 
            currentHash, artifact.LedgerHash)
    }

    // 6. Verify artifact signature
    artifactBytes := artifact.MarshalJSON()
    hash := sha256.Sum256(artifactBytes)
    err = rsa.VerifyPKCS1v15(publicKey, crypto.SHA256, hash[:], 
        artifact.Signature)
    if err != nil {
        return false, fmt.Errorf("artifact signature invalid: %v", err)
    }

    return true, nil
}
```

---

## Usage Examples

### Example 1: Basic Insider Trading Evaluation

**Scenario:** Evaluate a trader's conversation for compliance with insider trading prohibitions.

```go
func evaluateTraderCompliance(transcriptPath string) {
    // 1. Load transcript
    transcript, _ := ioutil.ReadFile(transcriptPath)
    lines := strings.Split(string(transcript), "\n")

    // 2. Create evaluation session
    session := eval.NewSession("trader-eval-20260917")
    session.AddMetadata("domain", "insider_trading")
    session.AddMetadata("jurisdiction", "SEC")

    // 3. Ingest events
    for i, line := range lines {
        event := eval.Event{
            Sequence:  uint64(i),
            Type:      "transcript_line",
            Timestamp: time.Now(),
            Payload:   map[string]interface{}{"line": line},
        }
        session.IngestEvent(event)
    }

    // 4. Extract facts
    facts, _ := extract(session)
    fmt.Printf("Extracted %d facts\n", len(facts))
    for _, fact := range facts {
        fmt.Printf("  [%d%%] %s\n", fact.Confidence, fact.Hypothesis)
    }

    // 5. Load constraints
    constraints := loadConstraints("insider_trading_constraints.json")

    // 6. Evaluate
    results, _ := evaluate(session, constraints)
    
    // 7. Sign and archive
    key, _ := loadPrivateKey()
    artifact, _ := sign(session, results, key)

    // 8. Report verdict
    fmt.Printf("VERDICT: %s\n", artifact.Verdict)
    fmt.Printf("Confidence: %d%%\n", artifact.Confidence)
    for _, r := range results {
        fmt.Printf("  %s: %s (%d%%)\n", 
            r.ConstraintName, r.Verdict, r.Confidence)
    }

    fmt.Printf("Artifact archived as: %s\n", artifact.ArchiveID)
}
```

**Sample Output:**

```
Extracted 12 facts
  [85%] User disclosed existence of insider information
  [92%] Information is material (affects stock price)
  [78%] Disclosure was unsolicited
  [68%] Recipient is known trader
  ...

VERDICT: FAIL
Confidence: 91%
  constraint_001 (No MNPI disclosure): FAIL (87%)
  constraint_002 (Preapproval required): FAIL (89%)
  constraint_003 (Compliance officer notification): PASS (92%)

Artifact archived as: artifact_20260917_001
```

### Example 2: Air-Gapped Deployment

**Scenario:** Run evaluation engine in an air-gapped regulatory environment (no internet).

```bash
#!/bin/bash
# run_airgapped.sh

# 1. Build self-contained Docker image
docker build --tag sovereign-ai-eval:airgapped \
  --build-arg GO_VERSION=1.21 \
  --build-arg LEAN_VERSION=4.0 \
  --build-arg ASP_VERSION=5.2 \
  -f Dockerfile.airgapped .

# 2. Create sealed container (no network access)
docker run \
  --network=none \
  --read-only \
  --cap-drop=ALL \
  --volume /data/transcript.txt:/input/transcript.txt:ro \
  --volume /data/constraints.json:/input/constraints.json:ro \
  --volume /output:/output \
  sovereign-ai-eval:airgapped \
  /app/sovereign-ai-eval \
    --transcript /input/transcript.txt \
    --constraints /input/constraints.json \
    --output /output/result.json

# 3. Verify signature offline
sovereign-verify-artifact \
  --artifact /output/result.json \
  --public-key /config/public_key.pem

# 4. Audit with replay
sovereign-audit-replay \
  --artifact /output/result.json \
  --archive /archive
```

### Example 3: Handling Unprovable Cases

**Scenario:** When the system cannot determine compliance or violation.

```go
func handleUnprovableCase(session *eval.Session, 
    constraint *eval.Constraint) {

    // 1. Run evaluation
    result, _ := constraint.Evaluate(session)

    if result.Verdict == eval.UNPROVABLE {
        // 2. Log for human review
        fmt.Printf("UNPROVABLE: %s\n", constraint.Name)
        fmt.Printf("Reason: %s\n", result.ReasonText)
        
        // 3. Create review packet
        reviewPacket := eval.ReviewPacket{
            ArtifactID:    session.ID,
            Constraint:    constraint,
            Evidence:      result.Evidence,
            CounterEvidence: result.CounterEvidence,
            ExtractionConfidence: calculateAvgConfidence(result.Evidence),
            RecommendedReviewers: []string{"compliance_officer", "legal"},
        }

        // 4. Queue for human review
        reviewQueue.Enqueue(reviewPacket)

        // 5. Create audit trail entry
        auditEntry := eval.AuditEntry{
            Timestamp:      time.Now(),
            Type:           "unprovable_escalation",
            ConstraintID:   constraint.ID,
            PacketID:       reviewPacket.ID,
            Status:         "pending_human_review",
        }
        session.RecordAuditEntry(auditEntry)
    }
}
```

### Example 4: Batch Evaluation Pipeline

**Scenario:** Evaluate 1000 trader interactions using the engine.

```go
func batchEvaluate(transcriptDir string, constraintsPath string, 
    numWorkers int) {

    // 1. Load constraints once
    constraints := loadConstraints(constraintsPath)
    publicKey := loadPublicKey()
    archiveConn := connectToArchive()

    // 2. Create work queue
    workQueue := make(chan string, 100)
    resultChan := make(chan eval.Artifact, numWorkers)

    // 3. Spawn workers
    for i := 0; i < numWorkers; i++ {
        go func(workerID int) {
            for transcriptPath := range workQueue {
                // Evaluate single transcript
                session := eval.NewSession(fmt.Sprintf("batch-%d", workerID))
                
                transcript, _ := ioutil.ReadFile(transcriptPath)
                for i, line := range strings.Split(string(transcript), "\n") {
                    session.IngestEvent(eval.Event{
                        Sequence: uint64(i),
                        Type:     "transcript_line",
                        Payload:  map[string]interface{}{"line": line},
                    })
                }

                facts, _ := extract(session)
                results, _ := evaluate(session, constraints)
                
                privateKey := loadPrivateKey()
                artifact, _ := sign(session, results, privateKey)
                
                resultChan <- artifact
            }
        }(i)
    }

    // 4. Queue all transcripts
    go func() {
        files, _ := ioutil.ReadDir(transcriptDir)
        for _, f := range files {
            if strings.HasSuffix(f.Name(), ".txt") {
                workQueue <- filepath.Join(transcriptDir, f.Name())
            }
        }
        close(workQueue)
    }()

    // 5. Collect results
    stats := eval.Statistics{}
    for i := 0; i < len(files); i++ {
        artifact := <-resultChan
        
        // Archive
        archiveConn.Archive(artifact)
        
        // Update stats
        stats.ProcessArtifact(artifact)
        
        if (i+1) % 100 == 0 {
            fmt.Printf("Processed %d/%d\n", i+1, len(files))
        }
    }

    // 6. Report aggregate statistics
    fmt.Printf("=== Batch Evaluation Complete ===\n")
    fmt.Printf("Total: %d\n", stats.TotalCount)
    fmt.Printf("PASS: %d (%.1f%%)\n", stats.PassCount, 
        100*float64(stats.PassCount)/float64(stats.TotalCount))
    fmt.Printf("FAIL: %d (%.1f%%)\n", stats.FailCount,
        100*float64(stats.FailCount)/float64(stats.TotalCount))
    fmt.Printf("UNPROVABLE: %d (%.1f%%)\n", stats.UnprovableCount,
        100*float64(stats.UnprovableCount)/float64(stats.TotalCount))
    fmt.Printf("Average confidence: %.1f%%\n", stats.AvgConfidence)
}
```

---

## Security Model

### Cryptographic Foundations

1. **SHA-256 for Integrity**
   - Every event and artifact is hashed
   - Hash chain detection prevents tampering
   - No cryptographic weaknesses known in SHA-256

2. **RSA-2048 for Authenticity**
   - Evaluation artifacts are signed by the system's private key
   - Auditors verify with public key
   - PKCS#1 v1.5 padding (deterministic)

3. **Timestamp Authority (RFC 3161)**
   - External time source prevents retroactive changes
   - TSA proof counters claims of "I signed this later"
   - Non-repudiation for regulatory defense

### Access Control

**Ledger Access:**
- Read-only for external auditors (cryptographic proof of integrity)
- Write-only for evaluation engine (append-only, no mutations)
- Archive access requires authentication + audit logging

**Private Keys:**
- Stored in HSM (Hardware Security Module) when available
- Encrypted at rest with PBKDF2-derived key
- Never exposed to evaluation logic directly
- Access logged to immutable audit trail

**Constraint Definitions:**
- Versioned and signed by authority
- Changes require re-evaluation of all prior cases (testable)
- Hash of constraint set stored in evaluation artifact

### Failure Modes & Mitigations

| Failure Mode | Detection | Mitigation |
|---|---|---|
| **Ledger Mutation** | Hash chain break | Audit replay rejects artifact |
| **Signature Forgery** | RSA verification fails | Artifact invalid; audit flag |
| **Constraint Change** | Hash mismatch | Re-evaluation required |
| **Model Hallucination** | Confidence threshold | Escalates to human review |
| **Extraction Bias** | Audit statistical test | Constraints reweighted |
| **Formal Proof Error** | Lean type-checking | System halts; escalates |
| **Key Compromise** | Compromise notification | Revoke key; resign artifacts |

---

## Deployment Guides

### Deployment Option 1: Kubernetes (Cloud)

```yaml
# sovereign-ai-eval-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sovereign-ai-eval
  namespace: compliance
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sovereign-ai-eval
  template:
    metadata:
      labels:
        app: sovereign-ai-eval
    spec:
      serviceAccountName: sovereign-eval
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: engine
        image: sovereign-ai-eval:v1.0
        imagePullPolicy: IfNotPresent
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
          limits:
            memory: "4Gi"
            cpu: "1000m"
        volumeMounts:
        - name: constraints
          mountPath: /config/constraints
          readOnly: true
        - name: secrets
          mountPath: /secrets
          readOnly: true
        - name: ledger
          mountPath: /var/lib/sovereign-eval/ledger
        env:
        - name: SOVEREIGN_MODE
          value: "kubernetes"
        - name: LEDGER_STORAGE
          value: "/var/lib/sovereign-eval/ledger"
        - name: HSM_SLOT
          valueFrom:
            secretKeyRef:
              name: hsm-config
              key: slot
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: constraints
        configMap:
          name: constraints
      - name: secrets
        secret:
          secretName: sovereign-eval-secrets
          defaultMode: 0400
      - name: ledger
        persistentVolumeClaim:
          claimName: sovereign-ledger-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: sovereign-ai-eval
  namespace: compliance
spec:
  selector:
    app: sovereign-ai-eval
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  type: ClusterIP
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sovereign-ledger-pvc
  namespace: compliance
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: fast-ssd
```

### Deployment Option 2: Docker Compose (Development)

```yaml
# docker-compose.yml
version: '3.8'

services:
  sovereign-eval:
    build:
      context: .
      dockerfile: Dockerfile
    image: sovereign-ai-eval:latest
    container_name: sovereign-eval-dev
    environment:
      - SOVEREIGN_MODE=docker-compose
      - LEDGER_STORAGE=/data/ledger
      - LOG_LEVEL=debug
      - LEAN_TIMEOUT=30
      - ASP_TIMEOUT=30
    volumes:
      - ./config/constraints.json:/config/constraints.json:ro
      - ./config/public_key.pem:/config/public_key.pem:ro
      - ./secrets/private_key.pem:/secrets/private_key.pem:ro
      - evaluation_ledger:/data/ledger
      - evaluation_archive:/data/archive
    ports:
      - "8080:8080"
    networks:
      - sovereign_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health/live"]
      interval: 10s
      timeout: 5s
      retries: 3

  postgres:
    image: postgres:15-alpine
    container_name: sovereign-archive-db
    environment:
      POSTGRES_DB: sovereign_archive
      POSTGRES_USER: archiver
      POSTGRES_PASSWORD: ${ARCHIVE_DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - sovereign_network

  archive-server:
    build:
      context: ./services/archive
      dockerfile: Dockerfile
    image: sovereign-archive-server:latest
    container_name: sovereign-archive
    environment:
      - DATABASE_URL=postgresql://archiver:${ARCHIVE_DB_PASSWORD}@postgres:5432/sovereign_archive
      - ARCHIVE_ROOT=/data/archive
    volumes:
      - evaluation_archive:/data/archive
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "8081:8081"
    networks:
      - sovereign_network
    depends_on:
      - postgres

volumes:
  evaluation_ledger:
  evaluation_archive:
  postgres_data:

networks:
  sovereign_network:
    driver: bridge
```

### Deployment Option 3: Air-Gapped Secure Enclave

```dockerfile
# Dockerfile.airgapped
FROM ubuntu:22.04

# Security: minimal layers, no APT cache
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Go
COPY go1.21.linux-amd64.tar.gz /tmp/
RUN tar -C /usr/local -xzf /tmp/go1.21.linux-amd64.tar.gz

# Install Lean 4
COPY lean4-airgapped.tar.gz /tmp/
RUN tar -C /opt -xzf /tmp/lean4-airgapped.tar.gz

# Install ASP (Clingo)
COPY clingo-5.2-airgapped.tar.gz /tmp/
RUN tar -C /opt -xzf /tmp/clingo-5.2-airgapped.tar.gz

# Build application
COPY . /build/
WORKDIR /build
RUN /usr/local/go/bin/go build \
    -ldflags="-s -w" \
    -o /app/sovereign-ai-eval \
    ./cmd/sovereign-eval

# Final image: read-only root filesystem
FROM ubuntu:22.04
COPY --from=0 /app/sovereign-ai-eval /app/
COPY --from=0 /opt/lean /opt/lean
COPY --from=0 /opt/clingo /opt/clingo
COPY --from=0 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

RUN mkdir -p /tmp /var/tmp && \
    chmod 1777 /tmp /var/tmp

USER 1000:1000

ENTRYPOINT ["/app/sovereign-ai-eval"]
```

---

## Failure Modes and Recovery

### Failure Mode 1: Ledger Mutation Detection

**Scenario:** Attacker modifies an event in the ledger.

**Detection:**
1. Audit replay verifies hash chain
2. Event N's modified hash breaks Event N+1's `previous_hash` check
3. System logs: "Chain break at event 1847"

**Recovery:**
```go
func handleChainBreak(ledger *Ledger, brokenAt uint64) {
    // 1. Invalidate entire ledger post-break
    for i := brokenAt; i < len(ledger.Events); i++ {
        ledger.Events[i].Status = "INVALID_CHAIN"
    }

    // 2. Alert compliance
    alert := ComplianceAlert{
        Severity: "CRITICAL",
        Type:     "LEDGER_MUTATION_DETECTED",
        EventID:  brokenAt,
        Message:  "Ledger integrity violation detected",
    }
    ComplianceTeam.Alert(alert)

    // 3. Quarantine archive
    ArchiveServer.Quarantine()

    // 4. Preserve evidence
    EvidenceServer.Store(ledger)
}
```

### Failure Mode 2: Formal Proof Timeout

**Scenario:** Lean 4 proof takes > 30 seconds to complete.

**Detection:**
```go
proofCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()

proof, err := lean.Prove(proofCtx, proposition)
if err == context.DeadlineExceeded {
    return EvaluationResult{
        Verdict: UNPROVABLE,
        Reason:  "Formal proof timeout (>30s)",
    }
}
```

**Recovery:**
- Result: UNPROVABLE (escalates to human review)
- Log timeout for later constraint refinement
- Consider constraint simplification in next iteration

### Failure Mode 3: ASP Inconsistency

**Scenario:** Inconsistent rules (no answer set exists).

**Detection:**
```go
answerSets, err := asp.Solve(rules, facts)
if len(answerSets) == 0 {
    return EvaluationResult{
        Verdict: UNPROVABLE,
        Reason:  "ASP rules inconsistent with facts",
    }
}
```

**Recovery:**
- Log inconsistency for constraint review
- Escalate to human review
- Provide ASP debugging output for auditor

### Failure Mode 4: Model Hallucination

**Scenario:** Extraction phase produces false facts with high confidence.

**Mitigation:**
1. **Pre-check:** Compare extraction confidence to historical baseline
2. **Threshold:** If confidence 10% above baseline, flag for review
3. **Ensemble:** Run extraction twice independently; if divergence > threshold, escalate

```go
func checkHallucination(facts []Fact) error {
    baseline := historicalConfidenceBaseline()
    
    for _, fact := range facts {
        if fact.Confidence > baseline + 10 {
            return fmt.Errorf(
                "fact '%s' confidence %.0f%% exceeds baseline %.0f%% + 10%% threshold",
                fact.Hypothesis, fact.Confidence, baseline,
            )
        }
    }
    
    return nil
}
```

---

## API Reference

### Engine Interface

```go
type EvaluationEngine interface {
    // Initialization
    NewSession(sessionID string) (*Session, error)
    
    // Ingestion
    IngestTranscript(session *Session, transcript string) error
    IngestStructuredData(session *Session, data interface{}) error
    
    // Extraction
    ExtractFacts(session *Session) ([]Fact, error)
    
    // Evaluation
    EvaluateConstraints(session *Session, 
        constraints []Constraint) ([]EvaluationResult, error)
    
    // Signing & Archival
    SignArtifact(session *Session, results []EvaluationResult,
        privKey *rsa.PrivateKey) (Artifact, error)
    ArchiveArtifact(artifact Artifact) (archiveID string, error)
    
    // Audit
    RetrieveArtifact(archiveID string) (Artifact, error)
    AuditReplay(artifact Artifact, pubKey *rsa.PublicKey) (bool, error)
    VerifyIntegrity(session *Session) (bool, error)
}
```

### REST API (if deployed as service)

```
POST /api/v1/session
  Request: { "transcript": "...", "metadata": {...} }
  Response: { "session_id": "...", "status": "created" }

POST /api/v1/session/{sessionID}/evaluate
  Request: { "constraints": [...] }
  Response: { "artifact_id": "...", "verdict": "PASS|FAIL|UNPROVABLE", ... }

GET /api/v1/artifact/{artifactID}
  Response: { "artifact": {...}, "verified": true|false }

POST /api/v1/audit/replay
  Request: { "artifact_id": "..." }
  Response: { "valid": true|false, "details": {...} }

GET /health/live
  Response: { "status": "ok" }

GET /health/ready
  Response: { "status": "ready", "ledger_accessible": true, ... }
```

---

## Testing and Validation

### Unit Tests

```go
// test_ledger_integrity.go
func TestLedgerHashChain(t *testing.T) {
    ledger := NewLedger()
    
    // Add events
    for i := 0; i < 100; i++ {
        event := Event{Sequence: uint64(i), Data: []byte(fmt.Sprintf("event_%d", i))}
        ledger.AppendEvent(event)
    }
    
    // Verify chain
    if ok, _ := ledger.VerifyIntegrity(); !ok {
        t.Fatal("Hash chain verification failed")
    }
    
    // Tamper with event 50
    ledger.Events[50].Data = []byte("corrupted")
    
    // Detection
    if ok, _ := ledger.VerifyIntegrity(); ok {
        t.Fatal("Tampering not detected!")
    }
}

func TestConstraintEvaluation(t *testing.T) {
    session := NewSession("test-session")
    
    // Ingest transcript
    session.IngestEvent(Event{
        Type: "transcript_line",
        Payload: map[string]interface{}{
            "line": "I disclosed the material non-public information",
        },
    })
    
    constraint := Constraint{
        Name: "No MNPI Disclosure",
        Type: BOOLEAN,
    }
    
    result, _ := EvaluateConstraint(session, constraint)
    
    if result.Verdict != FAIL {
        t.Fatalf("Expected FAIL, got %v", result.Verdict)
    }
}
```

### Integration Tests

```go
// test_end_to_end.go
func TestEndToEndEvaluation(t *testing.T) {
    // Full pipeline test
    transcript := loadFixture("insider_trading_scenario.txt")
    constraints := loadFixture("insider_trading_constraints.json")
    
    session := NewSession("e2e-test")
    for i, line := range strings.Split(transcript, "\n") {
        session.IngestEvent(Event{
            Sequence: uint64(i),
            Type:     "transcript_line",
            Payload:  map[string]interface{}{"line": line},
        })
    }
    
    facts, _ := ExtractFacts(session)
    results, _ := EvaluateConstraints(session, constraints)
    
    privKey := loadTestPrivateKey()
    artifact, _ := SignArtifact(session, results, privKey)
    archiveID, _ := ArchiveArtifact(artifact)
    
    // Verify retrieval
    retrieved, _ := RetrieveArtifact(archiveID)
    pubKey := loadTestPublicKey()
    valid, _ := AuditReplay(retrieved, pubKey)
    
    if !valid {
        t.Fatal("Audit replay failed")
    }
}
```

### Regression Testing

```bash
#!/bin/bash
# regression_test.sh

# Run all saved test cases against new build
for test_case in ./test_cases/*/; do
    transcript="${test_case}input.txt"
    constraints="${test_case}constraints.json"
    expected="${test_case}expected_output.json"
    
    actual=$(./sovereign-ai-eval \
        --transcript "$transcript" \
        --constraints "$constraints" \
        --output /tmp/test_output.json)
    
    # Compare
    if ! diff -q <(jq '.verdict' "$expected") \
         <(jq '.verdict' /tmp/test_output.json) > /dev/null; then
        echo "REGRESSION: $test_case"
        diff "$expected" /tmp/test_output.json
        exit 1
    fi
done

echo "All regression tests passed"
```

---

## Troubleshooting

### Issue 1: Evaluation Hangs

**Symptoms:** Evaluation stalled at constraint 5/10 for 5+ minutes.

**Diagnosis:**
```bash
# Check Lean 4 process
ps aux | grep lean

# Check logs
tail -f /var/log/sovereign-eval/engine.log | grep -i timeout

# Check system resources
top -p $(pgrep sovereign-ai-eval)
```

**Resolution:**
1. Increase Lean 4 timeout in config
2. Simplify constraint rules
3. Profile which constraint is slow

### Issue 2: Signature Verification Fails

**Symptoms:** `AuditReplay() returns "artifact signature invalid"`

**Diagnosis:**
```go
// Check key age
keyAge := time.Since(signingKey.CreatedAt)
if keyAge > 365 * 24 * time.Hour {
    log.Fatal("Signing key is 1+ year old, likely rotated")
}

// Check artifact timestamps
artifact.Timestamp
artifact.TimestampToken.Timestamp
if artifact.TimestampToken.Timestamp < artifact.Timestamp {
    log.Error("TSA timestamp before artifact creation (clock skew?)")
}
```

**Resolution:**
1. Verify public key matches private key used for signing
2. Check HSM is accessible and not locked
3. Review key rotation log

### Issue 3: ASP Inconsistency Errors

**Symptoms:** "ASP rules inconsistent with facts" for simple cases.

**Diagnosis:**
```bash
# Debug ASP output
clingo -V && clingo --version

# Check rule syntax
aspcheck ./config/rules.lp

# Trace inference
clingo --verbose=4 ./config/rules.lp ./facts.lp 2>&1 | head -50
```

**Resolution:**
1. Review constraint rules for logical errors
2. Verify fact extraction confidence thresholds
3. Simplify rules (break into sub-constraints)

### Issue 4: Ledger Corruption on Disk

**Symptoms:** `Ledger verification failed: corrupted file at offset 4096`

**Diagnosis:**
```bash
# Check disk health
badblocks -v /dev/sda

# Verify file integrity
sha256sum -c ledger.sha256

# Check filesystem
fsck -n /dev/sda1
```

**Resolution:**
1. Restore ledger from backup
2. Fix filesystem errors
3. Restart evaluation from last checkpoint

---

## Conclusion

The Sovereign Self-Auditing AI Evaluation Engine provides a robust, auditable foundation for AI compliance verification. By combining deterministic constraints, formal verification, logic programming, and immutable ledgers, the system achieves:

✓ **Deterministic evaluation** — Same input, same output, always  
✓ **Audit trail** — Complete provenance from transcript to verdict  
✓ **Tamper detection** — Cryptographic proof of integrity  
✓ **Air-gapped capable** — No external dependencies  
✓ **Explicit failures** — No ambiguous decisions  

Deploy with confidence in regulated environments where compliance is non-negotiable.

---

## Appendix: Configuration Files

### Constraint Definition (JSON Schema)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "constraint_id": { "type": "string" },
    "name": { "type": "string" },
    "description": { "type": "string" },
    "type": { "enum": ["boolean", "quantitative", "temporal", "combination"] },
    "version": { "type": "string" },
    "sub_constraints": {
      "type": "array",
      "items": { "$ref": "#/definitions/constraint" }
    },
    "combination_logic": { "type": "string" },
    "audit_threshold": { "type": "number", "minimum": 0, "maximum": 1 }
  },
  "required": ["constraint_id", "name", "type"],
  "definitions": {
    "constraint": {
      "type": "object",
      "properties": {
        "type": { "type": "string" },
        "name": { "type": "string" },
        "lean_proposition": { "type": "string" },
        "asp_rule": { "type": "string" }
      }
    }
  }
}
```

---

**© 2026 Sovereign Leviathan — AI Compliance Through Deterministic Verification**
