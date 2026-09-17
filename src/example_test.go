package api

import (
	"testing"

	"devflow-finance-twin/classifier/primitives"
)

// MockClassifier implements Classifier for testing
type MockClassifier struct {
	predictions map[string]*primitives.DecisionEnvelope
}

// NewMockClassifier creates a mock classifier
func NewMockClassifier() *MockClassifier {
	return &MockClassifier{
		predictions: make(map[string]*primitives.DecisionEnvelope),
	}
}

// Predict returns a canned prediction
func (mc *MockClassifier) Predict(input interface{}) (*primitives.DecisionEnvelope, error) {
	if str, ok := input.(string); ok {
		if env, exists := mc.predictions[str]; exists {
			return env, nil
		}
	}

	// Default envelope
	return &primitives.DecisionEnvelope{
		ModelID:      "test-model",
		ModelVersion: "1.0",
		Disposition:  "GENERAL",
		NoulChoices: []*primitives.NoulChoice{
			{
				Name:     "valid",
				Decision: "YES",
			},
		},
		RouteChoices: []*primitives.RouteChoice{
			{
				Name:     "domain",
				Selected: true,
			},
		},
		CalibrationMetadata: map[string]interface{}{
			"confidence": 0.95,
			"risk":       0.05,
		},
	}, nil
}

// PredictBatch returns batch predictions
func (mc *MockClassifier) PredictBatch(inputs []interface{}) ([]*primitives.DecisionEnvelope, error) {
	results := make([]*primitives.DecisionEnvelope, len(inputs))
	for i, input := range inputs {
		env, _ := mc.Predict(input)
		results[i] = env
	}
	return results, nil
}

// SetBackend sets the backend (no-op for mock)
func (mc *MockClassifier) SetBackend(backend string) error {
	return nil
}

// AddPrediction adds a mock prediction
func (mc *MockClassifier) AddPrediction(input string, envelope *primitives.DecisionEnvelope) {
	mc.predictions[input] = envelope
}

// TestMathRoutingClassifier tests the math routing example
func TestMathRoutingClassifier(t *testing.T) {
	mock := NewMockClassifier()
	router := NewDefaultRouter("test")
	classifier := NewMathRoutingClassifier(mock, router)

	// Test basic classification
	route, err := classifier.Classify("test input")
	if err != nil {
		t.Fatalf("Classify failed: %v", err)
	}

	if route == "" {
		t.Fatal("Expected non-empty route")
	}

	t.Logf("Classify result: %s", route)
}

// TestConsistencyValidator tests the consistency validator
func TestConsistencyValidator(t *testing.T) {
	mock := NewMockClassifier()
	validator := NewConsistencyValidator(mock)

	envelope := &primitives.DecisionEnvelope{
		ModelID:      "test",
		ModelVersion: "1.0",
		Disposition:  "CODE",
		NoulChoices: []*primitives.NoulChoice{
			{
				Name:     "valid",
				Decision: "YES",
			},
		},
		RouteChoices: []*primitives.RouteChoice{
			{
				Name:     "domain",
				Selected: true,
			},
		},
		CalibrationMetadata: map[string]interface{}{
			"confidence": 0.95,
			"risk":       0.05,
		},
	}

	result := validator.ValidateCodeClassification(envelope)
	if !result.Valid {
		t.Fatalf("ValidateCodeClassification failed: %v", result.Errors)
	}

	t.Logf("Consistency check result: %s", result.Message)
}

// TestAbstentionExample tests the abstention example
func TestAbstentionExample(t *testing.T) {
	mock := NewMockClassifier()

	// Create envelope with low confidence
	lowConfEnv := &primitives.DecisionEnvelope{
		ModelID:      "test",
		ModelVersion: "1.0",
		Disposition:  "UNKNOWN",
		CalibrationMetadata: map[string]interface{}{
			"confidence": 0.60,
			"risk":       0.20,
		},
	}

	mock.AddPrediction("uncertain input", lowConfEnv)

	router := NewDefaultRouter("test")
	abstainer := NewAbstentionExample(mock, router)

	result, err := abstainer.ClassifyWithAbstention("uncertain input")
	if err != nil {
		// This is expected for low confidence
		t.Logf("ClassifyWithAbstention returned: %s", result)
	}

	if result != "ABSTAIN" {
		t.Fatalf("Expected ABSTAIN for low confidence, got %s", result)
	}

	t.Logf("Abstention result: %s", result)
}

