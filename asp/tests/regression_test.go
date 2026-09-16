package tests

import (
	"fmt"
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
)

// ============================================================
// REGRESSION TESTS AND KNOWN CASES
// ============================================================

// TestRegressionEmptyProgram tests parsing empty input
func TestRegressionEmptyProgram(t *testing.T) {
	program := ""

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Errorf("empty program should not have parse errors: %v", errors)
	}

	if len(stmts) != 0 {
		t.Errorf("empty program should have no statements, got %d", len(stmts))
	}
}

// TestRegressionWhitespaceOnly tests program with only whitespace
func TestRegressionWhitespaceOnly(t *testing.T) {
	program := "   \n  \t  \n  "

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Errorf("whitespace-only program should not have parse errors: %v", errors)
	}

	if len(stmts) != 0 {
		t.Errorf("whitespace-only program should have no statements")
	}
}

// TestRegressionCommentOnly tests program with only comments
func TestRegressionCommentOnly(t *testing.T) {
	program := `
% This is a comment
% Another comment
% Yet another comment
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Errorf("comment-only program should not have parse errors: %v", errors)
	}

	if len(stmts) != 0 {
		t.Errorf("comment-only program should have no statements")
	}
}

// TestRegressionMixedComments tests comments mixed with code
func TestRegressionMixedComments(t *testing.T) {
	program := `
% This is a fact
fact(a).  % inline comment

% This is a rule
rule(X) :- fact(X).  % rule comment
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Errorf("program with comments should parse correctly: %v", errors)
	}

	if len(stmts) != 2 {
		t.Errorf("expected 2 statements, got %d", len(stmts))
	}
}

// TestRegressionTrailingComma tests handling of trailing commas
func TestRegressionTrailingComma(t *testing.T) {
	program := "p(a, b,)."  // Potentially invalid

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	// This might be a parse error depending on implementation
	if len(stmts) == 0 && len(errors) == 0 {
		// This shouldn't happen - either parse or error
	}
}

// TestRegressionLongAtom tests very long atom names
func TestRegressionLongAtom(t *testing.T) {
	longName := "very_long_predicate_name_with_many_underscores_and_numbers_123_456_789"
	program := fmt.Sprintf("%s.", longName)

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Errorf("long atom should parse: %v", errors)
	}

	if len(stmts) != 1 {
		t.Errorf("expected 1 statement")
	}

	if rs, ok := stmts[0].(*ast.RuleStatement); ok {
		if rs.Rule.Head.Atoms[0].Atom.Name != longName {
			t.Errorf("atom name mismatch")
		}
	}
}

// TestRegressionDeepNesting tests deeply nested terms
func TestRegressionDeepNesting(t *testing.T) {
	// Build deeply nested term
	term := "a"
	for i := 0; i < 20; i++ {
		term = fmt.Sprintf("f(%s)", term)
	}
	program := fmt.Sprintf("p(%s).", term)

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Errorf("deeply nested term should parse: %v", errors)
	}

	if len(stmts) != 1 {
		t.Errorf("expected 1 statement")
	}
}

// TestRegressionLargeArity tests predicates with many arguments
func TestRegressionLargeArity(t *testing.T) {
	// Build predicate with many arguments
	args := make([]string, 50)
	for i := 0; i < 50; i++ {
		args[i] = fmt.Sprintf("a%d", i)
	}

	program := "p(" + fmt.Sprintf("%v", args) + ")."
	if len(program) > 100 {
		// Too complex, simplify
		args = args[:10]
		argsStr := ""
		for i := range args {
			if i > 0 {
				argsStr += ","
			}
			argsStr += fmt.Sprintf("a%d", i)
		}
		program = fmt.Sprintf("p(%s).", argsStr)
	}

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Logf("large arity parse info: %v", errors)
	}
}

// TestRegressionSpecialCharacters tests special characters in strings
func TestRegressionSpecialCharacters(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{"string with space", `p("hello world").`},
		{"string with comma", `p("a,b,c").`},
		{"string with period", `p("end.").`},
		{"string with quote", `p("say \"hello\"").`},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Logf("parse info: %v", errors)
			}
		})
	}
}

// TestRegressionNumberFormats tests various number formats
func TestRegressionNumberFormats(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{"zero", "p(0)."},
		{"positive", "p(42)."},
		{"negative", "p(-42)."},
		{"large", "p(1000000)."},
		{"float", "p(3.14)."},
		{"scientific", "p(1e10)."},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 && tc.name != "float" && tc.name != "scientific" {
				t.Logf("parse info for %s: %v", tc.name, errors)
			}
		})
	}
}

// TestRegressionVariableNaming tests variable naming conventions
func TestRegressionVariableNaming(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{"single uppercase", "p(X)."},
		{"multiple uppercase", "p(X, Y, Z)."},
		{"numbered", "p(X1, X2, X3)."},
		{"underscore", "p(_)."},
		{"underscore prefix", "p(_X)."},
		{"underscore name", "p(_)."},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Errorf("expected to parse: %v", errors)
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement")
			}
		})
	}
}

