package model

import (
	"devflow-finance-twin/classifier/primitives"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"sort"
	"sync"
	"time"
)

// Encoder produces shared representation from input
type Encoder interface {
	Encode(input interface{}) ([]float64, error)
	InputShape() []int
	HiddenDim() int
}

// Calibrator adjusts scores post-inference
type Calibrator interface {
	Calibrate(name string, score *primitives.Score) *primitives.Score
}

// CalibrationMetadata tracks calibration state
type CalibrationMetadata struct {
	Applied      bool
	Temperature  float64
	Offset       float64
	ScaleFactor  float64
	Method       string
	Timestamp    time.Time
}

// NoulHead produces binary decision from hidden state
type NoulHead struct {
	name      string
	weights   []float64
	bias      float64
	threshold float64
}

// NewNoulHead creates a new binary classification head
func NewNoulHead(name string, weights []float64, bias float64, threshold float64) *NoulHead {
	if threshold < 0 || threshold > 1 {
		threshold = 0.5
	}
	return &NoulHead{
		name:      name,
		weights:   weights,
		bias:      bias,
		threshold: threshold,
	}
}

// Forward executes binary classification
func (h *NoulHead) Forward(hidden []float64) *primitives.Noul {
	logit := dotProduct(hidden, h.weights) + h.bias
	prob := sigmoid(logit)

	var decision string
	if prob >= h.threshold {
		decision = "YES"
	} else {
		decision = "NO"
	}

	margin := 2*prob - 1
	if decision == "NO" {
		margin = 1 - 2*prob
	}

	return &primitives.Noul{
		Decision:    decision,
		Probability: prob,
		Logit:       logit,
		Margin:      margin,
		Threshold:   h.threshold,
	}
}

// ChoiceHead produces categorical decision from hidden state
type ChoiceHead struct {
	name      string
	labels    []string
	weights   [][]float64
	bias      []float64
	threshold float64
}

// NewChoiceHead creates a new categorical classification head
func NewChoiceHead(name string, labels []string, weights [][]float64, bias []float64, threshold float64) *ChoiceHead {
	if threshold < 0 || threshold > 1 {
		threshold = 0.0
	}
	return &ChoiceHead{
		name:      name,
		labels:    labels,
		weights:   weights,
		bias:      bias,
		threshold: threshold,
	}
}

// Forward executes categorical classification
func (h *ChoiceHead) Forward(hidden []float64) *primitives.Choice {
	logits := make(map[string]float64)
	rawLogits := matVecMul(h.weights, hidden)

	if len(rawLogits) != len(h.labels) {
		rawLogits = make([]float64, len(h.labels))
	}

	for i, label := range h.labels {
		biasVal := 0.0
		if i < len(h.bias) {
			biasVal = h.bias[i]
		}
		logits[label] = rawLogits[i] + biasVal
	}

	probs := softmax(logits)

	var selected string
	maxProb := 0.0
	for label, prob := range probs {
		if prob > maxProb {
			maxProb = prob
			selected = label
		}
	}

	if selected == "" && len(h.labels) > 0 {
		selected = h.labels[0]
		maxProb = probs[selected]
	}

	rank := rankByProbability(probs)
	entropy := computeEntropy(probs)
	marginVal := maxProb - secondMax(probs)

	return &primitives.Choice{
		Selected:      selected,
		Probabilities: probs,
		Logits:        logits,
		Rank:          rank,
		Entropy:       entropy,
		Margin:        marginVal,
		Threshold:     h.threshold,
	}
}

// ScoreHead produces numeric score from hidden state
type ScoreHead struct {
	name      string
	weights   []float64
	bias      float64
	semantics string // "probability" | "confidence" | "risk" | "score"
	normalize bool
}

// NewScoreHead creates a new regression head
func NewScoreHead(name string, weights []float64, bias float64, semantics string, normalize bool) *ScoreHead {
	return &ScoreHead{
		name:      name,
		weights:   weights,
		bias:      bias,
		semantics: semantics,
		normalize: normalize,
	}
}

