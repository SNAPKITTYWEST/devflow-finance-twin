// Package ground provides advanced grounding capabilities
// Includes domain analysis, incremental grounding, and optimization strategies
package ground

import (
	"fmt"
	"sort"
	"sync"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/ir"
)

// DomainAnalyzer performs domain analysis for efficient grounding
type DomainAnalyzer struct {
	mu               sync.RWMutex
	predicateInfo    map[string]*PredicateInfo
	variableInfo     map[string]*VariableInfo
	domainBounds     map[string]DomainBound
	dependencyGraph  *DependencyGraph
}

// PredicateInfo contains metadata about a predicate
type PredicateInfo struct {
	Name            string
	Arity           int
	Occurrences     int
	InHeadCount     int
	InBodyCount     int
	GroundingSize   int
	IsRecursive     bool
	Dependencies    []string
}

// VariableInfo contains information about a variable
type VariableInfo struct {
	Name             string
	Occurrences      int
	PositiveCount    int
	NegativeCount    int
	AggregateCount   int
	PossibleValues   int
	IsSafe           bool
	BindingRules     []*ast.Rule
}

// DomainBound represents known bounds on a domain
type DomainBound struct {
	PredicateName string
	MinSize       int
	MaxSize       int
	IsFinite      bool
	ExactSize     int
}

// DependencyGraph represents dependencies between predicates
type DependencyGraph struct {
	nodes map[string]*DependencyNode
	edges map[string][]string
}

// DependencyNode represents a node in the dependency graph
type DependencyNode struct {
	Predicate  string
	Positive   map[string]bool // Positive dependencies
	Negative   map[string]bool // Negation dependencies
	Recursive  bool
	Stratified bool
}

// NewDomainAnalyzer creates a new domain analyzer
func NewDomainAnalyzer() *DomainAnalyzer {
	return &DomainAnalyzer{
		predicateInfo:   make(map[string]*PredicateInfo),
		variableInfo:    make(map[string]*VariableInfo),
		domainBounds:    make(map[string]DomainBound),
		dependencyGraph: NewDependencyGraph(),
	}
}

// NewDependencyGraph creates a new dependency graph
func NewDependencyGraph() *DependencyGraph {
	return &DependencyGraph{
		nodes: make(map[string]*DependencyNode),
		edges: make(map[string][]string),
	}
}

// AnalyzeProgram performs comprehensive domain analysis
func (da *DomainAnalyzer) AnalyzeProgram(program []ast.Statement) error {
	da.mu.Lock()
	defer da.mu.Unlock()

	// First pass: collect basic information
	if err := da.collectPredicateInfo(program); err != nil {
		return err
	}

	// Second pass: build dependency graph
	if err := da.buildDependencyGraph(program); err != nil {
		return err
	}

	// Third pass: analyze variables
	if err := da.analyzeVariables(program); err != nil {
		return err
	}

	// Fourth pass: estimate domain bounds
	if err := da.estimateDomainBounds(program); err != nil {
		return err
	}

	return nil
}

// collectPredicateInfo gathers information about each predicate
func (da *DomainAnalyzer) collectPredicateInfo(program []ast.Statement) error {
	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule

			// Process head
			if rule.Head != nil {
				for _, headAtom := range rule.Head.Atoms {
					pred := headAtom.Atom.Name
					arity := len(headAtom.Args)

					if info, exists := da.predicateInfo[pred]; exists {
						info.InHeadCount++
						if info.Arity != arity {
							return fmt.Errorf("predicate %s has inconsistent arity", pred)
						}
					} else {
						da.predicateInfo[pred] = &PredicateInfo{
							Name:        pred,
							Arity:       arity,
							InHeadCount: 1,
						}
					}
				}
			}

			// Process body
			for _, lit := range rule.Body {
				if lit.Atom != nil {
					pred := lit.Atom.Name
					arity := len(lit.Args)

					if info, exists := da.predicateInfo[pred]; exists {
						info.InBodyCount++
						if info.Arity != arity {
							return fmt.Errorf("predicate %s has inconsistent arity", pred)
						}
					} else {
						da.predicateInfo[pred] = &PredicateInfo{
							Name:       pred,
							Arity:      arity,
							InBodyCount: 1,
						}
					}
				}
			}
		}
	}

	return nil
}

