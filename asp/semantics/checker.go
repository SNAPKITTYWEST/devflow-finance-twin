package semantics

import (
	"fmt"
	"sort"

	"devflow-finance-twin/asp/ast"
)

// Checker performs fine-grained semantic checks on ASP programs
type Checker struct {
	validator      *Validator
	rules          []*ast.Rule
	diagnostics    []Diagnostic
	dependencyMap  map[string][]string // predicate dependencies
	aggregateRules []*ast.Rule          // rules containing aggregates
}

// NewChecker creates a new semantic checker
func NewChecker(v *Validator) *Checker {
	return &Checker{
		validator:      v,
		rules:          make([]*ast.Rule, 0),
		diagnostics:    make([]Diagnostic, 0),
		dependencyMap:  make(map[string][]string),
		aggregateRules: make([]*ast.Rule, 0),
	}
}

// CheckProgram performs all semantic checks on the program
func (c *Checker) CheckProgram(program []ast.Statement) []Diagnostic {
	// Extract rules
	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			c.rules = append(c.rules, rs.Rule)
		}
	}

	// Run all checks
	c.checkRecursion()
	c.checkAggregateUsage()
	c.checkChoiceRules()
	c.checkConstraints()
	c.checkStrictly()

	return c.diagnostics
}

// checkRecursion detects recursive predicates
func (c *Checker) checkRecursion() {
	// Build dependency map
	for _, rule := range c.rules {
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
			// Add edge from head to body
			c.dependencyMap[headPred] = append(c.dependencyMap[headPred], bodyPred)
		}
	}

	// Detect cycles through positive literals (recursion)
	visited := make(map[string]bool)
	recStack := make(map[string]bool)
	path := make(map[string][]string)

	for pred := range c.dependencyMap {
		if !visited[pred] {
			c.dfsRecursion(pred, visited, recStack, path, []string{})
		}
	}
}

// dfsRecursion performs DFS to detect positive cycles (left recursion)
func (c *Checker) dfsRecursion(node string, visited, recStack map[string]bool, path map[string][]string, currentPath []string) {
	visited[node] = true
	recStack[node] = true
	currentPath = append(currentPath, node)
	path[node] = currentPath

	if edges, exists := c.dependencyMap[node]; exists {
		for _, edge := range edges {
			if !visited[edge] {
				c.dfsRecursion(edge, visited, recStack, path, append([]string{}, currentPath...))
			} else if recStack[edge] {
				// Found a cycle - left recursion
				cycleStart := -1
				for i, p := range currentPath {
					if p == edge {
						cycleStart = i
						break
					}
				}
				if cycleStart >= 0 {
					// This is informational, not an error in ASP
					diag := Diagnostic{
						File:       "",
						Line:       0,
						Column:     0,
						Severity:   SEV_INFO,
						Code:       "left_recursion",
						Message:    fmt.Sprintf("left-recursive predicate detected: %s", edge),
						Suggestion: "Consider optimizing with tail-call or reordering body literals",
						Context:    fmt.Sprintf("Cycle: %v", currentPath[cycleStart:]),
					}
					c.diagnostics = append(c.diagnostics, diag)
				}
			}
		}
	}

	recStack[node] = false
}

