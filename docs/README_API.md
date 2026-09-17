# Classifier API

Production-grade typed-decision classification API in Go.

## Core Design

- **Zero-text** — model outputs only typed tensors (Noul, Choices, Scores)
- **Decision-native** — no natural language intermediate representation
- **Deterministic** — identical inputs → identical routes
- **Auditable** — SHA-256 canonical hashing of all decisions
- **Hardware-agnostic** — CPU, CUDA, ROCm, WASM backends

## Quick Start

```go
package main

import (
    "devflow-finance-twin/classifier/api"
    "devflow-finance-twin/classifier/model"
    "devflow-finance-twin/classifier/primitives"
)

func main() {
    // Create classifier
    classifier := model.NewDefaultClassifier(...)
    
    // Create router
    router := api.NewDefaultRouter("main")
    router.Validate()
    
    // Predict
    envelope, _ := classifier.Predict(input)
    
    // Route
    router.Route(envelope)
    
    // Receive: envelope.Route
    fmt.Println(envelope.Route) // DISPATCH(MATH_ENGINE) or ABSTAIN
}
```

## API Interfaces

### Classifier

```go
type Classifier interface {
    Predict(input interface{}) (*primitives.DecisionEnvelope, error)
    PredictBatch(inputs []interface{}) ([]*primitives.DecisionEnvelope, error)
    SetBackend(backend string) error
}
```

Core classification interface. Predictions return typed decision envelopes.

### Router

```go
type Router interface {
    Route(decision *primitives.DecisionEnvelope) error
    Validate() error
}
```

Deterministic routing based on decision envelope. Routes are computed from dispositions.

## Primitives

### Noul

Binary YES/NO decision from classification heads.

```go
type NoulChoice struct {
    Name        string
    Decision    string             // YES or NO
    Probability float64
    Logits      map[string]float64
}
```

### Choice

Categorical selection from label set.

```go
type RouteChoice struct {
    Name            string
    Selected        bool
    Probabilities   map[string]float64
}
```

### Score

Calibrated numeric confidence (0.0 - 1.0).

```go
type CalibratedScore struct {
    NormalizedValue float64
}
```

## Examples

### 1. Math Routing Classifier

Routes requests to mathematical reasoning engines.

```go
classifier := api.NewMathRoutingClassifier(clf, router)
route, _ := classifier.Classify("Prove that sqrt(2) is irrational")

// Output: DISPATCH(MATH_ENGINE)
```

Features:
- Input validation
- Batch processing
- Confidence thresholding

### 2. Consistency Validator

Verifies multi-head decision consistency.

```go
validator := api.NewConsistencyValidator(clf)
result := validator.ValidateCodeClassification(envelope)

if !result.Valid {
    fmt.Printf("Consistency errors: %v\n", result.Errors)
}
```

Rules:
- `valid == YES`
- `confidence >= 0.90`
- `risk <= 0.10`
- Multi-head agreement

### 3. Abstention Example

Handles low-confidence classifications.

```go
abstainer := api.NewAbstentionExample(clf, router)
decision, _ := abstainer.ClassifyWithDetailedAbstention(input)

switch decision.Disposition {
case "ROUTE":
    fmt.Println("Route to:", decision.Route)
case "ABSTAIN_LOW_CONFIDENCE":
    fmt.Println("Confidence too low:", decision.Confidence)
case "ABSTAIN_UNCERTAIN":
    fmt.Println("Uncertain:", decision.Reason)
}
```

Thresholds:
- `< 0.70`: Abstain (low confidence)
- `0.70 - 0.90`: Abstain (uncertain)
- `>= 0.90`: Route (accept)

## Architecture

```
1. Input → Encode (shared representation)
2. Noul Head | Choice Head | Score Head (parallel)
3. Calibration (temperature, Platt, isotonic, beta)
4. Deterministic Router (DSL → IR → evaluation)
5. Dispatch / Reject / Abstain
```

## Zero-Text Guarantee

No text generation. No parsing. No regex. No JSON extraction.

The model output IS the decision.

## Auditability

Every decision is hashed:

```go
type DecisionEnvelope struct {
    InputHash    string  // SHA-256 of input
    RouterHash   string  // SHA-256 of route
    Timestamp    int64   // Decision timestamp
    ModelID      string  // Model identifier
    ModelVersion string  // Model version
}
```

## Determinism

Identical inputs → identical envelopes → identical routes.

No randomness in inference or routing.

## Backends

Supported backends via `SetBackend()`:

- `cpu` — CPU inference
- `cuda` — NVIDIA CUDA
- `rocm` — AMD ROCm
- `wasm` — WebAssembly
- `metal` — Apple Metal

## Testing

```bash
go test devflow-finance-twin/classifier/api -v
```

Tests include:
- Unit tests for each example
- Integration tests
- Benchmarks
- Consistency validation

## Performance

Typical latencies (on CPU):

- Single prediction: 5-10ms
- Batch (100): 50-100ms
- Consistency check: <1ms

## Error Handling

API returns typed errors:

```go
if err := router.Validate(); err != nil {
    // Handle validation error
}

if err := router.Route(envelope); err != nil {
    // Handle routing error
}
```

## Configuration

```go
config := &api.ClassifierConfig{
    ModelID:      "prod-model-v1",
    ModelVersion: "1.0.0",
    Backend:      "cpu",
    MaxBatchSize: 1000,
}
```

## Documentation

- [ARCHITECTURE.md](./docs/ARCHITECTURE.md) — System design
- [PRIMITIVES.md](./docs/PRIMITIVES.md) — Type system
- [CALIBRATION.md](./docs/CALIBRATION.md) — Confidence calibration
- [ROUTER_DSL.md](./docs/ROUTER_DSL.md) — Routing language
- [DETERMINISM.md](./docs/DETERMINISM.md) — Reproducibility guarantees
- [AUDITABILITY.md](./docs/AUDITABILITY.md) — Decision audit trails

## License

See LICENSE file.
