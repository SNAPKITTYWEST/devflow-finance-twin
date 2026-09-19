package model

import (
	"devflow-finance-twin/classifier/primitives"
	"errors"
	"fmt"
	"math"
	"sort"
	"sync"
	"time"
)

// AdvancedFeatureExtractor performs feature engineering
type AdvancedFeatureExtractor struct {
	transformations []FeatureTransformation
	mu              sync.RWMutex
}

// FeatureTransformation applies a transformation to features
type FeatureTransformation interface {
	Transform(features []float64) []float64
	Name() string
}

// PolynomialFeatureTransformation creates polynomial features
type PolynomialFeatureTransformation struct {
	degree int
	name   string
}

// NewPolynomialFeatureTransformation creates polynomial transformer
func NewPolynomialFeatureTransformation(degree int) *PolynomialFeatureTransformation {
	return &PolynomialFeatureTransformation{
		degree: degree,
		name:   fmt.Sprintf("polynomial_degree_%d", degree),
	}
}

// Transform creates polynomial features
func (pft *PolynomialFeatureTransformation) Transform(features []float64) []float64 {
	if len(features) == 0 || pft.degree <= 0 {
		return features
	}

	output := make([]float64, 0)
	output = append(output, features...)

	for d := 2; d <= pft.degree; d++ {
		for _, feat := range features {
			val := feat
			for i := 1; i < d; i++ {
				val *= feat
			}
			output = append(output, val)
		}
	}

	return output
}

// Name returns transformer name
func (pft *PolynomialFeatureTransformation) Name() string {
	return pft.name
}

// NormalizationTransformation normalizes features
type NormalizationTransformation struct {
	means   []float64
	stds    []float64
	fitted  bool
	name    string
}

// NewNormalizationTransformation creates normalization transformer
func NewNormalizationTransformation() *NormalizationTransformation {
	return &NormalizationTransformation{
		name: "normalization",
	}
}

// Fit computes normalization statistics
func (nt *NormalizationTransformation) Fit(features [][]float64) error {
	if len(features) == 0 {
		return errors.New("features cannot be empty")
	}

	dimLen := len(features[0])
	nt.means = make([]float64, dimLen)
	nt.stds = make([]float64, dimLen)

	// Compute means
	for _, feat := range features {
		for i, f := range feat {
			nt.means[i] += f
		}
	}
	for i := range nt.means {
		nt.means[i] /= float64(len(features))
	}

	// Compute standard deviations
	for _, feat := range features {
		for i, f := range feat {
			diff := f - nt.means[i]
			nt.stds[i] += diff * diff
		}
	}
	for i := range nt.stds {
		nt.stds[i] = math.Sqrt(nt.stds[i] / float64(len(features)))
		if nt.stds[i] == 0 {
			nt.stds[i] = 1.0
		}
	}

	nt.fitted = true
	return nil
}

// Transform normalizes features
func (nt *NormalizationTransformation) Transform(features []float64) []float64 {
	if !nt.fitted || len(nt.means) != len(features) {
		return features
	}

	output := make([]float64, len(features))
	for i, f := range features {
		output[i] = (f - nt.means[i]) / nt.stds[i]
	}

	return output
}

// Name returns transformer name
func (nt *NormalizationTransformation) Name() string {
	return nt.name
}

// NewAdvancedFeatureExtractor creates feature extractor
func NewAdvancedFeatureExtractor() *AdvancedFeatureExtractor {
	return &AdvancedFeatureExtractor{
		transformations: make([]FeatureTransformation, 0),
	}
}

// AddTransformation adds a feature transformation
func (afe *AdvancedFeatureExtractor) AddTransformation(transform FeatureTransformation) {
	afe.mu.Lock()
	defer afe.mu.Unlock()
	afe.transformations = append(afe.transformations, transform)
}

// Extract applies all transformations
func (afe *AdvancedFeatureExtractor) Extract(features []float64) []float64 {
	afe.mu.RLock()
	defer afe.mu.RUnlock()

	result := features
	for _, transform := range afe.transformations {
		result = transform.Transform(result)
	}

	return result
}

// AttentionHead applies attention mechanism
type AttentionHead struct {
	queryWeight  []float64
	keyWeight    []float64
	valueWeight  []float64
	scaleFactor  float64
	name         string
}

