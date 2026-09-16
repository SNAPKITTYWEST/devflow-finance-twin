// Package ground provides optimization strategies for grounding
package ground

import (
	"fmt"
	"math"
	"sort"
	"sync"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/ir"
)

// GroundingStrategy defines the algorithm used for grounding
type GroundingStrategy int

const (
	STRATEGY_STANDARD GroundingStrategy = iota
	STRATEGY_LAZY
	STRATEGY_MAGIC_SET
	STRATEGY_BOTTOM_UP
)

// GroundingOptimizer applies optimizations during grounding
type GroundingOptimizer struct {
	mu              sync.RWMutex
	strategy        GroundingStrategy
	domainAnalyzer  *DomainAnalyzer
	cacheEnabled    bool
	lazyMode        bool
	substitutions   map[string]*Substitution
	groundedRuleCache map[uint64]bool
	estimatedSize   int64
	maxGroundingSize int64
}

// NewGroundingOptimizer creates a new optimizer
func NewGroundingOptimizer(analyzer *DomainAnalyzer) *GroundingOptimizer {
	return &GroundingOptimizer{
		strategy:         STRATEGY_STANDARD,
		domainAnalyzer:   analyzer,
		cacheEnabled:     true,
		lazyMode:         false,
		substitutions:   make(map[string]*Substitution),
		groundedRuleCache: make(map[uint64]bool),
		maxGroundingSize:  1000000, // 1M ground rules
	}
}

// SetStrategy sets the grounding strategy
func (go *GroundingOptimizer) SetStrategy(s GroundingStrategy) {
	go.mu.Lock()
	defer go.mu.Unlock()
	go.strategy = s
}

// EstimateGroundingSize estimates the size of the grounding
func (go *GroundingOptimizer) EstimateGroundingSize(program []ast.Statement) (int64, error) {
	go.mu.Lock()
	defer go.mu.Unlock()

	totalSize := int64(1)

	// For each rule, estimate instantiations
	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule

			// Skip facts
			if rule.Type == ast.RULE_FACT || len(rule.Body) == 0 {
				continue
			}

			// Estimate based on body predicates
			ruleSize := go.estimateRuleSize(rule)
			totalSize *= ruleSize
			if totalSize > go.maxGroundingSize {
				return 0, fmt.Errorf("estimated grounding too large: > %d", go.maxGroundingSize)
			}
		}
	}

	go.estimatedSize = totalSize
	return totalSize, nil
}

// estimateRuleSize estimates how many times a rule will be instantiated
func (go *GroundingOptimizer) estimateRuleSize(rule *ast.Rule) int64 {
	if len(rule.Body) == 0 {
		return 1
	}

	// Estimate based on body literals
	size := int64(1)
	for _, lit := range rule.Body {
		if lit.Atom != nil {
			if info := go.domainAnalyzer.GetPredicateInfo(lit.Atom.Name); info != nil {
				bound := go.domainAnalyzer.GetDomainBound(lit.Atom.Name)
				if bound.IsFinite {
					size *= int64(bound.MaxSize)
				} else {
					// Unknown size, assume worst case
					size *= 100
				}
			}
		}
	}

	return int64(math.Min(float64(size), float64(go.maxGroundingSize)))
}

// ShouldUseIncrementalGrounding determines if incremental grounding is beneficial
func (go *GroundingOptimizer) ShouldUseIncrementalGrounding(program []ast.Statement) bool {
	go.mu.RLock()
	defer go.mu.RUnlock()

	// Check if there are recursive predicates
	recursivePreds := go.domainAnalyzer.GetRecursivePredicates()
	return len(recursivePreds) > 0
}

// OptimizeRuleOrder reorders rules for better grounding efficiency
func (go *GroundingOptimizer) OptimizeRuleOrder(rules []*ast.Rule) []*ast.Rule {
	go.mu.Lock()
	defer go.mu.Unlock()

	// Create sortable wrapper
	sortable := &RuleOrderer{
		rules:    rules,
		analyzer: go.domainAnalyzer,
	}

	sort.Sort(sortable)
	return sortable.rules
}

// RuleOrderer helps sort rules for grounding optimization
type RuleOrderer struct {
	rules    []*ast.Rule
	analyzer *DomainAnalyzer
}

// Len implements sort.Interface
func (ro *RuleOrderer) Len() int {
	return len(ro.rules)
}

// Less implements sort.Interface - facts first, then by increasing size
func (ro *RuleOrderer) Less(i, j int) bool {
	rule1 := ro.rules[i]
	rule2 := ro.rules[j]

	// Facts come first
	if (rule1.Type == ast.RULE_FACT) != (rule2.Type == ast.RULE_FACT) {
		return rule1.Type == ast.RULE_FACT
	}

	// For rules, smaller estimated size comes first
	size1 := ro.analyzer.predicateInfo
	size2 := len(rule2.Body)

	return len(rule1.Body) < size2
}

// Swap implements sort.Interface
func (ro *RuleOrderer) Swap(i, j int) {
	ro.rules[i], ro.rules[j] = ro.rules[j], ro.rules[i]
}

