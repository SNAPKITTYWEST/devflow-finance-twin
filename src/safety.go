// Package ground implements safety checking for ASP rules
// Safety checking ensures that all variables in a rule head or constraints
// appear in positive body literals (preventing unsafe instantiation)
package ground

import (
	"fmt"
	"sort"
	"strings"

	"devflow-finance-twin/asp/ast"
)

// SafetyChecker validates that ASP rules satisfy safety constraints
// A rule is safe if every variable in the head appears in at least one
// positive body literal (not negated). This ensures finiteness of grounding.
type SafetyChecker struct {
	rules          []*ast.Rule
	diagnostics    []string
	unsafeVars     map[string]bool
	bodyVars       map[string]bool
	headVars       map[string]bool
	positiveVars   map[string]bool
	negativeOnlyVars map[string]bool
}

// NewSafetyChecker creates a new safety checker instance
func NewSafetyChecker() *SafetyChecker {
	return &SafetyChecker{
		rules:             make([]*ast.Rule, 0),
		diagnostics:       make([]string, 0),
		unsafeVars:        make(map[string]bool),
		bodyVars:          make(map[string]bool),
		headVars:          make(map[string]bool),
		positiveVars:      make(map[string]bool),
		negativeOnlyVars: make(map[string]bool),
	}
}

// IsSafe checks if a rule satisfies the safety constraint
// Returns true if rule is safe, false otherwise
func (sc *SafetyChecker) IsSafe(rule *ast.Rule) bool {
	// Reset temporary maps for this check
	sc.unsafeVars = make(map[string]bool)
	sc.bodyVars = make(map[string]bool)
	sc.headVars = make(map[string]bool)
	sc.positiveVars = make(map[string]bool)
	sc.negativeOnlyVars = make(map[string]bool)

	// Facts are always safe
	if rule.Type == ast.RULE_FACT || len(rule.Body) == 0 {
		return true
	}

	// Extract head variables
	sc.extractHeadVariables(rule)

	// Extract body variables
	sc.extractBodyVariables(rule)

	// Check safety: every head variable must appear in a positive body literal
	for headVar := range sc.headVars {
		if !sc.positiveVars[headVar] {
			sc.unsafeVars[headVar] = true
		}
	}

	// If there are unsafe variables, rule is not safe
	return len(sc.unsafeVars) == 0
}

// CheckSafety performs comprehensive safety analysis on a program
// Returns list of safety violations found
func (sc *SafetyChecker) CheckSafety(program []ast.Statement) []string {
	sc.diagnostics = make([]string, 0)
	sc.rules = make([]*ast.Rule, 0)

	// Extract all rules from statements
	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			sc.rules = append(sc.rules, rs.Rule)
		}
	}

	// Check each rule
	for _, rule := range sc.rules {
		if !sc.IsSafe(rule) {
			diagnostic := sc.generateSafetyDiagnostic(rule)
			sc.diagnostics = append(sc.diagnostics, diagnostic)
		}
	}

	return sc.diagnostics
}

// extractHeadVariables collects all variables appearing in rule head
func (sc *SafetyChecker) extractHeadVariables(rule *ast.Rule) {
	if rule.Head == nil {
		return
	}

	for _, headAtom := range rule.Head.Atoms {
		if headAtom != nil {
			for _, arg := range headAtom.Args {
				sc.extractVariablesFromTerm(arg, sc.headVars)
			}
		}
	}
}

// extractBodyVariables collects variables from body literals
// Distinguishes between positive (safe) and negative (potentially unsafe) occurrences
func (sc *SafetyChecker) extractBodyVariables(rule *ast.Rule) {
	for _, lit := range rule.Body {
		if lit.Atom != nil {
			// Extract variables from literal arguments
			for _, arg := range lit.Args {
				sc.extractVariablesFromTerm(arg, sc.bodyVars)

				// Track positive vs negative occurrences
				if lit.Positive {
					sc.extractVariablesFromTerm(arg, sc.positiveVars)
				} else {
					// For negative literals, mark as potential negation-only variables
					if v, ok := arg.(*ast.Variable); ok && v.Name != "_" {
						if !sc.positiveVars[v.Name] {
							sc.negativeOnlyVars[v.Name] = true
						}
					}
				}
			}
		}

		// Extract variables from aggregate expressions
		if lit.Aggregate != nil {
			for _, aggVar := range lit.Aggregate.Variables {
				sc.extractVariablesFromTerm(aggVar, sc.bodyVars)
				if lit.Positive {
					sc.extractVariablesFromTerm(aggVar, sc.positiveVars)
				}
			}

			// Extract variables from aggregate condition
			if lit.Aggregate.Condition != nil {
				for _, arg := range lit.Aggregate.Condition.Args {
					sc.extractVariablesFromTerm(arg, sc.bodyVars)
					if lit.Aggregate.Condition.Positive {
						sc.extractVariablesFromTerm(arg, sc.positiveVars)
					}
				}
			}
		}
	}
}