// NewAttentionHead creates attention head
func NewAttentionHead(name string, dim int) *AttentionHead {
	return &AttentionHead{
		queryWeight: make([]float64, dim),
		keyWeight:   make([]float64, dim),
		valueWeight: make([]float64, dim),
		scaleFactor: 1.0 / math.Sqrt(float64(dim)),
		name:        name,
	}
}

// Forward computes attention
func (ah *AttentionHead) Forward(hidden []float64, context [][]float64) []float64 {
	if len(hidden) == 0 || len(context) == 0 {
		return hidden
	}

	query := dotProduct(hidden, ah.queryWeight)
	scores := make([]float64, len(context))

	for i, ctx := range context {
		key := dotProduct(ctx, ah.keyWeight)
		scores[i] = (query * key) * ah.scaleFactor
	}

	// Softmax on scores
	maxScore := scores[0]
	for _, s := range scores {
		if s > maxScore {
			maxScore = s
		}
	}

	expScores := make([]float64, len(scores))
	sumExp := 0.0
	for i, s := range scores {
		expScores[i] = math.Exp(s - maxScore)
		sumExp += expScores[i]
	}

	attention := make([]float64, len(scores))
	for i := range attention {
		attention[i] = expScores[i] / sumExp
	}

	// Weighted sum of values
	result := make([]float64, len(hidden))
	for i, ctx := range context {
		value := dotProduct(ctx, ah.valueWeight)
		for j := range result {
			result[j] += attention[i] * value
		}
	}

	return result
}

// ModelRegistry manages multiple models
type ModelRegistry struct {
	models map[string]*Classifier
	mu     sync.RWMutex
}

// NewModelRegistry creates model registry
func NewModelRegistry() *ModelRegistry {
	return &ModelRegistry{
		models: make(map[string]*Classifier),
	}
}

// Register adds a model to registry
func (mr *ModelRegistry) Register(name string, classifier *Classifier) error {
	if name == "" {
		return errors.New("model name cannot be empty")
	}
	if classifier == nil {
		return errors.New("classifier cannot be nil")
	}

	mr.mu.Lock()
	defer mr.mu.Unlock()
	mr.models[name] = classifier
	return nil
}

// Get retrieves a model from registry
func (mr *ModelRegistry) Get(name string) (*Classifier, error) {
	mr.mu.RLock()
	defer mr.mu.RUnlock()

	classifier, ok := mr.models[name]
	if !ok {
		return nil, fmt.Errorf("model '%s' not found in registry", name)
	}

	return classifier, nil
}

// List returns all registered model names
func (mr *ModelRegistry) List() []string {
	mr.mu.RLock()
	defer mr.mu.RUnlock()

	names := make([]string, 0, len(mr.models))
	for name := range mr.models {
		names = append(names, name)
	}

	sort.Strings(names)
	return names
}

// Remove deletes a model from registry
func (mr *ModelRegistry) Remove(name string) error {
	mr.mu.Lock()
	defer mr.mu.Unlock()

	if _, ok := mr.models[name]; !ok {
		return fmt.Errorf("model '%s' not found", name)
	}

	delete(mr.models, name)
	return nil
}

// Count returns number of registered models
func (mr *ModelRegistry) Count() int {
	mr.mu.RLock()
	defer mr.mu.RUnlock()
	return len(mr.models)
}

// PredictionCache caches predictions for inputs
type PredictionCache struct {
	cache   map[string]*primitives.DecisionEnvelope
	ttl     map[string]time.Time
	maxSize int
	mu      sync.RWMutex
}

// NewPredictionCache creates prediction cache
func NewPredictionCache(maxSize int) *PredictionCache {
	return &PredictionCache{
		cache:   make(map[string]*primitives.DecisionEnvelope),
		ttl:     make(map[string]time.Time),
		maxSize: maxSize,
	}
}

// Get retrieves cached prediction
func (pc *PredictionCache) Get(key string) (*primitives.DecisionEnvelope, bool) {
	pc.mu.RLock()
	defer pc.mu.RUnlock()

	envelope, ok := pc.cache[key]
	if !ok {
		return nil, false
	}

	if time.Now().After(pc.ttl[key]) {
		return nil, false
	}

	return envelope, true
}

