package batch

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"devflow-finance-twin/classifier/audit"
	"devflow-finance-twin/classifier/primitives"
)

// Backend interface for vectorized operations
type Backend interface {
	EncodeInputs(inputs []interface{}) ([][]float64, error)
	ExecuteHeads(encodings [][]float64, headNames []string) ([]HeadOutput, error)
}

// HeadOutput represents the output of a single head on a batch
type HeadOutput struct {
	HeadName    string
	Decisions   []string
	Probabilities []map[string]float64
	Logits      []map[string]float64
}

// Encoder interface for input encoding
type Encoder interface {
	Encode(input interface{}) ([]float64, error)
}

// RouterEngine interface for routing decisions
type RouterEngine interface {
	Route(encoding []float64) (string, []*primitives.RouteChoice, error)
}

// BatchInference manages vectorized batch processing
type BatchInference struct {
	mu              sync.RWMutex
	encoder         Encoder
	backend         Backend
	router          RouterEngine
	batchSize       int
	maxConcurrency  int
	timeout         time.Duration
	auditLog        *audit.AuditLog
	stats           *BatchStats
	metrics         *BatchMetrics
	verificationEnabled bool
}

// BatchStats tracks batch processing statistics
type BatchStats struct {
	mu                  sync.Mutex
	TotalBatchesProcessed  int64
	TotalItemsProcessed    int64
	TotalErrors            int64
	AverageLatencyNs       int64
	MaxLatencyNs           int64
	MinLatencyNs           int64
	TotalExecutionTimeNs   int64
	DispositionCounts      map[string]int64
	RouteCounts            map[string]int64
}

// BatchMetrics tracks real-time metrics
type BatchMetrics struct {
	mu                     sync.Mutex
	CurrentBatchSize       int32
	ActiveBatches          int32
	PendingItems           int32
	SuccessCount           int32
	ErrorCount             int32
	LatencyPercentiles     map[string]int64
	ThroughputItemsPerSec  float64
}

// NewBatchInference creates a new batch inference engine
func NewBatchInference(
	encoder Encoder,
	backend Backend,
	router RouterEngine,
	batchSize int,
	maxConcurrency int,
	timeout time.Duration,
) *BatchInference {
	return &BatchInference{
		encoder:         encoder,
		backend:         backend,
		router:          router,
		batchSize:       batchSize,
		maxConcurrency:  maxConcurrency,
		timeout:         timeout,
		stats:           &BatchStats{DispositionCounts: make(map[string]int64), RouteCounts: make(map[string]int64)},
		metrics:         &BatchMetrics{LatencyPercentiles: make(map[string]int64)},
		verificationEnabled: true,
	}
}

// WithAuditLog sets the audit log for tracking decisions
func (bi *BatchInference) WithAuditLog(al *audit.AuditLog) *BatchInference {
	bi.mu.Lock()
	defer bi.mu.Unlock()
	bi.auditLog = al
	return bi
}

// EnableVerification enables decision verification
func (bi *BatchInference) EnableVerification(enabled bool) *BatchInference {
	bi.mu.Lock()
	defer bi.mu.Unlock()
	bi.verificationEnabled = enabled
	return bi
}

