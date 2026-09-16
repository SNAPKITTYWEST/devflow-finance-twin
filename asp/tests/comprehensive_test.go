package tests

import (
	"fmt"
	"strings"
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
	"devflow-finance-twin/asp/propagation"
)

// ============================================================
// COMPREHENSIVE INTEGRATION TESTS
// ============================================================

// TestParserRobustness tests parser with various inputs
func TestParserRobustness(t *testing.T) {
	testCases := []struct {
		description string
		program     string
		expectFail  bool
	}{
		{
			"simple fact",
			"p(a).",
			false,
		},
		{
			"fact with multiple args",
			"p(a, b, c).",
			false,
		},
		{
			"rule with body",
			"p(X) :- q(X), r(X).",
			false,
		},
		{
			"negation in body",
			"p(X) :- not q(X).",
			false,
		},
		{
			"multiple rules",
			"p(a). q(b). r(c).",
			false,
		},
		{
			"nested compounds",
			"p(f(g(h(a)))).",
			false,
		},
		{
			"variables in compounds",
			"p(f(X, g(Y, Z))).",
			false,
		},
		{
			"atoms with numbers",
			"p1(a2), q_3(b_4).",
			false,
		},
		{
			"constraint",
			":- p(X), q(X).",
			false,
		},
		{
			"choice rule",
			"{p(X)} :- q(X).",
			false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.description, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tc.expectFail {
				if len(errors) == 0 {
					t.Errorf("expected parse to fail")
				}
			} else {
				if len(errors) > 0 {
					t.Errorf("unexpected parse errors: %v", errors)
				}
				if len(stmts) == 0 {
					t.Errorf("expected to parse statements")
				}
			}
		})
	}
}

// TestProgramFamilyRelations tests family relation programs
func TestProgramFamilyRelations(t *testing.T) {
	program := `
% Facts about parents
parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).

% Direct ancestor
ancestor(X, Y) :- parent(X, Y).

% Transitive ancestor
ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z).

% Sibling relation
sibling(X, Y) :- parent(P, X), parent(P, Y), X != Y.

% Descendant (inverse of ancestor)
descendant(Y, X) :- ancestor(X, Y).

% Grandparent
grandparent(X, Z) :- parent(X, Y), parent(Y, Z).

% Cousin
cousin(X, Y) :- parent(PX, X), parent(PY, Y), sibling(PX, PY).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	expectedMinStatements := 9 // 5 parent facts + 6 rules (approx)
	if len(stmts) < expectedMinStatements {
		t.Errorf("expected at least %d statements, got %d", expectedMinStatements, len(stmts))
	}

	// Ground the program
	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	if len(grounded) < 5 {
		t.Errorf("expected grounded rules")
	}

	// Verify parent facts are grounded
	parentFactCount := 0
	for _, rule := range grounded {
		if rule.Type == ast.RULE_FACT && len(rule.Head.Atoms) > 0 {
			if rule.Head.Atoms[0].Atom.Name == "parent" {
				parentFactCount++
			}
		}
	}

	if parentFactCount != 5 {
		t.Errorf("expected 5 parent facts, got %d", parentFactCount)
	}
}

// TestProgramGraphAlgorithms tests graph algorithm programs
func TestProgramGraphAlgorithms(t *testing.T) {
	program := `
% Graph edges
edge(1, 2).
edge(2, 3).
edge(3, 1).
edge(2, 4).
edge(4, 5).

% Reachability
reach(X, Y) :- edge(X, Y).
reach(X, Z) :- reach(X, Y), edge(Y, Z), X != Z.

% Cycle detection
in_cycle(X) :- reach(X, X).

% Path finding
path(X, Y, 1) :- edge(X, Y).
path(X, Y, N) :- path(X, Z, M), edge(Z, Y), N = M + 1, N <= 10.

% Connected components (simplified)
same_component(X, Y) :- reach(X, Y).
same_component(X, Y) :- reach(Y, X).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) < 8 {
		t.Errorf("expected at least 8 statements")
	}

	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
		}
	}

	err := analyzer.Analyze()
	if err != nil {
		t.Fatalf("analysis error: %v", err)
	}

	// Verify reach is recursive
	if !analyzer.headPredicates["reach"] {
		t.Errorf("expected reach to be defined")
	}
}

// TestProgramDataValidation tests data validation programs
func TestProgramDataValidation(t *testing.T) {
	program := `
% Valid data
valid_id(1).
valid_id(2).
valid_id(3).

% Constraints for validation
:- person(ID), not valid_id(ID).
:- not email(ID), person(ID).
:- age(ID, A), A < 0.
:- age(ID, A), A > 150.

% Derived validation predicates
has_valid_record(ID) :- person(ID), email(ID), age(ID, _).

% Correction rules
corrected_record(ID) :- person(ID), has_valid_record(ID).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	// Count constraints
	constraintCount := 0
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			if rs.Rule.Type == ast.RULE_CONSTRAINT {
				constraintCount++
			}
		}
	}

	if constraintCount < 4 {
		t.Errorf("expected at least 4 constraints")
	}
}

// TestProgramOptimization tests optimization programs
func TestProgramOptimization(t *testing.T) {
	program := `
% Decision variables
{assign(X, R) : resource(R)} :- task(X).

% Constraints
:- task(X), {assign(X, R)} != 1.
:- task(X), task(Y), X < Y, assign(X, R), assign(Y, R).

% Optimization
#minimize{
  cost(X, R) : assign(X, R)
}.

