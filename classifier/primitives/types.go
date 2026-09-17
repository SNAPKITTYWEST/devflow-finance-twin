package primitives

import (
	"time"
)

// RouteChoice represents a routing decision at a specific junction
type RouteChoice struct {
	Name          string
	Selected      bool
	Probabilities map[string]float64 // class -> probability
}

// NoulChoice represents a Noul head decision
type NoulChoice struct {
	Name        string
	Decision    string             // selected decision
	Probability float64            // probability of decision
	Logits      map[string]float64 // class -> logit
}

// DecisionEnvelope encapsulates a complete classification decision
type DecisionEnvelope struct {
	// Metadata
	Timestamp    int64
	ModelID      string
	ModelVersion string
	InputHash    string
	RouterHash   string

	// Routing decisions
	RouteChoices []*RouteChoice

	// Noul decisions (classification heads)
	NoulChoices []*NoulChoice

	// Scoring metadata
	CalibrationMetadata map[string]interface{}

	// Thresholds applied during decision
	Thresholds map[string]float64

	// Disposition (final classification result)
	Disposition string

	// Route taken (path through router)
	Route string
}

// ModelMetadata contains model-level information for audit trails
type ModelMetadata struct {
	ModelID      string
	ModelVersion string
	Hash         string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// InputMetadata contains input-level information
type InputMetadata struct {
	Hash        string
	Features    map[string]interface{}
	Timestamp   time.Time
	Source      string
	Version     int32
}

// RouterMetadata contains router configuration metadata
type RouterMetadata struct {
	Hash       string
	ConfigHash string
	Version    string
	UpdatedAt  time.Time
	Nodes      []string
}

// CalibrationInfo represents calibration metadata
type CalibrationInfo struct {
	TemperatureScaling float64
	IsotonicRegression map[string]float64
	PlattScaling       map[string]float64
	Metrics            map[string]float64
}
