package model

import (
	"devflow-finance-twin/classifier/primitives"
)

// Classifier interface defines the core classification contract
type Classifier interface {
	Predict(input interface{}) (*primitives.DecisionEnvelope, error)
	PredictWithContext(input interface{}, context map[string]interface{}) (*primitives.DecisionEnvelope, error)
	GetModelMetadata() *primitives.ModelMetadata
}

// Head represents a classification head (Noul)
type Head interface {
	Classify(encoding []float64) (*primitives.NoulChoice, error)
	Name() string
}

// DefaultClassifier is a basic implementation
type DefaultClassifier struct {
	metadata *primitives.ModelMetadata
	heads    map[string]Head
	router   Router
}

// Router interface for routing logic
type Router interface {
	Route(encoding []float64) (string, []*primitives.RouteChoice, error)
}

// NewDefaultClassifier creates a new default classifier
func NewDefaultClassifier(
	metadata *primitives.ModelMetadata,
	heads map[string]Head,
	router Router,
) *DefaultClassifier {
	return &DefaultClassifier{
		metadata: metadata,
		heads:    heads,
		router:   router,
	}
}

// Predict makes a prediction on a single input
func (c *DefaultClassifier) Predict(input interface{}) (*primitives.DecisionEnvelope, error) {
	return c.PredictWithContext(input, make(map[string]interface{}))
}

// PredictWithContext makes a prediction with additional context
func (c *DefaultClassifier) PredictWithContext(
	input interface{},
	context map[string]interface{},
) (*primitives.DecisionEnvelope, error) {
	// Encode input
	encoding, err := encodeInput(input)
	if err != nil {
		return nil, err
	}

	// Route decision
	route, routeChoices, err := c.router.Route(encoding)
	if err != nil {
		return nil, err
	}

	// Execute heads
	noulChoices := make([]*primitives.NoulChoice, 0, len(c.heads))
	for _, head := range c.heads {
		choice, err := head.Classify(encoding)
		if err != nil {
			return nil, err
		}
		noulChoices = append(noulChoices, choice)
	}

	// Assemble envelope
	envelope := &primitives.DecisionEnvelope{
		ModelID:      c.metadata.ModelID,
		ModelVersion: c.metadata.ModelVersion,
		RouteChoices: routeChoices,
		NoulChoices:  noulChoices,
		Route:        route,
		Thresholds:   make(map[string]float64),
	}

	if len(noulChoices) > 0 {
		envelope.Disposition = noulChoices[0].Decision
	}

	return envelope, nil
}

// GetModelMetadata returns model metadata
func (c *DefaultClassifier) GetModelMetadata() *primitives.ModelMetadata {
	return c.metadata
}

// encodeInput performs basic input encoding
func encodeInput(input interface{}) ([]float64, error) {
	// Basic implementation - would use actual encoder in practice
	switch v := input.(type) {
	case []float64:
		return v, nil
	default:
		return []float64{}, nil
	}
}
