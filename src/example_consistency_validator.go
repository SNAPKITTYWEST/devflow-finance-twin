package api

import (
	"fmt"

	"devflow-finance-twin/classifier/primitives"
)

// ConsistencyValidator verifies multi-head consistency in decisions
// Example: valid == YES AND domain == CODE AND confidence >= 0.90 AND risk <= 0.10
type ConsistencyValidator struct {
	classifier Classifier
	rules      []*ConsistencyRule
}

// ConsistencyRule defines a consistency check
type ConsistencyRule struct {
	Name      string
	Evaluate  func(*primitives.DecisionEnvelope) error
	Severity  string // "strict" or "warning"
}

// NewConsistencyValidator creates a new validator
func NewConsistencyValidator(classifier Classifier) *ConsistencyValidator {
	return &ConsistencyValidator{
		classifier: classifier,
		rules:      make([]*ConsistencyRule, 0),
	}
}

// AddRule adds a consistency rule
func (cv *ConsistencyValidator) AddRule(rule *ConsistencyRule) {
	if rule != nil {
		cv.rules = append(cv.rules, rule)
	}
}

// Validate checks an envelope for consistency
func (cv *ConsistencyValidator) Validate(envelope *primitives.DecisionEnvelope) *ConsistencyResult {
	if envelope == nil {
		return &ConsistencyResult{
			Valid:   false,
			Message: "nil envelope",
			Errors:  []string{"envelope is nil"},
		}
	}

	result := &ConsistencyResult{
		Valid:   true,
		Errors:  make([]string, 0),
	}

	// Apply all rules
	for _, rule := range cv.rules {
		err := rule.Evaluate(envelope)
		if err != nil {
			if rule.Severity == "strict" {
				result.Valid = false
			}
			result.Errors = append(result.Errors, fmt.Sprintf("%s: %v", rule.Name, err))
		}
	}

	if result.Valid {
		result.Message = "all consistency checks passed"
	} else if len(result.Errors) > 0 {
		result.Message = fmt.Sprintf("consistency check failed: %d error(s)", len(result.Errors))
	}

	return result
}

// ValidateCodeClassification validates CODE domain classification
func (cv *ConsistencyValidator) ValidateCodeClassification(envelope *primitives.DecisionEnvelope) *ConsistencyResult {
	helper := NewDecisionEnvelopeHelper(envelope)
	result := &ConsistencyResult{Valid: true, Errors: make([]string, 0)}

	// Check valid decision
	validNoul := helper.Noul("valid")
	if validNoul == nil || !validNoul.IsYes() {
		result.Valid = false
		result.Errors = append(result.Errors, "invalid noul decision: expected YES")
	}

	// Check domain choice
	domainChoice := helper.Choice("domain")
	if domainChoice == nil || domainChoice.Selected == false {
		result.Valid = false
		result.Errors = append(result.Errors, "domain choice not selected")
	}

	// Check confidence threshold
	confidence := helper.Score("confidence")
	if confidence.NormalizedValue < 0.90 {
		result.Valid = false
		result.Errors = append(result.Errors, fmt.Sprintf("confidence %.2f < 0.90", confidence.NormalizedValue))
	}

	// Check risk threshold
	risk := helper.Score("risk")
	if risk.NormalizedValue > 0.10 {
		result.Valid = false
		result.Errors = append(result.Errors, fmt.Sprintf("risk %.2f > 0.10", risk.NormalizedValue))
	}

	if result.Valid {
		result.Message = "code classification consistent"
	} else {
		result.Message = fmt.Sprintf("code classification check failed: %d error(s)", len(result.Errors))
	}

	return result
}

// ValidateMathematicalClassification validates MATH domain classification
func (cv *ConsistencyValidator) ValidateMathematicalClassification(envelope *primitives.DecisionEnvelope) *ConsistencyResult {
	helper := NewDecisionEnvelopeHelper(envelope)
	result := &ConsistencyResult{Valid: true, Errors: make([]string, 0)}

	// Check valid noul
	validNoul := helper.Noul("valid")
	if validNoul == nil || !validNoul.IsYes() {
		result.Valid = false
		result.Errors = append(result.Errors, "mathematical request must be valid (YES)")
	}

	// Check confidence >= 0.85 (slightly lower than code)
	confidence := helper.Score("confidence")
	if confidence.NormalizedValue < 0.85 {
		result.Valid = false
		result.Errors = append(result.Errors, fmt.Sprintf("confidence %.2f < 0.85", confidence.NormalizedValue))
	}

	// Check risk <= 0.15 (slightly higher tolerance than code)
	risk := helper.Score("risk")
	if risk.NormalizedValue > 0.15 {
		result.Valid = false
		result.Errors = append(result.Errors, fmt.Sprintf("risk %.2f > 0.15", risk.NormalizedValue))
	}

	if result.Valid {
		result.Message = "mathematical classification consistent"
	} else {
		result.Message = fmt.Sprintf("mathematical classification check failed: %d error(s)", len(result.Errors))
	}

	return result
}

// ValidateMultiHeadAgreement checks that all heads agree
func (cv *ConsistencyValidator) ValidateMultiHeadAgreement(envelope *primitives.DecisionEnvelope) *ConsistencyResult {
	if envelope == nil {
		return &ConsistencyResult{
			Valid:   false,
			Message: "nil envelope",
			Errors:  []string{"envelope is nil"},
		}
	}

	result := &ConsistencyResult{Valid: true, Errors: make([]string, 0)}

	// All Noul heads should have consistent dispositions
	if len(envelope.NoulChoices) > 0 {
		firstDecision := envelope.NoulChoices[0].Decision
		for i, noul := range envelope.NoulChoices[1:] {
			if noul.Decision != firstDecision {
				result.Valid = false
				result.Errors = append(result.Errors,
					fmt.Sprintf("noul head %d decision mismatch: expected %s, got %s",
						i+1, firstDecision, noul.Decision))
			}
		}
	}

	// Route choices should have agreement on best class
	if len(envelope.RouteChoices) > 0 {
		// Check that selected routes match
		selectedRoutes := make([]string, 0)
		for _, rc := range envelope.RouteChoices {
			if rc.Selected {
				selectedRoutes = append(selectedRoutes, rc.Name)
			}
		}

		if len(selectedRoutes) > 1 {
			result.Valid = false
			result.Errors = append(result.Errors,
				fmt.Sprintf("multiple routes selected: %v", selectedRoutes))
		}
	}

	if result.Valid {
		result.Message = "multi-head agreement verified"
	} else {
		result.Message = fmt.Sprintf("multi-head agreement check failed: %d error(s)", len(result.Errors))
	}

	return result
}