// extractVariablesFromTerm recursively extracts all variables from a term
func (sc *SafetyChecker) extractVariablesFromTerm(term ast.Term, varSet map[string]bool) {
	switch t := term.(type) {
	case *ast.Variable:
		// Don't track anonymous variables
		if t.Name != "_" {
			varSet[t.Name] = true
		}
	case *ast.Compound:
		// Recursively process compound term arguments
		for _, arg := range t.Args {
			sc.extractVariablesFromTerm(arg, varSet)
		}
	case *ast.Constant:
		// Constants don't contain variables
	case *ast.Atom:
		// Atoms don't contain variables
	}
}

// generateSafetyDiagnostic creates a detailed error message for an unsafe rule
func (sc *SafetyChecker) generateSafetyDiagnostic(rule *ast.Rule) string {
	// Collect unsafe variables again for diagnostic
	unsafeVars := make([]string, 0)
	for headVar := range sc.headVars {
		if !sc.positiveVars[headVar] {
			unsafeVars = append(unsafeVars, headVar)
		}
	}
	sort.Strings(unsafeVars)

	headStr := sc.formatRuleHead(rule)
	bodyStr := sc.formatRuleBody(rule)
	varStr := strings.Join(unsafeVars, ", ")

	return fmt.Sprintf(
		"Safety violation at %v: unsafe variable(s) [%s] in head do not appear in positive body. Rule: %s :- %s",
		rule.Pos, varStr, headStr, bodyStr,
	)
}

// formatRuleHead returns a string representation of the rule head
func (sc *SafetyChecker) formatRuleHead(rule *ast.Rule) string {
	if rule.Head == nil || len(rule.Head.Atoms) == 0 {
		return ""
	}

	parts := make([]string, 0)
	for _, atom := range rule.Head.Atoms {
		parts = append(parts, sc.formatHeadAtom(atom))
	}
	return strings.Join(parts, " | ")
}

// formatHeadAtom returns string representation of a head atom
func (sc *SafetyChecker) formatHeadAtom(atom *ast.HeadAtom) string {
	if atom == nil || atom.Atom == nil {
		return ""
	}

	if len(atom.Args) == 0 {
		return atom.Atom.Name
	}

	argStrs := make([]string, 0)
	for _, arg := range atom.Args {
		argStrs = append(argStrs, sc.formatTerm(arg))
	}
	return fmt.Sprintf("%s(%s)", atom.Atom.Name, strings.Join(argStrs, ", "))
}

// formatRuleBody returns a string representation of the rule body
func (sc *SafetyChecker) formatRuleBody(rule *ast.Rule) string {
	if len(rule.Body) == 0 {
		return ""
	}

	parts := make([]string, 0)
	for _, lit := range rule.Body {
		parts = append(parts, sc.formatLiteral(lit))
	}
	return strings.Join(parts, ", ")
}

// formatLiteral returns string representation of a literal
func (sc *SafetyChecker) formatLiteral(lit *ast.Literal) string {
	prefix := ""
	if !lit.Positive {
		prefix = "not "
	}

	if lit.Atom == nil {
		return ""
	}

	if len(lit.Args) == 0 {
		return prefix + lit.Atom.Name
	}

	argStrs := make([]string, 0)
	for _, arg := range lit.Args {
		argStrs = append(argStrs, sc.formatTerm(arg))
	}
	return fmt.Sprintf("%s%s(%s)", prefix, lit.Atom.Name, strings.Join(argStrs, ", "))
}

// formatTerm returns string representation of a term
func (sc *SafetyChecker) formatTerm(term ast.Term) string {
	switch t := term.(type) {
	case *ast.Variable:
		return t.Name
	case *ast.Atom:
		return t.Name
	case *ast.Constant:
		switch t.Type {
		case ast.CONST_STRING:
			return fmt.Sprintf("\"%v\"", t.Value)
		default:
			return fmt.Sprintf("%v", t.Value)
		}
	case *ast.Compound:
		if len(t.Args) == 0 {
			return t.Functor
		}
		argStrs := make([]string, 0)
		for _, arg := range t.Args {
			argStrs = append(argStrs, sc.formatTerm(arg))
		}
		return fmt.Sprintf("%s(%s)", t.Functor, strings.Join(argStrs, ", "))
	default:
		return "?"
	}
}

// GetUnsafeVariables returns the set of unsafe variables from the last check
func (sc *SafetyChecker) GetUnsafeVariables() []string {
	vars := make([]string, 0)
	for v := range sc.unsafeVars {
		vars = append(vars, v)
	}
	sort.Strings(vars)
	return vars
}

// GetDiagnostics returns all accumulated diagnostics
func (sc *SafetyChecker) GetDiagnostics() []string {
	return sc.diagnostics
}

// HasDiagnostics returns true if any diagnostics were recorded
func (sc *SafetyChecker) HasDiagnostics() bool {
	return len(sc.diagnostics) > 0
}

