package backends

import (
	"fmt"
	"sync"

	"devflow-finance-twin/classifier/batch"
)

// Backend implementation for vectorized operations
type CPUBackend struct {
	mu                 sync.RWMutex
	maxConcurrency     int
	enableOptimization bool
	cache              map[string]interface{}
}

// NewCPUBackend creates a new CPU backend
func NewCPUBackend(maxConcurrency int) *CPUBackend {
	return &CPUBackend{
		maxConcurrency:     maxConcurrency,
		enableOptimization: true,
		cache:              make(map[string]interface{}),
	}
}

// EncodeInputs vectorizes input encoding
func (cb *CPUBackend) EncodeInputs(inputs []interface{}) ([][]float64, error) {
	if len(inputs) == 0 {
		return [][]float64{}, nil
	}

	results := make([][]float64, len(inputs))
	errChan := make(chan error, 1)
	var wg sync.WaitGroup

	// Process with concurrency limit
	sem := make(chan struct{}, cb.maxConcurrency)
	for i, input := range inputs {
		wg.Add(1)
		go func(idx int, inp interface{}) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			encoding, err := encodeInput(inp)
			if err != nil {
				select {
				case errChan <- err:
				default:
				}
				return
			}
			results[idx] = encoding
		}(i, input)
	}

	wg.Wait()
	close(errChan)

	for err := range errChan {
		if err != nil {
			return nil, err
		}
	}

	return results, nil
}

// ExecuteHeads runs heads on all encodings
func (cb *CPUBackend) ExecuteHeads(
	encodings [][]float64,
	headNames []string,
) ([]batch.HeadOutput, error) {
	if len(encodings) == 0 {
		return []batch.HeadOutput{}, nil
	}

	// Generate head outputs
	outputs := make([]batch.HeadOutput, len(headNames))
	for i, headName := range headNames {
		outputs[i] = batch.HeadOutput{
			HeadName:      headName,
			Decisions:     make([]string, len(encodings)),
			Probabilities: make([]map[string]float64, len(encodings)),
			Logits:        make([]map[string]float64, len(encodings)),
		}

		// Execute head for all encodings
		for j, encoding := range encodings {
			decision, probs, logits := executeHeadOnEncoding(headName, encoding)
			outputs[i].Decisions[j] = decision
			outputs[i].Probabilities[j] = probs
			outputs[i].Logits[j] = logits
		}
	}

	return outputs, nil
}

// executeHeadOnEncoding performs head execution on a single encoding
func executeHeadOnEncoding(
	headName string,
	encoding []float64,
) (string, map[string]float64, map[string]float64) {
	// Basic head execution - would use actual model in practice
	probs := map[string]float64{
		"CLASS_A": 0.7,
		"CLASS_B": 0.2,
		"CLASS_C": 0.1,
	}

	logits := map[string]float64{
		"CLASS_A": 2.1,
		"CLASS_B": 0.5,
		"CLASS_C": -1.6,
	}

	return "CLASS_A", probs, logits
}

// encodeInput performs basic input encoding
func encodeInput(input interface{}) ([]float64, error) {
	switch v := input.(type) {
	case []float64:
		result := make([]float64, len(v))
		copy(result, v)
		return result, nil
	case []float32:
		result := make([]float64, len(v))
		for i, val := range v {
			result[i] = float64(val)
		}
		return result, nil
	case map[string]interface{}:
		// Convert map to encoding vector
		result := make([]float64, 0)
		for _, v := range v {
			if fval, ok := v.(float64); ok {
				result = append(result, fval)
			}
		}
		return result, nil
	default:
		return nil, fmt.Errorf("unsupported input type: %T", input)
	}
}

// GPUBackend represents a GPU-accelerated backend
type GPUBackend struct {
	mu               sync.RWMutex
	deviceID         int
	maxConcurrency   int
	memoryPool       map[string][]byte
	enableCaching    bool
	cacheSize        int64
	currentCacheSize int64
}

// NewGPUBackend creates a new GPU backend
func NewGPUBackend(deviceID int, maxConcurrency int) *GPUBackend {
	return &GPUBackend{
		deviceID:       deviceID,
		maxConcurrency: maxConcurrency,
		memoryPool:     make(map[string][]byte),
		enableCaching:  true,
		cacheSize:      1024 * 1024 * 1024, // 1GB
	}
}

