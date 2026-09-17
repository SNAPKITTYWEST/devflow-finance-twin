# Classifier Examples

Complete worked examples of the Classifier API.

## Example 1: Math Routing Classifier

Route requests to mathematical reasoning engines.

### Scenario

Input: "Determine whether this request should be routed to the mathematical reasoning engine."

Model outputs:
- Noul: `valid = YES, P(YES) = 0.997`
- Choice: `domain = MATH (0.971), CODE (0.011), GENERAL (0.018)`
- Score: `confidence = 0.982, risk = 0.014`

### Code

```go
package main

import (
    "fmt"
    "devflow-finance-twin/classifier/api"
    "devflow-finance-twin/classifier/model"
    "devflow-finance-twin/classifier/primitives"
)

func main() {
    // Create classifier (from trained model)
    clf := model.NewDefaultClassifier(
        &primitives.ModelMetadata{
            ModelID:      "math-router-v1",
            ModelVersion: "1.0.0",
        },
        map[string]model.Head{},  // Populated from model
        &model.DefaultRouter{},   // Routing logic
    )
    
    // Create router
    router := api.NewDefaultRouter("math-routing")
    router.Validate()
    
    // Create classifier wrapper
    mathClassifier := api.NewMathRoutingClassifier(clf, router)
    
    // Classify
    request := "Prove that the set of prime numbers is infinite"
    route, err := mathClassifier.Classify(request)
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    
    fmt.Printf("Request: %s\n", request)
    fmt.Printf("Route: %s\n", route)  // DISPATCH(MATH_ENGINE)
    
    // Get full metadata
    envelope, _ := mathClassifier.ClassifyWithMetadata(request)
    fmt.Printf("Confidence: %.3f\n", envelope.CalibrationMetadata["confidence"])
    fmt.Printf("Risk: %.3f\n", envelope.CalibrationMetadata["risk"])
}
```

### Output

```
Request: Prove that the set of prime numbers is infinite
Route: DISPATCH(MATH_ENGINE)
Confidence: 0.982
Risk: 0.014
```

### Batch Processing

```go
requests := []string{
    "Compute the derivative of x^2",
    "What color is the sky?",
    "Solve the Riemann hypothesis",
}

routes, _ := mathClassifier.ClassifyBatch(requests)

for i, route := range routes {
    fmt.Printf("%d. %s\n", i, route)
}
```

### With Confidence Threshold

```go
// Only route if confidence >= 0.90
route, err := mathClassifier.ClassifyWithThreshold(request, 0.90)
if err != nil {
    fmt.Printf("Below threshold: %v\n", err)
}
```

---

## Example 2: Consistency Validator

Verify multi-head decision consistency.

### Scenario

Ensure CODE classifications meet strict requirements:
- valid == YES
- domain == CODE
- confidence >= 0.90
- risk <= 0.10

### Code

```go
package main

import (
    "fmt"
    "devflow-finance-twin/classifier/api"
    "devflow-finance-twin/classifier/primitives"
)

func main() {
    // Create validator
    validator := api.NewConsistencyValidator(clf)
    
    // Create a decision envelope
    envelope := &primitives.DecisionEnvelope{
        ModelID:      "classifier-v1",
        ModelVersion: "1.0.0",
        Disposition:  "CODE",
        
        NoulChoices: []*primitives.NoulChoice{
            {
                Name:        "valid",
                Decision:    "YES",
                Probability: 0.999,
            },
        },
        
        RouteChoices: []*primitives.RouteChoice{
            {
                Name:     "domain",
                Selected: true,
                Probabilities: map[string]float64{
                    "CODE":    0.95,
                    "MATH":    0.03,
                    "GENERAL": 0.02,
                },
            },
        },
        
        CalibrationMetadata: map[string]interface{}{
            "confidence": 0.95,
            "risk":       0.03,
        },
    }
    
    // Validate CODE classification
    result := validator.ValidateCodeClassification(envelope)
    
    if result.Valid {
        fmt.Println("✓ Classification is consistent")
    } else {
        fmt.Printf("✗ Validation failed:\n")
        for _, err := range result.Errors {
            fmt.Printf("  - %s\n", err)
        }
    }
}
```

### Output

```
✓ Classification is consistent
```

### Failed Validation

```go
// Envelope with low confidence
envelope.CalibrationMetadata["confidence"] = 0.80

result := validator.ValidateCodeClassification(envelope)
// Output:
// ✗ Validation failed:
//   - confidence 0.80 < 0.90
```