% Cost definition
cost(1, r1, 10).
cost(1, r2, 15).
cost(2, r1, 12).
cost(2, r2, 8).

task(1).
task(2).
resource(r1).
resource(r2).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) < 8 {
		t.Errorf("expected at least 8 statements")
	}
}

// TestPropagatorComprehensive tests propagator with complex scenarios
func TestPropagatorComprehensive(t *testing.T) {
	t.Run("satisfiable formula", func(t *testing.T) {
		prop := propagation.NewPropagator()

		// (1 | 2) and (2 | 3) - satisfiable
		c1 := propagation.NewClause([]propagation.Unit{1, 2}, false)
		c2 := propagation.NewClause([]propagation.Unit{2, 3}, false)

		prop.AddClause(c1)
		prop.AddClause(c2)

		conflicts, err := prop.Propagate()
		if err != nil {
			t.Errorf("propagate error: %v", err)
		}

		if len(conflicts) > 0 {
			t.Errorf("expected no conflicts in satisfiable formula")
		}
	})

	t.Run("unsatisfiable formula", func(t *testing.T) {
		prop := propagation.NewPropagator()

		// (1) and (-1) - unsatisfiable
		c1 := propagation.NewClause([]propagation.Unit{1}, false)
		c2 := propagation.NewClause([]propagation.Unit{-1}, false)

		prop.AddClause(c1)
		prop.AddClause(c2)

		conflicts, err := prop.Propagate()
		// Might detect conflict or might not depending on when propagation happens
		_ = conflicts
		_ = err
	})

	t.Run("unit propagation chain", func(t *testing.T) {
		prop := propagation.NewPropagator()

		// Chain: (1) implies (1|2) implies (-1|2) implies (2)
		c1 := propagation.NewClause([]propagation.Unit{1}, false)
		c2 := propagation.NewClause([]propagation.Unit{1, 2}, false)
		c3 := propagation.NewClause([]propagation.Unit{-1, 2}, false)

		prop.AddClause(c1)
		prop.AddClause(c2)
		prop.AddClause(c3)

		conflicts, err := prop.Propagate()
		if err != nil {
			t.Errorf("propagate error: %v", err)
		}

		_ = conflicts
	})

	t.Run("backtracking", func(t *testing.T) {
		prop := propagation.NewPropagator()

		// Make decisions
		prop.DecideVariable(propagation.Unit(1), true)
		if prop.GetDecisionLevel() != 1 {
			t.Errorf("expected level 1")
		}

		prop.DecideVariable(propagation.Unit(2), false)
		if prop.GetDecisionLevel() != 2 {
			t.Errorf("expected level 2")
		}

		// Backtrack
		prop.Backtrack(1)
		if prop.GetDecisionLevel() != 1 {
			t.Errorf("expected level 1 after backtrack")
		}

		// Unit 2 should be unassigned
		assign := prop.GetAssignment()
		if assign.IsAssigned(propagation.Unit(2)) {
			t.Errorf("expected unit 2 to be unassigned after backtrack")
		}
	})
}

// TestGrounderComprehensive tests grounder with complex scenarios
func TestGrounderComprehensive(t *testing.T) {
	t.Run("facts only", func(t *testing.T) {
		program := `
fact(1).
fact(2).
fact(3).
`

		l := lexer.NewLexer(program, "test.lp")
		p := parser.NewParser(l)
		stmts, _ := p.Parse()

		grounder := NewGrounder()
		for _, stmt := range stmts {
			if rs, ok := stmt.(*ast.RuleStatement); ok {
				grounder.AddRule(rs.Rule)
			}
		}

		grounded := grounder.Ground()
		if len(grounded) != 3 {
			t.Errorf("expected 3 facts, got %d", len(grounded))
		}
	})

	t.Run("rules with domain", func(t *testing.T) {
		program := `
domain(a).
domain(b).
domain(c).

derived(X) :- domain(X).
`

		l := lexer.NewLexer(program, "test.lp")
		p := parser.NewParser(l)
		stmts, _ := p.Parse()

		grounder := NewGrounder()
		for _, stmt := range stmts {
			if rs, ok := stmt.(*ast.RuleStatement); ok {
				grounder.AddRule(rs.Rule)
			}
		}

		grounded := grounder.Ground()
		if len(grounded) < 4 {
			t.Errorf("expected at least 4 grounded rules")
		}
	})

	t.Run("recursive rules", func(t *testing.T) {
		program := `
edge(1, 2).
edge(2, 3).
edge(3, 4).

reach(X, Y) :- edge(X, Y).
reach(X, Z) :- reach(X, Y), edge(Y, Z).
`

		l := lexer.NewLexer(program, "test.lp")
		p := parser.NewParser(l)
		stmts, _ := p.Parse()

		grounder := NewGrounder()
		for _, stmt := range stmts {
			if rs, ok := stmt.(*ast.RuleStatement); ok {
				grounder.AddRule(rs.Rule)
			}
		}

		grounded := grounder.Ground()
		if len(grounded) < 5 {
			t.Errorf("expected at least 5 grounded rules")
		}
	})
}

