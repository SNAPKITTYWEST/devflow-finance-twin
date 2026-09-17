# Sovereign Self-Auditing AI Evaluation Engine — Complete Architecture Specification

## Executive Summary

The Sovereign Evaluation Engine is a local, deterministic, auditable assessment system that replaces cloud-hosted probabilistic judgment with cryptographically-verifiable evaluation. It enables air-gapped deployments where an AI system proposes facts (not conclusions), deterministic rules evaluate constraints, and formal verification proves correctness.

**Core Principles:**
- No cloud dependency (fully self-contained)
- Deterministic verification (reproducible results)
- Immutable audit ledger (tamper-proof)
- Model proposes facts, system verifies conclusions
- Air-gapped capable (no external API calls)
- Cryptographically auditable (SHA-256 hashes, signed manifests)

---

## Architecture Layers

### Layer 1: M/MUMPS Orchestration Gateway

**Purpose:** State management, event sequencing, deterministic transitions

**Responsibilities:**
- Session creation and lifecycle management
- Event ingestion from raw transcripts
- Deterministic state machine transitions
- Atomic commit of evaluation records
- Replayable execution semantics
- Failure-state handling and recovery

**State Machine:**
```
States:
  INGESTION       → PROCESSING
  PROCESSING      → EXTRACTION
  EXTRACTION      → EVALUATION
  EVALUATION      → VERIFICATION
  VERIFICATION    → REVIEWED
  REVIEWED        → FINALIZED
  Any state       → FAILED (on constraint violation)
  
Transitions:
  - Unidirectional (no backtracking)
  - Explicitly logged (no implicit state changes)
  - Atomic (all-or-nothing commits)
  - Replayable from event log
```

**API:**
```
session := NewSession(sessionID, rubricVersion, constraintVersion)
session.Ingest(rawTranscript)                    // → INGESTION → PROCESSING
session.ExtractFacts()                           // → EXTRACTION
session.EvaluateConstraints()                    // → EVALUATION
session.VerifyFormalProofs()                     // → VERIFICATION
session.ReviewGate(humanApproval)                // → REVIEWED → FINALIZED
session.Finalize(manifest)                       // → FINALIZED + signed
```

**Failure Handling:**
- On any constraint violation: transition to FAILED
- Record failure reason with timestamp and event sequence
- Prevent finalization of failed sessions
- Require explicit human review before override

---

### Layer 2: Immutable Event Ledger

**Purpose:** Hash-chained, tamper-proof record of all evaluation events

**Structure:**
```
Event {
  event_id               UUID              # Unique event identifier
  sequence_number        uint64            # Global order (1, 2, 3, ...)
  timestamp              datetime          # UTC timestamp of event
  speaker                string            # "model", "evaluator", "human"
  event_type             enum              # INGESTION, FACT, CONSTRAINT, PROOF, etc.
  
  # Raw content
  raw_content            string            # Original unmodified content
  raw_content_hash       SHA-256           # SHA-256(raw_content)
  
  # Normalized content (for deterministic comparison)
  normalized_content     string            # Whitespace/format normalized
  normalized_content_hash SHA-256          # SHA-256(normalized_content)
  
  # Ledger chain
  previous_event_hash    SHA-256           # Hash of prior event (nil for event #1)
  current_event_hash     SHA-256           # Hash of this event
  
  # Versioning
  evaluation_version     string            # Version of evaluation rules
  constraint_version     string            # Version of constraint set
  
  # Metadata
  metadata               map[string]any    # Arbitrary metadata
}
```

**Hash Computation:**
```
current_event_hash = SHA-256(
  event_id ||
  sequence_number ||
  timestamp ||
  speaker ||
  event_type ||
  raw_content_hash ||
  normalized_content_hash ||
  previous_event_hash ||
  evaluation_version ||
  constraint_version ||
  metadata_json
)
```