// buildDependencyGraph creates a graph of predicate dependencies
func (da *DomainAnalyzer) buildDependencyGraph(program []ast.Statement) error {
	// Initialize all predicate nodes
	for pred := range da.predicateInfo {
		da.dependencyGraph.nodes[pred] = &DependencyNode{
			Predicate: pred,
			Positive:  make(map[string]bool),
			Negative:  make(map[string]bool),
			Recursive: false,
			Stratified: true,
		}
	}

	// Build edges
	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule

			// Get head predicates
			var headPreds []string
			if rule.Head != nil {
				for _, headAtom := range rule.Head.Atoms {
					headPreds = append(headPreds, headAtom.Atom.Name)
				}
			}

			// Add dependencies for each head predicate
			for _, headPred := range headPreds {
				if node, ok := da.dependencyGraph.nodes[headPred]; ok {
					// Add body predicate dependencies
					for _, lit := range rule.Body {
						if lit.Atom != nil {
							bodyPred := lit.Atom.Name
							if lit.Positive {
								node.Positive[bodyPred] = true
							} else {
								node.Negative[bodyPred] = true
							}

							if !da.dependencyGraph.hasEdge(headPred, bodyPred) {
								da.dependencyGraph.addEdge(headPred, bodyPred)
							}
						}
					}
				}
			}
		}
	}

	// Detect recursion
	da.detectRecursion()
	return nil
}

// detectRecursion identifies recursive predicates
func (da *DomainAnalyzer) detectRecursion() {
	for pred := range da.dependencyGraph.nodes {
		if da.hasPath(pred, pred) {
			da.dependencyGraph.nodes[pred].Recursive = true
			if info, ok := da.predicateInfo[pred]; ok {
				info.IsRecursive = true
			}
		}
	}
}

// hasPath checks if there's a path from src to dst in the dependency graph
func (da *DomainAnalyzer) hasPath(src, dst string) bool {
	visited := make(map[string]bool)
	return da.dfs(src, dst, visited)
}

// dfs performs depth-first search
func (da *DomainAnalyzer) dfs(current, target string, visited map[string]bool) bool {
	if visited[current] {
		return false
	}
	visited[current] = true

	if current == target && len(visited) > 1 {
		return true
	}

	for _, neighbor := range da.dependencyGraph.edges[current] {
		if da.dfs(neighbor, target, visited) {
			return true
		}
	}

	return false
}

// analyzeVariables examines variable properties
func (da *DomainAnalyzer) analyzeVariables(program []ast.Statement) error {
	vars := make(map[string]*VariableInfo)

	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule

			// Process head variables
			if rule.Head != nil {
				for _, headAtom := range rule.Head.Atoms {
					for _, arg := range headAtom.Args {
						if v, ok := arg.(*ast.Variable); ok && v.Name != "_" {
							if _, exists := vars[v.Name]; !exists {
								vars[v.Name] = &VariableInfo{
									Name:         v.Name,
									BindingRules: make([]*ast.Rule, 0),
								}
							}
							vars[v.Name].Occurrences++
						}
					}
				}
			}

			// Process body variables
			for _, lit := range rule.Body {
				if lit.Atom != nil {
					for _, arg := range lit.Args {
						if v, ok := arg.(*ast.Variable); ok && v.Name != "_" {
							if _, exists := vars[v.Name]; !exists {
								vars[v.Name] = &VariableInfo{
									Name:         v.Name,
									BindingRules: make([]*ast.Rule, 0),
								}
							}
							info := vars[v.Name]
							info.Occurrences++
							if lit.Positive {
								info.PositiveCount++
							} else {
								info.NegativeCount++
							}
						}
					}
				}
			}
		}
	}

	da.variableInfo = vars
	return nil
}