// Set stores prediction in cache
func (pc *PredictionCache) Set(key string, envelope *primitives.DecisionEnvelope, ttl time.Duration) {
	pc.mu.Lock()
	defer pc.mu.Unlock()

	if len(pc.cache) >= pc.maxSize {
		// Remove oldest entry
		oldestKey := ""
		oldestTime := time.Now()
		for k, t := range pc.ttl {
			if t.Before(oldestTime) {
				oldestTime = t
				oldestKey = k
			}
		}
		if oldestKey != "" {
			delete(pc.cache, oldestKey)
			delete(pc.ttl, oldestKey)
		}
	}

	pc.cache[key] = envelope
	pc.ttl[key] = time.Now().Add(ttl)
}

// Clear clears all cached predictions
func (pc *PredictionCache) Clear() {
	pc.mu.Lock()
	defer pc.mu.Unlock()
	pc.cache = make(map[string]*primitives.DecisionEnvelope)
	pc.ttl = make(map[string]time.Time)
}

// Size returns cache size
func (pc *PredictionCache) Size() int {
	pc.mu.RLock()
	defer pc.mu.RUnlock()
	return len(pc.cache)
}

// ClassifierValidator validates classifier correctness
type ClassifierValidator struct {
	testCases []ValidationCase
	mu        sync.RWMutex
}

// ValidationCase is a test case for validation
type ValidationCase struct {
	Input          interface{}
	ExpectedNoul   string
	ExpectedChoice string
	MinProbability float64
}

// NewClassifierValidator creates validator
func NewClassifierValidator() *ClassifierValidator {
	return &ClassifierValidator{
		testCases: make([]ValidationCase, 0),
	}
}

// AddTestCase adds a validation test case
func (cv *ClassifierValidator) AddTestCase(testCase ValidationCase) {
	cv.mu.Lock()
	defer cv.mu.Unlock()
	cv.testCases = append(cv.testCases, testCase)
}

// Validate runs all test cases
func (cv *ClassifierValidator) Validate(classifier *Classifier) (bool, []string) {
	cv.mu.RLock()
	defer cv.mu.RUnlock()

	errors := make([]string, 0)
	for i, testCase := range cv.testCases {
		envelope, err := classifier.Predict(testCase.Input)
		if err != nil {
			errors = append(errors, fmt.Sprintf("test %d: prediction failed: %v", i, err))
			continue
		}

		if testCase.ExpectedNoul != "" {
			for _, noul := range envelope.Nouls {
				if noul.Decision != testCase.ExpectedNoul && noul.Probability < testCase.MinProbability {
					errors = append(errors, fmt.Sprintf("test %d: noul decision mismatch", i))
				}
			}
		}

		if testCase.ExpectedChoice != "" {
			for _, choice := range envelope.Choices {
				if choice.Selected != testCase.ExpectedChoice && choice.Probabilities[choice.Selected] < testCase.MinProbability {
					errors = append(errors, fmt.Sprintf("test %d: choice mismatch", i))
				}
			}
		}
	}

	return len(errors) == 0, errors
}

// AdaptiveThresholdOptimizer optimizes decision thresholds
type AdaptiveThresholdOptimizer struct {
	historicalProbs []float64
	historicalTrue  []bool
	mu              sync.RWMutex
}

// NewAdaptiveThresholdOptimizer creates optimizer
func NewAdaptiveThresholdOptimizer() *AdaptiveThresholdOptimizer {
	return &AdaptiveThresholdOptimizer{
		historicalProbs: make([]float64, 0),
		historicalTrue:  make([]bool, 0),
	}
}

// RecordPrediction records a prediction and outcome
func (ato *AdaptiveThresholdOptimizer) RecordPrediction(probability float64, trueLabel bool) {
	ato.mu.Lock()
	defer ato.mu.Unlock()
	ato.historicalProbs = append(ato.historicalProbs, probability)
	ato.historicalTrue = append(ato.historicalTrue, trueLabel)
}