**Verification Algorithm:**
```
Algorithm: VerifyLedger(ledger)
  previous_hash = nil
  for each event in ledger:
    
    # Check chain integrity
    if event.previous_event_hash != previous_hash:
      return INVALID("chain broken at event " + event.event_id)
    
    # Recompute hash
    computed_hash = ComputeHash(event)
    if computed_hash != event.current_event_hash:
      return INVALID("hash mismatch at event " + event.event_id)
    
    # Update running hash
    previous_hash = event.current_event_hash
  
  return VALID
```

**Ledger Properties:**
- Append-only (no modifications to past events)
- Cryptographically bound (any change invalidates chain)
- Sequence-complete (no gaps in sequence_number)
- Timestamp-monotonic (timestamps never decrease)
- Reproducible (same inputs produce same hashes)

---

### Layer 3: Constraint Engine

**Purpose:** Deterministic evaluation of requirements against accumulated facts

**Constraint Types:**

#### Boolean Constraints (Must/Must-Not)
```
type BooleanConstraint struct {
  name              string
  description       string
  required_facts    []string      # Facts that must be present
  prohibited_facts  []string      # Facts that must NOT be present
  evaluation_logic  RuleSet       # DSL for evaluation
}

Example:
  Constraint: "code_snippet_verified"
  RequiredFacts: ["code_snippet_extracted", "syntax_valid"]
  ProhibitedFacts: ["syntax_error"]
  Logic: (extracted AND valid) AND NOT error
```

#### Temporal Constraints (Sequence, Timing)
```
type TemporalConstraint struct {
  name              string
  before_event      string        # Event A must occur before B
  after_event       string        # Event B must occur after A
  max_delay         duration      # Maximum elapsed time
  strict_order      bool          # No intervening events allowed
}

Example:
  Constraint: "extraction_before_evaluation"
  BeforeEvent: "facts_extracted"
  AfterEvent: "constraints_evaluated"
  StrictOrder: true              # No other events between them
```

#### Cardinality Constraints (Count, Min/Max)
```
type CardinalityConstraint struct {
  name              string
  fact_name         string        # Name of fact to count
  minimum_count     int           # Minimum occurrences required
  maximum_count     int           # Maximum occurrences allowed
  scope             string        # "session", "transcript", "agent"
}

Example:
  Constraint: "multiple_verification_passes"
  FactName: "formal_proof_verified"
  MinimumCount: 1
  MaximumCount: 3
```

#### Logical Constraints (AND, OR, NOT, Implication)
```
type LogicalConstraint struct {
  name              string
  expression        string        # Boolean logic expression
  requires_all      []string      # AND conditions
  requires_any      []string      # OR conditions
  prohibits         []string      # NOT conditions
  implication       struct {
    if_fact         string        # If this fact is true
    then_fact       string        # Then this must be true
  }
}

Example:
  Constraint: "ambiguous_requires_human_review"
  IfFact: "facts_contain_ambiguity"
  ThenFact: "human_review_performed"
```

#### Evidence Constraints (Proof Obligations)
```
type EvidenceConstraint struct {
  name              string
  requires_proof    []string      # Facts that need formal proof
  proof_type        string        # "lean4", "coq", "z3"
  max_proof_depth   int           # Maximum proof tree depth
  must_be_sound     bool          # Proof must be machine-verified sound
}

Example:
  Constraint: "all_verdicts_proven"
  RequiresProof: ["verdict_correct", "constraints_satisfied"]
  ProofType: "lean4"
  MustBeSound: true
```

**Constraint Evaluation:**
```
Algorithm: EvaluateConstraints(session, constraints, facts)
  results = []
  for each constraint in constraints:
    
    result = EvaluateConstraint(constraint, facts)
    
    if result == FAIL:
      session.TransitionTo(FAILED)
      session.RecordFailure(constraint.name, reason)
      return FAILED
    
    results.append(result)
  
  if AllPassed(results):
    session.TransitionTo(next_state)
    return PASS
  else:
    return PARTIAL_PASS  # Some constraints uncertain
```

