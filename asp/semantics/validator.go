package semantics

import (
	"fmt"
	"strings"

	"devflow-finance-twin/asp/ast"
)

// Severity represents diagnostic severity level
type Severity int

const (
	SEV_ERROR Severity = iota
	SEV_WARNING
	SEV_INFO
)

// Diagnostic represents a semantic error, warning, or info message
type Diagnostic struct {
	File       string
	Line       int
	Column     int
	Severity   Severity
	Code       string
	Message    string
	Suggestion string
	Context    string // Source line or relevant context
}

func (d Diagnostic) String() string {
	return fmt.Sprintf("%s:%d:%d: %s [%s]: %s", d.File, d.Line, d.Column, d.severityStr(), d.Code, d.Message)
}

func (d Diagnostic) severityStr() string {
	switch d.Severity {
	case SEV_ERROR:
		return "error"
	case SEV_WARNING:
		return "warning"
	case SEV_INFO:
		return "info"
	default:
		return "unknown"
	}
}

// Validator performs semantic analysis on ASP programs
type Validator struct {
	// undefined tracks which predicates are used but not defined
	undefined map[string]bool

	// defined tracks predicates that have been explicitly defined
	defined map[string]bool

	// diagnostics accumulates all validation issues
	diagnostics []Diagnostic

	// rules keeps reference to all rules for validation passes
	rules []*ast.Rule

	// currentFile for error reporting
	currentFile string
}

// NewValidator creates a new semantic validator
func NewValidator() *Validator {
	return &Validator{
		undefined:   make(map[string]bool),
		defined:     make(map[string]bool),
		diagnostics: make([]Diagnostic, 0),
		rules:       make([]*ast.Rule, 0),
	}
}

// ValidateProgram performs complete semantic analysis on an ASP program
// Returns all diagnostics found (errors, warnings, and info messages)
func (v *Validator) ValidateProgram(program []ast.Statement) []Diagnostic {
	v.diagnostics = make([]Diagnostic, 0)
	v.rules = make([]*ast.Rule, 0)
	v.defined = make(map[string]bool)
	v.undefined = make(map[string]bool)

	// Extract all rules from statements
	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			v.rules = append(v.rules, rs.Rule)
		}
	}

	// Pass 1: Collect all defined predicates
	v.collectDefinedPredicates()

	// Pass 2: Check undefined predicates
	undefinedDiags := v.CheckUndefined(program)
	v.diagnostics = append(v.diagnostics, undefinedDiags...)

	// Pass 3: Check safety of each rule
	for _, rule := range v.rules {
		if err := v.CheckSafety(rule); err != nil {
			// CheckSafety adds diagnostics directly
		}
	}

	// Pass 4: Check aggregate syntax
	for _, rule := range v.rules {
		v.checkAggregatesInRule(rule)
	}

	// Pass 5: Check for negative cycles in dependency graph
	v.checkNegativeCycles()

	return v.diagnostics
}

// collectDefinedPredicates scans all rules and marks predicates as defined
func (v *Validator) collectDefinedPredicates() {
	for _, rule := range v.rules {
		if rule.Head == nil || len(rule.Head.Atoms) == 0 {
			continue
		}
		for _, headAtom := range rule.Head.Atoms {
			if headAtom.Atom != nil {
				// Predicate is identified by name/arity for better precision
				predID := predicateID(headAtom.Atom.Name, len(headAtom.Args))
				v.defined[predID] = true
			}
		}
	}
}

// CheckUndefined checks that all used predicates are defined
func (v *Validator) CheckUndefined(program []ast.Statement) []Diagnostic {
	diags := make([]Diagnostic, 0)

	for _, rule := range v.rules {
		// Check body literals
		if rule.Body != nil {
			for _, lit := range rule.Body {
				if lit.Atom != nil {
					arity := 0
					if lit.Args != nil {
						arity = len(lit.Args)
					}
					predID := predicateID(lit.Atom.Name, arity)

					// Built-in predicates are always defined
					if isBuiltin(lit.Atom.Name) {
						continue
					}

					// Check if predicate is defined
					if !v.defined[predID] {
						diag := Diagnostic{
							File:       lit.Pos.File,
							Line:       lit.Pos.Line,
							Column:     lit.Pos.Column,
							Severity:   SEV_ERROR,
							Code:       "undefined_pred",
							Message:    fmt.Sprintf("predicate '%s/%d' is not defined", lit.Atom.Name, arity),
							Suggestion: fmt.Sprintf("Define a rule for %s/%d or ensure it's imported", lit.Atom.Name, arity),
							Context:    fmt.Sprintf("In rule at %s:%d", rule.Pos.File, rule.Pos.Line),
						}
						diags = append(diags, diag)
					}
				}
				// Check aggregates for undefined predicates
				if lit.Aggregate != nil {
					if lit.Aggregate.Condition != nil && lit.Aggregate.Condition.Atom != nil {
						arity := 0
						if lit.Aggregate.Condition.Args != nil {
							arity = len(lit.Aggregate.Condition.Args)
						}
						predID := predicateID(lit.Aggregate.Condition.Atom.Name, arity)
						if !isBuiltin(lit.Aggregate.Condition.Atom.Name) && !v.defined[predID] {
							diag := Diagnostic{
								File:       lit.Aggregate.Pos.File,
								Line:       lit.Aggregate.Pos.Line,
								Column:     lit.Aggregate.Pos.Column,
								Severity:   SEV_ERROR,
								Code:       "undefined_pred_aggregate",
								Message:    fmt.Sprintf("predicate '%s/%d' in aggregate is not defined", lit.Aggregate.Condition.Atom.Name, arity),
								Suggestion: fmt.Sprintf("Define %s/%d", lit.Aggregate.Condition.Atom.Name, arity),
								Context:    fmt.Sprintf("In aggregate at %s:%d", lit.Aggregate.Pos.File, lit.Aggregate.Pos.Line),
							}
							diags = append(diags, diag)
						}
					}
				}
			}
		}
	}

	return diags
}

