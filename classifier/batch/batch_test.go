package batch

import (
	"context"
	"errors"
	"testing"
	"time"

	"devflow-finance-twin/classifier/primitives"
)

// MockEncoder for testing
type MockEncoder struct {
	failAt int
	callCount int
}

func (me *MockEncoder) Encode(input interface{}) ([]float64, error) {
	me.callCount++
	if me.failAt > 0 && me.callCount == me.failAt {
		return nil, errors.New("encode error")
	}

	// Return simple encoding
	if fval, ok := input.(float64); ok {
		return []float64{fval}, nil
	}
	return []float64{1.0, 2.0, 3.0}, nil
}

// MockBackend for testing
type MockBackend struct {
	failAt int
	callCount int
}

func (mb *MockBackend) EncodeInputs(inputs []interface{}) ([][]float64, error) {
	mb.callCount++
	encodings := make([][]float64, len(inputs))
	for i := range inputs {
		encodings[i] = []float64{float64(i), 1.0, 2.0}
	}
	return encodings, nil
}

func (mb *MockBackend) ExecuteHeads(encodings [][]float64, headNames []string) ([]HeadOutput, error) {
	outputs := make([]HeadOutput, len(headNames))
	for i := range headNames {
		output := HeadOutput{
			HeadName:      "head_" + string(rune(i)),
			Decisions:     make([]string, len(encodings)),
			Probabilities: make([]map[string]float64, len(encodings)),
			Logits:        make([]map[string]float64, len(encodings)),
		}

		for j := range encodings {
			output.Decisions[j] = "CLASS_A"
			output.Probabilities[j] = map[string]float64{
				"CLASS_A": 0.9,
				"CLASS_B": 0.1,
			}
			output.Logits[j] = map[string]float64{
				"CLASS_A": 2.0,
				"CLASS_B": -1.0,
			}
		}
		outputs[i] = output
	}
	return outputs, nil
}

// MockRouter for testing
type MockRouter struct {
	failAt int
	callCount int
}

func (mr *MockRouter) Route(encoding []float64) (string, []*primitives.RouteChoice, error) {
	mr.callCount++
	if mr.failAt > 0 && mr.callCount == mr.failAt {
		return "", nil, errors.New("route error")
	}

	choices := []*primitives.RouteChoice{
		{
			Name:     "route_main",
			Selected: true,
			Probabilities: map[string]float64{
				"main": 0.95,
				"alt":  0.05,
			},
		},
	}
	return "route_main", choices, nil
}

func TestBatchInferenceCreate(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	if bi == nil {
		t.Fatal("BatchInference should be created")
	}
	if bi.batchSize != 32 {
		t.Fatalf("batch size should be 32, got %d", bi.batchSize)
	}
}

func TestPredictBatch(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	inputs := []interface{}{1.0, 2.0, 3.0, 4.0, 5.0}
	ctx := context.Background()

	results, err := bi.PredictBatch(ctx, inputs)
	if err != nil {
		t.Fatalf("PredictBatch failed: %v", err)
	}

	if len(results) != len(inputs) {
		t.Fatalf("expected %d results, got %d", len(inputs), len(results))
	}

	for i, result := range results {
		if result == nil {
			t.Fatalf("result %d is nil", i)
		}
		if result.Disposition == "" {
			t.Fatalf("result %d has empty disposition", i)
		}
	}
}

func TestPredictBatchEmpty(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	results, err := bi.PredictBatch(context.Background(), []interface{}{})
	if err != nil {
		t.Fatalf("PredictBatch should handle empty input: %v", err)
	}

	if len(results) != 0 {
		t.Fatalf("expected 0 results for empty input, got %d", len(results))
	}
}

func TestPredictBatchTimeout(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 1, time.Millisecond*10)

	inputs := make([]interface{}, 1000)
	for i := range inputs {
		inputs[i] = float64(i)
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond*5)
	defer cancel()

	_, err := bi.PredictBatch(ctx, inputs)
	if err == nil {
		t.Fatal("PredictBatch should timeout")
	}
}

func TestBatchInferenceWithAuditLog(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	// This should not panic
	bi.WithAuditLog(nil)
}

func TestEnableVerification(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	bi.EnableVerification(true)
	bi.EnableVerification(false)
}

func TestGetStats(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	inputs := []interface{}{1.0, 2.0, 3.0}
	bi.PredictBatch(context.Background(), inputs)

	stats := bi.GetStats()
	if stats == nil {
		t.Fatal("stats should not be nil")
	}

	if _, ok := stats["total_items"].(int64); !ok {
		t.Fatalf("stats should contain total_items")
	}
}

func TestGetMetrics(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	metrics := bi.GetMetrics()
	if metrics == nil {
		t.Fatal("metrics should not be nil")
	}
}

func TestBatchInferenceWithRetry(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)
	bwr := NewBatchInferenceWithRetry(bi, 3)

	inputs := []interface{}{1.0, 2.0, 3.0}
	results, err := bwr.PredictBatchWithRetry(context.Background(), inputs)

	if err != nil {
		t.Fatalf("PredictBatchWithRetry failed: %v", err)
	}

	if len(results) != len(inputs) {
		t.Fatalf("expected %d results, got %d", len(inputs), len(results))
	}
}

func TestIsRetryableError(t *testing.T) {
	tests := []struct {
		err       error
		retryable bool
	}{
		{errors.New("network error"), true},
		{context.Canceled, false},
		{nil, false},
	}

	for _, test := range tests {
		result := isRetryableError(test.err)
		if result != test.retryable {
			t.Fatalf("isRetryableError(%v) = %v, expected %v", test.err, result, test.retryable)
		}
	}
}

