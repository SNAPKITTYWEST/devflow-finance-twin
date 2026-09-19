// Package classifier is the public facade for the multi-head classification system.
// External consumers should import only this package; do not import sub-packages directly.
package classifier

import (
	"devflow-finance-twin/classifier/backends"
	"devflow-finance-twin/classifier/model"
	"devflow-finance-twin/classifier/primitives"
)

// ---------------------------------------------------------------------------
// Type aliases — primitives
// ---------------------------------------------------------------------------

// DecisionEnvelope is the complete output of a single classification pass.
type DecisionEnvelope = primitives.DecisionEnvelope

// RouteChoice records the routing decision made at a specific junction.
type RouteChoice = primitives.RouteChoice

// NoulChoice records the output of a single binary classification head.
type NoulChoice = primitives.NoulChoice

// ModelMetadata carries model identity and version information.
type ModelMetadata = primitives.ModelMetadata

// InputMetadata describes the input that was classified.
type InputMetadata = primitives.InputMetadata

// ---------------------------------------------------------------------------
// Type aliases — model
// ---------------------------------------------------------------------------

// Classifier is the primary interface for all classification implementations.
type Classifier = model.Classifier

// DefaultClassifier is the standard classifier backed by Noul heads and a router.
type DefaultClassifier = model.DefaultClassifier

// Head is the interface for a single classification head (Noul).
type Head = model.Head

// Router is the interface for routing inputs through the classification graph.
type Router = model.Router

// ---------------------------------------------------------------------------
// Type aliases — backends
// ---------------------------------------------------------------------------

// CPUBackend is the vectorised CPU backend for batch inference.
type CPUBackend = backends.CPUBackend

// ---------------------------------------------------------------------------
// Constructor helpers
// ---------------------------------------------------------------------------

// NewClassifier creates a DefaultClassifier from metadata, heads, and a router.
// It is a direct alias for model.NewDefaultClassifier.
var NewClassifier = model.NewDefaultClassifier

// NewCPUBackend creates a CPU backend capped at maxConcurrency parallel goroutines.
var NewCPUBackend = backends.NewCPUBackend