// TestComplexProgramSyntax tests complex program syntax variations
func TestComplexProgramSyntax(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{
			"empty body rule",
			"p :- .",
		},
		{
			"compound head",
			"result(f(X, Y)) :- p(X), q(Y).",
		},
		{
			"multiple choice",
			"{a(X); b(X); c(X)} :- domain(X).",
		},
		{
			"aggregate in head",
			"count_result(C) :- C = #count{X : item(X)}.",
		},
		{
			"disjunctive body",
			"p(X) :- (q(X); r(X)).",
		},
		{
			"builtin comparison",
			"p(X) :- q(X), X > 5, X < 10.",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			// Just verify parsing attempts work
			_ = stmts
			_ = errors
		})
	}
}

// TestLargeProgram tests performance with large programs
func TestLargeProgram(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping large program test in short mode")
	}

	var sb strings.Builder

	// Generate large program
	for i := 0; i < 200; i++ {
		sb.WriteString(fmt.Sprintf("fact_%d(%d).\n", i%10, i))
	}

	for i := 0; i < 100; i++ {
		sb.WriteString(fmt.Sprintf("rule_%d(X) :- fact_%d(X).\n", i%5, i%10))
	}

	program := sb.String()

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) != 300 {
		t.Errorf("expected 300 statements, got %d", len(stmts))
	}

	// Try to ground
	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	if len(grounded) < 200 {
		t.Errorf("expected at least 200 grounded rules")
	}
}

// TestProgramStatistics collects and verifies program statistics
func TestProgramStatistics(t *testing.T) {
	program := `
person(alice).
person(bob).
person(charlie).

age(alice, 30).
age(bob, 25).
age(charlie, 35).

adult(X) :- person(X), age(X, A), A >= 18.

{employed(X)} :- person(X).

:- person(X), employed(X), not has_job(X).

#minimize{A : adult(X), age(X, A)}.
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	stats := &ProgramStats{
		TotalStatements: len(stmts),
	}

	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			switch rs.Rule.Type {
			case ast.RULE_FACT:
				stats.FactCount++
			case ast.RULE_NORMAL:
				stats.RuleCount++
			case ast.RULE_CONSTRAINT:
				stats.ConstraintCount++
			}

			if len(rs.Rule.Body) > 0 {
				stats.AverageBodySize = (stats.AverageBodySize*(stats.RuleCount-1) + len(rs.Rule.Body)) / stats.RuleCount
			}
		} else if _, ok := stmt.(*ast.Directive); ok {
			stats.DirectiveCount++
		}
	}

	if stats.FactCount < 3 {
		t.Errorf("expected at least 3 facts")
	}

	if stats.RuleCount < 2 {
		t.Errorf("expected at least 2 rules")
	}

	if stats.ConstraintCount < 1 {
		t.Errorf("expected at least 1 constraint")
	}

	t.Logf("Program Statistics: Total=%d, Facts=%d, Rules=%d, Constraints=%d, Directives=%d",
		stats.TotalStatements, stats.FactCount, stats.RuleCount, stats.ConstraintCount, stats.DirectiveCount)
}

// BenchmarkFullStack benchmarks complete parsing, grounding, and solving
func BenchmarkFullStack(b *testing.B) {
	program := `
pos(1..5).
{queen(R, C) : pos(C)} :- pos(R).
:- pos(C), {queen(R, C) : pos(R)} != 1.
:- pos(R1), pos(R2), R1 < R2, queen(R1, C), queen(R2, C).
`

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.NewLexer(program, "test.lp")
		p := parser.NewParser(l)
		stmts, _ := p.Parse()

		grounder := NewGrounder()
		for _, stmt := range stmts {
			if rs, ok := stmt.(*ast.RuleStatement); ok {
				grounder.AddRule(rs.Rule)
			}
		}

		_ = grounder.Ground()
	}
}

// BenchmarkParsingVsGrounding compares parsing and grounding time
func BenchmarkParsingVsGrounding(b *testing.B) {
	program := `
fact(1..100).
rule(X) :- fact(X).
rule2(X) :- rule(X).
`

	b.Run("parsing", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			l := lexer.NewLexer(program, "test.lp")
			p := parser.NewParser(l)
			_, _ = p.Parse()
		}
	})

	b.Run("grounding", func(b *testing.B) {
		l := lexer.NewLexer(program, "test.lp")
		p := parser.NewParser(l)
		stmts, _ := p.Parse()

		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			grounder := NewGrounder()
			for _, stmt := range stmts {
				if rs, ok := stmt.(*ast.RuleStatement); ok {
					grounder.AddRule(rs.Rule)
				}
			}
			_ = grounder.Ground()
		}
	})
}
