package semantics

import (
	"testing"

	"devflow-finance-twin/asp/ast"
)

// Helper functions for creating test AST nodes

func makePosition(line, col int) ast.Position {
	return ast.Position{
		File:   "test.lp",
		Line:   line,
		Column: col,
		Offset: 0,
	}
}

func makeAtom(name string, pos ast.Position) *ast.Atom {
	return &ast.Atom{Name: name, Pos: pos}
}

func makeVariable(name string, pos ast.Position) *ast.Variable {
	return &ast.Variable{Name: name, Pos: pos}
}

func makeHeadAtom(name string, args []ast.Term, pos ast.Position) *ast.HeadAtom {
	return &ast.HeadAtom{
		Atom: makeAtom(name, pos),
		Args: args,
		Pos:  pos,
	}
}

func makeHead(atoms []*ast.HeadAtom, pos ast.Position) *ast.Head {
	return &ast.Head{
		Atoms: atoms,
		Type:  ast.HEAD_NORMAL,
		Pos:   pos,
	}
}

func makeLiteral(positive bool, atomName string, args []ast.Term, pos ast.Position) *ast.Literal {
	return &ast.Literal{
		Positive: positive,
		Atom:     makeAtom(atomName, pos),
		Args:     args,
		Pos:      pos,
	}
}

func makeRule(head *ast.Head, body []*ast.Literal, pos ast.Position) *ast.Rule {
	return &ast.Rule{
		Head: head,
		Body: body,
		Type: ast.RULE_NORMAL,
		Pos:  pos,
	}
}

// Test 1: Undefined predicate detection
func TestUndefinedPredicate(t *testing.T) {
	pos := makePosition(1, 1)

	// Rule: parent(X, Y) :- ancestor(X, Y).
	// ancestor is not defined
	rule := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("parent", []ast.Term{
				makeVariable("X", pos),
				makeVariable("Y", pos),
			}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(true, "ancestor", []ast.Term{
				makeVariable("X", pos),
				makeVariable("Y", pos),
			}, pos),
		},
		pos,
	)

	program := []ast.Statement{
		&ast.RuleStatement{Rule: rule, Pos: pos},
	}

	validator := NewValidator()
	diags := validator.ValidateProgram(program)

	found := false
	for _, d := range diags {
		if d.Code == "undefined_pred" {
			found = true
			break
		}
	}

	if !found {
		t.Error("Expected undefined predicate diagnostic, but none found")
	}
}

// Test 2: Unsafe variable detection
func TestUnsafeVariable(t *testing.T) {
	pos := makePosition(2, 1)

	// Rule: p(X) :- q(Y).
	// X appears in head but not in positive body (unsafe)
	rule := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("p", []ast.Term{
				makeVariable("X", pos),
			}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(true, "q", []ast.Term{
				makeVariable("Y", pos),
			}, pos),
		},
		pos,
	)

	program := []ast.Statement{
		&ast.RuleStatement{Rule: rule, Pos: pos},
	}

	validator := NewValidator()
	diags := validator.ValidateProgram(program)

	found := false
	for _, d := range diags {
		if d.Code == "unsafe_var" {
			found = true
			break
		}
	}

	if !found {
		t.Error("Expected unsafe variable diagnostic, but none found")
	}
}

// Test 3: Safe rule (no errors expected)
func TestSafeRule(t *testing.T) {
	pos := makePosition(3, 1)

	// Facts
	factParent := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("parent", []ast.Term{
				makeAtom("john", pos),
				makeAtom("mary", pos),
			}, pos),
		}, pos),
		nil, // no body = fact
		pos,
	)

	// Rule: ancestor(X, Y) :- parent(X, Y).
	ruleAncestor := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("ancestor", []ast.Term{
				makeVariable("X", pos),
				makeVariable("Y", pos),
			}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(true, "parent", []ast.Term{
				makeVariable("X", pos),
				makeVariable("Y", pos),
			}, pos),
		},
		pos,
	)

	program := []ast.Statement{
		&ast.RuleStatement{Rule: factParent, Pos: pos},
		&ast.RuleStatement{Rule: ruleAncestor, Pos: pos},
	}

	validator := NewValidator()
	diags := validator.ValidateProgram(program)

	errorCount := 0
	for _, d := range diags {
		if d.Severity == SEV_ERROR {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Expected no errors, but got %d: %v", errorCount, diags)
	}
}

// Test 4: Aggregate validation
func TestAggregateValidation(t *testing.T) {
	pos := makePosition(4, 1)

	// Create aggregate
	agg := &ast.Aggregate{
		Op: ast.AGG_COUNT,
		Variables: []ast.Term{
			makeVariable("X", pos),
		},
		Condition: makeLiteral(true, "elem", []ast.Term{
			makeVariable("X", pos),
		}, pos),
		Pos: pos,
	}

	validator := NewValidator()
	err := validator.CheckAggregates(agg)

	if err != nil {
		t.Errorf("Aggregate validation failed: %v", err)
	}
}

// Test 5: Invalid aggregate operation
func TestInvalidAggregateOp(t *testing.T) {
	pos := makePosition(5, 1)

	// Create invalid aggregate
	agg := &ast.Aggregate{
		Op: "invalid_op",
		Variables: []ast.Term{
			makeVariable("X", pos),
		},
		Pos: pos,
	}

	validator := NewValidator()
	validator.CheckAggregates(agg)

	found := false
	for _, d := range validator.GetDiagnostics() {
		if d.Code == "invalid_aggregate_op" {
			found = true
			break
		}
	}

	if !found {
		t.Error("Expected invalid aggregate operation diagnostic")
	}
}

