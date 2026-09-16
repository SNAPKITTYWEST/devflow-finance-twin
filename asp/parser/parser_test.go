package parser

import (
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
)

// TestParseFact tests parsing of simple facts
func TestParseFact(t *testing.T) {
	input := "bird(tweety)."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if stmt.Rule.Type != ast.RULE_FACT {
		t.Fatalf("expected RULE_FACT, got %v", stmt.Rule.Type)
	}

	if len(stmt.Rule.Head.Atoms) != 1 {
		t.Fatalf("expected 1 head atom, got %d", len(stmt.Rule.Head.Atoms))
	}

	atom := stmt.Rule.Head.Atoms[0]
	if atom.Atom.Name != "bird" {
		t.Fatalf("expected atom 'bird', got %s", atom.Atom.Name)
	}

	if len(atom.Args) != 1 {
		t.Fatalf("expected 1 argument, got %d", len(atom.Args))
	}
}

// TestParseRule tests parsing of rules
func TestParseRule(t *testing.T) {
	input := "flies(X) :- bird(X), not abnormal(X)."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if stmt.Rule.Type != ast.RULE_NORMAL {
		t.Fatalf("expected RULE_NORMAL, got %v", stmt.Rule.Type)
	}

	if len(stmt.Rule.Body) != 2 {
		t.Fatalf("expected 2 body literals, got %d", len(stmt.Rule.Body))
	}

	// Check first body literal: bird(X)
	if !stmt.Rule.Body[0].Positive {
		t.Fatal("expected positive literal")
	}

	// Check second body literal: not abnormal(X)
	if stmt.Rule.Body[1].Positive {
		t.Fatal("expected negative literal")
	}
}

// TestParseConstraint tests parsing of constraints
func TestParseConstraint(t *testing.T) {
	input := ":- negative_body."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if stmt.Rule.Type != ast.RULE_CONSTRAINT {
		t.Fatalf("expected RULE_CONSTRAINT, got %v", stmt.Rule.Type)
	}

	if len(stmt.Rule.Body) != 1 {
		t.Fatalf("expected 1 body literal, got %d", len(stmt.Rule.Body))
	}
}

// TestParseCompound tests parsing compound terms
func TestParseCompound(t *testing.T) {
	input := "parent(john, mary). sibling(X, Y) :- parent(Z, X), parent(Z, Y)."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 2 {
		t.Fatalf("expected 2 statements, got %d", len(stmts))
	}
}

// TestParseAggregate tests parsing aggregate expressions
func TestParseAggregate(t *testing.T) {
	input := "query :- #count { X : person(X) } >= 2."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if len(stmt.Rule.Body) != 1 {
		t.Fatalf("expected 1 body literal, got %d", len(stmt.Rule.Body))
	}

	lit := stmt.Rule.Body[0]
	if lit.Aggregate == nil {
		t.Fatal("expected aggregate literal")
	}

	if lit.Aggregate.Op != ast.AGG_COUNT {
		t.Fatalf("expected COUNT aggregate, got %s", lit.Aggregate.Op)
	}
}

// TestParseDirective tests parsing directives
func TestParseDirective(t *testing.T) {
	input := "#show person/1."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	dir, ok := stmts[0].(*ast.Directive)
	if !ok {
		t.Fatalf("expected Directive, got %T", stmts[0])
	}

	if dir.Type != "show" {
		t.Fatalf("expected 'show' directive, got %s", dir.Type)
	}
}

// TestParseChoiceRule tests parsing choice rules
func TestParseChoiceRule(t *testing.T) {
	input := "{ p(X) : item(X) } = 1."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if stmt.Rule.Head.Type != ast.HEAD_CHOICE {
		t.Fatalf("expected HEAD_CHOICE, got %v", stmt.Rule.Head.Type)
	}
}

