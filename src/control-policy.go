package control

import (
	"fmt"
	"sync"
	"time"
)

// OperationType enum for different archive operations
type OperationType int

const (
	OP_READ OperationType = iota
	OP_WRITE
	OP_CREATE_ARCHIVE
	OP_EXTRACT_ARCHIVE
	OP_DELETE
	OP_RENAME
	OP_VERIFY
	OP_HASH
)

// String representation of OperationType
func (o OperationType) String() string {
	switch o {
	case OP_READ:
		return "READ"
	case OP_WRITE:
		return "WRITE"
	case OP_CREATE_ARCHIVE:
		return "CREATE_ARCHIVE"
	case OP_EXTRACT_ARCHIVE:
		return "EXTRACT_ARCHIVE"
	case OP_DELETE:
		return "DELETE"
	case OP_RENAME:
		return "RENAME"
	case OP_VERIFY:
		return "VERIFY"
	case OP_HASH:
		return "HASH"
	default:
		return "UNKNOWN"
	}
}

// PolicyRule defines authorization constraints for an operation
type PolicyRule struct {
	Operation            OperationType
	AllowedPaths         []string // allowed destination patterns (glob-style)
	MaxFileSize          int64    // in bytes; 0 = unlimited
	RequiresConfirmation bool
	RateLimitPerMin      int // requests per minute; 0 = unlimited
}

// PolicySet holds all authorization rules and manages policy state
type PolicySet struct {
	Rules         map[OperationType]PolicyRule
	rateLimitLock sync.RWMutex
	rateLimitBins map[string][]time.Time // tracks request timestamps per operation type
	mu            sync.RWMutex
}

// NewPolicySet creates a new PolicySet with default rules
func NewPolicySet() *PolicySet {
	ps := &PolicySet{
		Rules:        make(map[OperationType]PolicyRule),
		rateLimitBins: make(map[string][]time.Time),
	}
	return ps
}

// AddRule adds or updates a policy rule
func (p *PolicySet) AddRule(rule PolicyRule) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.Rules[rule.Operation] = rule
}

// GetRule retrieves a policy rule by operation type
func (p *PolicySet) GetRule(op OperationType) (PolicyRule, bool) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	rule, exists := p.Rules[op]
	return rule, exists
}

// pathMatches checks if a path matches any allowed patterns using simple glob matching
func pathMatches(path string, patterns []string) bool {
	if len(patterns) == 0 {
		// No patterns means anything is allowed
		return true
	}
	for _, pattern := range patterns {
		if simpleGlobMatch(path, pattern) {
			return true
		}
	}
	return false
}

// simpleGlobMatch performs basic glob pattern matching (* matches any sequence)
func simpleGlobMatch(text, pattern string) bool {
	// Handle exact matches
	if pattern == "*" {
		return true
	}
	if text == pattern {
		return true
	}

	// Handle wildcard at beginning
	if len(pattern) > 0 && pattern[0] == '*' {
		suffix := pattern[1:]
		if suffix == "" {
			return true
		}
		if len(suffix) > 0 && suffix[0] == '/' {
			// */<rest> matches anything followed by /<rest>
			for i := 0; i < len(text); i++ {
				if text[i] == '/' && simpleGlobMatch(text[i:], suffix) {
					return true
				}
			}
			return false
		}
		// Otherwise check suffix match anywhere in text
		for i := 0; i <= len(text)-len(suffix); i++ {
			if text[i:i+len(suffix)] == suffix {
				return true
			}
		}
		return false
	}

	// Handle wildcard at end
	if len(pattern) > 0 && pattern[len(pattern)-1] == '*' {
		prefix := pattern[:len(pattern)-1]
		if len(text) >= len(prefix) {
			return text[:len(prefix)] == prefix
		}
		return false
	}

	// Handle wildcard in middle
	parts := splitOnWildcard(pattern)
	if len(parts) == 1 {
		return text == pattern
	}

	// Match first part
	if !begins(text, parts[0]) {
		return false
	}
	text = text[len(parts[0]):]

	// Match middle parts
	for i := 1; i < len(parts)-1; i++ {
		idx := indexOf(text, parts[i])
		if idx == -1 {
			return false
		}
		text = text[idx+len(parts[i]):]
	}

	// Match last part
	return ends(text, parts[len(parts)-1])
}

