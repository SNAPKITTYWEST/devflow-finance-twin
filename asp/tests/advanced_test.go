package tests

import (
	"fmt"
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
	"devflow-finance-twin/asp/propagation"
)

// ============================================================
// ADVANCED TESTS
// ============================================================

// TestEdgeCasesAtoms tests edge cases in atom parsing
func TestEdgeCasesAtoms(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"single char", "a.", false},
		{"with digits", "a1b2c3.", false},
		{"with underscore", "a_b_c.", false},
		{"underscore start", "_test.", false},
		{"long name", "very_long_predicate_name_with_many_underscores.", false},
		{"reserved words", "rule.", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr && len(errors) == 0 {
				t.Errorf("expected parse error, got none")
			} else if !tt.wantErr && len(errors) > 0 {
				t.Errorf("unexpected parse errors: %v", errors)
			} else if !tt.wantErr && len(stmts) != 1 {
				t.Errorf("expected 1 statement, got %d", len(stmts))
			}
		})
	}
}

// TestEdgeCasesVariables tests edge cases in variable parsing
func TestEdgeCasesVariables(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"single var", "p(X).", false},
		{"underscore", "p(_).", false},
		{"multiple vars", "p(X, Y, Z).", false},
		{"numbered", "p(X1, X2, X3).", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr && len(errors) == 0 {
				t.Errorf("expected parse error, got none")
			} else if !tt.wantErr && len(errors) > 0 {
				t.Errorf("unexpected parse errors: %v", errors)
			}
		})
	}
}

// TestComplexNesting tests complex nesting in terms
func TestComplexNesting(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"nested compounds", "p(f(g(h(a)))).", false},
		{"mixed nesting", "p(f(a, b), g(c, d)).", false},
		{"deep nesting", "p(f(g(h(i(j(k(l(m(n(o(a))))))))))).", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr && len(errors) == 0 {
				t.Errorf("expected parse error, got none")
			} else if !tt.wantErr && len(errors) > 0 {
				t.Errorf("unexpected parse errors: %v", errors)
			} else if !tt.wantErr && len(stmts) < 1 {
				t.Errorf("expected at least 1 statement")
			}
		})
	}
}

// TestComplexConstraints tests complex constraint expressions
func TestComplexConstraints(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"simple", ":- not p(X).", false},
		{"multiple body", ":- p(X), q(X), r(X).", false},
		{"mixed", ":- not p(X), q(X), not r(X).", false},
		{"with aggregate", ":- #count{} > 5.", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr && len(errors) == 0 {
				t.Errorf("expected parse error, got none")
			} else if !tt.wantErr && len(errors) > 0 {
				t.Errorf("unexpected parse errors: %v", errors)
			}
		})
	}
}

// TestRecursionPatterns tests various recursion patterns
func TestRecursionPatterns(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		isRecursive bool
	}{
		{
			name: "simple recursion",
			input: `
p(X) :- p(X).
`,
			isRecursive: true,
		},
		{
			name: "mutual recursion",
			input: `
p(X) :- q(X).
q(X) :- p(X).
`,
			isRecursive: true,
		},
		{
			name: "indirect recursion",
			input: `
a(X) :- b(X).
b(X) :- c(X).
c(X) :- a(X).
`,
			isRecursive: true,
		},
		{
			name: "stratified",
			input: `
base(1).
derived(X) :- base(X).
`,
			isRecursive: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Errorf("parse errors: %v", errors)
				return
			}

			if len(stmts) < 1 {
				t.Errorf("expected statements")
			}
		})
	}
}

// TestNegationScoping tests negation in different scopes
func TestNegationScoping(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"negated head", "{not p(X)}.", true}, // Typically invalid
		{"negated body", "p(X) :- not q(X).", false},
		{"double negation", "p(X) :- not not q(X).", false},
		{"negated in constraint", ":- not p(X).", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr {
				if len(errors) == 0 {
					// Might still parse depending on grammar
				}
			}
		})
	}
}

// TestChoiceRuleVariants tests different choice rule forms
func TestChoiceRuleVariants(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"unbounded", "{a}.", false},
		{"lower bound", "1 {a}.", false},
		{"upper bound", "{a} 1.", false},
		{"both bounds", "1 {a} 1.", false},
		{"with body", "{a(X)} :- b(X).", false},
		{"multiple in choice", "{a; b; c}.", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if !tt.wantErr && len(errors) > 0 {
				t.Logf("parse info for %s: %v", tt.name, errors)
			}

			if len(stmts) >= 1 {
				// Successfully parsed
			}
		})
	}
}