**Failure Modes:**
- Required fact missing → EXPLICIT FAIL
- Prohibited fact present → EXPLICIT FAIL
- Cardinality violated → EXPLICIT FAIL
- Proof obligation unprovable → UNPROVABLE (not PASS)
- Temporal ordering violated → EXPLICIT FAIL

---

### Layer 4: Formal Verification (Lean 4)

**Purpose:** Machine-verified correctness proofs of evaluation outcomes

**Proof Obligations:**
```
ProofObligation {
  obligation_id       string                # Unique identifier
  theorem_name        string                # Lean theorem to prove
  statement           string                # Formal statement
  context             ProofContext          # Assumptions, imports
  constraints         []Constraint          # Constraints to verify
  facts               FactSet               # Accumulated facts
  
  # Proof artifact
  proof_source        string                # Lean 4 proof code
  proof_hash          SHA-256               # Hash of proof source
  
  # Verification result
  verification_status enum                  # PROVEN, UNPROVABLE, TIMEOUT
  proof_transcript    string                # Lean output/diagnostic
  verification_time   duration              # Time to verify
}
```

**Proof Generation:**
```
Algorithm: GenerateProofObligation(evaluation_state)
  
  # Extract decision to verify
  decision = evaluation_state.final_verdict
  
  # Generate Lean theorem
  theorem_stmt = GenerateLeanStatement(decision, constraints, facts)
  
  # Generate proof tactics
  proof_tactics = GenerateProofTactics(theorem_stmt, facts)
  
  # Create obligation
  obligation = ProofObligation{
    theorem_name: "eval_" + evaluation_state.session_id,
    statement: theorem_stmt,
    proof_source: proof_tactics,
  }
  
  return obligation
```

**Proof Verification:**
```
Algorithm: VerifyProof(obligation)
  
  # Invoke Lean 4 type checker
  result = LeanTypeChecker(obligation.proof_source)
  
  if result.success:
    obligation.verification_status = PROVEN
    obligation.proof_hash = SHA-256(obligation.proof_source)
    return PROVEN
  else if result.timeout:
    obligation.verification_status = TIMEOUT
    return UNPROVABLE
  else:
    obligation.verification_status = UNPROVABLE
    obligation.proof_transcript = result.errors
    return UNPROVABLE
```

**Example Proof Obligations:**

1. **Constraint Satisfaction**
   ```lean
   theorem all_constraints_satisfied (session : Session) : 
     ∀ c ∈ session.constraints, EvaluateConstraint(c, session.facts) = PASS := by
       intro c hc
       -- Prove each constraint
   ```

2. **Verdict Correctness**
   ```lean
   theorem verdict_is_correct (decision : Decision) :
     (decision.facts_complete ∧ 
      decision.constraints_satisfied ∧
      decision.proofs_valid) →
     decision.verdict = APPROVED := by
       intro ⟨hc, hs, hp⟩
       -- Derive conclusion
   ```

3. **Audit Trail Integrity**
   ```lean
   theorem ledger_integrity (ledger : EventLedger) :
     VerifyLedger(ledger) = VALID := by
       induction ledger with
       | nil => simp
       | cons e es ih => 
           -- Prove hash chain validity
   ```

---

### Layer 5: ASP Reasoning Layer

**Purpose:** Rule-based logic programming for provenance explanation and complex constraint satisfaction

**Rule Language (Answer Set Programming):**
```
% Define base facts
fact_extracted(snippet_A).
fact_extracted(snippet_B).

% Define rules
can_evaluate :- 
  fact_extracted(X),
  syntax_valid(X),
  not corrupted(X).

should_escalate :-
  can_evaluate,
  ambiguity_detected(X),
  not human_reviewed(X).

% Constraints (integrity rules)
:- ambiguous(X), not reviewed_by(human, X).
:- verdict(APPROVE), not all_constraints(satisfied).

% Query
#show should_escalate/0.
#show verdict/1.
```