// Forward executes regression
func (h *ScoreHead) Forward(hidden []float64) *primitives.Score {
	logit := dotProduct(hidden, h.weights) + h.bias

	normalized := logit
	if h.normalize {
		normalized = sigmoid(logit)
	}

	return &primitives.Score{
		Value:           logit,
		NormalizedValue: normalized,
		Semantics:       h.semantics,
		Logit:           logit,
		IsCalibrated:    false,
	}
}

// Classifier: parallel inference from shared encoder
type Classifier struct {
	name        string
	encoder     Encoder
	noulHeads   map[string]*NoulHead
	choiceHeads map[string]*ChoiceHead
	scoreHeads  map[string]*ScoreHead
	calibrator  Calibrator
	mu          sync.RWMutex
}

// NewClassifier creates a new classifier
func NewClassifier(name string, encoder Encoder) *Classifier {
	return &Classifier{
		name:        name,
		encoder:     encoder,
		noulHeads:   make(map[string]*NoulHead),
		choiceHeads: make(map[string]*ChoiceHead),
		scoreHeads:  make(map[string]*ScoreHead),
	}
}

// AddNoulHead adds a binary classification head
func (c *Classifier) AddNoulHead(name string, head *NoulHead) error {
	if name == "" {
		return errors.New("head name cannot be empty")
	}
	if head == nil {
		return errors.New("head cannot be nil")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.noulHeads[name] = head
	return nil
}

// AddChoiceHead adds a categorical classification head
func (c *Classifier) AddChoiceHead(name string, head *ChoiceHead) error {
	if name == "" {
		return errors.New("head name cannot be empty")
	}
	if head == nil {
		return errors.New("head cannot be nil")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.choiceHeads[name] = head
	return nil
}

// AddScoreHead adds a regression head
func (c *Classifier) AddScoreHead(name string, head *ScoreHead) error {
	if name == "" {
		return errors.New("head name cannot be empty")
	}
	if head == nil {
		return errors.New("head cannot be nil")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.scoreHeads[name] = head
	return nil
}

// SetCalibrator sets the calibrator
func (c *Classifier) SetCalibrator(calibrator Calibrator) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.calibrator = calibrator
}

// Predict produces a decision envelope from input
func (c *Classifier) Predict(input interface{}) (*primitives.DecisionEnvelope, error) {
	if input == nil {
		return nil, errors.New("input cannot be nil")
	}

	// Encode input once
	hidden, err := c.encoder.Encode(input)
	if err != nil {
		return nil, fmt.Errorf("encoding failed: %w", err)
	}

	if len(hidden) != c.encoder.HiddenDim() {
		return nil, fmt.Errorf("hidden dimension mismatch: got %d, expected %d", len(hidden), c.encoder.HiddenDim())
	}

	// Create envelope
	envelope := &primitives.DecisionEnvelope{
		RequestID:   generateRequestID(),
		Timestamp:   time.Now(),
		Nouls:       make(map[string]*primitives.Noul),
		Choices:     make(map[string]*primitives.Choice),
		Scores:      make(map[string]*primitives.Score),
		Calibration: make(map[string]CalibrationMetadata),
		Metadata:    make(map[string]interface{}),
	}

	c.mu.RLock()
	defer c.mu.RUnlock()

	// Execute Noul heads
	for name, head := range c.noulHeads {
		envelope.Nouls[name] = head.Forward(hidden)
	}

	// Execute Choice heads
	for name, head := range c.choiceHeads {
		envelope.Choices[name] = head.Forward(hidden)
	}

	// Execute Score heads
	for name, head := range c.scoreHeads {
		score := head.Forward(hidden)

		// Apply calibration if available
		if c.calibrator != nil {
			calibrated := c.calibrator.Calibrate(name, score)
			envelope.Calibration[name] = CalibrationMetadata{
				Applied:   true,
				Timestamp: time.Now(),
				Method:    "post-hoc",
			}
			score = calibrated
		}

		envelope.Scores[name] = score
	}

	// Add metadata
	envelope.Metadata["encoder"] = c.encoder
	envelope.Metadata["model_name"] = c.name
	envelope.Metadata["num_heads"] = len(c.noulHeads) + len(c.choiceHeads) + len(c.scoreHeads)

	return envelope, nil
}

// PredictBatch produces decision envelopes from batch of inputs
func (c *Classifier) PredictBatch(inputs []interface{}) ([]*primitives.DecisionEnvelope, error) {
	if len(inputs) == 0 {
		return nil, errors.New("inputs cannot be empty")
	}

	results := make([]*primitives.DecisionEnvelope, len(inputs))
	errors := make([]error, len(inputs))
	var wg sync.WaitGroup

	// Parallel batch processing
	for i, input := range inputs {
		wg.Add(1)
		go func(idx int, inp interface{}) {
			defer wg.Done()
			env, err := c.Predict(inp)
			results[idx] = env
			errors[idx] = err
		}(i, input)
	}

	wg.Wait()

	// Check for errors
	for _, err := range errors {
		if err != nil {
			return nil, err
		}
	}

	return results, nil
}

// Math utilities

// dotProduct computes vector dot product
func dotProduct(a, b []float64) float64 {
	if len(a) != len(b) {
		return 0
	}
	result := 0.0
	for i := range a {
		result += a[i] * b[i]
	}
	return result
}

// matVecMul multiplies matrix by vector
func matVecMul(mat [][]float64, vec []float64) []float64 {
	result := make([]float64, len(mat))
	for i, row := range mat {
		result[i] = dotProduct(row, vec)
	}
	return result
}

// sigmoid activation function
func sigmoid(x float64) float64 {
	if x > 500 {
		return 1.0
	}
	if x < -500 {
		return 0.0
	}
	return 1.0 / (1.0 + math.Exp(-x))
}

// softmax normalizes logits to probabilities
func softmax(logits map[string]float64) map[string]float64 {
	probs := make(map[string]float64)

	if len(logits) == 0 {
		return probs
	}

	// Find max for numerical stability
	maxLogit := math.Inf(-1)
	for _, val := range logits {
		if val > maxLogit {
			maxLogit = val
		}
	}

	// Compute exponentials
	sum := 0.0
	for label, logit := range logits {
		expVal := math.Exp(logit - maxLogit)
		probs[label] = expVal
		sum += expVal
	}

	// Normalize
	for label := range probs {
		probs[label] /= sum
	}

	return probs
}

// computeEntropy calculates Shannon entropy
func computeEntropy(probs map[string]float64) float64 {
	entropy := 0.0
	for _, prob := range probs {
		if prob > 0 {
			entropy -= prob * math.Log2(prob)
		}
	}
	return entropy
}

// secondMax finds second highest value in probability map
func secondMax(probs map[string]float64) float64 {
	values := make([]float64, 0, len(probs))
	for _, prob := range probs {
		values = append(values, prob)
	}

	if len(values) < 2 {
		return 0
	}

	sort.Float64s(values)
	return values[len(values)-2]
}

// rankByProbability creates ranked ordering of categories
func rankByProbability(probs map[string]float64) []string {
	type pair struct {
		label string
		prob  float64
	}

	pairs := make([]pair, 0, len(probs))
	for label, prob := range probs {
		pairs = append(pairs, pair{label, prob})
	}

	sort.Slice(pairs, func(i, j int) bool {
		return pairs[i].prob > pairs[j].prob
	})

	result := make([]string, len(pairs))
	for i, p := range pairs {
		result[i] = p.label
	}

	return result
}

// generateRequestID creates a unique request identifier
func generateRequestID() string {
	b := make([]byte, 16)
	_, err := rand.Read(b)
	if err != nil {
		return fmt.Sprintf("req_%d", time.Now().UnixNano())
	}
	return fmt.Sprintf("req_%s", hex.EncodeToString(b))
}

// TemperatureCalibrator scales scores by temperature
type TemperatureCalibrator struct {
	temperature float64
	offsets     map[string]float64
	mu          sync.RWMutex
}

// NewTemperatureCalibrator creates a new temperature calibrator
func NewTemperatureCalibrator(temperature float64) *TemperatureCalibrator {
	if temperature <= 0 {
		temperature = 1.0
	}
	return &TemperatureCalibrator{
		temperature: temperature,
		offsets:     make(map[string]float64),
	}
}

// Calibrate applies temperature scaling
func (tc *TemperatureCalibrator) Calibrate(name string, score *primitives.Score) *primitives.Score {
	tc.mu.RLock()
	defer tc.mu.RUnlock()

	offset := 0.0
	if off, exists := tc.offsets[name]; exists {
		offset = off
	}

	calibrated := &primitives.Score{
		Value:           score.Value / tc.temperature,
		NormalizedValue: sigmoid((score.Logit + offset) / tc.temperature),
		Semantics:       score.Semantics,
		Logit:           (score.Logit + offset) / tc.temperature,
		IsCalibrated:    true,
	}

	return calibrated
}

// SetOffset sets calibration offset for a head
func (tc *TemperatureCalibrator) SetOffset(name string, offset float64) {
	tc.mu.Lock()
	defer tc.mu.Unlock()
	tc.offsets[name] = offset
}

// IsotonicCalibrator uses isotonic regression
type IsotonicCalibrator struct {
	breakpoints map[string][]float64
	values      map[string][]float64
	mu          sync.RWMutex
}

// NewIsotonicCalibrator creates a new isotonic calibrator
func NewIsotonicCalibrator() *IsotonicCalibrator {
	return &IsotonicCalibrator{
		breakpoints: make(map[string][]float64),
		values:      make(map[string][]float64),
	}
}

// Calibrate applies isotonic regression
func (ic *IsotonicCalibrator) Calibrate(name string, score *primitives.Score) *primitives.Score {
	ic.mu.RLock()
	defer ic.mu.RUnlock()

	breakpoints, ok := ic.breakpoints[name]
	if !ok || len(breakpoints) == 0 {
		return score
	}

	values := ic.values[name]

	// Find interpolation points
	logit := score.Logit
	for i, bp := range breakpoints {
		if logit <= bp {
			if i == 0 {
				score.NormalizedValue = values[0]
			} else {
				// Linear interpolation
				prev := breakpoints[i-1]
				alpha := (logit - prev) / (bp - prev)
				score.NormalizedValue = values[i-1]*(1-alpha) + values[i]*alpha
			}
			break
		}
		if i == len(breakpoints)-1 {
			score.NormalizedValue = values[i]
		}
	}

	score.IsCalibrated = true
	return score
}

// AddCalibrationPoint adds a calibration point
func (ic *IsotonicCalibrator) AddCalibrationPoint(name string, logit float64, value float64) {
	ic.mu.Lock()
	defer ic.mu.Unlock()

	ic.breakpoints[name] = append(ic.breakpoints[name], logit)
	ic.values[name] = append(ic.values[name], value)

	// Sort by breakpoints
	if len(ic.breakpoints[name]) > 1 {
		for i := len(ic.breakpoints[name]) - 1; i > 0; i-- {
			if ic.breakpoints[name][i] < ic.breakpoints[name][i-1] {
				ic.breakpoints[name][i], ic.breakpoints[name][i-1] = ic.breakpoints[name][i-1], ic.breakpoints[name][i]
				ic.values[name][i], ic.values[name][i-1] = ic.values[name][i-1], ic.values[name][i]
			}
		}
	}
}

// EnsembleClassifier combines multiple classifiers
type EnsembleClassifier struct {
	classifiers []*Classifier
	weights     []float64
	mu          sync.RWMutex
}

// NewEnsembleClassifier creates a new ensemble classifier
func NewEnsembleClassifier(classifiers []*Classifier, weights []float64) (*EnsembleClassifier, error) {
	if len(classifiers) == 0 {
		return nil, errors.New("ensemble requires at least one classifier")
	}

	if len(weights) != len(classifiers) {
		weights = make([]float64, len(classifiers))
		for i := range weights {
			weights[i] = 1.0 / float64(len(classifiers))
		}
	}

	// Normalize weights
	sum := 0.0
	for _, w := range weights {
		sum += w
	}
	for i := range weights {
		weights[i] /= sum
	}

	return &EnsembleClassifier{
		classifiers: classifiers,
		weights:     weights,
	}, nil
}

// Predict produces ensemble decision
func (ec *EnsembleClassifier) Predict(input interface{}) (*primitives.DecisionEnvelope, error) {
	ec.mu.RLock()
	defer ec.mu.RUnlock()

	envelopes := make([]*primitives.DecisionEnvelope, len(ec.classifiers))
	var wg sync.WaitGroup

	for i, classifier := range ec.classifiers {
		wg.Add(1)
		go func(idx int, clf *Classifier) {
			defer wg.Done()
			env, _ := clf.Predict(input)
			envelopes[idx] = env
		}(i, classifier)
	}

	wg.Wait()

	// Aggregate results
	result := &primitives.DecisionEnvelope{
		RequestID:   generateRequestID(),
		Timestamp:   time.Now(),
		Nouls:       make(map[string]*primitives.Noul),
		Choices:     make(map[string]*primitives.Choice),
		Scores:      make(map[string]*primitives.Score),
		Calibration: make(map[string]CalibrationMetadata),
		Metadata:    make(map[string]interface{}),
	}

	// Aggregate Nouls
	noulCounts := make(map[string]int)
	noulProbs := make(map[string]float64)

	for _, env := range envelopes {
		for name, noul := range env.Nouls {
			noulCounts[name]++
			noulProbs[name] += noul.Probability
		}
	}

	for name, count := range noulCounts {
		if count > 0 {
			avgProb := noulProbs[name] / float64(count)
			decision := "NO"
			if avgProb >= 0.5 {
				decision = "YES"
			}
			result.Nouls[name] = &primitives.Noul{
				Decision:    decision,
				Probability: avgProb,
				Logit:       math.Log(avgProb / (1 - avgProb)),
				Margin:      math.Abs(2*avgProb - 1),
				Threshold:   0.5,
			}
		}
	}

	// Aggregate Choices
	choiceVotes := make(map[string]map[string]float64)

	for _, env := range envelopes {
		for name, choice := range env.Choices {
			if choiceVotes[name] == nil {
				choiceVotes[name] = make(map[string]float64)
			}
			for label, prob := range choice.Probabilities {
				choiceVotes[name][label] += prob * ec.weights[len(envelopes)]
			}
		}
	}

	for name, votes := range choiceVotes {
		normalized := votes
		result.Choices[name] = &primitives.Choice{
			Selected:      findMaxKey(normalized),
			Probabilities: normalized,
			Logits:        make(map[string]float64),
			Rank:          rankByProbability(normalized),
			Entropy:       computeEntropy(normalized),
			Margin:        secondMax(normalized),
			Threshold:     0.0,
		}
	}

	// Aggregate Scores
	scoreAggregates := make(map[string]float64)
	scoreCount := make(map[string]int)

	for i, env := range envelopes {
		for name, score := range env.Scores {
			scoreAggregates[name] += score.NormalizedValue * ec.weights[i]
			scoreCount[name]++
		}
	}

	for name, aggregate := range scoreAggregates {
		if scoreCount[name] > 0 {
			result.Scores[name] = &primitives.Score{
				Value:           aggregate,
				NormalizedValue: aggregate,
				Semantics:       "ensemble",
				Logit:           aggregate,
				IsCalibrated:    false,
			}
		}
	}

	result.Metadata["ensemble_size"] = len(ec.classifiers)
	result.Metadata["aggregation"] = "weighted-mean"

	return result, nil
}

// findMaxKey returns the key with maximum value in map
func findMaxKey(m map[string]float64) string {
	var maxKey string
	maxVal := math.Inf(-1)
	for key, val := range m {
		if val > maxVal {
			maxVal = val
			maxKey = key
		}
	}
	return maxKey
}

// ValidationMetrics tracks classifier performance
type ValidationMetrics struct {
	Accuracy      float64
	Precision     map[string]float64
	Recall        map[string]float64
	F1Score       map[string]float64
	ConfusionMat  map[string]map[string]int
	CalibrationErr float64
	Timestamp     time.Time
}

// MetricsCollector collects validation metrics
type MetricsCollector struct {
	predictions []string
	actuals     []string
	confidences []float64
	mu          sync.RWMutex
}

// NewMetricsCollector creates a new metrics collector
func NewMetricsCollector() *MetricsCollector {
	return &MetricsCollector{
		predictions: make([]string, 0),
		actuals:     make([]string, 0),
		confidences: make([]float64, 0),
	}
}

// AddPrediction records a prediction
func (mc *MetricsCollector) AddPrediction(predicted string, actual string, confidence float64) {
	mc.mu.Lock()
	defer mc.mu.Unlock()
	mc.predictions = append(mc.predictions, predicted)
	mc.actuals = append(mc.actuals, actual)
	mc.confidences = append(mc.confidences, confidence)
}

// ComputeMetrics calculates validation metrics
func (mc *MetricsCollector) ComputeMetrics() *ValidationMetrics {
	mc.mu.RLock()
	defer mc.mu.RUnlock()

	if len(mc.predictions) == 0 {
		return &ValidationMetrics{Timestamp: time.Now()}
	}

	metrics := &ValidationMetrics{
		Precision:    make(map[string]float64),
		Recall:       make(map[string]float64),
		F1Score:      make(map[string]float64),
		ConfusionMat: make(map[string]map[string]int),
		Timestamp:    time.Now(),
	}

	// Compute accuracy
	correct := 0
	for i := range mc.predictions {
		if mc.predictions[i] == mc.actuals[i] {
			correct++
		}
	}
	metrics.Accuracy = float64(correct) / float64(len(mc.predictions))

	// Initialize confusion matrix
	labels := make(map[string]bool)
	for _, label := range mc.actuals {
		labels[label] = true
	}
	for label := range labels {
		metrics.ConfusionMat[label] = make(map[string]int)
		for l := range labels {
			metrics.ConfusionMat[label][l] = 0
		}
	}

	// Fill confusion matrix
	for i := range mc.predictions {
		pred := mc.predictions[i]
		actual := mc.actuals[i]
		if _, ok := metrics.ConfusionMat[actual]; !ok {
			metrics.ConfusionMat[actual] = make(map[string]int)
		}
		metrics.ConfusionMat[actual][pred]++
	}

	// Compute precision, recall, F1
	for label := range labels {
		tp := metrics.ConfusionMat[label][label]
		fp := 0
		fn := 0

		for _, pred := range metrics.ConfusionMat[label] {
			for predictedLabel := range metrics.ConfusionMat {
				if predictedLabel != label {
					fp += metrics.ConfusionMat[predictedLabel][label]
				}
			}
		}

		for predictedLabel := range metrics.ConfusionMat[label] {
			if predictedLabel != label {
				fn += metrics.ConfusionMat[label][predictedLabel]
			}
		}

		precision := 0.0
		if tp+fp > 0 {
			precision = float64(tp) / float64(tp+fp)
		}
		metrics.Precision[label] = precision

		recall := 0.0
		if tp+fn > 0 {
			recall = float64(tp) / float64(tp+fn)
		}
		metrics.Recall[label] = recall

		f1 := 0.0
		if precision+recall > 0 {
			f1 = 2 * (precision * recall) / (precision + recall)
		}
		metrics.F1Score[label] = f1
	}

	// Compute calibration error
	calibErr := 0.0
	for i := range mc.predictions {
		if mc.predictions[i] == mc.actuals[i] {
			calibErr += (1.0 - mc.confidences[i]) * (1.0 - mc.confidences[i])
		} else {
			calibErr += mc.confidences[i] * mc.confidences[i]
		}
	}
	metrics.CalibrationErr = math.Sqrt(calibErr / float64(len(mc.predictions)))

	return metrics
}