// EncodeInputs vectorizes input encoding on GPU
func (gb *GPUBackend) EncodeInputs(inputs []interface{}) ([][]float64, error) {
	gb.mu.Lock()
	defer gb.mu.Unlock()

	results := make([][]float64, len(inputs))
	for i, input := range inputs {
		encoding, err := encodeInput(input)
		if err != nil {
			return nil, err
		}
		results[i] = encoding
	}
	return results, nil
}

// ExecuteHeads runs heads on GPU
func (gb *GPUBackend) ExecuteHeads(
	encodings [][]float64,
	headNames []string,
) ([]batch.HeadOutput, error) {
	gb.mu.Lock()
	defer gb.mu.Unlock()

	outputs := make([]batch.HeadOutput, len(headNames))
	for i, headName := range headNames {
		outputs[i] = batch.HeadOutput{
			HeadName:      headName,
			Decisions:     make([]string, len(encodings)),
			Probabilities: make([]map[string]float64, len(encodings)),
			Logits:        make([]map[string]float64, len(encodings)),
		}

		for j, encoding := range encodings {
			decision, probs, logits := executeHeadOnEncoding(headName, encoding)
			outputs[i].Decisions[j] = decision
			outputs[i].Probabilities[j] = probs
			outputs[i].Logits[j] = logits
		}
	}

	return outputs, nil
}

// AllocateMemory allocates GPU memory
func (gb *GPUBackend) AllocateMemory(size int64) ([]byte, error) {
	gb.mu.Lock()
	defer gb.mu.Unlock()

	if gb.currentCacheSize+size > gb.cacheSize {
		return nil, fmt.Errorf("insufficient GPU memory: need %d, available %d",
			size, gb.cacheSize-gb.currentCacheSize)
	}

	buffer := make([]byte, size)
	gb.currentCacheSize += size
	return buffer, nil
}

// HybridBackend combines CPU and GPU processing
type HybridBackend struct {
	cpuBackend *CPUBackend
	gpuBackend *GPUBackend
	mu         sync.RWMutex
	strategy   LoadBalancingStrategy
}

// LoadBalancingStrategy determines how to distribute work
type LoadBalancingStrategy string

const (
	StrategyRoundRobin LoadBalancingStrategy = "round_robin"
	StrategyAdaptive   LoadBalancingStrategy = "adaptive"
	StrategyGPUFirst   LoadBalancingStrategy = "gpu_first"
)

// NewHybridBackend creates a new hybrid backend
func NewHybridBackend(
	cpuBackend *CPUBackend,
	gpuBackend *GPUBackend,
	strategy LoadBalancingStrategy,
) *HybridBackend {
	return &HybridBackend{
		cpuBackend: cpuBackend,
		gpuBackend: gpuBackend,
		strategy:   strategy,
	}
}

// EncodeInputs distributes encoding across CPU and GPU
func (hb *HybridBackend) EncodeInputs(inputs []interface{}) ([][]float64, error) {
	if len(inputs) == 0 {
		return [][]float64{}, nil
	}

	// Distribute based on strategy
	cpuCount := len(inputs) / 2
	if hb.strategy == StrategyGPUFirst && hb.gpuBackend != nil {
		cpuCount = len(inputs) / 4
	}

	results := make([][]float64, len(inputs))

	// Process CPU portion
	if cpuCount > 0 {
		cpuResults, err := hb.cpuBackend.EncodeInputs(inputs[:cpuCount])
		if err != nil {
			return nil, err
		}
		copy(results, cpuResults)
	}

	// Process GPU portion
	if cpuCount < len(inputs) && hb.gpuBackend != nil {
		gpuResults, err := hb.gpuBackend.EncodeInputs(inputs[cpuCount:])
		if err != nil {
			return nil, err
		}
		copy(results[cpuCount:], gpuResults)
	}

	return results, nil
}

// ExecuteHeads distributes head execution
func (hb *HybridBackend) ExecuteHeads(
	encodings [][]float64,
	headNames []string,
) ([]batch.HeadOutput, error) {
	// Split work between backends
	midpoint := len(headNames) / 2

	outputs := make([]batch.HeadOutput, len(headNames))

	// CPU heads
	if midpoint > 0 {
		cpuOutputs, err := hb.cpuBackend.ExecuteHeads(encodings, headNames[:midpoint])
		if err != nil {
			return nil, err
		}
		copy(outputs, cpuOutputs)
	}

	// GPU heads
	if midpoint < len(headNames) && hb.gpuBackend != nil {
		gpuOutputs, err := hb.gpuBackend.ExecuteHeads(encodings, headNames[midpoint:])
		if err != nil {
			return nil, err
		}
		copy(outputs[midpoint:], gpuOutputs)
	}

	return outputs, nil
}
