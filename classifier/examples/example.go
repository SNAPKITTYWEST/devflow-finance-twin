package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"devflow-finance-twin/classifier/audit"
	"devflow-finance-twin/classifier/backends"
	"devflow-finance-twin/classifier/batch"
	"devflow-finance-twin/classifier/primitives"
)

// ExampleEncoder implements a simple encoder
type ExampleEncoder struct{}

func (ee *ExampleEncoder) Encode(input interface{}) ([]float64, error) {
	if floatSlice, ok := input.([]float64); ok {
		return floatSlice, nil
	}
	if fval, ok := input.(float64); ok {
		return []float64{fval}, nil
	}
	return []float64{1.0, 2.0, 3.0}, nil
}

// ExampleRouter implements a simple router
type ExampleRouter struct{}

func (er *ExampleRouter) Route(encoding []float64) (string, []*primitives.RouteChoice, error) {
	choices := []*primitives.RouteChoice{
		{
			Name:     "primary",
			Selected: true,
			Probabilities: map[string]float64{
				"primary": 0.8,
				"backup":  0.2,
			},
		},
	}
	return "primary", choices, nil
}

// Example 1: Deterministic Canonical Encoding and Hashing
func ExampleCanonicalEncoding() {
	fmt.Println("=== Example 1: Canonical Encoding and Hashing ===")

	envelope := &primitives.DecisionEnvelope{
		Timestamp:    time.Now().UnixNano(),
		ModelID:      "classifier-v1",
		ModelVersion: "1.0.0",
		InputHash:    "input-abc123",
		RouterHash:   "router-xyz789",
		Disposition:  "APPROVED",
		Route:        "main",
		RouteChoices: []*primitives.RouteChoice{
			{
				Name:     "main",
				Selected: true,
				Probabilities: map[string]float64{
					"main": 0.95,
					"alt":  0.05,
				},
			},
		},
		NoulChoices: []*primitives.NoulChoice{
			{
				Name:        "classification_head",
				Decision:    "APPROVED",
				Probability: 0.98,
				Logits: map[string]float64{
					"APPROVED": 4.2,
					"REJECTED": -2.1,
				},
			},
		},
		Thresholds: map[string]float64{
			"approval_threshold": 0.5,
		},
	}

	// Compute deterministic hash
	hash := audit.ComputeDecisionHash(envelope)
	fmt.Printf("Decision Hash: %s\n", hash)

	// Compute again - should be identical
	hash2 := audit.ComputeDecisionHash(envelope)
	fmt.Printf("Hash Verification: %v\n", hash == hash2)
}

// Example 2: Audit Trail with Hash Chain
func ExampleAuditTrail() {
	fmt.Println("\n=== Example 2: Audit Trail with Hash Chain ===")

	auditLog := audit.NewAuditLog("audit_trail.jsonl")

	// Create audit records
	for i := 0; i < 5; i++ {
		record := &audit.AuditRecord{
			InputHash:       fmt.Sprintf("input-hash-%d", i),
			ModelHash:       "model-hash-123",
			ModelVersion:    "1.0.0",
			RouterHash:      "router-hash-456",
			DecisionHash:    fmt.Sprintf("decision-hash-%d", i),
			Timestamp:       time.Now().UnixNano() + int64(i*1000000),
			Route:           "main",
			Disposition:     fmt.Sprintf("CLASS_%s", string(rune('A'+(i%3)))),
			Thresholds:      map[string]float64{"threshold": 0.5},
			SelectedClasses: map[string]string{"class": "selected"},
			Scores:          map[string]float64{"score": 0.8},
		}

		if err := auditLog.Append(record); err != nil {
			log.Fatal(err)
		}
	}

	// Verify audit trail integrity
	if err := auditLog.Verify(); err != nil {
		log.Fatal(err)
	}
	fmt.Println("Audit trail verified successfully")

	// Get statistics
	stats := auditLog.GetStats()
	fmt.Printf("Total Records: %v\n", stats["total_records"])
	fmt.Printf("Disposition Counts: %v\n", stats["disposition_counts"])
	fmt.Printf("Route Counts: %v\n", stats["route_counts"])

	// Query by disposition
	classARecords := auditLog.GetRecordsByDisposition("CLASS_A")
	fmt.Printf("CLASS_A Records: %d\n", len(classARecords))
}

// Example 3: Batch Inference with Vectorization
func ExampleBatchInference() {
	fmt.Println("\n=== Example 3: Batch Inference with Vectorization ===")

	encoder := &ExampleEncoder{}
	cpuBackend := backends.NewCPUBackend(4)
	router := &ExampleRouter{}

	// Create batch inference engine
	bi := batch.NewBatchInference(encoder, cpuBackend, router, 32, 4, time.Second*30)

	// Set up audit log
	auditLog := audit.NewAuditLog("batch_audit.jsonl")
	bi.WithAuditLog(auditLog)

	// Prepare inputs
	inputs := make([]interface{}, 100)
	for i := 0; i < 100; i++ {
		inputs[i] = float64(i)
	}

	// Run batch inference
	ctx := context.Background()
	results, err := bi.PredictBatch(ctx, inputs)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Processed %d inputs\n", len(inputs))
	fmt.Printf("Generated %d results\n", len(results))

	// Display results
	for i := 0; i < 3; i++ {
		if i < len(results) {
			result := results[i]
			fmt.Printf("Result %d: Disposition=%s, Route=%s\n",
				i, result.Disposition, result.Route)
		}
	}

	// Get statistics
	stats := bi.GetStats()
	fmt.Printf("Total Items Processed: %v\n", stats["total_items"])
	fmt.Printf("Average Latency (ns): %v\n", stats["average_latency_ns"])
	fmt.Printf("Disposition Counts: %v\n", stats["disposition_counts"])
}

