# Classifier Primitives

Type system for zero-text classification decisions.

## Core Primitives

### Noul (Binary Decision)

Binary classification: YES or NO.

```go
type NoulChoice struct {
    Name        string
    Decision    string             // "YES" or "NO"
    Probability float64            // P(Decision)
    Logits      map[string]float64 // Raw logits
}
```

**Usage:**
```go
if noulChoice.IsYes() {
    // Accept classification
} else if noulChoice.IsNo() {
    // Reject classification
}
```

**Examples:**
- `valid == YES` — Input is well-formed
- `mathematical == YES` — Content is mathematical
- `adversarial == NO` — Input is not adversarial

**Properties:**
- Deterministic (no randomness)
- Calibrated probability [0, 1]
- Logits for debugging

---

### Choice (Categorical Decision)

Multi-class selection from label set.

```go
type RouteChoice struct {
    Name            string
    Selected        bool
    Probabilities   map[string]float64  // P(class) for all classes
}
```

**Usage:**
```go
choice := envelope.RouteChoices[0]
if choice.Selected {
    fmt.Printf("Selected class: %s\n", choice.Name)
    for class, prob := range choice.Probabilities {
        fmt.Printf("  %s: %.2f\n", class, prob)
    }
}
```

**Examples:**
- `domain` — CLASS ∈ {CODE, MATH, GENERAL, LEGAL}
- `language` — LANG ∈ {EN, FR, DE, ES, ...}
- `sentiment` — SENT ∈ {POSITIVE, NEGATIVE, NEUTRAL}

**Properties:**
- Probabilities sum to 1.0
- All classes have probabilities (not just selected)
- Deterministic class selection based on argmax

---

### Score (Confidence/Risk)

Continuous numeric value [0, 1].

```go
type CalibratedScore struct {
    NormalizedValue float64  // [0, 1]
}
```

**Usage:**
```go
confidence := envelope.CalibrationMetadata["confidence"].(float64)
if confidence >= 0.90 {
    // High confidence — route
} else if confidence < 0.70 {
    // Low confidence — abstain
}
```

**Examples:**
- `confidence` — Model confidence in prediction
- `risk` — Risk of misclassification
- `entropy` — Prediction uncertainty
- `margin` — Margin between top-2 classes

**Properties:**
- Calibrated [0, 1] range
- Monotonic (higher = higher confidence)
- Useful for thresholding

---

## Decision Envelope

Complete decision record.

```go
type DecisionEnvelope struct {
    // Metadata
    Timestamp    int64  // Unix timestamp
    ModelID      string // Model identifier (e.g., "prod-v1")
    ModelVersion string // Version (e.g., "1.0.0")
    InputHash    string // SHA-256 of input
    RouterHash   string // SHA-256 of route decision
    
    // Decisions
    RouteChoices []*RouteChoice  // Categorical decisions
    NoulChoices  []*NoulChoice   // Binary decisions
    
    // Metadata
    CalibrationMetadata map[string]interface{} // Scores, calibration info
    Thresholds          map[string]float64     // Applied thresholds
    
    // Disposition
    Disposition string // Final classification (e.g., "CODE")
    Route       string // Route decision (e.g., "DISPATCH(CODE)")
}
```

**Interpretation:**
```go
envelope := &DecisionEnvelope{
    ModelID:      "prod-v1",
    ModelVersion: "1.0.0",
    
    // This is the decision:
    Disposition: "MATH_ENGINE",  // What was decided
    Route:       "DISPATCH(MATH_ENGINE)",  // Where to route
    
    // This is why:
    NoulChoices: []*NoulChoice{
        {Name: "valid", Decision: "YES", Probability: 0.999},
    },
    RouteChoices: []*RouteChoice{
        {Name: "domain", Selected: true, Probabilities: map[string]float64{
            "CODE": 0.01,
            "MATH": 0.97,  // Winner
            "GENERAL": 0.02,
        }},
    },
    CalibrationMetadata: map[string]interface{}{
        "confidence": 0.96,
        "risk": 0.02,
    },
}
```

---

## Model Metadata

Information about the model.

```go
type ModelMetadata struct {
    ModelID      string    // Unique identifier
    ModelVersion string    // SemVer (e.g., "1.0.0")
    Hash         string    // SHA-256 of model weights
    CreatedAt    time.Time
    UpdatedAt    time.Time
}
```