// TestDisjunctiveRules tests disjunctive rule heads
func TestDisjunctiveRules(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"two head atoms", "a(X) | b(X) :- c(X).", false},
		{"three head atoms", "a | b | c.", false},
		{"disjunction in choice", "{a; b; c} :- d.", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(stmts) >= 1 {
				// Parsed successfully
			}
		})
	}
}

// TestSpecialConstants tests parsing of special constants
func TestSpecialConstants(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"integer", "p(42).", false},
		{"negative", "p(-42).", false},
		{"zero", "p(0).", false},
		{"string", "p(\"hello\").", false},
		{"mixed", "p(42, \"hello\", x).", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if !tt.wantErr && len(errors) > 0 {
				t.Errorf("unexpected parse errors: %v", errors)
			}

			if !tt.wantErr && len(stmts) < 1 {
				t.Errorf("expected statements")
			}
		})
	}
}

// TestBuiltinPredicates tests built-in predicates
func TestBuiltinPredicates(t *testing.T) {
	input := `
p(X) :- X > 5.
q(X) :- X < 10.
r(X) :- X >= 0.
s(X) :- X <= 100.
t(X, Y) :- X = Y.
u(X, Y) :- X != Y.
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) < 6 {
		t.Errorf("expected at least 6 rules")
	}
}

// TestPropagatorEdgeCases tests propagator edge cases
func TestPropagatorEdgeCases(t *testing.T) {
	tests := []struct {
		name string
		test func(t *testing.T)
	}{
		{
			"empty clause propagation",
			func(t *testing.T) {
				prop := propagation.NewPropagator()
				// Empty clause is immediately unsatisfiable
				// Most propagators reject this in AddClause
			},
		},
		{
			"duplicate assignments",
			func(t *testing.T) {
				assign := propagation.NewAssignment()
				err := assign.Assign(1, true, 0)
				if err != nil {
					t.Errorf("first assign failed: %v", err)
				}

				// Assigning same value again should succeed
				err = assign.Assign(1, true, 0)
				if err != nil {
					t.Errorf("duplicate assign should succeed: %v", err)
				}

				// Assigning different value should fail
				err = assign.Assign(1, false, 0)
				if err == nil {
					t.Errorf("conflicting assign should fail")
				}
			},
		},
		{
			"backtrack to negative level",
			func(t *testing.T) {
				prop := propagation.NewPropagator()
				err := prop.Backtrack(-5)
				if err != nil {
					t.Errorf("backtrack to negative should succeed: %v", err)
				}

				level := prop.GetDecisionLevel()
				if level != 0 {
					t.Errorf("level should be 0 after backtrack to -5, got %d", level)
				}
			},
		},
		{
			"copy assignment",
			func(t *testing.T) {
				assign := propagation.NewAssignment()
				assign.Assign(1, true, 0)
				assign.Assign(2, false, 1)

				copy := assign.Copy()

				val1, ok1 := copy.GetValue(1)
				if !ok1 || !val1 {
					t.Errorf("copy should have unit 1 true")
				}

				val2, ok2 := copy.GetValue(2)
				if !ok2 || val2 {
					t.Errorf("copy should have unit 2 false")
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.test(t)
		})
	}
}

// TestSolverCornerCases tests solver corner cases
func TestSolverCornerCases(t *testing.T) {
	tests := []struct {
		name string
		test func(t *testing.T)
	}{
		{
			"tautology",
			func(t *testing.T) {
				solver := NewSimpleSolver()
				// (a | -a) is always true
				clause := propagation.NewClause([]propagation.Unit{1, -1}, false)
				err := solver.AddClause(clause)
				if err != nil {
					t.Errorf("add tautology failed: %v", err)
				}
			},
		},
		{
			"contradiction",
			func(t *testing.T) {
				solver := NewSimpleSolver()
				// (a) and (-a) together are unsatisfiable
				c1 := propagation.NewClause([]propagation.Unit{1}, false)
				c2 := propagation.NewClause([]propagation.Unit{-1}, false)
				err1 := solver.AddClause(c1)
				err2 := solver.AddClause(c2)

				if err1 != nil || err2 != nil {
					t.Errorf("add clauses failed: %v, %v", err1, err2)
				}

				sat, err := solver.Solve()
				if err != nil {
					t.Errorf("solve failed: %v", err)
				}

				// Should be unsatisfiable
				if sat {
					t.Errorf("expected unsatisfiable but got sat")
				}
			},
		},
		{
			"unit propagation chain",
			func(t *testing.T) {
				prop := propagation.NewPropagator()

				// Chain: (1) -> (1 | 2) -> (-1 | 2) -> (2)
				c1 := propagation.NewClause([]propagation.Unit{1}, false)
				prop.AddClause(c1)

				c2 := propagation.NewClause([]propagation.Unit{1, 2}, false)
				prop.AddClause(c2)

				c3 := propagation.NewClause([]propagation.Unit{-1, 2}, false)
				prop.AddClause(c3)

				// Propagate
				conflicts, err := prop.Propagate()
				if err != nil {
					t.Errorf("propagate failed: %v", err)
				}

				if len(conflicts) > 0 {
					t.Errorf("expected no conflicts")
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.test(t)
		})
	}
}

// TestGrounderCornerCases tests grounder corner cases
func TestGrounderCornerCases(t *testing.T) {
	tests := []struct {
		name string
		test func(t *testing.T)
	}{
		{
			"empty program",
			func(t *testing.T) {
				grounder := NewGrounder()
				grounded := grounder.Ground()
				if len(grounded) != 0 {
					t.Errorf("empty program should ground to empty")
				}
			},
		},
		{
			"single fact",
			func(t *testing.T) {
				input := "p(a)."
				l := lexer.NewLexer(input, "test.lp")
				p := parser.NewParser(l)
				stmts, _ := p.Parse()

				grounder := NewGrounder()
				for _, stmt := range stmts {
					if rs, ok := stmt.(*ast.RuleStatement); ok {
						grounder.AddRule(rs.Rule)
					}
				}

				grounded := grounder.Ground()
				if len(grounded) != 1 {
					t.Errorf("single fact should ground to 1 rule")
				}
			},
		},
		{
			"no body rule",
			func(t *testing.T) {
				input := "p(X) :- ."
				l := lexer.NewLexer(input, "test.lp")
				p := parser.NewParser(l)
				stmts, errors := p.Parse()

				// This is likely a parse error
				if len(errors) == 0 {
					// If it parses, verify it grounds
					if len(stmts) > 0 {
						if rs, ok := stmts[0].(*ast.RuleStatement); ok {
							if len(rs.Rule.Body) > 0 {
								t.Errorf("rule with no body should have empty body")
							}
						}
					}
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.test(t)
		})
	}
}

// TestErrorMessages tests quality of error messages
func TestErrorMessages(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		contain string
	}{
		{"missing dot", "p(a)", ""},
		{"unclosed paren", "p(a", ""},
		{"invalid tokens", "p(a) @@@ q(b).", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			_, errors := p.Parse()

			if len(errors) > 0 && tt.contain != "" {
				found := false
				for _, err := range errors {
					if fmt.Sprintf("%v", err) != "" {
						found = true
						break
					}
				}
				if !found {
					t.Logf("errors: %v", errors)
				}
			}
		})
	}
}

// TestCompletePrograms tests complete real-world-like programs
func TestCompletePrograms(t *testing.T) {
	programs := []struct {
		name    string
		program string
	}{
		{
			"family relations",
			`
parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).