// PredictBatch processes a batch of inputs and returns decision envelopes
func (bi *BatchInference) PredictBatch(ctx context.Context, inputs []interface{}) ([]*primitives.DecisionEnvelope, error) {
	if len(inputs) == 0 {
		return []*primitives.DecisionEnvelope{}, nil
	}

	startTime := time.Now()
	ctx, cancel := context.WithTimeout(ctx, bi.timeout)
	defer cancel()

	bi.mu.RLock()
	batchSize := bi.batchSize
	maxConcurrency := bi.maxConcurrency
	bi.mu.RUnlock()

	// Process in chunks to respect batch size
	results := make([]*primitives.DecisionEnvelope, len(inputs))
	errChan := make(chan error, 1)
	resultChan := make(chan *batchResult, len(inputs)/batchSize+1)

	// Semaphore for concurrency control
	sem := make(chan struct{}, maxConcurrency)

	// Process batches
	batchCount := 0
	for i := 0; i < len(inputs); i += batchSize {
		end := i + batchSize
		if end > len(inputs) {
			end = len(inputs)
		}

		batchIdx := batchCount
		batchCount++

		go func(start, finish, idx int) {
			sem <- struct{}{}
			defer func() { <-sem }()

			batchResults, err := bi.predictBatchInternal(ctx, inputs[start:finish], start)
			if err != nil {
				select {
				case errChan <- err:
				default:
				}
				return
			}

			resultChan <- &batchResult{
				startIdx: start,
				results:  batchResults,
			}
		}(i, end, batchIdx)
	}

	// Collect results
	receivedBatches := 0
	expectedBatches := batchCount

	for receivedBatches < expectedBatches {
		select {
		case err := <-errChan:
			return nil, err
		case br := <-resultChan:
			copy(results[br.startIdx:br.startIdx+len(br.results)], br.results)
			receivedBatches++
		case <-ctx.Done():
			return nil, fmt.Errorf("batch processing timeout: %w", ctx.Err())
		}
	}

	// Update metrics
	elapsed := time.Since(startTime)
	bi.updateMetrics(len(inputs), elapsed, results)

	return results, nil
}

// batchResult carries results from a batch processing goroutine
type batchResult struct {
	startIdx int
	results  []*primitives.DecisionEnvelope
}

// predictBatchInternal processes a single batch internally
func (bi *BatchInference) predictBatchInternal(
	ctx context.Context,
	batch []interface{},
	batchOffset int,
) ([]*primitives.DecisionEnvelope, error) {
	if len(batch) == 0 {
		return []*primitives.DecisionEnvelope{}, nil
	}

	// Step 1: Encode all inputs in parallel
	encodingChan := make(chan *encodingResult, len(batch))
	var encWg sync.WaitGroup

	for idx, input := range batch {
		encWg.Add(1)
		go func(i int, inp interface{}) {
			defer encWg.Done()
			enc, err := bi.encoder.Encode(inp)
			encodingChan <- &encodingResult{index: i, encoding: enc, err: err}
		}(idx, input)
	}

	// Collect encodings
	encodings := make([][]float64, len(batch))
	go func() {
		encWg.Wait()
		close(encodingChan)
	}()

	for result := range encodingChan {
		if result.err != nil {
			return nil, fmt.Errorf("encoding error at index %d: %w", result.index, result.err)
		}
		encodings[result.index] = result.encoding
	}

	// Step 2: Perform routing on all encodings
	routeChoices := make([][]*primitives.RouteChoice, len(batch))
	routes := make([]string, len(batch))

	for idx, encoding := range encodings {
		route, choices, err := bi.router.Route(encoding)
		if err != nil {
			return nil, fmt.Errorf("routing error at index %d: %w", idx, err)
		}
		routes[idx] = route
		routeChoices[idx] = choices
	}

	// Step 3: Execute all heads on all encodings via backend
	headNames := []string{} // Would be populated from model configuration
	headOutputs, err := bi.backend.ExecuteHeads(encodings, headNames)
	if err != nil {
		return nil, fmt.Errorf("backend execution error: %w", err)
	}

	// Step 4: Assemble decision envelopes
	results := make([]*primitives.DecisionEnvelope, len(batch))
	for i := 0; i < len(batch); i++ {
		envelope := &primitives.DecisionEnvelope{
			Timestamp:      time.Now().UnixNano(),
			RouteChoices:   routeChoices[i],
			NoulChoices:    assembleNoulChoices(headOutputs, i),
			Thresholds:     make(map[string]float64),
			Route:          routes[i],
			Disposition:    determineDisposition(headOutputs, i),
		}

		results[i] = envelope

		// Compute hashes for verification
		if bi.verificationEnabled {
			envelope.InputHash = fmt.Sprintf("batch-input-%d", batchOffset+i)
			envelope.DecisionHash = audit.ComputeDecisionHash(envelope)

			// Log to audit trail if configured
			if bi.auditLog != nil {
				ar := &audit.AuditRecord{
					InputHash:        envelope.InputHash,
					ModelHash:        envelope.ModelID,
					ModelVersion:     envelope.ModelVersion,
					RouterHash:       envelope.RouterHash,
					DecisionHash:     envelope.DecisionHash,
					Timestamp:        envelope.Timestamp,
					Route:            envelope.Route,
					Disposition:      envelope.Disposition,
					Thresholds:       envelope.Thresholds,
					SelectedClasses:  make(map[string]string),
					Scores:           make(map[string]float64),
				}
				bi.auditLog.Append(ar)
			}
		}
	}

	return results, nil
}