func splitOnWildcard(s string) []string {
	var parts []string
	var current string
	for i := 0; i < len(s); i++ {
		if s[i] == '*' {
			parts = append(parts, current)
			current = ""
		} else {
			current += string(s[i])
		}
	}
	if current != "" || (len(s) > 0 && s[len(s)-1] == '*') {
		parts = append(parts, current)
	}
	return parts
}

func begins(text, prefix string) bool {
	if prefix == "" {
		return true
	}
	if len(text) < len(prefix) {
		return false
	}
	return text[:len(prefix)] == prefix
}

func ends(text, suffix string) bool {
	if suffix == "" {
		return true
	}
	if len(text) < len(suffix) {
		return false
	}
	return text[len(text)-len(suffix):] == suffix
}

func indexOf(text, substring string) int {
	if substring == "" {
		return 0
	}
	for i := 0; i <= len(text)-len(substring); i++ {
		if text[i:i+len(substring)] == substring {
			return i
		}
	}
	return -1
}

// EvaluatePolicy checks if operation is authorized based on policy rules
// Returns (authorized, reason) where reason explains the decision
func (p *PolicySet) EvaluatePolicy(op OperationType, paths ...string) (bool, string) {
	p.mu.RLock()
	rule, exists := p.Rules[op]
	p.mu.RUnlock()

	// If no rule exists, deny by default
	if !exists {
		return false, fmt.Sprintf("Operation %s not defined in policy", op)
	}

	// Check path authorization
	if len(rule.AllowedPaths) > 0 && len(paths) > 0 {
		for _, path := range paths {
			if !pathMatches(path, rule.AllowedPaths) {
				return false, fmt.Sprintf("Path %s not in allowed patterns for %s", path, op)
			}
		}
	}

	// Check file size constraint (hypothetical check - would need actual file size)
	// This is where file size validation would occur if we had the file

	// Check rate limit
	if rule.RateLimitPerMin > 0 {
		if !p.checkRateLimit(op) {
			return false, fmt.Sprintf("Rate limit exceeded for %s (%d per minute)", op, rule.RateLimitPerMin)
		}
	}

	return true, fmt.Sprintf("Operation %s authorized", op)
}

// checkRateLimit verifies if operation is within rate limit
func (p *PolicySet) checkRateLimit(op OperationType) bool {
	p.rateLimitLock.Lock()
	defer p.rateLimitLock.Unlock()

	rule, exists := p.Rules[op]
	if !exists || rule.RateLimitPerMin <= 0 {
		return true
	}

	key := rule.Operation.String()
	now := time.Now()
	oneMinuteAgo := now.Add(-1 * time.Minute)

	// Clean old timestamps (older than 1 minute)
	validTimestamps := []time.Time{}
	for _, ts := range p.rateLimitBins[key] {
		if ts.After(oneMinuteAgo) {
			validTimestamps = append(validTimestamps, ts)
		}
	}

	// Check if we've exceeded the limit
	if len(validTimestamps) >= rule.RateLimitPerMin {
		p.rateLimitBins[key] = validTimestamps
		return false
	}

	// Record this request
	validTimestamps = append(validTimestamps, now)
	p.rateLimitBins[key] = validTimestamps

	return true
}

// EvaluatePolicyBatch checks multiple operations with path sets
// Returns slice of (operation, paths, authorized, reason)
func (p *PolicySet) EvaluatePolicyBatch(operations []OperationType, pathSets [][]string) []EvaluationResult {
	results := make([]EvaluationResult, 0, len(operations))

	for i, op := range operations {
		var paths []string
		if i < len(pathSets) {
			paths = pathSets[i]
		}

		authorized, reason := p.EvaluatePolicy(op, paths...)
		results = append(results, EvaluationResult{
			Operation: op,
			Paths:     paths,
			Authorized: authorized,
			Reason:    reason,
			Timestamp: time.Now(),
		})
	}

	return results
}