// OptimizeThreshold computes optimal threshold
func (ato *AdaptiveThresholdOptimizer) OptimizeThreshold(metric string) float64 {
	ato.mu.RLock()
	defer ato.mu.RUnlock()

	if len(ato.historicalProbs) == 0 {
		return 0.5
	}

	bestThreshold := 0.5
	bestScore := math.Inf(-1)

	for t := 0.0; t <= 1.0; t += 0.01 {
		tp, fp, fn := 0, 0, 0

		for i, prob := range ato.historicalProbs {
			predicted := prob >= t
			actual := ato.historicalTrue[i]

			if predicted && actual {
				tp++
			} else if predicted && !actual {
				fp++
			} else if !predicted && actual {
				fn++
			}
		}

		var score float64
		if metric == "f1" {
			if tp+fp == 0 || tp+fn == 0 {
				score = 0
			} else {
				precision := float64(tp) / float64(tp+fp)
				recall := float64(tp) / float64(tp+fn)
				if precision+recall > 0 {
					score = 2 * (precision * recall) / (precision + recall)
				}
			}
		} else if metric == "accuracy" {
			tn := len(ato.historicalTrue) - tp - fp - fn
			score = float64(tp+tn) / float64(len(ato.historicalTrue))
		}

		if score > bestScore {
			bestScore = score
			bestThreshold = t
		}
	}

	return bestThreshold
}

// ExplainabilityReport generates model explanations
type ExplainabilityReport struct {
	FeatureImportance    map[string]float64
	ContributingFeatures []string
	DecisionPath         string
	ConfidenceFactors    []string
	Timestamp            time.Time
}

// ExplainabilityEngine generates explanations
type ExplainabilityEngine struct {
	featureNames []string
	mu           sync.RWMutex
}

// NewExplainabilityEngine creates explanation engine
func NewExplainabilityEngine(featureNames []string) *ExplainabilityEngine {
	return &ExplainabilityEngine{
		featureNames: featureNames,
	}
}

// Explain generates explanation for prediction
func (ee *ExplainabilityEngine) Explain(input []float64, envelope *primitives.DecisionEnvelope, weights []float64) *ExplainabilityReport {
	ee.mu.RLock()
	defer ee.mu.RUnlock()

	report := &ExplainabilityReport{
		FeatureImportance:    make(map[string]float64),
		ContributingFeatures: make([]string, 0),
		ConfidenceFactors:    make([]string, 0),
		Timestamp:            time.Now(),
	}

	// Compute feature importance
	if len(input) == len(weights) {
		for i, val := range input {
			importance := math.Abs(val * weights[i])
			if i < len(ee.featureNames) {
				report.FeatureImportance[ee.featureNames[i]] = importance
			}
		}
	}

	// Find top contributing features
	type feat struct {
		name       string
		importance float64
	}
	features := make([]feat, 0)
	for name, imp := range report.FeatureImportance {
		features = append(features, feat{name, imp})
	}
	sort.Slice(features, func(i, j int) bool {
		return features[i].importance > features[j].importance
	})

	for i := 0; i < 3 && i < len(features); i++ {
		report.ContributingFeatures = append(report.ContributingFeatures, features[i].name)
	}

	// Generate confidence factors
	totalNouls := len(envelope.Nouls)
	if totalNouls > 0 {
		report.ConfidenceFactors = append(report.ConfidenceFactors, fmt.Sprintf("Binary decisions: %d heads", totalNouls))
	}

	totalChoices := len(envelope.Choices)
	if totalChoices > 0 {
		report.ConfidenceFactors = append(report.ConfidenceFactors, fmt.Sprintf("Categorical decisions: %d heads", totalChoices))
	}

	totalScores := len(envelope.Scores)
	if totalScores > 0 {
		report.ConfidenceFactors = append(report.ConfidenceFactors, fmt.Sprintf("Score outputs: %d heads", totalScores))
	}

	return report
}

// InferenceContext manages inference state
type InferenceContext struct {
	classifier *Classifier
	cache      *PredictionCache
	validator  *ClassifierValidator
	registry   *ModelRegistry
	metrics    *MetricsCollector
	explainer  *ExplainabilityEngine
	mu         sync.RWMutex
}

// NewInferenceContext creates inference context
func NewInferenceContext(classifier *Classifier, cacheSize int) *InferenceContext {
	return &InferenceContext{
		classifier: classifier,
		cache:      NewPredictionCache(cacheSize),
		validator:  NewClassifierValidator(),
		registry:   NewModelRegistry(),
		metrics:    NewMetricsCollector(),
	}
}

// PredictWithCache predicts with caching
func (ic *InferenceContext) PredictWithCache(input interface{}, key string, ttl time.Duration) (*primitives.DecisionEnvelope, error) {
	ic.mu.RLock()
	defer ic.mu.RUnlock()

	if cached, ok := ic.cache.Get(key); ok {
		return cached, nil
	}

	envelope, err := ic.classifier.Predict(input)
	if err != nil {
		return nil, err
	}

	ic.cache.Set(key, envelope, ttl)
	return envelope, nil
}