**Grounder and Solver:**
```
Algorithm: ReasonAboutFacts(rules, facts)
  
  # 1. Ground: Instantiate all rules with concrete facts
  grounded_program = Ground(rules, facts)
  
  # 2. Solve: Compute answer sets (stable models)
  answer_sets = Solve(grounded_program)
  
  # 3. Extract: Find rules that fire
  fired_rules = {rule | rule ∈ answer_sets}
  
  # 4. Explain: Generate provenance trace
  provenance = ExplainRules(fired_rules, facts)
  
  return {
    answer_sets: answer_sets,
    fired_rules: fired_rules,
    provenance: provenance
  }
```

**Provenance Explanation:**
```
struct ProvenanceTrace {
  rule_name         string           # Rule that fired
  supporting_facts  []Fact           # Facts that enabled rule
  derived_fact      Fact             # Fact derived from rule
  rule_source       RuleSet          # Which rule set version
  derivation_order  int              # Order in stratified evaluation
  proof_depth       int              # Distance from base facts
}

Example:
  Rule: "can_evaluate"
  SupportingFacts: [fact_extracted(A), syntax_valid(A)]
  DerivedFact: can_evaluate()
  DerivationOrder: 2
  ProofDepth: 1
```

**Why-Provenance Query:**
```
Query: "Why did we escalate this to human review?"
Answer:
  1. Fact: ambiguity_detected(snippet_42) [from layer 6]
  2. Rule: "escalate_if_ambiguous" → should_escalate
  3. Fact: not human_reviewed(snippet_42) [true, not yet reviewed]
  4. Fired: should_escalate ✓
  5. Action: Escalate to human_review queue
```

---

### Layer 6: Local Judge Interface

**Purpose:** Semantic extraction and fact proposal (NOT conclusion drawing)

**Input Processing:**
```
Algorithm: ProcessTranscript(transcript)
  
  # 1. Tokenize and normalize
  normalized = Normalize(transcript)
  
  # 2. Segment into utterances
  utterances = Segment(normalized)
  
  # 3. For each utterance, propose facts (don't conclude)
  facts = []
  for utterance in utterances:
    proposed_facts = ExtractFacts(utterance)
    
    for fact in proposed_facts:
      fact.confidence = EstimateConfidence(fact, utterance)
      fact.ambiguity_flags = DetectAmbiguity(fact, utterance)
      fact.source_span = TokenSpan(utterance, fact)
      
      facts.append(fact)
  
  return facts
```

**Fact Proposal (Not Conclusion):**
```
struct FactProposal {
  fact_id             UUID            # Unique identifier
  fact_category       enum            # "code", "math", "evidence", "ambiguous"
  proposed_fact       string          # The fact (no conclusion!)
  confidence_score    float           # 0.0-1.0 confidence
  
  # Evidence chain
  source_transcript   string          # Original text
  source_hash         SHA-256         # Hash of source
  extraction_method   string          # Which model extracted
  
  # Ambiguity tracking
  ambiguity_markers   []string        # Unclear references, polysemy
  requires_review     bool            # Flagged for human review
  
  # Metadata
  extracted_at        datetime        # Timestamp
  layer_version       string          # Version of extraction layer
}

Example (NOT a conclusion):
  ProposedFact: "snippet_contains_recursive_call"
  ConfidenceScore: 0.92
  AmbiguityMarkers: []
  RequiresReview: false

Example (flagged as ambiguous):
  ProposedFact: "user_asked_for_optimization"
  ConfidenceScore: 0.65
  AmbiguityMarkers: ["'optimization' could mean performance or code clarity"]
  RequiresReview: true
```

**Semantic Extraction:**
```
ExtractionSchema {
  
  # Code facts
  code_snippet_present: bool
  code_language: string
  code_has_error: bool
  code_error_type: enum
  
  # Math facts
  math_expression_present: bool
  math_domain: string
  math_needs_proof: bool
  
  # Evidence facts
  claim_made: bool
  evidence_cited: bool
  evidence_count: int
  
  # Ambiguity facts
  pronouns_unresolved: bool
  temporal_references: int
  scope_ambiguity: bool
  
  # Request facts
  request_type: enum       # "generate", "verify", "explain", "optimize"
  request_clarity: float   # 0.0-1.0 clarity score
}
```