// EvaluationResult represents the outcome of a policy evaluation
type EvaluationResult struct {
	Operation  OperationType
	Paths      []string
	Authorized bool
	Reason     string
	Timestamp  time.Time
}

// AuditLog records policy decisions for compliance tracking
type AuditLog struct {
	Results []EvaluationResult
	mu      sync.RWMutex
}

// Record adds an evaluation result to the audit log
func (a *AuditLog) Record(result EvaluationResult) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.Results = append(a.Results, result)
}

// GetLog returns all audit records
func (a *AuditLog) GetLog() []EvaluationResult {
	a.mu.RLock()
	defer a.mu.RUnlock()

	// Return a copy to prevent external modification
	logCopy := make([]EvaluationResult, len(a.Results))
	copy(logCopy, a.Results)
	return logCopy
}

// GetLogSince returns audit records since a given time
func (a *AuditLog) GetLogSince(since time.Time) []EvaluationResult {
	a.mu.RLock()
	defer a.mu.RUnlock()

	var filtered []EvaluationResult
	for _, result := range a.Results {
		if result.Timestamp.After(since) {
			filtered = append(filtered, result)
		}
	}
	return filtered
}

// OperationCounter tracks statistics about policy operations
type OperationCounter struct {
	counts map[OperationType]int64
	mu     sync.RWMutex
}

// NewOperationCounter creates a new counter
func NewOperationCounter() *OperationCounter {
	return &OperationCounter{
		counts: make(map[OperationType]int64),
	}
}

// Increment increments the count for an operation
func (oc *OperationCounter) Increment(op OperationType) {
	oc.mu.Lock()
	defer oc.mu.Unlock()
	oc.counts[op]++
}

// Get returns the count for an operation
func (oc *OperationCounter) Get(op OperationType) int64 {
	oc.mu.RLock()
	defer oc.mu.RUnlock()
	return oc.counts[op]
}

// GetAll returns all counts
func (oc *OperationCounter) GetAll() map[OperationType]int64 {
	oc.mu.RLock()
	defer oc.mu.RUnlock()

	// Return a copy
	result := make(map[OperationType]int64)
	for k, v := range oc.counts {
		result[k] = v
	}
	return result
}

// Reset clears all counts
func (oc *OperationCounter) Reset() {
	oc.mu.Lock()
	defer oc.mu.Unlock()
	oc.counts = make(map[OperationType]int64)
}

// PolicyValidator validates policy rules for consistency
type PolicyValidator struct {
	policy *PolicySet
}

// NewPolicyValidator creates a new validator
func NewPolicyValidator(policy *PolicySet) *PolicyValidator {
	return &PolicyValidator{policy: policy}
}

// Validate checks policy configuration for issues
func (pv *PolicyValidator) Validate() []string {
	var issues []string

	pv.policy.mu.RLock()
	defer pv.policy.mu.RUnlock()

	if len(pv.policy.Rules) == 0 {
		issues = append(issues, "Policy has no rules defined")
	}

	for opType, rule := range pv.policy.Rules {
		if rule.MaxFileSize < 0 {
			issues = append(issues, fmt.Sprintf("%s: MaxFileSize cannot be negative", opType))
		}
		if rule.RateLimitPerMin < 0 {
			issues = append(issues, fmt.Sprintf("%s: RateLimitPerMin cannot be negative", opType))
		}
		if len(rule.AllowedPaths) == 0 && opType != OP_READ {
			// Warning: write operations with no path restrictions
			issues = append(issues, fmt.Sprintf("%s: No path restrictions (potentially dangerous)", opType))
		}
	}

	return issues
}