// TestAbstentionStats tests statistics computation
func TestAbstentionStats(t *testing.T) {
	decisions := []*AbstentionDecision{
		{Request: "req1", Confidence: 0.95, Risk: 0.05, Disposition: "ROUTE"},
		{Request: "req2", Confidence: 0.60, Risk: 0.20, Disposition: "ABSTAIN_LOW_CONFIDENCE"},
		{Request: "req3", Confidence: 0.80, Risk: 0.10, Disposition: "ABSTAIN_UNCERTAIN"},
	}

	stats := ComputeStats(decisions)

	if stats.Total != 3 {
		t.Fatalf("Expected 3 total, got %d", stats.Total)
	}

	if stats.Routed != 1 {
		t.Fatalf("Expected 1 routed, got %d", stats.Routed)
	}

	if stats.Abstained != 2 {
		t.Fatalf("Expected 2 abstained, got %d", stats.Abstained)
	}

	t.Logf("Stats: Total=%d, Routed=%d, Abstained=%d, AbstainRate=%.2f",
		stats.Total, stats.Routed, stats.Abstained, stats.AbstainRate)
}

// TestDecisionEnvelopeHelper tests helper methods
func TestDecisionEnvelopeHelper(t *testing.T) {
	envelope := &primitives.DecisionEnvelope{
		NoulChoices: []*primitives.NoulChoice{
			{Name: "valid", Decision: "YES"},
		},
		RouteChoices: []*primitives.RouteChoice{
			{Name: "domain", Selected: true},
		},
		CalibrationMetadata: map[string]interface{}{
			"confidence": 0.92,
		},
	}

	helper := NewDecisionEnvelopeHelper(envelope)

	noul := helper.Noul("valid")
	if noul == nil || !noul.IsYes() {
		t.Fatal("Failed to get noul decision")
	}

	choice := helper.Choice("domain")
	if choice == nil || !choice.Selected {
		t.Fatal("Failed to get route choice")
	}

	score := helper.Score("confidence")
	if score == nil || score.NormalizedValue < 0.90 {
		t.Fatal("Failed to get confidence score")
	}

	t.Log("DecisionEnvelopeHelper test passed")
}

// TestDefaultRouter tests the default router
func TestDefaultRouter(t *testing.T) {
	router := NewDefaultRouter("test-router")

	err := router.Validate()
	if err != nil {
		t.Fatalf("Validate failed: %v", err)
	}

	envelope := &primitives.DecisionEnvelope{
		ModelID:      "test",
		ModelVersion: "1.0",
		Disposition:  "MATH_ENGINE",
	}

	err = router.Route(envelope)
	if err != nil {
		t.Fatalf("Route failed: %v", err)
	}

	if envelope.Route == "" {
		t.Fatal("Route not set")
	}

	if envelope.RouterHash == "" {
		t.Fatal("RouterHash not set")
	}

	t.Logf("Route: %s, RouterHash: %s", envelope.Route, envelope.RouterHash)
}

// BenchmarkClassify benchmarks classification
func BenchmarkClassify(b *testing.B) {
	mock := NewMockClassifier()
	router := NewDefaultRouter("bench")
	classifier := NewMathRoutingClassifier(mock, router)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		classifier.Classify("benchmark input")
	}
}

// BenchmarkValidation benchmarks consistency validation
func BenchmarkValidation(b *testing.B) {
	mock := NewMockClassifier()
	validator := NewConsistencyValidator(mock)

	envelope := &primitives.DecisionEnvelope{
		ModelID: "test",
		NoulChoices: []*primitives.NoulChoice{
			{Name: "valid", Decision: "YES"},
		},
		RouteChoices: []*primitives.RouteChoice{
			{Name: "domain", Selected: true},
		},
		CalibrationMetadata: map[string]interface{}{
			"confidence": 0.95,
			"risk":       0.05,
		},
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		validator.ValidateCodeClassification(envelope)
	}
}