func TestBatchInferenceWithValidation(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	validator := &NoOpValidator{}
	bwv := NewBatchInferenceWithValidation(bi, validator)

	inputs := []interface{}{1.0, 2.0}
	results, err := bwv.PredictBatchWithValidation(context.Background(), inputs)

	if err != nil {
		t.Fatalf("PredictBatchWithValidation failed: %v", err)
	}

	if len(results) != len(inputs) {
		t.Fatalf("expected %d results, got %d", len(inputs), len(results))
	}
}

type NoOpValidator struct{}

func (nv *NoOpValidator) Validate(envelope *primitives.DecisionEnvelope) error {
	return nil
}

type FailingValidator struct{}

func (fv *FailingValidator) Validate(envelope *primitives.DecisionEnvelope) error {
	return errors.New("validation failed")
}

func TestBatchInferenceWithFailingValidation(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	validator := &FailingValidator{}
	bwv := NewBatchInferenceWithValidation(bi, validator)

	inputs := []interface{}{1.0}
	_, err := bwv.PredictBatchWithValidation(context.Background(), inputs)

	if err == nil {
		t.Fatal("PredictBatchWithValidation should fail on validation error")
	}
}

func TestAdaptiveBatchSize(t *testing.T) {
	abs := NewAdaptiveBatchSize(32, 16, 128, 100.0)

	currentSize := abs.GetCurrentBatchSize()
	if currentSize != 32 {
		t.Fatalf("initial batch size should be 32, got %d", currentSize)
	}

	// Test adjustment when below target
	metrics := map[string]interface{}{
		"throughput_items_per_sec": 50.0,
	}
	newSize := abs.AdjustBatchSize(metrics)
	if newSize <= currentSize {
		t.Fatalf("batch size should increase when below target")
	}
}

func TestAdaptiveBatchSizeIncrease(t *testing.T) {
	abs := NewAdaptiveBatchSize(32, 16, 64, 100.0)

	// Below target - should increase
	metrics := map[string]interface{}{
		"throughput_items_per_sec": 50.0,
	}

	newSize := abs.AdjustBatchSize(metrics)
	prevSize := newSize

	// Call again
	newSize = abs.AdjustBatchSize(metrics)
	if newSize != prevSize {
		t.Log("batch size adjusted on second call")
	}
}

func TestPredictBatchParallel(t *testing.T) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	batchGroups := [][]interface{}{
		{1.0, 2.0, 3.0},
		{4.0, 5.0},
		{6.0},
	}

	results, err := bi.PredictBatchParallel(context.Background(), batchGroups)
	if err != nil {
		t.Fatalf("PredictBatchParallel failed: %v", err)
	}

	if len(results) != len(batchGroups) {
		t.Fatalf("expected %d result groups, got %d", len(batchGroups), len(results))
	}

	expectedCount := 0
	for _, batch := range batchGroups {
		expectedCount += len(batch)
	}

	actualCount := 0
	for _, resultBatch := range results {
		actualCount += len(resultBatch)
	}

	if actualCount != expectedCount {
		t.Fatalf("expected %d total results, got %d", expectedCount, actualCount)
	}
}

func TestAssembleNoulChoices(t *testing.T) {
	headOutputs := []HeadOutput{
		{
			HeadName: "head_1",
			Decisions: []string{"CLASS_A", "CLASS_B"},
			Probabilities: []map[string]float64{
				{"CLASS_A": 0.9, "CLASS_B": 0.1},
				{"CLASS_A": 0.6, "CLASS_B": 0.4},
			},
			Logits: []map[string]float64{
				{"CLASS_A": 2.0, "CLASS_B": -1.0},
				{"CLASS_A": 0.5, "CLASS_B": -0.5},
			},
		},
	}

	choices := assembleNoulChoices(headOutputs, 0)
	if len(choices) != 1 {
		t.Fatalf("expected 1 choice, got %d", len(choices))
	}

	if choices[0].Decision != "CLASS_A" {
		t.Fatalf("expected CLASS_A, got %s", choices[0].Decision)
	}
}

func TestDetermineDisposition(t *testing.T) {
	headOutputs := []HeadOutput{
		{
			HeadName:  "head_1",
			Decisions: []string{"CLASS_A", "CLASS_B", "CLASS_C"},
		},
	}

	disp := determineDisposition(headOutputs, 0)
	if disp != "CLASS_A" {
		t.Fatalf("expected CLASS_A, got %s", disp)
	}

	disp = determineDisposition(headOutputs, 2)
	if disp != "CLASS_C" {
		t.Fatalf("expected CLASS_C, got %s", disp)
	}

	// Empty head outputs
	disp = determineDisposition([]HeadOutput{}, 0)
	if disp != "UNKNOWN" {
		t.Fatalf("expected UNKNOWN for empty heads, got %s", disp)
	}
}

func BenchmarkPredictBatch(b *testing.B) {
	encoder := &MockEncoder{}
	backend := &MockBackend{}
	router := &MockRouter{}

	bi := NewBatchInference(encoder, backend, router, 32, 4, time.Second*30)

	inputs := make([]interface{}, 100)
	for i := range inputs {
		inputs[i] = float64(i)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		bi.PredictBatch(context.Background(), inputs)
	}
}

func BenchmarkCanonicalEncode(b *testing.B) {
	envelope := &primitives.DecisionEnvelope{
		Timestamp:    time.Now().UnixNano(),
		ModelID:      "model-123",
		ModelVersion: "1.0.0",
		InputHash:    "input-hash",
		Disposition:  "CLASS_A",
		Route:        "main",
		NoulChoices: []*primitives.NoulChoice{
			{
				Name:        "noul-1",
				Decision:    "CLASS_A",
				Probability: 0.95,
			},
		},
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = assembleNoulChoices([]HeadOutput{}, 0)
	}
}