// assembleNoulChoices constructs NoulChoice objects from head outputs
func assembleNoulChoices(headOutputs []HeadOutput, batchIdx int) []*primitives.NoulChoice {
	var choices []*primitives.NoulChoice

	for _, headOut := range headOutputs {
		if batchIdx < len(headOut.Decisions) {
			choice := &primitives.NoulChoice{
				Name:        headOut.HeadName,
				Decision:    headOut.Decisions[batchIdx],
				Probability: 0.0,
			}

			// Set probability if available
			if batchIdx < len(headOut.Probabilities) && headOut.Probabilities[batchIdx] != nil {
				for _, p := range headOut.Probabilities[batchIdx] {
					choice.Probability = p
					break
				}
			}

			// Set logits if available
			if batchIdx < len(headOut.Logits) {
				choice.Logits = headOut.Logits[batchIdx]
			} else {
				choice.Logits = make(map[string]float64)
			}

			choices = append(choices, choice)
		}
	}

	return choices
}

// determineDisposition determines the final disposition from head outputs
func determineDisposition(headOutputs []HeadOutput, batchIdx int) string {
	if len(headOutputs) == 0 {
		return "UNKNOWN"
	}

	// Use first head's decision as disposition
	if batchIdx < len(headOutputs[0].Decisions) {
		return headOutputs[0].Decisions[batchIdx]
	}

	return "UNKNOWN"
}

// encodingResult carries encoding results from goroutines
type encodingResult struct {
	index    int
	encoding []float64
	err      error
}

// PredictBatchParallel processes multiple batches in parallel using goroutines
func (bi *BatchInference) PredictBatchParallel(
	ctx context.Context,
	batchGroups [][]interface{},
) ([][]*primitives.DecisionEnvelope, error) {
	results := make([][]*primitives.DecisionEnvelope, len(batchGroups))
	errChan := make(chan error, len(batchGroups))
	var wg sync.WaitGroup

	bi.mu.RLock()
	maxConcurrency := bi.maxConcurrency
	bi.mu.RUnlock()

	// Semaphore for concurrency control
	sem := make(chan struct{}, maxConcurrency)

	for idx, batch := range batchGroups {
		wg.Add(1)
		go func(i int, b []interface{}) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			batchResults, err := bi.PredictBatch(ctx, b)
			if err != nil {
				select {
				case errChan <- fmt.Errorf("batch %d error: %w", i, err):
				default:
				}
				return
			}
			results[i] = batchResults
		}(idx, batch)
	}

	// Wait for completion
	go func() {
		wg.Wait()
		close(errChan)
	}()

	// Collect errors
	for err := range errChan {
		if err != nil {
			return nil, err
		}
	}

	return results, nil
}

// StreamBatch streams results from batch processing
func (bi *BatchInference) StreamBatch(
	ctx context.Context,
	inputs []interface{},
	resultChan chan<- *primitives.DecisionEnvelope,
	errChan chan<- error,
) {
	defer close(resultChan)

	results, err := bi.PredictBatch(ctx, inputs)
	if err != nil {
		errChan <- err
		return
	}

	for _, result := range results {
		select {
		case resultChan <- result:
		case <-ctx.Done():
			errChan <- ctx.Err()
			return
		}
	}
}

