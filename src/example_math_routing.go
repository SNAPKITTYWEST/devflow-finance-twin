package api

import (
	"fmt"

	"devflow-finance-twin/classifier/primitives"
)

// MathRoutingClassifier routes requests to mathematical reasoning engines
// Example: "Determine whether this request should be routed to the mathematical reasoning engine."
type MathRoutingClassifier struct {
	classifier Classifier
	router     Router
	config     *ClassifierConfig
}

// NewMathRoutingClassifier creates a new math routing classifier
func NewMathRoutingClassifier(classifier Classifier, router Router) *MathRoutingClassifier {
	return &MathRoutingClassifier{
		classifier: classifier,
		router:     router,
		config:     &ClassifierConfig{},
	}
}

// Classify takes a request string and routes it to appropriate handler
// Returns route destination or error
func (m *MathRoutingClassifier) Classify(request string) (string, error) {
	if request == "" {
		return "", fmt.Errorf("classify: empty request")
	}

	// Step 1: Predict
	envelope, err := m.classifier.Predict(request)
	if err != nil {
		return "", fmt.Errorf("classify: prediction failed: %w", err)
	}

	if envelope == nil {
		return "", fmt.Errorf("classify: nil decision envelope")
	}

	// Step 2: Route
	err = m.router.Route(envelope)
	if err != nil {
		return "", fmt.Errorf("classify: routing failed: %w", err)
	}

	// Step 3: Return route
	return envelope.Route, nil
}

// ClassifyWithMetadata takes a request and returns full decision metadata
func (m *MathRoutingClassifier) ClassifyWithMetadata(request string) (*primitives.DecisionEnvelope, error) {
	if request == "" {
		return nil, fmt.Errorf("classify_with_metadata: empty request")
	}

	envelope, err := m.classifier.Predict(request)
	if err != nil {
		return nil, err
	}

	err = m.router.Route(envelope)
	if err != nil {
		return nil, err
	}

	return envelope, nil
}

// ClassifyBatch processes multiple requests
func (m *MathRoutingClassifier) ClassifyBatch(requests []string) ([]string, error) {
	if len(requests) == 0 {
		return []string{}, nil
	}

	inputs := make([]interface{}, len(requests))
	for i, req := range requests {
		inputs[i] = req
	}

	envelopes, err := m.classifier.PredictBatch(inputs)
	if err != nil {
		return nil, err
	}

	routes := make([]string, len(envelopes))
	for i, envelope := range envelopes {
		if envelope != nil {
			err := m.router.Route(envelope)
			if err != nil {
				routes[i] = "ERROR"
				continue
			}
			routes[i] = envelope.Route
		}
	}

	return routes, nil
}

// ClassifyWithThreshold routes only if confidence is above threshold
func (m *MathRoutingClassifier) ClassifyWithThreshold(request string, threshold float64) (string, error) {
	envelope, err := m.classifier.Predict(request)
	if err != nil {
		return "", err
	}

	helper := NewDecisionEnvelopeHelper(envelope)

	// Check confidence from calibration metadata
	confidence := helper.Score("confidence")
	if confidence.NormalizedValue < threshold {
		return "ABSTAIN", fmt.Errorf("classify_with_threshold: confidence %.2f below threshold %.2f",
			confidence.NormalizedValue, threshold)
	}

	err = m.router.Route(envelope)
	if err != nil {
		return "", err
	}

	return envelope.Route, nil
}