// checkAggregateUsage validates aggregate usage patterns
func (c *Checker) checkAggregateUsage() {
	for _, rule := range c.rules {
		if rule.Body == nil {
			continue
		}

		for _, lit := range rule.Body {
			if lit.Aggregate == nil {
				continue
			}

			c.aggregateRules = append(c.aggregateRules, rule)

			// Check 1: Aggregates should only appear in non-choice rules
			if rule.Type == ast.RULE_CHOICE {
				diag := Diagnostic{
					File:       lit.Aggregate.Pos.File,
					Line:       lit.Aggregate.Pos.Line,
					Column:     lit.Aggregate.Pos.Column,
					Severity:   SEV_WARNING,
					Code:       "aggregate_in_choice",
					Message:    "aggregate appears in choice rule",
					Suggestion: "Consider using aggregate in non-choice rule for clarity",
					Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
				}
				c.diagnostics = append(c.diagnostics, diag)
			}

			// Check 2: Validate aggregate variables
			if lit.Aggregate.Variables == nil || len(lit.Aggregate.Variables) == 0 {
				diag := Diagnostic{
					File:       lit.Aggregate.Pos.File,
					Line:       lit.Aggregate.Pos.Line,
					Column:     lit.Aggregate.Pos.Column,
					Severity:   SEV_WARNING,
					Code:       "aggregate_no_variables",
					Message:    "aggregate has no variables to aggregate over",
					Suggestion: "Add variable bindings to aggregate",
					Context:    fmt.Sprintf("Aggregate at %s:%d", lit.Aggregate.Pos.File, lit.Aggregate.Pos.Line),
				}
				c.diagnostics = append(c.diagnostics, diag)
			}

			// Check 3: For SUM aggregates, ensure numeric context
			if lit.Aggregate.Op == ast.AGG_SUM {
				c.checkSumAggregate(lit.Aggregate, rule)
			}
		}
	}
}

// checkSumAggregate validates sum aggregate usage
func (c *Checker) checkSumAggregate(agg *ast.Aggregate, rule *ast.Rule) {
	// SUM should have numeric bounds or be used in comparison
	if agg.Bound == nil {
		diag := Diagnostic{
			File:       agg.Pos.File,
			Line:       agg.Pos.Line,
			Column:     agg.Pos.Column,
			Severity:   SEV_INFO,
			Code:       "sum_aggregate_unbounded",
			Message:    "unbounded sum aggregate",
			Suggestion: "Consider adding bounds like #sum { X : elem(X) } N",
			Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
		}
		c.diagnostics = append(c.diagnostics, diag)
	}
}

// checkChoiceRules validates choice rule structure
func (c *Checker) checkChoiceRules() {
	for _, rule := range c.rules {
		if rule.Type != ast.RULE_CHOICE {
			continue
		}

		// Check 1: Choice rules should have multiple head atoms
		if rule.Head != nil && len(rule.Head.Atoms) == 1 {
			diag := Diagnostic{
				File:       rule.Pos.File,
				Line:       rule.Pos.Line,
				Column:     rule.Pos.Column,
				Severity:   SEV_INFO,
				Code:       "single_choice",
				Message:    "choice rule has only one head atom",
				Suggestion: "Add more alternatives or convert to normal rule",
				Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
			}
			c.diagnostics = append(c.diagnostics, diag)
		}

		// Check 2: Choice rules with empty body are allowed (free choices)
		if rule.Body == nil || len(rule.Body) == 0 {
			diag := Diagnostic{
				File:       rule.Pos.File,
				Line:       rule.Pos.Line,
				Column:     rule.Pos.Column,
				Severity:   SEV_INFO,
				Code:       "free_choice",
				Message:    "free choice rule (always non-deterministic)",
				Suggestion: "Ensure this is intentional",
				Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
			}
			c.diagnostics = append(c.diagnostics, diag)
		}
	}
}

// checkConstraints validates constraint rule structure
func (c *Checker) checkConstraints() {
	for _, rule := range c.rules {
		if rule.Type != ast.RULE_CONSTRAINT {
			continue
		}

		// Constraints should have empty head
		if rule.Head != nil && len(rule.Head.Atoms) > 0 {
			diag := Diagnostic{
				File:       rule.Pos.File,
				Line:       rule.Pos.Line,
				Column:     rule.Pos.Column,
				Severity:   SEV_ERROR,
				Code:       "constraint_with_head",
				Message:    "constraint rule has non-empty head",
				Suggestion: "Remove head atoms from constraint rule",
				Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
			}
			c.diagnostics = append(c.diagnostics, diag)
		}

		// Constraints should have body
		if rule.Body == nil || len(rule.Body) == 0 {
			diag := Diagnostic{
				File:       rule.Pos.File,
				Line:       rule.Pos.Line,
				Column:     rule.Pos.Column,
				Severity:   SEV_ERROR,
				Code:       "empty_constraint",
				Message:    "constraint rule has empty body",
				Suggestion: "Add conditions to constraint",
				Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
			}
			c.diagnostics = append(c.diagnostics, diag)
		}
	}
}