**Ambiguity Detection:**
```
Algorithm: DetectAmbiguity(fact, utterance)
  
  ambiguities = []
  
  # Pronoun resolution
  if UnresolvedPronoun(fact, utterance):
    ambiguities.append("unresolved_pronoun")
  
  # Temporal reference
  if VagueTemporalRef(fact, utterance):
    ambiguities.append("temporal_vagueness")
  
  # Scope ambiguity
  if ScopeAmbiguity(fact, utterance):
    ambiguities.append("scope_ambiguity")
  
  # Polysemy (word has multiple meanings)
  if PolysemousWord(fact, utterance):
    ambiguities.append("polysemy")
  
  return ambiguities
```

---

### Layer 7: Cryptographic Provenance

**Purpose:** Signed evaluation manifests and auditable artifact creation

**Evaluation Manifest:**
```
struct EvaluationManifest {
  # Identification
  manifest_id         UUID
  session_id          UUID
  timestamp           datetime
  evaluator_id        string        # Which agent/human evaluated
  
  # Versioning
  rubric_version      string        # Version of rubric/criteria
  constraint_version  string        # Version of constraints
  layer_versions      map[string]string  # Per-layer version tracking
  
  # Signatures
  rubric_signature    Signature     # Signature of rubric version
  constraint_signature Signature    # Signature of constraints
  
  # Content hashes (for integrity verification)
  input_content_hash  SHA-256       # Hash of original input
  ledger_hash         SHA-256       # Hash of event ledger
  facts_hash          SHA-256       # Hash of all facts
  constraints_result_hash SHA-256   # Hash of constraint evaluation
  proofs_hash         SHA-256       # Hash of proof artifacts
  
  # Evaluation results
  verdict             enum          # APPROVED, REJECTED, ESCALATED, UNPROVABLE
  verdict_reason      string        # Human-readable reason
  constraint_results  map[string]ConstraintResult
  proof_status        map[string]ProofStatus
  
  # Signature of entire manifest
  manifest_signature  Signature     # RSA-3072 or ECDSA-P256
  
  # Audit trail
  review_history      []ReviewRecord
}

struct ReviewRecord {
  reviewer_id         string
  action              enum          # REVIEWED, APPROVED, REJECTED, QUESTIONED
  comment             string
  timestamp           datetime
  signature           Signature     # Reviewer's signature
}
```

**Signing Process:**
```
Algorithm: SignManifest(manifest, private_key)
  
  # 1. Serialize manifest (without signature field)
  manifest_bytes = Serialize(manifest)
  
  # 2. Compute hash
  manifest_hash = SHA-256(manifest_bytes)
  
  # 3. Sign with RSA-3072 or ECDSA-P256
  signature = Sign(manifest_hash, private_key)
  
  # 4. Attach signature
  manifest.manifest_signature = signature
  
  return manifest
```

**Verification:**
```
Algorithm: VerifyManifest(manifest, public_key)
  
  # 1. Extract and zero signature field
  saved_signature = manifest.manifest_signature
  manifest.manifest_signature = nil
  
  # 2. Recompute hash
  manifest_bytes = Serialize(manifest)
  manifest_hash = SHA-256(manifest_bytes)
  
  # 3. Verify signature
  if Verify(manifest_hash, saved_signature, public_key):
    return VALID
  else:
    return INVALID("signature verification failed")
```

**Artifact Versioning:**
```
RubricVersion {
  version_id          string        # e.g., "rubric-2026-09-17-v3"
  created_at          datetime
  author              string
  content_hash        SHA-256       # Hash of rubric
  parent_version      string        # Previous version (nil for v1)
  change_description  string        # What changed from parent
  signature           Signature     # Author's signature
}

ConstraintSet {
  version_id          string        # e.g., "constraints-2026-09-17-v2"
  created_at          datetime
  constraints         []Constraint
  constraint_count    int
  content_hash        SHA-256
  signature           Signature
}
```

---

