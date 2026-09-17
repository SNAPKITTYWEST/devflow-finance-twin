package api

import (
	"crypto/sha256"
	"fmt"
	"time"

	"devflow-finance-twin/classifier/primitives"
)

// Classifier API: minimal public interface
type Classifier interface {
	Predict(input interface{}) (*primitives.DecisionEnvelope, error)
	PredictBatch(inputs []interface{}) ([]*primitives.DecisionEnvelope, error)
	SetBackend(backend string) error
}

// Router API: deterministic routing based on decision envelope
type Router interface {
	Route(decision *primitives.DecisionEnvelope) error
	Validate() error
}

// ClassifierConfig holds classifier configuration
type ClassifierConfig struct {
	ModelID      string
	ModelVersion string
	Backend      string
	MaxBatchSize int
}

// DefaultRouter is a basic router implementation
type DefaultRouter struct {
	name      string
	validated bool
}

// NewDefaultRouter creates a new default router
func NewDefaultRouter(name string) *DefaultRouter {
	return &DefaultRouter{
		name:      name,
		validated: false,
	}
}

// Route implements the Router interface
func (r *DefaultRouter) Route(decision *primitives.DecisionEnvelope) error {
	if decision == nil {
		return fmt.Errorf("route: nil decision envelope")
	}

	// Compute route hash for auditability
	h := sha256.New()
	h.Write([]byte(fmt.Sprintf("%s:%s:%s", decision.ModelID, decision.Disposition, r.name)))
	decision.RouterHash = fmt.Sprintf("%x", h.Sum(nil))

	// Set route based on disposition
	if decision.Disposition == "" {
		decision.Route = "ABSTAIN"
	} else {
		decision.Route = fmt.Sprintf("DISPATCH(%s)", decision.Disposition)
	}

	decision.Timestamp = time.Now().Unix()
	return nil
}

// Validate implements the Router interface
func (r *DefaultRouter) Validate() error {
	if r.name == "" {
		return fmt.Errorf("route: router name required")
	}
	r.validated = true
	return nil
}

// DecisionEnvelopeHelper provides accessor methods for DecisionEnvelope
type DecisionEnvelopeHelper struct {
	envelope *primitives.DecisionEnvelope
}

// NewDecisionEnvelopeHelper creates a new helper
func NewDecisionEnvelopeHelper(envelope *primitives.DecisionEnvelope) *DecisionEnvelopeHelper {
	return &DecisionEnvelopeHelper{envelope: envelope}
}

// Noul returns the Noul choice by name
func (dh *DecisionEnvelopeHelper) Noul(name string) *primitives.NoulChoice {
	if dh.envelope == nil {
		return nil
	}
	for _, nc := range dh.envelope.NoulChoices {
		if nc.Name == name {
			return nc
		}
	}
	return nil
}

// Choice returns the RouteChoice by name
func (dh *DecisionEnvelopeHelper) Choice(name string) *primitives.RouteChoice {
	if dh.envelope == nil {
		return nil
	}
	for _, rc := range dh.envelope.RouteChoices {
		if rc.Name == name {
			return rc
		}
	}
	return nil
}

// Score returns the score from CalibrationMetadata
func (dh *DecisionEnvelopeHelper) Score(key string) *CalibratedScore {
	if dh.envelope == nil || dh.envelope.CalibrationMetadata == nil {
		return &CalibratedScore{NormalizedValue: 0.0}
	}

	val, ok := dh.envelope.CalibrationMetadata[key]
	if !ok {
		return &CalibratedScore{NormalizedValue: 0.0}
	}

	if score, ok := val.(float64); ok {
		return &CalibratedScore{NormalizedValue: score}
	}

	return &CalibratedScore{NormalizedValue: 0.0}
}

// CalibratedScore represents a calibrated numeric score
type CalibratedScore struct {
	NormalizedValue float64
}

// NoulDecision represents a YES/NO decision
type NoulDecision struct {
	IsYes bool
}

// IsYes returns true if the Noul decision is YES
func (nd *primitives.NoulChoice) IsYes() bool {
	return nd.Decision == "YES"
}

// IsNo returns true if the Noul decision is NO
func (nd *primitives.NoulChoice) IsNo() bool {
	return nd.Decision == "NO"
}

// ConsistencyResult holds validation results
type ConsistencyResult struct {
	Valid   bool
	Message string
	Errors  []string
}

// BatchPredictRequest holds a batch prediction request
type BatchPredictRequest struct {
	Inputs       []interface{}
	MaxConcurrent int
}

// BatchPredictResponse holds batch prediction results
type BatchPredictResponse struct {
	Results   []*primitives.DecisionEnvelope
	Errors    []error
	Timestamp int64
}