// CachingSubstitutionGenerator caches substitution generation
type CachingSubstitutionGenerator struct {
	mu             sync.RWMutex
	cache          map[string][]map[string]ast.Term
	computedRules  map[uint64]bool
}

// NewCachingSubstitutionGenerator creates a new generator
func NewCachingSubstitutionGenerator() *CachingSubstitutionGenerator {
	return &CachingSubstitutionGenerator{
		cache:         make(map[string][]map[string]ast.Term),
		computedRules: make(map[uint64]bool),
	}
}

// Get retrieves cached substitutions
func (csg *CachingSubstitutionGenerator) Get(key string) ([]map[string]ast.Term, bool) {
	csg.mu.RLock()
	defer csg.mu.RUnlock()
	subs, ok := csg.cache[key]
	return subs, ok
}

// Set caches substitutions
func (csg *CachingSubstitutionGenerator) Set(key string, subs []map[string]ast.Term) {
	csg.mu.Lock()
	defer csg.mu.Unlock()
	csg.cache[key] = subs
}

// Clear clears the cache
func (csg *CachingSubstitutionGenerator) Clear() {
	csg.mu.Lock()
	defer csg.mu.Unlock()
	csg.cache = make(map[string][]map[string]ast.Term)
	csg.computedRules = make(map[uint64]bool)
}

// MagicSetTransformer applies magic set optimization
type MagicSetTransformer struct {
	program       []ast.Statement
	queryGoals    []string
	magicRules    []*ast.Rule
	modifiedRules []*ast.Rule
}

// NewMagicSetTransformer creates a new transformer
func NewMagicSetTransformer(program []ast.Statement) *MagicSetTransformer {
	return &MagicSetTransformer{
		program:       program,
		queryGoals:    make([]string, 0),
		magicRules:    make([]*ast.Rule, 0),
		modifiedRules: make([]*ast.Rule, 0),
	}
}

// SetQueryGoals sets the goals to optimize for
func (mst *MagicSetTransformer) SetQueryGoals(goals []string) {
	mst.queryGoals = goals
}

// Transform applies magic set transformation
func (mst *MagicSetTransformer) Transform() ([]*ast.Rule, error) {
	if len(mst.queryGoals) == 0 {
		// No transformation needed
		return mst.extractRules(), nil
	}

	// Create magic predicates for each query goal
	for _, goal := range mst.queryGoals {
		magicRule := mst.createMagicRule(goal)
		if magicRule != nil {
			mst.magicRules = append(mst.magicRules, magicRule)
		}
	}

	// Add magic rules to program
	result := append(mst.extractRules(), mst.magicRules...)
	return result, nil
}

// extractRules extracts all rules from statements
func (mst *MagicSetTransformer) extractRules() []*ast.Rule {
	result := make([]*ast.Rule, 0)
	for _, stmt := range mst.program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			result = append(result, rs.Rule)
		}
	}
	return result
}

// createMagicRule creates a magic predicate rule
func (mst *MagicSetTransformer) createMagicRule(goal string) *ast.Rule {
	// This is a simplified implementation
	// Real magic set transformation is more complex
	magicAtom := &ast.Atom{Name: "magic_" + goal}

	return &ast.Rule{
		Head: &ast.Head{
			Atoms: []*ast.HeadAtom{
				{Atom: magicAtom, Args: []ast.Term{}},
			},
			Type: ast.HEAD_NORMAL,
		},
		Body: make([]*ast.Literal, 0),
		Type: ast.RULE_FACT,
	}
}

// GroundingProgress tracks grounding progress
type GroundingProgress struct {
	mu              sync.RWMutex
	processed       int
	total           int
	groundRulesGenerated int
	groundAtomsGenerated int
	startTime       int64
	lastUpdate      int64
}

// NewGroundingProgress creates a new progress tracker
func NewGroundingProgress(total int) *GroundingProgress {
	return &GroundingProgress{
		total: total,
	}
}

// Update updates the progress
func (gp *GroundingProgress) Update(processed, groundRules, groundAtoms int) {
	gp.mu.Lock()
	defer gp.mu.Unlock()
	gp.processed = processed
	gp.groundRulesGenerated = groundRules
	gp.groundAtomsGenerated = groundAtoms
}

// Percentage returns the percentage of completion
func (gp *GroundingProgress) Percentage() float64 {
	gp.mu.RLock()
	defer gp.mu.RUnlock()
	if gp.total == 0 {
		return 0
	}
	return (float64(gp.processed) / float64(gp.total)) * 100
}

// ParallelGrounder implements parallel grounding for independent rules
type ParallelGrounder struct {
	workerCount int
	grounder    *Grounder
	ruleChannel chan *ast.Rule
	resultChannel chan *ir.GroundRule
}

// NewParallelGrounder creates a new parallel grounder
func NewParallelGrounder(workerCount int, g *Grounder) *ParallelGrounder {
	return &ParallelGrounder{
		workerCount:   workerCount,
		grounder:      g,
		ruleChannel:   make(chan *ast.Rule, workerCount*2),
		resultChannel: make(chan *ir.GroundRule, workerCount*2),
	}
}