## End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. RAW TRANSCRIPT                                               │
│    User: "Verify that this recursive algorithm terminates"      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 2. M/MUMPS INGESTION GATEWAY (Layer 1)                          │
│    - Create session, sequence events                            │
│    - INGESTION → PROCESSING                                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 3. IMMUTABLE LEDGER (Layer 2)                                   │
│    - Record: Event#1, hash chain, verify integrity              │
│    - Sequence#1, timestamp, speaker, event_type                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 4. LOCAL JUDGE EXTRACTION (Layer 6)                             │
│    - Extract facts (NOT conclusions):                           │
│      * fact: "algorithm_is_recursive"                           │
│      * fact: "user_requests_termination_proof"                  │
│      * fact: "code_provided_in_request"                         │
│    - Flag ambiguities, confidence scores                        │
│    - EXTRACTION completed                                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 5. ASP REASONING (Layer 5)                                      │
│    - Apply rules: can_evaluate(recursive) ← true                │
│    - Fire rules to derive: needs_termination_proof              │
│    - Generate provenance traces                                 │
│    - Explain: "Yes, termination proof needed because ..."       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 6. CONSTRAINT EVALUATION (Layer 3)                              │
│    - Check all constraints:                                     │
│      * "code_provided" ✓ PASS                                   │
│      * "recursive_detected" ✓ PASS                              │
│      * "termination_provable" ? UNCERTAIN                       │
│    - If all constraints pass → proceed to verification          │
│    - If any fails → FAILED state                                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 7. FORMAL VERIFICATION (Layer 4)                                │
│    - Generate Lean 4 proof obligation:                          │
│      theorem termination_provable(prog : Program) : ...         │
│    - Invoke Lean type checker                                   │
│    - Status: PROVEN ✓ or UNPROVABLE ✗                           │
│    - Record proof transcript and proof_hash                     │
│    - VERIFICATION completed                                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
         ┌─────────────────┴─────────────────┐
         │                                   │
    PROVEN                            UNPROVABLE
         │                                   │
         ▼                                   ▼
    Proceed to Human Review      Escalate to Human Review
    State: REVIEWED (gate)       State: REVIEWED (gate)
         │                                   │
         └─────────────────┬─────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 8. HUMAN REVIEW GATE (Required)                                 │
│    - Human (or authorized reviewer) inspects:                   │
│      * All extracted facts                                      │
│      * Constraint results                                       │
│      * Proof status (if PROVEN, usually auto-approve)           │
│      * Ambiguity flags                                          │
│    - Decision: APPROVE, REJECT, or REQUEST REVISION             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 9. CRYPTOGRAPHIC PROVENANCE (Layer 7)                           │
│    - Create EvaluationManifest with:                            │
│      * manifest_id, session_id, timestamp                       │
│      * rubric_version, constraint_version                       │
│      * All hashes (input, ledger, facts, constraints, proofs)   │
│      * Verdict + reason                                         │
│      * Review history + signatures                              │
│    - Sign manifest with RSA-3072/ECDSA-P256                     │
│    - Compute manifest_signature                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 10. SIGNED EVALUATION ARTIFACT                                  │
│     {                                                           │
│       manifest_id: "eval-2026-09-17-abc123",                   │
│       session_id: "sess-xyz789",                                │
│       verdict: APPROVED,                                        │
│       ledger_hash: "abc123def456...",                           │
│       facts_hash: "f1f2f3f4...",                                │
│       constraints_result_hash: "c1c2c3c4...",                   │
│       proofs_hash: "p1p2p3p4...",                               │
│       manifest_signature: "sig_..."                             │
│     }                                                           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ 11. AUDIT LOG (Immutable, Versioned, Reproducible)              │
│    - Append evaluation manifest to audit log                    │
│    - Log all review actions with reviewer signatures            │
│    - Store versions of rubric, constraints at evaluation time   │
│    - Enable: "Reproduce evaluation from 2026-09-15 with rules"  │
│    - Final state: FINALIZED                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Failure Modes and Recovery