// checkStrictly validates that the program is "strictly" stratifiable
func (c *Checker) checkStrictly() {
	// Build stratification levels
	strata := make(map[string]int)
	changed := true
	iteration := 0
	maxIterations := 100

	for changed && iteration < maxIterations {
		changed = false
		iteration++

		for _, rule := range c.rules {
			if rule.Head == nil || len(rule.Head.Atoms) == 0 {
				continue
			}

			headPred := predicateID(rule.Head.Atoms[0].Atom.Name, len(rule.Head.Atoms[0].Args))
			currentStratum := strata[headPred]

			maxBodyStratum := -1
			negBodyStratum := -1

			if rule.Body != nil {
				for _, lit := range rule.Body {
					if lit.Atom == nil {
						continue
					}
					bodyPred := predicateID(lit.Atom.Name, len(lit.Args))
					bodyStratum := strata[bodyPred]

					if lit.Positive {
						if bodyStratum > maxBodyStratum {
							maxBodyStratum = bodyStratum
						}
					} else {
						// Negation requires strict stratification
						if bodyStratum > negBodyStratum {
							negBodyStratum = bodyStratum
						}
					}
				}
			}

			// Head stratum must be higher than positive body
			if maxBodyStratum >= 0 {
				newStratum := maxBodyStratum + 1
				if negBodyStratum >= 0 && negBodyStratum >= newStratum {
					// Non-stratifiable: negation at or above head
					diag := Diagnostic{
						File:       rule.Pos.File,
						Line:       rule.Pos.Line,
						Column:     rule.Pos.Column,
						Severity:   SEV_WARNING,
						Code:       "non_stratifiable",
						Message:    fmt.Sprintf("predicate '%s' may not be stratifiable", headPred),
						Suggestion: "Reorder rules to ensure each negated predicate is fully defined before use",
						Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
					}
					c.diagnostics = append(c.diagnostics, diag)
				}

				if newStratum > currentStratum {
					strata[headPred] = newStratum
					changed = true
				}
			}
		}
	}

	if iteration >= maxIterations {
		diag := Diagnostic{
			File:       "",
			Line:       0,
			Column:     0,
			Severity:   SEV_WARNING,
			Code:       "stratification_timeout",
			Message:    "stratification analysis exceeded maximum iterations",
			Suggestion: "Program may have complex recursive patterns",
			Context:    "Global program property",
		}
		c.diagnostics = append(c.diagnostics, diag)
	}
}

// CheckConsistency performs consistency checks
func (c *Checker) CheckConsistency(program []ast.Statement) []Diagnostic {
	diags := make([]Diagnostic, 0)

	// Check for duplicate rules
	ruleSet := make(map[string]bool)
	for _, rule := range c.rules {
		ruleStr := ruleToString(rule)
		if ruleSet[ruleStr] {
			diag := Diagnostic{
				File:       rule.Pos.File,
				Line:       rule.Pos.Line,
				Column:     rule.Pos.Column,
				Severity:   SEV_WARNING,
				Code:       "duplicate_rule",
				Message:    "duplicate rule definition",
				Suggestion: "Remove or consolidate duplicate rules",
				Context:    fmt.Sprintf("Rule at %s:%d", rule.Pos.File, rule.Pos.Line),
			}
			diags = append(diags, diag)
		}
		ruleSet[ruleStr] = true
	}

	// Check for inconsistent fact/rule definition
	c.checkInconsistentDefinitions(diags)

	return diags
}