// TestParseMultipleStatements tests parsing multiple statements
func TestParseMultipleStatements(t *testing.T) {
	input := `
		bird(tweety).
		bird(kermit).
		flies(X) :- bird(X), not abnormal(X).
		abnormal(kermit).
	`
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 4 {
		t.Fatalf("expected 4 statements, got %d", len(stmts))
	}

	// Verify all are RuleStatements
	for i, stmt := range stmts {
		if _, ok := stmt.(*ast.RuleStatement); !ok {
			t.Fatalf("statement %d is not RuleStatement, got %T", i, stmt)
		}
	}
}

// TestParseComparison tests parsing comparison literals
func TestParseComparison(t *testing.T) {
	input := "old(X) :- age(X, Y), Y > 65."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if len(stmt.Rule.Body) != 2 {
		t.Fatalf("expected 2 body literals, got %d", len(stmt.Rule.Body))
	}

	// Second literal should be comparison: Y > 65
	comp := stmt.Rule.Body[1]
	if comp.Atom.Name != ">" {
		t.Fatalf("expected '>' comparison, got %s", comp.Atom.Name)
	}

	if len(comp.Args) != 2 {
		t.Fatalf("expected 2 comparison arguments, got %d", len(comp.Args))
	}
}

// TestParseNegation tests parsing negated literals
func TestParseNegation(t *testing.T) {
	input := "safe(X) :- not dangerous(X)."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	lit := stmt.Rule.Body[0]
	if lit.Positive {
		t.Fatal("expected negative literal")
	}
}

// TestParseDisjunctiveHead tests parsing disjunctive rules
func TestParseDisjunctiveHead(t *testing.T) {
	input := "a(X) | b(X) :- c(X)."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if stmt.Rule.Head.Type != ast.HEAD_DISJUNCTIVE {
		t.Fatalf("expected HEAD_DISJUNCTIVE, got %v", stmt.Rule.Head.Type)
	}

	if len(stmt.Rule.Head.Atoms) != 2 {
		t.Fatalf("expected 2 head atoms, got %d", len(stmt.Rule.Head.Atoms))
	}
}

// TestParseAggregateSum tests sum aggregate
func TestParseAggregateSum(t *testing.T) {
	input := "balance(N) :- #sum { C,X : cost(X,C) } = N."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if len(stmt.Rule.Body) < 1 {
		t.Fatalf("expected at least 1 body literal")
	}

	// Find aggregate literal
	hasAggregate := false
	for _, lit := range stmt.Rule.Body {
		if lit.Aggregate != nil && lit.Aggregate.Op == ast.AGG_SUM {
			hasAggregate = true
			break
		}
	}

	if !hasAggregate {
		t.Fatal("expected sum aggregate in body")
	}
}

// TestParseNegativeNumbers tests parsing negative number constants
func TestParseNegativeNumbers(t *testing.T) {
	input := "temp(X) :- temperature(X), X < -5."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if len(stmt.Rule.Body) != 2 {
		t.Fatalf("expected 2 body literals, got %d", len(stmt.Rule.Body))
	}
}

// TestParseStringConstants tests parsing string constants
func TestParseStringConstants(t *testing.T) {
	input := `name("Alice").`
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(stmts))
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if len(stmt.Rule.Head.Atoms[0].Args) != 1 {
		t.Fatalf("expected 1 argument, got %d", len(stmt.Rule.Head.Atoms[0].Args))
	}
}

// TestParserErrorRecovery tests error recovery
func TestParserErrorRecovery(t *testing.T) {
	// Missing period
	input := "bird(tweety)"
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	_, errors := p.Parse()

	if len(errors) == 0 {
		t.Fatal("expected parse error for missing period")
	}
}

// TestParseArithmetic tests parsing arithmetic expressions
func TestParseArithmetic(t *testing.T) {
	input := "result(N) :- X = 1, Y = 2, N = X + Y."
	l := lexer.NewLexer(input, "test.lp")
	p := NewParser(l)

	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	stmt, ok := stmts[0].(*ast.RuleStatement)
	if !ok {
		t.Fatalf("expected RuleStatement, got %T", stmts[0])
	}

	if len(stmt.Rule.Body) < 3 {
		t.Fatalf("expected at least 3 body literals, got %d", len(stmt.Rule.Body))
	}
}