**Usage:**
```go
metadata := classifier.GetModelMetadata()
fmt.Printf("Running model: %s v%s (hash: %s)\n",
    metadata.ModelID,
    metadata.ModelVersion,
    metadata.Hash)
```

---

## Input Metadata

Information about the input.

```go
type InputMetadata struct {
    Hash      string                 // SHA-256 of input
    Features  map[string]interface{} // Extracted features
    Timestamp time.Time
    Source    string                 // Where input came from
    Version   int32                  // Input schema version
}
```

---

## Router Metadata

Information about the router.

```go
type RouterMetadata struct {
    Hash       string    // SHA-256 of router config
    ConfigHash string    // SHA-256 of decision rules
    Version    string
    UpdatedAt  time.Time
    Nodes      []string  // Route nodes
}
```

---

## Calibration Info

Calibration parameters and metrics.

```go
type CalibrationInfo struct {
    TemperatureScaling float64            // Temperature T for scaling
    IsotonicRegression map[string]float64 // Isotonic map
    PlattScaling       map[string]float64 // Platt {a, b}
    Metrics            map[string]float64 // ECE, MCE, Brier, etc.
}
```

**Metrics:**
- `ECE` — Expected Calibration Error
- `MCE` — Maximum Calibration Error
- `Brier` — Brier score
- `LogLoss` — Cross-entropy loss

---

## Type System

All decisions are one of three types:

| Type | Domain | Output | Calibration |
|------|--------|--------|-------------|
| **Noul** | Binary | YES/NO | Probability [0,1] |
| **Choice** | Categorical | Class ∈ Set | Probabilities per class |
| **Score** | Continuous | ℝ ∩ [0,1] | Normalized [0,1] |

### Type Safety

Go's type system enforces:

```go
// Type-safe access
noulChoice := envelope.NoulChoices[0]
decision := noulChoice.Decision  // string: "YES" or "NO"

// Type-safe helper
helper := api.NewDecisionEnvelopeHelper(envelope)
validNoul := helper.Noul("valid")
if validNoul.IsYes() { ... }

confidence := helper.Score("confidence")
if confidence.NormalizedValue >= 0.90 { ... }
```

---

## Consistency Guarantees

### Monotonicity

If decision probabilities are calibrated:

```
P(decision) >= P(any alternative)
```

### Coherence

All heads agree on best class:

```
argmax(RouteChoice.Probabilities) == Disposition
```

### Determinism

Same input → same envelope:

```
Predict(input) == Predict(input)  // Always
```

---

## JSON Serialization

```json
{
  "timestamp": 1694873456,
  "modelID": "prod-v1",
  "modelVersion": "1.0.0",
  "inputHash": "abc123...",
  "routerHash": "def456...",
  
  "noulChoices": [
    {
      "name": "valid",
      "decision": "YES",
      "probability": 0.999
    }
  ],
  
  "routeChoices": [
    {
      "name": "domain",
      "selected": true,
      "probabilities": {
        "CODE": 0.01,
        "MATH": 0.97,
        "GENERAL": 0.02
      }
    }
  ],
  
  "calibrationMetadata": {
    "confidence": 0.96,
    "risk": 0.02,
    "entropy": 0.15
  },
  
  "disposition": "MATH_ENGINE",
  "route": "DISPATCH(MATH_ENGINE)"
}
```

---

## Extension

### Custom Primitive

Add domain-specific primitive:

```go
type DomainSpecificDecision struct {
    Name    string
    Value   interface{}
}

envelope.CalibrationMetadata["custom"] = &DomainSpecificDecision{
    Name: "reasoning_depth",
    Value: 5,
}
```

### Custom Metadata

```go
envelope.CalibrationMetadata["audit_trail"] = map[string]interface{}{
    "user_id": "user123",
    "session": "sess456",
    "timestamp": time.Now(),
}
```

---

## Best Practices

1. **Always check nil** — Envelopes can have missing fields
2. **Use helpers** — `NewDecisionEnvelopeHelper()` for safe access
3. **Validate consistency** — Use `ConsistencyValidator`
4. **Log hashes** — Always record InputHash and RouterHash
5. **Check timestamps** — Verify envelope is fresh
6. **Monitor calibration** — Track ECE and MCE over time

---

## License

See LICENSE file.