### Mode 1: Ledger Mutation Detected

**Scenario:** Attacker modifies an event in the ledger

**Detection:**
```
VerifyLedger() detects hash mismatch at event#5
  reported hash: abc123
  computed hash: def456
```

**Response:**
- Reject all evaluations from that session
- Mark session as COMPROMISED
- Alert human operators
- No recovery (fail-closed)

### Mode 2: Constraint Violation

**Scenario:** Facts don't satisfy required constraint

**Detection:**
```
Constraint "code_must_compile" evaluates to FAIL
  required: code_error_count == 0
  actual: code_error_count == 2
```

**Response:**
- Transition session to FAILED state
- Record failure reason with evidence
- Escalate to human review
- Require explicit override approval

### Mode 3: Proof Obligation Unprovable

**Scenario:** Lean proof checker cannot verify correctness

**Detection:**
```
Lean 4 type checker: Error at line 12
  cannot prove: termination_provable(prog)
  reason: no decreasing argument found
```

**Response:**
- Mark verdict as UNPROVABLE (not PASS)
- DO NOT conclude: "Proof not available, so assume safe"
- Escalate to human review with full proof transcript
- Record as UNCERTAIN in manifest

### Mode 4: Human Override

**Scenario:** Human reviewer decides to override automated result

**Response:**
- Record override decision with reviewer ID and signature
- Timestamp override action
- Append to manifest.review_history
- Include reviewer comment explaining rationale
- Sign override with reviewer's private key
- Enable audit trail to show: "Who overrode? When? Why?"

### Mode 5: Air-Gapped Deployment Fails

**Scenario:** System needs to verify rubric/constraint signatures but has no access to CA

**Response:**
- Verify signatures offline using pre-loaded public keys
- Store rubric/constraint signatures at deployment time
- If signature invalid: fail-closed, require manual approval
- No external network calls to verify certificates

---

## Security Model

### Cryptographic Guarantees

1. **Hash Integrity**
   - SHA-256 used for content hashing
   - SHA-256 collision resistant (2^128 security)
   - All ledger events chain-hashed

2. **Signature Schemes**
   - RSA-3072 (minimum) or ECDSA-P256
   - Sign manifests with private key
   - Verify with public key (can be air-gapped)
   - All review actions signed by reviewer

3. **Versioning & Attribution**
   - Every artifact (rubric, constraints, proof) versioned
   - Version signature prevents mutation
   - Change tracking: "rubric-v1 → rubric-v2: changed threshold"
   - Author attribution: who made changes

### Access Control

- **Model (Layer 6):** Extract facts ONLY, not make conclusions
- **Engine (Layers 3, 4, 5):** Evaluate constraints, run proofs, apply rules
- **Human (Layer 7):** Review gate, approve/reject, sign decisions
- **System:** Record, hash, sign, never delete (append-only)

### Fail-Closed Defaults

- Unproven = Not approved (not "assume safe")
- Unprovable = Escalate (not "auto-pass")
- Ambiguous = Flag for review (not hide)
- Any signature invalid = Reject
- Any hash mismatch = Reject all

### Audit Trail

Every evaluation is reproducible:
```
ReproduceEvaluation(session_id, original_timestamp)
  1. Load ledger from time T (only events before T)
  2. Load rubric version that was active at time T
  3. Load constraint version that was active at time T
  4. Load Lean proofs that existed at time T
  5. Re-run all layers with identical input
  6. Verify output manifests match original
  → Proves: decision was deterministic, not arbitrary
```

---

## Deployment Modes

### Mode A: Connected (Cloud-Adjacent)

- Rubric and constraint updates fetched from trusted server
- Signatures verified before loading new versions
- Evaluation performed locally
- Results signed and stored locally
- Can operate offline if versions cached

### Mode B: Air-Gapped (Fully Disconnected)

- All rubric, constraint, proof versions pre-deployed
- No external network access
- All verification via cryptographic signatures (local public keys)
- Evaluation entirely self-contained
- Audit log remains local

### Mode C: Containerized (Docker)