// updateMetrics updates batch statistics
func (bi *BatchInference) updateMetrics(itemCount int, elapsed time.Duration, results []*primitives.DecisionEnvelope) {
	bi.stats.mu.Lock()
	defer bi.stats.mu.Unlock()

	atomic.AddInt64(&bi.stats.TotalBatchesProcessed, 1)
	atomic.AddInt64(&bi.stats.TotalItemsProcessed, int64(itemCount))

	latencyNs := elapsed.Nanoseconds()
	atomic.AddInt64(&bi.stats.TotalExecutionTimeNs, latencyNs)

	// Update min/max latency
	if bi.stats.MinLatencyNs == 0 || latencyNs < bi.stats.MinLatencyNs {
		bi.stats.MinLatencyNs = latencyNs
	}
	if latencyNs > bi.stats.MaxLatencyNs {
		bi.stats.MaxLatencyNs = latencyNs
	}

	// Update average latency
	if bi.stats.TotalBatchesProcessed > 0 {
		bi.stats.AverageLatencyNs = bi.stats.TotalExecutionTimeNs / bi.stats.TotalBatchesProcessed
	}

	// Update disposition counts
	for _, result := range results {
		if result != nil && result.Disposition != "" {
			bi.stats.DispositionCounts[result.Disposition]++
		}
		if result != nil && result.Route != "" {
			bi.stats.RouteCounts[result.Route]++
		}
	}
}

// GetStats returns current batch processing statistics
func (bi *BatchInference) GetStats() map[string]interface{} {
	bi.stats.mu.Lock()
	defer bi.stats.mu.Unlock()

	return map[string]interface{}{
		"total_batches":        bi.stats.TotalBatchesProcessed,
		"total_items":          bi.stats.TotalItemsProcessed,
		"total_errors":         bi.stats.TotalErrors,
		"average_latency_ns":   bi.stats.AverageLatencyNs,
		"max_latency_ns":       bi.stats.MaxLatencyNs,
		"min_latency_ns":       bi.stats.MinLatencyNs,
		"disposition_counts":   bi.stats.DispositionCounts,
		"route_counts":         bi.stats.RouteCounts,
	}
}

// GetMetrics returns real-time metrics
func (bi *BatchInference) GetMetrics() map[string]interface{} {
	bi.metrics.mu.Lock()
	defer bi.metrics.mu.Unlock()

	return map[string]interface{}{
		"current_batch_size":     atomic.LoadInt32(&bi.metrics.CurrentBatchSize),
		"active_batches":         atomic.LoadInt32(&bi.metrics.ActiveBatches),
		"pending_items":          atomic.LoadInt32(&bi.metrics.PendingItems),
		"success_count":          atomic.LoadInt32(&bi.metrics.SuccessCount),
		"error_count":            atomic.LoadInt32(&bi.metrics.ErrorCount),
		"latency_percentiles":    bi.metrics.LatencyPercentiles,
		"throughput_items_per_sec": bi.metrics.ThroughputItemsPerSec,
	}
}

// BatchInferenceWithRetry wraps batch inference with retry logic
type BatchInferenceWithRetry struct {
	bi       *BatchInference
	maxRetry int
}

// NewBatchInferenceWithRetry creates a new batch inference with retry support
func NewBatchInferenceWithRetry(bi *BatchInference, maxRetry int) *BatchInferenceWithRetry {
	return &BatchInferenceWithRetry{
		bi:       bi,
		maxRetry: maxRetry,
	}
}