// Test 6: Checker stratification
func TestStratification(t *testing.T) {
	pos := makePosition(6, 1)

	// p :- not q.
	// q :- not p.
	// (unstratifiable)

	ruleP := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("p", []ast.Term{}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(false, "q", []ast.Term{}, pos), // negation
		},
		pos,
	)

	ruleQ := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("q", []ast.Term{}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(false, "p", []ast.Term{}, pos), // negation
		},
		pos,
	)

	program := []ast.Statement{
		&ast.RuleStatement{Rule: ruleP, Pos: pos},
		&ast.RuleStatement{Rule: ruleQ, Pos: pos},
	}

	validator := NewValidator()
	diags := validator.ValidateProgram(program)

	// Check for negative cycle detection
	foundCycle := false
	for _, d := range diags {
		if d.Code == "negative_cycle" {
			foundCycle = true
			break
		}
	}

	if !foundCycle {
		t.Error("Expected negative cycle diagnostic for unstratifiable program")
	}
}

// Test 7: Multiple diagnostics summary
func TestDiagnosticsSummary(t *testing.T) {
	pos := makePosition(7, 1)

	// Multiple errors
	rule1 := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("p", []ast.Term{
				makeVariable("X", pos),
			}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(true, "undefined_pred", []ast.Term{}, pos),
		},
		pos,
	)

	program := []ast.Statement{
		&ast.RuleStatement{Rule: rule1, Pos: pos},
	}

	validator := NewValidator()
	diags := validator.ValidateProgram(program)

	if len(diags) == 0 {
		t.Error("Expected diagnostics but got none")
	}

	if validator.ErrorCount() == 0 {
		t.Error("Expected errors to be counted")
	}
}

// Test 8: Checker consistency
func TestConsistency(t *testing.T) {
	pos := makePosition(8, 1)

	// Create duplicate rules
	rule := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("fact", []ast.Term{
				makeAtom("a", pos),
			}, pos),
		}, pos),
		nil,
		pos,
	)

	program := []ast.Statement{
		&ast.RuleStatement{Rule: rule, Pos: pos},
		&ast.RuleStatement{Rule: rule, Pos: pos}, // duplicate
	}

	validator := NewValidator()
	checker := NewChecker(validator)

	// Extract rules first
	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			checker.rules = append(checker.rules, rs.Rule)
		}
	}

	diags := checker.CheckConsistency(program)

	foundDuplicate := false
	for _, d := range diags {
		if d.Code == "duplicate_rule" {
			foundDuplicate = true
			break
		}
	}

	if !foundDuplicate {
		t.Error("Expected duplicate rule diagnostic")
	}
}

// Test 9: Choice rule validation
func TestChoiceRuleValidation(t *testing.T) {
	pos := makePosition(9, 1)

	// { a; b } :- c.
	rule := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("a", []ast.Term{}, pos),
			makeHeadAtom("b", []ast.Term{}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(true, "c", []ast.Term{}, pos),
		},
		pos,
	)
	rule.Type = ast.RULE_CHOICE

	program := []ast.Statement{
		&ast.RuleStatement{Rule: rule, Pos: pos},
	}

	validator := NewValidator()
	checker := NewChecker(validator)

	for _, stmt := range program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			checker.rules = append(checker.rules, rs.Rule)
		}
	}

	checker.checkChoiceRules()
	diags := checker.GetDiagnostics()

	if len(diags) > 0 {
		// Choice rules with multiple head atoms are valid
		for _, d := range diags {
			if d.Code == "single_choice" {
				t.Errorf("Unexpected single_choice diagnostic for multi-head choice rule")
			}
		}
	}
}

// Test 10: Anonymous variable safety
func TestAnonymousVariableSafety(t *testing.T) {
	pos := makePosition(10, 1)

	// p(_) :- q(Y).
	// Anonymous variable _ should not trigger unsafe var error
	rule := makeRule(
		makeHead([]*ast.HeadAtom{
			makeHeadAtom("p", []ast.Term{
				makeVariable("_", pos),
			}, pos),
		}, pos),
		[]*ast.Literal{
			makeLiteral(true, "q", []ast.Term{
				makeVariable("Y", pos),
			}, pos),
		},
		pos,
	)

	program := []ast.Statement{
		&ast.RuleStatement{Rule: rule, Pos: pos},
	}

	validator := NewValidator()
	diags := validator.ValidateProgram(program)

	// Should not have unsafe_var for anonymous variable
	for _, d := range diags {
		if d.Code == "unsafe_var" && d.Message == "variable '_' in head does not appear in positive body" {
			t.Error("Anonymous variable should not trigger unsafe_var error")
		}
	}
}

// Benchmark: Validate large program
func BenchmarkValidation(b *testing.B) {
	pos := makePosition(1, 1)

	// Create a program with many rules
	program := make([]ast.Statement, 0)
	for i := 0; i < 100; i++ {
		rule := makeRule(
			makeHead([]*ast.HeadAtom{
				makeHeadAtom("p", []ast.Term{}, pos),
			}, pos),
			[]*ast.Literal{
				makeLiteral(true, "q", []ast.Term{}, pos),
			},
			pos,
		)
		program = append(program, &ast.RuleStatement{Rule: rule, Pos: pos})
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		validator := NewValidator()
		validator.ValidateProgram(program)
	}
}