```dockerfile
FROM lean4-base:latest

# Include Lean 4 proof checker
COPY lean4/ /opt/lean4/

# Include ASP solver (clingo)
COPY clingo/ /opt/clingo/

# Include M/MUMPS runtime
COPY mumps-runtime/ /opt/mumps/

# Engine binaries
COPY engine/ /app/

# Pre-loaded rubric/constraints
COPY rubric.v3.signed /etc/eval/
COPY constraints.v2.signed /etc/eval/

# Audit log volume (persistent)
VOLUME ["/var/log/eval-audit"]

ENTRYPOINT ["/app/evaluation-engine"]
```

### Mode D: Distributed (Multi-Node Verification)

```
Node A (Fact Extraction):        Extracts facts from transcript
         ↓
         Publishes facts + hash to shared ledger
         ↓
Node B (Constraint Evaluation):  Consumes facts
         ↓
         Evaluates constraints, publishes result
         ↓
Node C (Formal Verification):    Consumes constraint results
         ↓
         Generates proofs, publishes proof status
         ↓
Node D (Consensus):              Waits for all nodes
         ↓
         Verifies all hashes match across nodes
         ↓
         If consensus: proceed to human review
         If mismatch: FAIL (possible attack)
```

---

## Configuration Schema

```json
{
  "evaluation_engine": {
    "version": "1.0",
    "deployment_mode": "air-gapped",
    "session_management": {
      "timeout_seconds": 3600,
      "max_session_length_events": 10000
    },
    "constraints": {
      "version": "constraints-2026-09-17-v2",
      "signature": "sig_constraints_...",
      "public_key_thumbprint": "sha256:abc123"
    },
    "rubric": {
      "version": "rubric-2026-09-17-v3",
      "signature": "sig_rubric_...",
      "public_key_thumbprint": "sha256:def456"
    },
    "formal_verification": {
      "enabled": true,
      "proof_checker": "lean4",
      "lean4_path": "/opt/lean4/bin/lean",
      "proof_timeout_seconds": 30
    },
    "asp_reasoning": {
      "enabled": true,
      "solver": "clingo",
      "clingo_path": "/opt/clingo/bin/clingo"
    },
    "cryptography": {
      "hash_algorithm": "sha256",
      "signature_algorithm": "rsa3072",
      "public_key_path": "/etc/eval/public-keys/",
      "private_key_path": "/etc/eval/private-keys/"
    },
    "audit_log": {
      "path": "/var/log/eval-audit/",
      "retention_days": 2555
    }
  }
}
```

---

## Performance Characteristics

| Operation | Latency | Notes |
|-----------|---------|-------|
| Session creation | <1ms | Register state machine |
| Event ingestion | 1-5ms | Per event (100 events: 100-500ms) |
| Fact extraction | 50-200ms | Depends on transcript length |
| Constraint eval | 1-10ms | Per constraint (20 constraints: 20-200ms) |
| Proof generation | 100-500ms | Generate Lean tactics |
| Proof verification | 500ms-5s | Lean type checker (depends on proof complexity) |
| Manifest signing | 5-20ms | RSA-3072 signature |
| Ledger verification | 10-100ms | Per 1000 events |
| Full session (typical) | 1-10 seconds | End-to-end with human gate |

---

## Summary

The Sovereign Evaluation Engine replaces opaque cloud-based judgment with **deterministic, auditable, provably-correct** local verification. By layering M/MUMPS orchestration, immutable ledgers, deterministic constraints, formal proofs, ASP reasoning, local fact extraction, and cryptographic provenance, the system enables:

- **Reproducibility:** Exact same input → exact same output (deterministic)
- **Auditability:** Complete cryptographic trail (tamper-proof)
- **Explainability:** ASP provenance explains why rules fired
- **Verifiability:** Formal proofs check correctness (machine-verified)
- **Accountability:** Signed decisions with reviewer attribution
- **Air-Gapped Capability:** No external dependencies

**Guiding Principle:** "Model proposes facts, system verifies conclusions."