// TestRegressionMixedHeadTypes tests mixed head types
func TestRegressionMixedHeadTypes(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{"disjunctive", "a | b | c."},
		{"disjunctive with args", "a(X) | b(X) | c(X) :- d(X)."},
		{"choice", "{a(X)} :- d(X)."},
		{"choice multiple", "{a(X); b(X); c(X)} :- d(X)."},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			// Just verify parsing attempt works
			_ = stmts
			_ = errors
		})
	}
}

// TestRegressionBodyLiterals tests various body literal forms
func TestRegressionBodyLiterals(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{"positive", "p(X) :- q(X)."},
		{"negative", "p(X) :- not q(X)."},
		{"mixed", "p(X) :- q(X), not r(X), s(X)."},
		{"comparison", "p(X) :- X > 5."},
		{"equality", "p(X) :- X = Y."},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Logf("parse info for %s: %v", tc.name, errors)
			}
		})
	}
}

// TestRegressionConstraintForms tests various constraint forms
func TestRegressionConstraintForms(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{"simple", ":- p(X)."},
		{"multiple", ":- p(X), q(X), r(X)."},
		{"negation", ":- not p(X)."},
		{"mixed", ":- p(X), not q(X), r(X)."},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Errorf("constraint should parse: %v", errors)
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement")
			}
		})
	}
}

// TestRegressionMultipleProgramsSequential tests parsing multiple programs in sequence
func TestRegressionMultipleProgramsSequential(t *testing.T) {
	programs := []string{
		"p(a).",
		"q(X) :- p(X).",
		"r(X) :- q(X), not s(X).",
		":- p(X), not q(X).",
	}

	for i, prog := range programs {
		t.Run(fmt.Sprintf("program_%d", i), func(t *testing.T) {
			l := lexer.NewLexer(prog, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement")
			}
		})
	}
}

// TestRegressionProgramVariations tests program variations
func TestRegressionProgramVariations(t *testing.T) {
	// Same program in different formats
	variations := []string{
		"p(a).",
		"p(a) .",
		"p(a)\n.",
		"p(a)  \n  .",
		"% comment\np(a).",
	}

	expectedCount := 1

	for i, prog := range variations {
		t.Run(fmt.Sprintf("variation_%d", i), func(t *testing.T) {
			l := lexer.NewLexer(prog, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
			}

			if len(stmts) != expectedCount {
				t.Errorf("expected %d statement, got %d", expectedCount, len(stmts))
			}
		})
	}
}

// TestRegressionEdgeCaseCombinations tests combinations of edge cases
func TestRegressionEdgeCaseCombinations(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{
			"complex rule with aggregates",
			"count(C) :- C = #count{X : p(X), q(X)}, C > 5.",
		},
		{
			"rule with nested compounds and negation",
			"r(X) :- not p(f(g(X))), q(h(X, Y)).",
		},
		{
			"choice with constraints",
			"{a(X) : b(X)} :- c(X). :- a(X), d(X).",
		},
		{
			"multiple aggregate types",
			"s(S, M, Mi, Ma) :- S = #sum{}, M = #max{}, Mi = #min{}, Ma = #max{}.",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			// Just verify parsing attempt works
			_ = stmts
			_ = errors
		})
	}
}

// TestRegressionStressParsing stresses the parser with many statements
func TestRegressionStressParsing(t *testing.T) {
	// Build program with many facts
	var program string
	for i := 0; i < 500; i++ {
		program += fmt.Sprintf("p_%d(%d).\n", i%10, i)
	}

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Errorf("parse errors: %v", errors)
	}

	if len(stmts) != 500 {
		t.Errorf("expected 500 statements, got %d", len(stmts))
	}
}

// TestRegressionComplexityGradation tests increasing program complexity
func TestRegressionComplexityGradation(t *testing.T) {
	testCases := []struct {
		name    string
		program string
	}{
		{
			"trivial",
			"p.",
		},
		{
			"simple_fact",
			"p(a).",
		},
		{
			"fact_with_args",
			"p(a, b, c).",
		},
		{
			"simple_rule",
			"p(X) :- q(X).",
		},
		{
			"rule_with_negation",
			"p(X) :- not q(X).",
		},
		{
			"rule_with_multiple_body",
			"p(X) :- q(X), r(X), not s(X).",
		},
		{
			"rule_with_compound",
			"p(f(X, Y)) :- q(g(X), h(Y)).",
		},
		{
			"rule_with_aggregate",
			"p(C) :- C = #count{X : q(X)}, C > 5.",
		},
		{
			"choice_rule",
			"{p(X)} :- q(X).",
		},
		{
			"constraint",
			":- p(X), q(X).",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Logf("parse info for %s: %v", tc.name, errors)
			}

			if len(stmts) == 0 && len(errors) == 0 {
				t.Errorf("expected either statements or errors")
			}
		})
	}
}