// checkInconsistentDefinitions checks if a predicate is both fact and derived
func (c *Checker) checkInconsistentDefinitions(diags []Diagnostic) {
	predicateTypes := make(map[string][]ast.RuleType)

	for _, rule := range c.rules {
		if rule.Head == nil || len(rule.Head.Atoms) == 0 {
			continue
		}

		headPred := predicateID(rule.Head.Atoms[0].Atom.Name, len(rule.Head.Atoms[0].Args))
		predicateTypes[headPred] = append(predicateTypes[headPred], rule.Type)
	}

	for pred, types := range predicateTypes {
		hasFact := false
		hasDerived := false

		for _, t := range types {
			if t == ast.RULE_FACT {
				hasFact = true
			} else if t == ast.RULE_NORMAL {
				hasDerived = true
			}
		}

		// Mixed definitions are generally OK but worth noting
		if hasFact && hasDerived {
			diag := Diagnostic{
				File:       "",
				Line:       0,
				Column:     0,
				Severity:   SEV_INFO,
				Code:       "mixed_definition",
				Message:    fmt.Sprintf("predicate '%s' is defined as both fact and derived rule", pred),
				Suggestion: "Ensure consistent definition style for clarity",
				Context:    fmt.Sprintf("Predicate: %s", pred),
			}
			diags = append(diags, diag)
		}
	}
}

// ruleToString converts a rule to string representation for comparison
func ruleToString(rule *ast.Rule) string {
	if rule == nil {
		return ""
	}

	headStr := ""
	if rule.Head != nil && len(rule.Head.Atoms) > 0 {
		headStr = rule.Head.Atoms[0].Atom.Name
	}

	bodyStr := ""
	if rule.Body != nil {
		for _, lit := range rule.Body {
			if lit.Atom != nil {
				bodyStr += lit.Atom.Name + ","
			}
		}
	}

	return fmt.Sprintf("%s:-[%s]", headStr, bodyStr)
}

// GetDiagnostics returns all accumulated diagnostics
func (c *Checker) GetDiagnostics() []Diagnostic {
	return c.diagnostics
}

// SortDiagnostics sorts diagnostics by file, line, column for consistent output
func SortDiagnostics(diags []Diagnostic) {
	sort.Slice(diags, func(i, j int) bool {
		if diags[i].File != diags[j].File {
			return diags[i].File < diags[j].File
		}
		if diags[i].Line != diags[j].Line {
			return diags[i].Line < diags[j].Line
		}
		return diags[i].Column < diags[j].Column
	})
}

// FormatDiagnostics formats diagnostics for display
func FormatDiagnostics(diags []Diagnostic) string {
	if len(diags) == 0 {
		return "No issues found."
	}

	SortDiagnostics(diags)

	output := ""
	for _, d := range diags {
		output += d.String() + "\n"
		if d.Suggestion != "" {
			output += fmt.Sprintf("  Suggestion: %s\n", d.Suggestion)
		}
		if d.Context != "" {
			output += fmt.Sprintf("  Context: %s\n", d.Context)
		}
		output += "\n"
	}

	// Summary
	errorCount := 0
	warningCount := 0
	infoCount := 0

	for _, d := range diags {
		switch d.Severity {
		case SEV_ERROR:
			errorCount++
		case SEV_WARNING:
			warningCount++
		case SEV_INFO:
			infoCount++
		}
	}

	output += fmt.Sprintf("Summary: %d errors, %d warnings, %d info\n", errorCount, warningCount, infoCount)
	return output
}

// ValidateSemantically performs complete semantic validation
func ValidateSemantically(program []ast.Statement) ([]Diagnostic, bool) {
	validator := NewValidator()
	diags := validator.ValidateProgram(program)

	checker := NewChecker(validator)
	checkerDiags := checker.CheckProgram(program)
	diags = append(diags, checkerDiags...)

	consistencyDiags := checker.CheckConsistency(program)
	diags = append(diags, consistencyDiags...)

	SortDiagnostics(diags)

	hasErrors := false
	for _, d := range diags {
		if d.Severity == SEV_ERROR {
			hasErrors = true
			break
		}
	}

	return diags, hasErrors
}