// GroundRulesConcurrently grinds multiple rules in parallel
func (pg *ParallelGrounder) GroundRulesConcurrently(rules []*ast.Rule) ([]*ir.GroundRule, error) {
	// This would implement parallel grounding
	// For now, delegate to sequential implementation
	result := make([]*ir.GroundRule, 0)

	for _, rule := range rules {
		groundedRules, err := pg.grounder.GroundRule(rule)
		if err != nil {
			return nil, err
		}
		result = append(result, groundedRules...)
	}

	return result, nil
}

// GroundingValidator validates grounding correctness
type GroundingValidator struct {
	mu    sync.RWMutex
	rules []*ir.GroundRule
}

// NewGroundingValidator creates a new validator
func NewGroundingValidator() *GroundingValidator {
	return &GroundingValidator{
		rules: make([]*ir.GroundRule, 0),
	}
}

// Validate checks correctness of ground rules
func (gv *GroundingValidator) Validate() error {
	gv.mu.RLock()
	defer gv.mu.RUnlock()

	// Check for duplicate rules
	seen := make(map[string]bool)
	for _, rule := range gv.rules {
		key := rule.String()
		if seen[key] {
			return fmt.Errorf("duplicate ground rule: %s", key)
		}
		seen[key] = true
	}

	return nil
}

// AddRules adds rules to validate
func (gv *GroundingValidator) AddRules(rules []*ir.GroundRule) {
	gv.mu.Lock()
	defer gv.mu.Unlock()
	gv.rules = append(gv.rules, rules...)
}

// GroundingStatics provides static analysis of grounding
type GroundingStatistics struct {
	TotalRules           int
	TotalAtoms          int
	TotalConstraints    int
	FactCount           int
	NormalRuleCount     int
	ChoiceRuleCount     int
	ConstraintCount     int
	AverageHeadSize     float64
	AverageBodySize     float64
	MaxHeadSize         int
	MaxBodySize         int
	UniquePredicates    []string
}

// ComputeStatistics computes grounding statistics
func ComputeStatistics(groundRules []*ir.GroundRule) *GroundingStatistics {
	stats := &GroundingStatistics{
		TotalRules:       len(groundRules),
		UniquePredicates: make([]string, 0),
	}

	atomSet := make(map[string]bool)
	headSizes := make([]int, 0)
	bodySizes := make([]int, 0)

	for _, rule := range groundRules {
		// Count atoms
		for _, atom := range rule.Head {
			atomSet[atom.String()] = true
			stats.TotalAtoms++
		}

		// Count rules by type
		switch rule.Type {
		case ir.RULE_FACT:
			stats.FactCount++
		case ir.RULE_NORMAL:
			stats.NormalRuleCount++
		case ir.RULE_CHOICE:
			stats.ChoiceRuleCount++
		case ir.RULE_CONSTRAINT:
			stats.ConstraintCount++
			stats.TotalConstraints++
		}

		headSizes = append(headSizes, len(rule.Head))
		bodySizes = append(bodySizes, len(rule.Body))

		if len(rule.Head) > stats.MaxHeadSize {
			stats.MaxHeadSize = len(rule.Head)
		}
		if len(rule.Body) > stats.MaxBodySize {
			stats.MaxBodySize = len(rule.Body)
		}
	}

	stats.TotalAtoms = len(atomSet)

	// Compute averages
	if len(headSizes) > 0 {
		sum := 0
		for _, size := range headSizes {
			sum += size
		}
		stats.AverageHeadSize = float64(sum) / float64(len(headSizes))
	}

	if len(bodySizes) > 0 {
		sum := 0
		for _, size := range bodySizes {
			sum += size
		}
		stats.AverageBodySize = float64(sum) / float64(len(bodySizes))
	}

	return stats
}

// GroundingDebugger provides debugging information
type GroundingDebugger struct {
	mu       sync.RWMutex
	trace    []string
	verbose  bool
}

// NewGroundingDebugger creates a new debugger
func NewGroundingDebugger() *GroundingDebugger {
	return &GroundingDebugger{
		trace:   make([]string, 0),
		verbose: false,
	}
}

// SetVerbose enables verbose output
func (gd *GroundingDebugger) SetVerbose(v bool) {
	gd.mu.Lock()
	defer gd.mu.Unlock()
	gd.verbose = v
}

// Log adds an entry to the trace
func (gd *GroundingDebugger) Log(message string) {
	gd.mu.Lock()
	defer gd.mu.Unlock()

	if gd.verbose {
		fmt.Println("[DEBUG]", message)
	}
	gd.trace = append(gd.trace, message)
}

// GetTrace returns the debug trace
func (gd *GroundingDebugger) GetTrace() []string {
	gd.mu.RLock()
	defer gd.mu.RUnlock()
	result := make([]string, len(gd.trace))
	copy(result, gd.trace)
	return result
}

// ClearTrace clears the debug trace
func (gd *GroundingDebugger) ClearTrace() {
	gd.mu.Lock()
	defer gd.mu.Unlock()
	gd.trace = make([]string, 0)
}