// Example 4: Batch Inference with Retry and Validation
func ExampleBatchInferenceWithRetryAndValidation() {
	fmt.Println("\n=== Example 4: Batch Inference with Retry and Validation ===")

	encoder := &ExampleEncoder{}
	cpuBackend := backends.NewCPUBackend(4)
	router := &ExampleRouter{}

	bi := batch.NewBatchInference(encoder, cpuBackend, router, 32, 4, time.Second*30)

	// Add retry support
	biWithRetry := batch.NewBatchInferenceWithRetry(bi, 3)

	// Add validation
	validator := &SimpleValidator{}
	biWithValidation := batch.NewBatchInferenceWithValidation(bi, validator)

	inputs := []interface{}{1.0, 2.0, 3.0}

	// Execute with retry
	results, err := biWithRetry.PredictBatchWithRetry(context.Background(), inputs)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Batch with Retry: Processed %d inputs\n", len(results))

	// Execute with validation
	results, err = biWithValidation.PredictBatchWithValidation(context.Background(), inputs)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Batch with Validation: Processed %d inputs\n", len(results))
}

// SimpleValidator implements validation logic
type SimpleValidator struct{}

func (sv *SimpleValidator) Validate(envelope *primitives.DecisionEnvelope) error {
	if envelope == nil {
		return fmt.Errorf("envelope is nil")
	}
	if envelope.Disposition == "" {
		return fmt.Errorf("disposition is empty")
	}
	return nil
}

// Example 5: Adaptive Batch Sizing
func ExampleAdaptiveBatchSize() {
	fmt.Println("\n=== Example 5: Adaptive Batch Size ===")

	abs := batch.NewAdaptiveBatchSize(32, 16, 128, 1000.0)

	fmt.Printf("Initial Batch Size: %d\n", abs.GetCurrentBatchSize())

	// Simulate metrics showing low throughput
	metrics := map[string]interface{}{
		"throughput_items_per_sec": 500.0, // Below target of 1000
	}

	newSize := abs.AdjustBatchSize(metrics)
	fmt.Printf("Adjusted Batch Size (low throughput): %d\n", newSize)

	// Simulate metrics showing high throughput
	metrics["throughput_items_per_sec"] = 1500.0 // Above target
	newSize = abs.AdjustBatchSize(metrics)
	fmt.Printf("Adjusted Batch Size (high throughput): %d\n", newSize)
}

// Example 6: Parallel Batch Processing
func ExampleParallelBatchProcessing() {
	fmt.Println("\n=== Example 6: Parallel Batch Processing ===")

	encoder := &ExampleEncoder{}
	cpuBackend := backends.NewCPUBackend(4)
	router := &ExampleRouter{}

	bi := batch.NewBatchInference(encoder, cpuBackend, router, 32, 4, time.Second*30)

	// Create multiple batch groups
	batchGroups := [][]interface{}{
		{1.0, 2.0, 3.0},
		{4.0, 5.0},
		{6.0, 7.0, 8.0, 9.0},
	}

	// Process in parallel
	results, err := bi.PredictBatchParallel(context.Background(), batchGroups)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Processed %d batch groups in parallel\n", len(results))
	for i, batchResults := range results {
		fmt.Printf("Batch %d: %d results\n", i, len(batchResults))
	}
}

// Example 7: Hybrid Backend (CPU + GPU)
func ExampleHybridBackend() {
	fmt.Println("\n=== Example 7: Hybrid Backend (CPU + GPU) ===")

	cpuBackend := backends.NewCPUBackend(4)
	gpuBackend := backends.NewGPUBackend(0, 8)

	hybridBackend := backends.NewHybridBackend(
		cpuBackend,
		gpuBackend,
		backends.StrategyAdaptive,
	)

	encoder := &ExampleEncoder{}
	router := &ExampleRouter{}

	bi := batch.NewBatchInference(encoder, hybridBackend, router, 32, 4, time.Second*30)

	inputs := make([]interface{}, 50)
	for i := 0; i < 50; i++ {
		inputs[i] = float64(i)
	}

	results, err := bi.PredictBatch(context.Background(), inputs)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Hybrid Backend: Processed %d inputs with %d results\n",
		len(inputs), len(results))
}

// Example 8: Model and Router Hashing
func ExampleModelAndRouterHashing() {
	fmt.Println("\n=== Example 8: Model and Router Hashing ===")

	modelMetadata := &primitives.ModelMetadata{
		ModelID:      "model-123",
		ModelVersion: "1.0.0",
		Hash:         "model-content-hash",
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	modelHash := audit.ComputeModelHash(modelMetadata)
	fmt.Printf("Model Hash: %s\n", modelHash)

	routerMetadata := &primitives.RouterMetadata{
		Hash:       "router-config-hash",
		ConfigHash: "config-hash",
		Version:    "1.0",
		Nodes:      []string{"node-a", "node-b", "node-c"},
	}

	routerHash := audit.ComputeRouterHash(routerMetadata)
	fmt.Printf("Router Hash: %s\n", routerHash)
}

func main() {
	fmt.Println("Classifier Package Examples")
	fmt.Println("============================\n")

	ExampleCanonicalEncoding()
	ExampleAuditTrail()
	ExampleBatchInference()
	ExampleBatchInferenceWithRetryAndValidation()
	ExampleAdaptiveBatchSize()
	ExampleParallelBatchProcessing()
	ExampleHybridBackend()
	ExampleModelAndRouterHashing()

	fmt.Println("\n============================")
	fmt.Println("All examples completed successfully!")
}