// PredictBatchWithRetry executes batch prediction with exponential backoff
func (bwr *BatchInferenceWithRetry) PredictBatchWithRetry(
	ctx context.Context,
	inputs []interface{},
) ([]*primitives.DecisionEnvelope, error) {
	var results []*primitives.DecisionEnvelope
	var lastErr error

	for attempt := 0; attempt <= bwr.maxRetry; attempt++ {
		results, lastErr = bwr.bi.PredictBatch(ctx, inputs)
		if lastErr == nil {
			return results, nil
		}

		// Check if error is retryable
		if !isRetryableError(lastErr) {
			return nil, lastErr
		}

		if attempt < bwr.maxRetry {
			backoff := time.Duration(1<<uint(attempt)) * time.Millisecond
			select {
			case <-time.After(backoff):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
	}

	return nil, fmt.Errorf("batch processing failed after %d retries: %w", bwr.maxRetry, lastErr)
}

// isRetryableError determines if an error is retryable
func isRetryableError(err error) bool {
	if err == nil {
		return false
	}

	// Check for specific non-retryable errors
	if errors.Is(err, context.Canceled) {
		return false
	}

	// Default: retry
	return true
}

// BachInferenceWithValidation adds validation to batch inference
type BatchInferenceWithValidation struct {
	bi        *BatchInference
	validators []DecisionValidator
}

// DecisionValidator interface for validating decisions
type DecisionValidator interface {
	Validate(envelope *primitives.DecisionEnvelope) error
}

// NewBatchInferenceWithValidation creates batch inference with validation
func NewBatchInferenceWithValidation(
	bi *BatchInference,
	validators ...DecisionValidator,
) *BatchInferenceWithValidation {
	return &BatchInferenceWithValidation{
		bi:        bi,
		validators: validators,
	}
}

// PredictBatchWithValidation executes batch prediction with validation
func (bwv *BatchInferenceWithValidation) PredictBatchWithValidation(
	ctx context.Context,
	inputs []interface{},
) ([]*primitives.DecisionEnvelope, error) {
	results, err := bwv.bi.PredictBatch(ctx, inputs)
	if err != nil {
		return nil, err
	}

	// Validate each result
	for i, result := range results {
		for _, validator := range bwv.validators {
			if err := validator.Validate(result); err != nil {
				return nil, fmt.Errorf("validation error at index %d: %w", i, err)
			}
		}
	}

	return results, nil
}

// AdaptiveBatchSize manages dynamic batch sizing based on throughput
type AdaptiveBatchSize struct {
	mu           sync.RWMutex
	currentSize  int
	minSize      int
	maxSize      int
	targetThroughput float64 // items per second
	lastMetrics  map[string]interface{}
}

// NewAdaptiveBatchSize creates an adaptive batch sizing strategy
func NewAdaptiveBatchSize(initialSize, minSize, maxSize int, targetThroughput float64) *AdaptiveBatchSize {
	return &AdaptiveBatchSize{
		currentSize:      initialSize,
		minSize:          minSize,
		maxSize:          maxSize,
		targetThroughput: targetThroughput,
		lastMetrics:      make(map[string]interface{}),
	}
}

// AdjustBatchSize adjusts the batch size based on metrics
func (abs *AdaptiveBatchSize) AdjustBatchSize(metrics map[string]interface{}) int {
	abs.mu.Lock()
	defer abs.mu.Unlock()

	// Extract throughput from metrics
	throughput, ok := metrics["throughput_items_per_sec"].(float64)
	if !ok {
		return abs.currentSize
	}

	// Adjust based on target
	if throughput < abs.targetThroughput {
		// Increase batch size if below target
		newSize := abs.currentSize + 10
		if newSize > abs.maxSize {
			newSize = abs.maxSize
		}
		abs.currentSize = newSize
	} else if throughput > abs.targetThroughput*1.2 {
		// Decrease batch size if significantly above target
		newSize := abs.currentSize - 10
		if newSize < abs.minSize {
			newSize = abs.minSize
		}
		abs.currentSize = newSize
	}

	abs.lastMetrics = metrics
	return abs.currentSize
}

// GetCurrentBatchSize returns current batch size
func (abs *AdaptiveBatchSize) GetCurrentBatchSize() int {
	abs.mu.RLock()
	defer abs.mu.RUnlock()
	return abs.currentSize
}