// estimateDomainBounds estimates the size of predicate domains
func (da *DomainAnalyzer) estimateDomainBounds(program []ast.Statement) error {
	// Count facts and estimate size
	factCounts := make(map[string]int)

	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule
			if rule.Type == ast.RULE_FACT || len(rule.Body) == 0 {
				if rule.Head != nil && len(rule.Head.Atoms) > 0 {
					pred := rule.Head.Atoms[0].Atom.Name
					factCounts[pred]++
				}
			}
		}
	}

	// Create bounds from facts
	for pred, count := range factCounts {
		da.domainBounds[pred] = DomainBound{
			PredicateName: pred,
			MinSize:       count,
			MaxSize:       count,
			IsFinite:      true,
			ExactSize:     count,
		}
	}

	return nil
}

// GetPredicateInfo returns information about a predicate
func (da *DomainAnalyzer) GetPredicateInfo(pred string) *PredicateInfo {
	da.mu.RLock()
	defer da.mu.RUnlock()
	return da.predicateInfo[pred]
}

// GetDomainBound returns size bound for a predicate
func (da *DomainAnalyzer) GetDomainBound(pred string) DomainBound {
	da.mu.RLock()
	defer da.mu.RUnlock()
	return da.domainBounds[pred]
}

// GetRecursivePredicates returns all recursive predicates
func (da *DomainAnalyzer) GetRecursivePredicates() []string {
	da.mu.RLock()
	defer da.mu.RUnlock()

	recursive := make([]string, 0)
	for pred, info := range da.predicateInfo {
		if info.IsRecursive {
			recursive = append(recursive, pred)
		}
	}
	sort.Strings(recursive)
	return recursive
}

// DependencyGraph helper methods
func (dg *DependencyGraph) hasEdge(src, dst string) bool {
	for _, edge := range dg.edges[src] {
		if edge == dst {
			return true
		}
	}
	return false
}

func (dg *DependencyGraph) addEdge(src, dst string) {
	dg.edges[src] = append(dg.edges[src], dst)
}

// IncrementalGrounder extends Grounder with incremental capabilities
type IncrementalGrounder struct {
	base        *Grounder
	snapshots   []*GroundingSnapshot
	currentIdx  int
}

// GroundingSnapshot represents a saved grounding state
type GroundingSnapshot struct {
	Rules    []*ir.GroundRule
	Atoms    []*ir.GroundAtom
	Domain   *ir.Domain
	Timestamp int64
}

// NewIncrementalGrounder creates a new incremental grounder
func NewIncrementalGrounder(g *Grounder) *IncrementalGrounder {
	return &IncrementalGrounder{
		base:       g,
		snapshots:  make([]*GroundingSnapshot, 0),
		currentIdx: -1,
	}
}

// Push saves current grounding state
func (ig *IncrementalGrounder) Push() {
	snapshot := &GroundingSnapshot{
		Rules:   append([]*ir.GroundRule{}, ig.base.groundRules...),
		Atoms:   make([]*ir.GroundAtom, 0),
		Domain:  ig.base.domain,
	}
	ig.snapshots = append(ig.snapshots, snapshot)
	ig.currentIdx = len(ig.snapshots) - 1
}

// Pop restores previous grounding state
func (ig *IncrementalGrounder) Pop() error {
	if len(ig.snapshots) == 0 {
		return fmt.Errorf("cannot pop: no snapshots available")
	}

	ig.currentIdx--
	return nil
}

// GroundRuleSet handles a set of grounded rules
type GroundRuleSet struct {
	mu          sync.RWMutex
	rules       map[uint64]*ir.GroundRule
	byHead      map[string][]*ir.GroundRule
	byBody      map[string][]*ir.GroundRule
	nextID      uint64
}

