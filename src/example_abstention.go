package api

import (
	"fmt"

	"devflow-finance-twin/classifier/primitives"
)

// AbstentionExample demonstrates handling of uncertain classifications
// Strategy: Abstain if confidence < 0.70, accept if confidence >= 0.90, route otherwise
type AbstentionExample struct {
	classifier Classifier
	lowConf    float64  // Below this, abstain (default 0.70)
	highConf   float64  // Above this, accept (default 0.90)
	router     Router
}

// NewAbstentionExample creates a new abstention handler
func NewAbstentionExample(classifier Classifier, router Router) *AbstentionExample {
	return &AbstentionExample{
		classifier: classifier,
		lowConf:    0.70,
		highConf:   0.90,
		router:     router,
	}
}

// SetConfidenceThresholds sets custom thresholds
func (ae *AbstentionExample) SetConfidenceThresholds(low, high float64) error {
	if low < 0 || low > 1 || high < 0 || high > 1 {
		return fmt.Errorf("thresholds must be between 0 and 1")
	}
	if low > high {
		return fmt.Errorf("low threshold must be <= high threshold")
	}
	ae.lowConf = low
	ae.highConf = high
	return nil
}

// ClassifyWithAbstention performs classification with abstention logic
// Returns one of: "ABSTAIN", "ROUTE(...)", "ERROR"
func (ae *AbstentionExample) ClassifyWithAbstention(request string) (string, error) {
	if request == "" {
		return "ERROR", fmt.Errorf("classify_with_abstention: empty request")
	}

	envelope, err := ae.classifier.Predict(request)
	if err != nil {
		return "ERROR", fmt.Errorf("classify_with_abstention: prediction failed: %w", err)
	}

	if envelope == nil {
		return "ERROR", fmt.Errorf("classify_with_abstention: nil envelope")
	}

	helper := NewDecisionEnvelopeHelper(envelope)

	// Extract confidence
	confidence := helper.Score("confidence")
	if confidence == nil {
		return "ABSTAIN", fmt.Errorf("classify_with_abstention: confidence not available")
	}

	confValue := confidence.NormalizedValue

	// Low confidence: abstain
	if confValue < ae.lowConf {
		return "ABSTAIN", nil
	}

	// High confidence: route
	if confValue >= ae.highConf {
		err = ae.router.Route(envelope)
		if err != nil {
			return "ERROR", fmt.Errorf("classify_with_abstention: routing failed: %w", err)
		}
		return envelope.Route, nil
	}

	// Middle confidence: abstain with reason
	return "ABSTAIN", nil
}

// ClassifyWithDetailedAbstention returns detailed abstention reason
func (ae *AbstentionExample) ClassifyWithDetailedAbstention(request string) (*AbstentionDecision, error) {
	if request == "" {
		return nil, fmt.Errorf("classify_with_detailed_abstention: empty request")
	}

	envelope, err := ae.classifier.Predict(request)
	if err != nil {
		return nil, err
	}

	if envelope == nil {
		return nil, fmt.Errorf("classify_with_detailed_abstention: nil envelope")
	}

	decision := &AbstentionDecision{
		Request:   request,
		Timestamp: envelope.Timestamp,
		ModelID:   envelope.ModelID,
	}

	helper := NewDecisionEnvelopeHelper(envelope)

	// Extract metrics
	confidence := helper.Score("confidence")
	if confidence != nil {
		decision.Confidence = confidence.NormalizedValue
	}

	risk := helper.Score("risk")
	if risk != nil {
		decision.Risk = risk.NormalizedValue
	}

	// Determine disposition
	if decision.Confidence < ae.lowConf {
		decision.Disposition = "ABSTAIN_LOW_CONFIDENCE"
		decision.Reason = fmt.Sprintf("confidence %.3f < threshold %.3f", decision.Confidence, ae.lowConf)
		return decision, nil
	}

	if decision.Confidence >= ae.highConf {
		decision.Disposition = "ROUTE"
		err = ae.router.Route(envelope)
		if err != nil {
			decision.Disposition = "ERROR"
			decision.Reason = fmt.Sprintf("routing failed: %v", err)
			return decision, nil
		}
		decision.Reason = "confidence sufficient for routing"
		decision.Route = envelope.Route
		return decision, nil
	}

	decision.Disposition = "ABSTAIN_UNCERTAIN"
	decision.Reason = fmt.Sprintf("confidence %.3f in uncertain zone [%.3f, %.3f)",
		decision.Confidence, ae.lowConf, ae.highConf)
	return decision, nil
}

// AbstentionDecision holds detailed abstention analysis
type AbstentionDecision struct {
	Request     string
	Timestamp   int64
	ModelID     string
	Confidence  float64
	Risk        float64
	Disposition string // ABSTAIN_LOW_CONFIDENCE, ABSTAIN_UNCERTAIN, ROUTE, ERROR
	Reason      string
	Route       string
}

// BatchClassifyWithAbstention processes multiple requests with abstention
func (ae *AbstentionExample) BatchClassifyWithAbstention(requests []string) ([]*AbstentionDecision, error) {
	results := make([]*AbstentionDecision, len(requests))

	for i, req := range requests {
		decision, err := ae.ClassifyWithDetailedAbstention(req)
		if err != nil {
			results[i] = &AbstentionDecision{
				Request:     req,
				Disposition: "ERROR",
				Reason:      err.Error(),
			}
		} else {
			results[i] = decision
		}
	}

	return results, nil
}

// ShouldAbstain determines if classification should be abstained
func (ae *AbstentionExample) ShouldAbstain(envelope *primitives.DecisionEnvelope) bool {
	if envelope == nil {
		return true
	}

	helper := NewDecisionEnvelopeHelper(envelope)
	confidence := helper.Score("confidence")
	if confidence == nil {
		return true
	}

	return confidence.NormalizedValue < ae.lowConf
}

// ShouldRoute determines if classification should be routed
func (ae *AbstentionExample) ShouldRoute(envelope *primitives.DecisionEnvelope) bool {
	if envelope == nil {
		return false
	}

	helper := NewDecisionEnvelopeHelper(envelope)
	confidence := helper.Score("confidence")
	if confidence == nil {
		return false
	}

	return confidence.NormalizedValue >= ae.highConf
}

// AbstentionStats tracks abstention statistics
type AbstentionStats struct {
	Total            int
	Abstained        int
	Routed           int
	AbstainRate      float64
	AvgConfidence    float64
	AvgRisk          float64
	LowConfAbstains  int
	UncertainAbstains int
}

// ComputeStats computes statistics from decisions
func ComputeStats(decisions []*AbstentionDecision) *AbstentionStats {
	stats := &AbstentionStats{
		Total: len(decisions),
	}

	if stats.Total == 0 {
		return stats
	}

	totalConf := 0.0
	totalRisk := 0.0
	confCount := 0

	for _, d := range decisions {
		switch d.Disposition {
		case "ABSTAIN_LOW_CONFIDENCE":
			stats.Abstained++
			stats.LowConfAbstains++
		case "ABSTAIN_UNCERTAIN":
			stats.Abstained++
			stats.UncertainAbstains++
		case "ROUTE":
			stats.Routed++
		}

		if d.Confidence > 0 {
			totalConf += d.Confidence
			confCount++
		}
		totalRisk += d.Risk
	}

	stats.AbstainRate = float64(stats.Abstained) / float64(stats.Total)
	if confCount > 0 {
		stats.AvgConfidence = totalConf / float64(confCount)
	}
	if stats.Total > 0 {
		stats.AvgRisk = totalRisk / float64(stats.Total)
	}

	return stats
}