// GetMetrics returns current metrics
func (ic *InferenceContext) GetMetrics() *ValidationMetrics {
	ic.mu.RLock()
	defer ic.mu.RUnlock()
	return ic.metrics.ComputeMetrics()
}

// BatchPredictWithValidation runs batch prediction with validation
func (ic *InferenceContext) BatchPredictWithValidation(inputs []interface{}) ([]*primitives.DecisionEnvelope, []error) {
	ic.mu.RLock()
	defer ic.mu.RUnlock()

	results := make([]*primitives.DecisionEnvelope, len(inputs))
	errors := make([]error, len(inputs))

	for i, input := range inputs {
		envelope, err := ic.classifier.Predict(input)
		results[i] = envelope
		errors[i] = err
	}

	return results, errors
}

// HyperparameterTuner tunes model hyperparameters
type HyperparameterTuner struct {
	gridParams map[string][]interface{}
	bestParams map[string]interface{}
	bestScore  float64
	mu         sync.RWMutex
}

// NewHyperparameterTuner creates tuner
func NewHyperparameterTuner() *HyperparameterTuner {
	return &HyperparameterTuner{
		gridParams: make(map[string][]interface{}),
		bestParams: make(map[string]interface{}),
		bestScore:  math.Inf(-1),
	}
}

// AddParameterGrid adds parameter grid for tuning
func (ht *HyperparameterTuner) AddParameterGrid(paramName string, values []interface{}) {
	ht.mu.Lock()
	defer ht.mu.Unlock()
	ht.gridParams[paramName] = values
}

// GetBestParameters returns best found parameters
func (ht *HyperparameterTuner) GetBestParameters() map[string]interface{} {
	ht.mu.RLock()
	defer ht.mu.RUnlock()

	result := make(map[string]interface{})
	for k, v := range ht.bestParams {
		result[k] = v
	}

	return result
}

// UpdateBestScore updates best score
func (ht *HyperparameterTuner) UpdateBestScore(score float64, params map[string]interface{}) {
	ht.mu.Lock()
	defer ht.mu.Unlock()

	if score > ht.bestScore {
		ht.bestScore = score
		ht.bestParams = make(map[string]interface{})
		for k, v := range params {
			ht.bestParams[k] = v
		}
	}
}

// PredictionAnomalyDetector detects anomalies in predictions
type PredictionAnomalyDetector struct {
	baselines map[string]float64
	thresholds map[string]float64
	mu         sync.RWMutex
}

// NewPredictionAnomalyDetector creates anomaly detector
func NewPredictionAnomalyDetector() *PredictionAnomalyDetector {
	return &PredictionAnomalyDetector{
		baselines:  make(map[string]float64),
		thresholds: make(map[string]float64),
	}
}

// SetBaseline sets baseline for a metric
func (pad *PredictionAnomalyDetector) SetBaseline(metric string, baseline float64) {
	pad.mu.Lock()
	defer pad.mu.Unlock()
	pad.baselines[metric] = baseline
	pad.thresholds[metric] = baseline * 0.1 // 10% threshold by default
}

// IsAnomaly checks if value is anomalous
func (pad *PredictionAnomalyDetector) IsAnomaly(metric string, value float64) bool {
	pad.mu.RLock()
	defer pad.mu.RUnlock()

	baseline, ok := pad.baselines[metric]
	if !ok {
		return false
	}

	threshold, _ := pad.thresholds[metric]
	diff := math.Abs(value - baseline)

	return diff > threshold
}

// GetAnomalies returns anomalous predictions
func (pad *PredictionAnomalyDetector) GetAnomalies(envelope *primitives.DecisionEnvelope) []string {
	pad.mu.RLock()
	defer pad.mu.RUnlock()

	anomalies := make([]string, 0)

	for name, noul := range envelope.Nouls {
		if baseline, ok := pad.baselines[name]; ok {
			threshold := pad.thresholds[name]
			if math.Abs(noul.Probability-baseline) > threshold {
				anomalies = append(anomalies, fmt.Sprintf("Noul %s anomaly", name))
			}
		}
	}

	return anomalies
}