// NewGroundRuleSet creates a new rule set
func NewGroundRuleSet() *GroundRuleSet {
	return &GroundRuleSet{
		rules:  make(map[uint64]*ir.GroundRule),
		byHead: make(map[string][]*ir.GroundRule),
		byBody: make(map[string][]*ir.GroundRule),
		nextID: 1,
	}
}

// Add adds a ground rule to the set
func (grs *GroundRuleSet) Add(rule *ir.GroundRule) {
	grs.mu.Lock()
	defer grs.mu.Unlock()

	if rule.ID == 0 {
		rule.ID = grs.nextID
		grs.nextID++
	}

	grs.rules[rule.ID] = rule

	// Index by head
	for _, atom := range rule.Head {
		grs.byHead[atom.Predicate] = append(grs.byHead[atom.Predicate], rule)
	}

	// Index by body
	for _, lit := range rule.Body {
		if lit.Atom != nil {
			grs.byBody[lit.Atom.Predicate] = append(grs.byBody[lit.Atom.Predicate], rule)
		}
	}
}

// GetByHead returns rules with given head predicate
func (grs *GroundRuleSet) GetByHead(pred string) []*ir.GroundRule {
	grs.mu.RLock()
	defer grs.mu.RUnlock()
	return grs.byHead[pred]
}

// GetByBody returns rules with given body predicate
func (grs *GroundRuleSet) GetByBody(pred string) []*ir.GroundRule {
	grs.mu.RLock()
	defer grs.mu.RUnlock()
	return grs.byBody[pred]
}

// Count returns total number of rules
func (grs *GroundRuleSet) Count() int {
	grs.mu.RLock()
	defer grs.mu.RUnlock()
	return len(grs.rules)
}

// All returns all rules
func (grs *GroundRuleSet) All() []*ir.GroundRule {
	grs.mu.RLock()
	defer grs.mu.RUnlock()

	rules := make([]*ir.GroundRule, 0, len(grs.rules))
	for _, rule := range grs.rules {
		rules = append(rules, rule)
	}
	return rules
}

// GroundAtomSet manages a collection of ground atoms
type GroundAtomSet struct {
	mu         sync.RWMutex
	atoms      map[uint64]*ir.GroundAtom
	byPredicate map[string][]*ir.GroundAtom
	nextID     uint64
}

// NewGroundAtomSet creates a new atom set
func NewGroundAtomSet() *GroundAtomSet {
	return &GroundAtomSet{
		atoms:       make(map[uint64]*ir.GroundAtom),
		byPredicate: make(map[string][]*ir.GroundAtom),
		nextID:      1,
	}
}

// Add adds a ground atom to the set
func (gas *GroundAtomSet) Add(atom *ir.GroundAtom) {
	gas.mu.Lock()
	defer gas.mu.Unlock()

	if atom.ID == 0 {
		atom.ID = gas.nextID
		gas.nextID++
	}

	gas.atoms[atom.ID] = atom
	gas.byPredicate[atom.Predicate] = append(gas.byPredicate[atom.Predicate], atom)
}

// GetByPredicate returns atoms with given predicate
func (gas *GroundAtomSet) GetByPredicate(pred string) []*ir.GroundAtom {
	gas.mu.RLock()
	defer gas.mu.RUnlock()
	return gas.byPredicate[pred]
}

// Get retrieves atom by ID
func (gas *GroundAtomSet) Get(id uint64) (*ir.GroundAtom, bool) {
	gas.mu.RLock()
	defer gas.mu.RUnlock()
	atom, ok := gas.atoms[id]
	return atom, ok
}

// Count returns total number of atoms
func (gas *GroundAtomSet) Count() int {
	gas.mu.RLock()
	defer gas.mu.RUnlock()
	return len(gas.atoms)
}

// All returns all atoms
func (gas *GroundAtomSet) All() []*ir.GroundAtom {
	gas.mu.RLock()
	defer gas.mu.RUnlock()

	atoms := make([]*ir.GroundAtom, 0, len(gas.atoms))
	for _, atom := range gas.atoms {
		atoms = append(atoms, atom)
	}
	return atoms
}