// ClearDiagnostics resets the diagnostic list
func (sc *SafetyChecker) ClearDiagnostics() {
	sc.diagnostics = make([]string, 0)
}

// CheckAggregateElementVariables ensures variables in aggregate elements are safe
// An aggregate element variable X is safe if:
// 1. X appears in the aggregate condition as a positive literal, OR
// 2. X appears in the condition of the aggregate bound
func (sc *SafetyChecker) CheckAggregateElementVariables(agg *ast.Aggregate, rule *ast.Rule) bool {
	if agg == nil {
		return true
	}

	// Collect variables from aggregate
	aggVars := make(map[string]bool)
	for _, v := range agg.Variables {
		sc.extractVariablesFromTerm(v, aggVars)
	}

	// Collect variables appearing positively in aggregate condition
	condVars := make(map[string]bool)
	if agg.Condition != nil {
		for _, arg := range agg.Condition.Args {
			if agg.Condition.Positive {
				sc.extractVariablesFromTerm(arg, condVars)
			}
		}
	}

	// Check: each aggregate variable must appear in condition
	for aggVar := range aggVars {
		if !condVars[aggVar] {
			return false
		}
	}

	return true
}

// CheckConstraintVariables ensures all variables in a constraint appear in positive body
// Constraints have no head, so all variables must appear in positive body literals
func (sc *SafetyChecker) CheckConstraintVariables(constraint *ast.Rule) bool {
	if constraint.Type != ast.RULE_CONSTRAINT {
		return true
	}

	// Extract all variables from body
	bodyVars := make(map[string]bool)
	positiveBodyVars := make(map[string]bool)

	for _, lit := range constraint.Body {
		if lit.Atom != nil {
			for _, arg := range lit.Args {
				sc.extractVariablesFromTerm(arg, bodyVars)
				if lit.Positive {
					sc.extractVariablesFromTerm(arg, positiveBodyVars)
				}
			}
		}
	}

	// All variables must appear positively
	for v := range bodyVars {
		if !positiveBodyVars[v] {
			return false
		}
	}

	return true
}

// ValidateSafetyComprehensive performs full safety validation
// Checks:
// 1. Rule safety (head variables in positive body)
// 2. Constraint safety (all variables in positive body)
// 3. Aggregate safety (element variables in condition)
func (sc *SafetyChecker) ValidateSafetyComprehensive(rule *ast.Rule) (safe bool, message string) {
	// Rule safety check
	if !sc.IsSafe(rule) {
		unsafeVars := sc.GetUnsafeVariables()
		return false, fmt.Sprintf("rule safety violation: unsafe variables %v", unsafeVars)
	}

	// Constraint safety check
	if !sc.CheckConstraintVariables(rule) {
		return false, "constraint safety violation: not all variables in positive body"
	}

	// Aggregate safety check
	for _, lit := range rule.Body {
		if lit.Aggregate != nil {
			if !sc.CheckAggregateElementVariables(lit.Aggregate, rule) {
				return false, fmt.Sprintf("aggregate safety violation in %s", lit.Atom.Name)
			}
		}
	}

	return true, ""
}

// SortSafetyErrors returns safety diagnostics sorted by severity
func (sc *SafetyChecker) SortSafetyErrors() []string {
	// Sort by position information if available
	sorted := make([]string, len(sc.diagnostics))
	copy(sorted, sc.diagnostics)
	sort.Strings(sorted)
	return sorted
}

// FilterSafeRules returns only the safe rules from a rule list
func (sc *SafetyChecker) FilterSafeRules(rules []*ast.Rule) []*ast.Rule {
	safe := make([]*ast.Rule, 0)
	for _, rule := range rules {
		if sc.IsSafe(rule) {
			safe = append(safe, rule)
		}
	}
	return safe
}

// CountUnsafeRules returns the number of unsafe rules in a program
func (sc *SafetyChecker) CountUnsafeRules(rules []*ast.Rule) int {
	count := 0
	for _, rule := range rules {
		if !sc.IsSafe(rule) {
			count++
		}
	}
	return count
}

// GetSafetyViolations returns detailed information about each unsafe rule
type SafetyViolation struct {
	Rule           *ast.Rule
	UnsafeVariables []string
	Message        string
}

// AnalyzeSafetyViolations returns detailed violation information
func (sc *SafetyChecker) AnalyzeSafetyViolations(rules []*ast.Rule) []SafetyViolation {
	violations := make([]SafetyViolation, 0)

	for _, rule := range rules {
		if !sc.IsSafe(rule) {
			unsafeVars := sc.GetUnsafeVariables()
			violation := SafetyViolation{
				Rule:            rule,
				UnsafeVariables: unsafeVars,
				Message:         sc.generateSafetyDiagnostic(rule),
			}
			violations = append(violations, violation)
		}
	}

	return violations
}