### Custom Rules

```go
// Add custom consistency rule
rule := &api.ConsistencyRule{
    Name: "risk_bounds",
    Evaluate: func(env *primitives.DecisionEnvelope) error {
        helper := api.NewDecisionEnvelopeHelper(env)
        risk := helper.Score("risk")
        if risk.NormalizedValue > 0.05 {
            return fmt.Errorf("risk %.3f > 0.05", risk.NormalizedValue)
        }
        return nil
    },
    Severity: "strict",
}

validator.AddRule(rule)
result := validator.Validate(envelope)
```

---

## Example 3: Abstention Example

Handle uncertain classifications.

### Scenario

Strategy:
- Confidence < 0.70: Abstain (too uncertain)
- 0.70-0.90: Abstain with reason (uncertain)
- >= 0.90: Route (accept)

### Code

```go
package main

import (
    "fmt"
    "devflow-finance-twin/classifier/api"
)

func main() {
    // Create abstention handler
    abstainer := api.NewAbstentionExample(clf, router)
    
    // Set custom thresholds
    abstainer.SetConfidenceThresholds(0.65, 0.88)
    
    // Process request with uncertainty
    request := "Is this code correct?"
    result, _ := abstainer.ClassifyWithAbstention(request)
    
    switch result {
    case "ABSTAIN":
        fmt.Println("Low confidence - abstaining")
    case "ERROR":
        fmt.Println("Classification error")
    default:
        fmt.Printf("Routed to: %s\n", result)
    }
}
```

### Detailed Abstention

```go
decision, _ := abstainer.ClassifyWithDetailedAbstention(request)

fmt.Printf("Disposition: %s\n", decision.Disposition)
fmt.Printf("Confidence: %.2f\n", decision.Confidence)
fmt.Printf("Reason: %s\n", decision.Reason)

switch decision.Disposition {
case "ABSTAIN_LOW_CONFIDENCE":
    fmt.Println("Confidence too low - route to human review")
case "ABSTAIN_UNCERTAIN":
    fmt.Println("Uncertain - collect more data")
case "ROUTE":
    fmt.Printf("Route to: %s\n", decision.Route)
}
```

### Batch Processing with Statistics

```go
requests := []string{
    "Simple query",
    "Complex query",
    "Ambiguous query",
}

decisions, _ := abstainer.BatchClassifyWithAbstention(requests)

// Compute statistics
stats := api.ComputeStats(decisions)

fmt.Printf("Total: %d\n", stats.Total)
fmt.Printf("Routed: %d (%.1f%%)\n", stats.Routed, (float64(stats.Routed)/float64(stats.Total))*100)
fmt.Printf("Abstained: %d (%.1f%%)\n", stats.Abstained, (float64(stats.Abstained)/float64(stats.Total))*100)
fmt.Printf("  - Low confidence: %d\n", stats.LowConfAbstains)
fmt.Printf("  - Uncertain: %d\n", stats.UncertainAbstains)
fmt.Printf("Average confidence: %.2f\n", stats.AvgConfidence)
fmt.Printf("Average risk: %.2f\n", stats.AvgRisk)
```

### Output

```
Total: 3
Routed: 1 (33.3%)
Abstained: 2 (66.7%)
  - Low confidence: 1
  - Uncertain: 1
Average confidence: 0.78
Average risk: 0.12
```

---

## Example 4: Decision Envelope Helper

Safe access to decision components.

### Code

```go
package main

import (
    "fmt"
    "devflow-finance-twin/classifier/api"
    "devflow-finance-twin/classifier/primitives"
)

func main() {
    envelope := &primitives.DecisionEnvelope{
        NoulChoices: []*primitives.NoulChoice{
            {Name: "valid", Decision: "YES", Probability: 0.999},
            {Name: "adversarial", Decision: "NO", Probability: 0.95},
        },
        RouteChoices: []*primitives.RouteChoice{
            {
                Name: "domain",
                Selected: true,
                Probabilities: map[string]float64{
                    "CODE": 0.85,
                    "MATH": 0.10,
                    "GENERAL": 0.05,
                },
            },
        },
        CalibrationMetadata: map[string]interface{}{
            "confidence": 0.92,
            "risk": 0.06,
            "entropy": 0.18,
        },
    }
    
    helper := api.NewDecisionEnvelopeHelper(envelope)
    
    // Access Noul decisions
    validNoul := helper.Noul("valid")
    if validNoul != nil && validNoul.IsYes() {
        fmt.Println("✓ Input is valid")
    }
    
    advNoul := helper.Noul("adversarial")
    if advNoul != nil && advNoul.IsNo() {
        fmt.Println("✓ Input is not adversarial")
    }
    
    // Access Choice decisions
    domain := helper.Choice("domain")
    if domain != nil && domain.Selected {
        fmt.Printf("Domain selected\n")
        for class, prob := range domain.Probabilities {
            fmt.Printf("  %s: %.2f\n", class, prob)
        }
    }
    
    // Access Score decisions
    confidence := helper.Score("confidence")
    fmt.Printf("Confidence: %.2f\n", confidence.NormalizedValue)
    
    risk := helper.Score("risk")
    fmt.Printf("Risk: %.2f\n", risk.NormalizedValue)
    
    entropy := helper.Score("entropy")
    fmt.Printf("Entropy: %.2f\n", entropy.NormalizedValue)
}
```