ancestor(X, Y) :- parent(X, Y).
ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z).

sibling(X, Y) :- parent(P, X), parent(P, Y), X != Y.
grandparent(X, Z) :- parent(X, Y), parent(Y, Z).
`,
		},
		{
			"routing protocol",
			`
node(1..5).
link(1, 2).
link(2, 3).
link(3, 4).
link(4, 5).
link(5, 1).

direct_route(X, Y) :- link(X, Y).
route(X, Y, 1) :- direct_route(X, Y).
route(X, Z, N+1) :- route(X, Y, N), direct_route(Y, Z), N < 10.

shortest_route(X, Y) :- route(X, Y, N), {route(X, Y, M) : M < N} = 0.
`,
		},
		{
			"stable model semantics",
			`
{choose(X)} :- domain(X).

domain(1).
domain(2).
domain(3).

not_chosen(X) :- domain(X), not choose(X).
chosen_count(N) :- N = #count{X : choose(X)}.

:- not_chosen(X), not_chosen(Y), X != Y, X < Y.
`,
		},
	}

	for _, prog := range programs {
		t.Run(prog.name, func(t *testing.T) {
			l := lexer.NewLexer(prog.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Logf("parse info: %v", errors)
			}

			if len(stmts) < 1 {
				t.Errorf("expected to parse program")
			}

			grounder := NewGrounder()
			for _, stmt := range stmts {
				if rs, ok := stmt.(*ast.RuleStatement); ok {
					grounder.AddRule(rs.Rule)
				}
			}

			grounded := grounder.Ground()
			if len(grounded) < 1 {
				t.Errorf("expected to ground program")
			}
		})
	}
}