// CheckSafety verifies that all variables in the head appear in positive body literals
func (v *Validator) CheckSafety(rule *ast.Rule) error {
	if rule == nil || rule.Head == nil {
		return nil
	}

	// Collect all variables appearing in head
	headVars := make(map[string]bool)
	for _, headAtom := range rule.Head.Atoms {
		v.collectVariablesFromTerms(headAtom.Args, headVars)
	}

	// Collect all variables appearing in positive body literals
	positiveBodyVars := make(map[string]bool)
	if rule.Body != nil {
		for _, lit := range rule.Body {
			if lit.Positive { // Only positive literals
				v.collectVariablesFromTerms(lit.Args, positiveBodyVars)
				if lit.Aggregate != nil {
					v.collectVariablesFromAggregate(lit.Aggregate, positiveBodyVars)
				}
			}
		}
	}

	// Check each head variable appears in positive body
	for headVar := range headVars {
		if headVar == "_" {
			continue // Anonymous variables are always safe
		}
		if !positiveBodyVars[headVar] {
			diag := Diagnostic{
				File:       rule.Pos.File,
				Line:       rule.Pos.Line,
				Column:     rule.Pos.Column,
				Severity:   SEV_ERROR,
				Code:       "unsafe_var",
				Message:    fmt.Sprintf("variable '%s' in head does not appear in positive body", headVar),
				Suggestion: fmt.Sprintf("Add '%s' to a positive body literal or make it anonymous (_)", headVar),
				Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
			}
			v.diagnostics = append(v.diagnostics, diag)
		}
	}

	return nil
}

// collectVariablesFromTerms extracts all variables from a list of terms
func (v *Validator) collectVariablesFromTerms(terms []ast.Term, vars map[string]bool) {
	for _, term := range terms {
		if varTerm, ok := term.(*ast.Variable); ok {
			vars[varTerm.Name] = true
		} else if compTerm, ok := term.(*ast.Compound); ok {
			v.collectVariablesFromTerms(compTerm.Args, vars)
		}
	}
}

// collectVariablesFromAggregate extracts variables from aggregate elements
func (v *Validator) collectVariablesFromAggregate(agg *ast.Aggregate, vars map[string]bool) {
	if agg.Variables != nil {
		v.collectVariablesFromTerms(agg.Variables, vars)
	}
	if agg.Condition != nil {
		v.collectVariablesFromTerms(agg.Condition.Args, vars)
	}
}

// CheckAggregates verifies aggregate syntax and semantics
func (v *Validator) CheckAggregates(agg *ast.Aggregate) error {
	if agg == nil {
		return nil
	}

	// Validate aggregate operation
	switch agg.Op {
	case ast.AGG_COUNT, ast.AGG_SUM, ast.AGG_MIN, ast.AGG_MAX:
		// Valid operations
	default:
		diag := Diagnostic{
			File:       agg.Pos.File,
			Line:       agg.Pos.Line,
			Column:     agg.Pos.Column,
			Severity:   SEV_ERROR,
			Code:       "invalid_aggregate_op",
			Message:    fmt.Sprintf("invalid aggregate operation '%s'", agg.Op),
			Suggestion: fmt.Sprintf("Use one of: count, sum, min, max"),
			Context:    fmt.Sprintf("Aggregate at %s:%d", agg.Pos.File, agg.Pos.Line),
		}
		v.diagnostics = append(v.diagnostics, diag)
		return fmt.Errorf("invalid aggregate operation: %s", agg.Op)
	}

	// Check bounds consistency
	if agg.Bound != nil {
		if agg.Bound.Lower != nil && agg.Bound.Upper != nil {
			// For numeric aggregates, verify bounds make sense
			// This would require evaluating constants - simplified here
			if agg.Op == ast.AGG_SUM || agg.Op == ast.AGG_COUNT {
				// Bounds should be numeric
			}
		}
	}

	// Validate condition
	if agg.Condition != nil && agg.Condition.Atom != nil {
		if agg.Condition.Atom.Name == "" {
			diag := Diagnostic{
				File:       agg.Pos.File,
				Line:       agg.Pos.Line,
				Column:     agg.Pos.Column,
				Severity:   SEV_ERROR,
				Code:       "invalid_aggregate_condition",
				Message:    "aggregate condition has empty predicate name",
				Suggestion: "Provide a valid predicate name in aggregate condition",
				Context:    fmt.Sprintf("Aggregate at %s:%d", agg.Pos.File, agg.Pos.Line),
			}
			v.diagnostics = append(v.diagnostics, diag)
			return fmt.Errorf("invalid aggregate condition: empty predicate")
		}
	}

	return nil
}