### Output

```
✓ Input is valid
✓ Input is not adversarial
Domain selected
  CODE: 0.85
  MATH: 0.10
  GENERAL: 0.05
Confidence: 0.92
Risk: 0.06
Entropy: 0.18
```

---

## Example 5: Multi-Head Consistency

Check all heads agree.

### Code

```go
validator := api.NewConsistencyValidator(clf)

// All heads should agree
result := validator.ValidateMultiHeadAgreement(envelope)

if result.Valid {
    fmt.Println("✓ All heads agree")
} else {
    for _, err := range result.Errors {
        fmt.Printf("✗ %s\n", err)
    }
}
```

---

## Example 6: Audit Trail

Verify decisions with cryptographic hashes.

### Code

```go
package main

import (
    "crypto/sha256"
    "fmt"
    "devflow-finance-twin/classifier/api"
)

func main() {
    // Make classification
    request := "Compute 2+2"
    envelope, _ := clf.Predict(request)
    router.Route(envelope)
    
    // Verify input hash
    h := sha256.New()
    h.Write([]byte(request))
    expectedInputHash := fmt.Sprintf("%x", h.Sum(nil))
    
    if envelope.InputHash != expectedInputHash {
        fmt.Println("✗ Input hash mismatch!")
        return
    }
    
    fmt.Printf("✓ Input verified: %s\n", envelope.InputHash)
    fmt.Printf("✓ Router verified: %s\n", envelope.RouterHash)
    fmt.Printf("✓ Model: %s v%s\n", envelope.ModelID, envelope.ModelVersion)
    fmt.Printf("✓ Route: %s\n", envelope.Route)
    
    // Log for audit
    fmt.Printf("AUDIT: %d | %s | %s | %s\n",
        envelope.Timestamp,
        envelope.InputHash,
        envelope.RouterHash,
        envelope.Route,
    )
}
```

---

## Testing

All examples include unit tests:

```bash
go test devflow-finance-twin/classifier/api -v
```

Test files:
- `example_math_routing_test.go`
- `example_consistency_validator_test.go`
- `example_abstention_test.go`
- `example_helpers_test.go`

---

## Performance

Typical latencies:

| Operation | Time |
|-----------|------|
| Classify | 5-10ms |
| Batch(100) | 50-100ms |
| Validate | <1ms |
| Route | <1ms |

---

## Error Handling

```go
// Handle classification errors
route, err := classifier.Classify(request)
if err != nil {
    fmt.Printf("Classification failed: %v\n", err)
    // Fallback: route to human review
    return "DISPATCH(HUMAN_REVIEW)", nil
}

// Handle validation errors
result := validator.ValidateCodeClassification(envelope)
if !result.Valid {
    fmt.Printf("Validation failed: %v\n", result.Errors)
    // Escalate or reject
    return errors.New("classification failed validation")
}

// Handle routing errors
err := router.Route(envelope)
if err != nil {
    fmt.Printf("Routing failed: %v\n", err)
    return "", err
}
```

---

## Best Practices

1. **Always validate** — Use ConsistencyValidator before routing
2. **Set thresholds** — Configure abstention bounds for your domain
3. **Monitor stats** — Track abstention rates and confidence distribution
4. **Log decisions** — Record InputHash and RouterHash for auditing
5. **Batch when possible** — PredictBatch is more efficient
6. **Handle nil** — Check envelope and fields for nil before access
7. **Test edge cases** — Low confidence, high risk, conflicting heads

---

## License

See LICENSE file.