// checkAggregatesInRule checks all aggregates in a rule
func (v *Validator) checkAggregatesInRule(rule *ast.Rule) {
	if rule == nil || rule.Body == nil {
		return
	}
	for _, lit := range rule.Body {
		if lit.Aggregate != nil {
			v.CheckAggregates(lit.Aggregate)
		}
	}
}

// checkNegativeCycles detects cycles through negation (not allowed in stable semantics)
func (v *Validator) checkNegativeCycles() {
	// Build dependency graph
	graph := make(map[string][]depEdge)

	for _, rule := range v.rules {
		if rule.Head == nil || len(rule.Head.Atoms) == 0 {
			continue
		}

		headPred := predicateID(rule.Head.Atoms[0].Atom.Name, len(rule.Head.Atoms[0].Args))

		if rule.Body == nil {
			continue
		}

		for _, lit := range rule.Body {
			if lit.Atom == nil {
				continue
			}
			bodyPred := predicateID(lit.Atom.Name, len(lit.Args))
			edge := depEdge{
				to:       bodyPred,
				positive: lit.Positive,
			}
			graph[headPred] = append(graph[headPred], edge)
		}
	}

	// Detect cycles with negative edges using DFS
	visited := make(map[string]bool)
	recStack := make(map[string]bool)

	for node := range graph {
		if !visited[node] {
			v.dfsCycleDetection(node, graph, visited, recStack, []string{})
		}
	}
}

type depEdge struct {
	to       string
	positive bool
}

// dfsCycleDetection performs DFS to detect negative cycles
func (v *Validator) dfsCycleDetection(node string, graph map[string][]depEdge, visited, recStack map[string]bool, path []string) {
	visited[node] = true
	recStack[node] = true
	path = append(path, node)

	if edges, exists := graph[node]; exists {
		for _, edge := range edges {
			if !visited[edge.to] {
				v.dfsCycleDetection(edge.to, graph, visited, recStack, path)
			} else if recStack[edge.to] && !edge.positive {
				// Found a cycle with a negative edge
				cycleStart := -1
				for i, p := range path {
					if p == edge.to {
						cycleStart = i
						break
					}
				}
				if cycleStart >= 0 {
					cyclePath := strings.Join(path[cycleStart:], " -> ")
					diag := Diagnostic{
						File:       "",
						Line:       0,
						Column:     0,
						Severity:   SEV_ERROR,
						Code:       "negative_cycle",
						Message:    fmt.Sprintf("negative cycle detected: %s -> %s", cyclePath, edge.to),
						Suggestion: "Remove negation from cycle or restructure rules",
						Context:    "Program contains unstable semantics",
					}
					v.diagnostics = append(v.diagnostics, diag)
				}
			}
		}
	}

	recStack[node] = false
}

// Helper functions

// predicateID creates a unique identifier for a predicate based on name and arity
func predicateID(name string, arity int) string {
	return fmt.Sprintf("%s/%d", name, arity)
}

// isBuiltin checks if a predicate is a built-in (comparison, arithmetic, etc.)
func isBuiltin(name string) bool {
	builtins := map[string]bool{
		"=":       true,
		"!=":      true,
		"<":       true,
		">":       true,
		"<=":      true,
		">=":      true,
		"is":      true,
		"true":    true,
		"false":   true,
		"fail":    true,
		"!":       true,
		"\\+":     true,
	}
	return builtins[name]
}

// GetDiagnostics returns all accumulated diagnostics
func (v *Validator) GetDiagnostics() []Diagnostic {
	return v.diagnostics
}

// HasErrors returns true if there are any error diagnostics
func (v *Validator) HasErrors() bool {
	for _, diag := range v.diagnostics {
		if diag.Severity == SEV_ERROR {
			return true
		}
	}
	return false
}

// ErrorCount returns the number of error diagnostics
func (v *Validator) ErrorCount() int {
	count := 0
	for _, diag := range v.diagnostics {
		if diag.Severity == SEV_ERROR {
			count++
		}
	}
	return count
}

// WarningCount returns the number of warning diagnostics
func (v *Validator) WarningCount() int {
	count := 0
	for _, diag := range v.diagnostics {
		if diag.Severity == SEV_WARNING {
			count++
		}
	}
	return count
}
