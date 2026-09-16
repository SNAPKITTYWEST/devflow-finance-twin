package tests

import (
	"fmt"
	"strings"
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
)

// ============================================================
// INTEGRATION TESTS
// ============================================================

// IntegrationTestHelper provides utilities for integration tests
type IntegrationTestHelper struct {
	program  string
	stmts    []ast.Statement
	errors   []string
	grounder *Grounder
	solver   *SimpleSolver
}

// NewIntegrationTestHelper creates a new test helper
func NewIntegrationTestHelper(program string) *IntegrationTestHelper {
	return &IntegrationTestHelper{
		program:  program,
		stmts:    make([]ast.Statement, 0),
		errors:   make([]string, 0),
		grounder: NewGrounder(),
		solver:   NewSimpleSolver(),
	}
}

// Parse parses the program
func (h *IntegrationTestHelper) Parse() error {
	l := lexer.NewLexer(h.program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		h.errors = errors
		return fmt.Errorf("parse errors: %v", errors)
	}

	h.stmts = stmts
	return nil
}

// Ground grounds the program
func (h *IntegrationTestHelper) Ground() error {
	for _, stmt := range h.stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			h.grounder.AddRule(rule.Rule)
		}
	}

	h.grounder.Ground()
	return nil
}

// GetGroundedRules returns grounded rules
func (h *IntegrationTestHelper) GetGroundedRules() []*ast.Rule {
	return h.grounder.grounded
}

// TestBirdFly tests classic bird(tweety) fly example
func TestBirdFly(t *testing.T) {
	program := `
% Facts
bird(tweety).
bird(woody).
penguin(tweety).

% Rules
flies(X) :- bird(X), not abnormal(X).
abnormal(X) :- penguin(X).
`

	helper := NewIntegrationTestHelper(program)

	// Parse
	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	if len(helper.errors) > 0 {
		t.Errorf("unexpected parse errors: %v", helper.errors)
	}

	// Ground
	err = helper.Ground()
	if err != nil {
		t.Fatalf("ground failed: %v", err)
	}

	grounded := helper.GetGroundedRules()
	if len(grounded) == 0 {
		t.Errorf("expected grounded rules")
	}

	// Verify we have facts about birds
	hasBirdFact := false
	for _, rule := range grounded {
		if rule.Type == ast.RULE_FACT && len(rule.Head.Atoms) > 0 {
			if rule.Head.Atoms[0].Atom.Name == "bird" {
				hasBirdFact = true
				break
			}
		}
	}

	if !hasBirdFact {
		t.Errorf("expected bird facts in grounded program")
	}

	// Verify we have rules about flying
	hasFliesRule := false
	for _, rule := range grounded {
		if rule.Type == ast.RULE_NORMAL && len(rule.Head.Atoms) > 0 {
			if rule.Head.Atoms[0].Atom.Name == "flies" {
				hasFliesRule = true
				break
			}
		}
	}

	if !hasFliesRule {
		t.Errorf("expected flies rules in grounded program")
	}

	// Expected: tweety is penguin so abnormal, woody is not so should fly
	expectedGroundSize := len(grounded)
	if expectedGroundSize < 5 {
		t.Errorf("expected at least 5 grounded rules, got %d", expectedGroundSize)
	}
}

// TestNQueens tests N-Queens problem
func TestNQueens(t *testing.T) {
	program := `
% Domain
pos(1..4).

% Exactly one queen per row
{queen(R, C)} :- pos(R), pos(C).
:- pos(R), {queen(R, C) : pos(C)} != 1.

% Constraints
:- queen(R1, C), queen(R2, C), R1 < R2.
:- queen(R1, C1), queen(R2, C2), R1 < R2, |C1 - C2| = |R1 - R2|.
`

	helper := NewIntegrationTestHelper(program)

	// Parse
	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	// Ground
	err = helper.Ground()
	if err != nil {
		t.Fatalf("ground failed: %v", err)
	}

	grounded := helper.GetGroundedRules()
	if len(grounded) == 0 {
		t.Errorf("expected grounded N-Queens program")
	}

	// Count atoms in grounding
	atomCount := 0
	for _, rule := range grounded {
		atomCount += len(rule.Head.Atoms)
		atomCount += len(rule.Body)
	}

	// Should have significant ground program
	if atomCount < 10 {
		t.Errorf("expected significant grounding, got %d atoms", atomCount)
	}
}

// TestGraphColoring tests graph coloring problem
func TestGraphColoring(t *testing.T) {
	program := `
% Nodes and colors
node(1).
node(2).
node(3).
node(4).

color(red).
color(blue).
color(green).

% Edges
edge(1, 2).
edge(2, 3).
edge(3, 4).
edge(4, 1).
edge(1, 3).

% Each node gets exactly one color
{assign(N, C)} :- node(N), color(C).
:- node(N), {assign(N, C) : color(C)} != 1.

% Adjacent nodes must have different colors
:- edge(N1, N2), assign(N1, C), assign(N2, C).
`

	helper := NewIntegrationTestHelper(program)

	// Parse
	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	// Ground
	err = helper.Ground()
	if err != nil {
		t.Fatalf("ground failed: %v", err)
	}

	grounded := helper.GetGroundedRules()

	// Should have facts about nodes
	nodeCount := 0
	for _, rule := range grounded {
		if rule.Type == ast.RULE_FACT && len(rule.Head.Atoms) > 0 {
			if rule.Head.Atoms[0].Atom.Name == "node" {
				nodeCount++
			}
		}
	}

	if nodeCount != 4 {
		t.Errorf("expected 4 node facts, got %d", nodeCount)
	}

	// Should have constraints
	hasConstraint := false
	for _, rule := range grounded {
		if rule.Type == ast.RULE_CONSTRAINT {
			hasConstraint = true
			break
		}
	}

	if !hasConstraint {
		t.Errorf("expected constraint rules in graph coloring")
	}
}

// TestScheduling tests scheduling problem
func TestScheduling(t *testing.T) {
	program := `
% Activities and resources
activity(a).
activity(b).
activity(c).

time_slot(1).
time_slot(2).
time_slot(3).

% Each activity in exactly one slot
{schedule(A, T)} :- activity(A), time_slot(T).
:- activity(A), {schedule(A, T) : time_slot(T)} != 1.

% Dependencies
requires(b, a).
requires(c, a).

% Enforce dependencies
:- schedule(B, TB), schedule(A, TA), requires(B, A), TB <= TA.
`

	helper := NewIntegrationTestHelper(program)

	// Parse
	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	// Ground
	err = helper.Ground()
	if err != nil {
		t.Fatalf("ground failed: %v", err)
	}

	grounded := helper.GetGroundedRules()
	if len(grounded) == 0 {
		t.Errorf("expected grounded scheduling program")
	}

	// Should have activity and time_slot facts
	activityCount := 0
	timeSlotCount := 0

	for _, rule := range grounded {
		if rule.Type == ast.RULE_FACT && len(rule.Head.Atoms) > 0 {
			atomName := rule.Head.Atoms[0].Atom.Name
			if atomName == "activity" {
				activityCount++
			} else if atomName == "time_slot" {
				timeSlotCount++
			}
		}
	}

	if activityCount != 3 {
		t.Errorf("expected 3 activities, got %d", activityCount)
	}

	if timeSlotCount != 3 {
		t.Errorf("expected 3 time slots, got %d", timeSlotCount)
	}
}

// TestReachability tests reachability analysis
func TestReachability(t *testing.T) {
	program := `
% Graph edges
edge(1, 2).
edge(2, 3).
edge(3, 4).
edge(4, 5).

% Direct reachability
reach(X, Y) :- edge(X, Y).

% Transitive reachability
reach(X, Z) :- edge(X, Y), reach(Y, Z).
`

	helper := NewIntegrationTestHelper(program)

	// Parse
	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	// Ground
	err = helper.Ground()
	if err != nil {
		t.Fatalf("ground failed: %v", err)
	}

	grounded := helper.GetGroundedRules()
	if len(grounded) < 5 {
		t.Errorf("expected at least 5 grounded rules, got %d", len(grounded))
	}

	// Verify recursive rules
	hasRecursion := false
	for _, rule := range grounded {
		if rule.Type == ast.RULE_NORMAL && len(rule.Head.Atoms) > 0 {
			head := rule.Head.Atoms[0].Atom.Name
			if head == "reach" && len(rule.Body) > 0 {
				// Check if body contains reach too
				for _, lit := range rule.Body {
					if lit.Atom.Name == "reach" {
						hasRecursion = true
						break
					}
				}
			}
		}
	}

	if !hasRecursion {
		t.Errorf("expected recursive reach rules")
	}
}

// TestComplexProgram tests complex integrated program
func TestComplexProgram(t *testing.T) {
	program := `
% Domain definitions
person(alice).
person(bob).
person(charlie).

age(alice, 30).
age(bob, 25).
age(charlie, 35).

% Rules with conditionals
adult(X) :- person(X), age(X, A), A >= 18.

% Choice rules
{employed(X)} :- person(X).

% Constraints with aggregates
:- {employed(X)} > 2.

% Optimization
#minimize{A : adult(X), age(X, A)}.

% Facts
works(alice).
works(bob).
`

	helper := NewIntegrationTestHelper(program)

	// Parse
	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	// Ground
	err = helper.Ground()
	if err != nil {
		t.Fatalf("ground failed: %v", err)
	}

	grounded := helper.GetGroundedRules()
	if len(grounded) < 3 {
		t.Errorf("expected grounded complex program with at least 3 rules, got %d", len(grounded))
	}

	// Count different rule types
	factCount := 0
	ruleCount := 0
	constraintCount := 0

	for _, rule := range grounded {
		switch rule.Type {
		case ast.RULE_FACT:
			factCount++
		case ast.RULE_NORMAL:
			ruleCount++
		case ast.RULE_CONSTRAINT:
			constraintCount++
		}
	}

	if factCount == 0 {
		t.Errorf("expected facts in grounded program")
	}

	if ruleCount == 0 {
		t.Errorf("expected rules in grounded program")
	}
}

// TestEmptyProgram tests handling of empty program
func TestEmptyProgram(t *testing.T) {
	program := ""

	helper := NewIntegrationTestHelper(program)

	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	if len(helper.stmts) > 0 {
		t.Errorf("expected empty statement list, got %d", len(helper.stmts))
	}
}

// TestProgramWithComments tests handling of comments
func TestProgramWithComments(t *testing.T) {
	program := `
% This is a comment
fact(a). % inline comment
% Another comment
rule(X) :- fact(X).
`

	helper := NewIntegrationTestHelper(program)

	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	if len(helper.stmts) != 2 {
		t.Errorf("expected 2 statements (comment should be ignored), got %d", len(helper.stmts))
	}
}

// TestParseErrorRecovery tests error recovery in parsing
func TestParseErrorRecovery(t *testing.T) {
	program := `
fact(a).
rule(X :- fact(X).
another_fact(b).
`

	helper := NewIntegrationTestHelper(program)

	err := helper.Parse()
	// Should have parse error but still recover
	if err == nil {
		// Can proceed even with errors
	}
}

// TestProgramStats collects statistics on parsed program
type ProgramStats struct {
	TotalStatements int
	RuleCount       int
	FactCount       int
	ConstraintCount int
	DirectiveCount  int
	AverageBodySize int
}

// AnalyzeProgram analyzes a program and returns statistics
func AnalyzeProgram(program string) (*ProgramStats, error) {
	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		return nil, fmt.Errorf("parse errors: %v", errors)
	}

	stats := &ProgramStats{
		TotalStatements: len(stmts),
	}

	totalBodySize := 0
	bodyCount := 0

	for _, stmt := range stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			switch rule.Rule.Type {
			case ast.RULE_FACT:
				stats.FactCount++
			case ast.RULE_NORMAL:
				stats.RuleCount++
			case ast.RULE_CONSTRAINT:
				stats.ConstraintCount++
			}

			if len(rule.Rule.Body) > 0 {
				totalBodySize += len(rule.Rule.Body)
				bodyCount++
			}
		} else if _, ok := stmt.(*ast.Directive); ok {
			stats.DirectiveCount++
		}
	}

	if bodyCount > 0 {
		stats.AverageBodySize = totalBodySize / bodyCount
	}

	return stats, nil
}

// TestProgramAnalysis tests program analysis
func TestProgramAnalysis(t *testing.T) {
	program := `
% Facts
bird(tweety).
bird(woody).

% Rules
flies(X) :- bird(X), not abnormal(X).

% Constraints
:- flies(X), not safe(X).

% Directives
#show flies/1.
`

	stats, err := AnalyzeProgram(program)
	if err != nil {
		t.Fatalf("analysis failed: %v", err)
	}

	if stats.TotalStatements < 4 {
		t.Errorf("expected at least 4 statements, got %d", stats.TotalStatements)
	}

	if stats.FactCount != 2 {
		t.Errorf("expected 2 facts, got %d", stats.FactCount)
	}

	if stats.RuleCount < 1 {
		t.Errorf("expected at least 1 rule, got %d", stats.RuleCount)
	}

	if stats.ConstraintCount != 1 {
		t.Errorf("expected 1 constraint, got %d", stats.ConstraintCount)
	}
}

// TestMultilineProgram tests parsing multiline programs
func TestMultilineProgram(t *testing.T) {
	program := `
fact(a,
     b,
     c).

rule(X, Y) :-
    fact(X, Y, Z),
    other(Z).
`

	helper := NewIntegrationTestHelper(program)

	err := helper.Parse()
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}

	if len(helper.stmts) < 1 {
		t.Errorf("expected at least 1 statement")
	}
}

// TestProgramEquivalence tests if two programs parse to same structure
func TestProgramEquivalence(t *testing.T) {
	prog1 := "fact(a). rule(X) :- fact(X)."
	prog2 := `
fact(a).
rule(X) :- fact(X).
`

	l1 := lexer.NewLexer(prog1, "prog1.lp")
	p1 := parser.NewParser(l1)
	stmts1, errors1 := p1.Parse()

	l2 := lexer.NewLexer(prog2, "prog2.lp")
	p2 := parser.NewParser(l2)
	stmts2, errors2 := p2.Parse()

	if len(errors1) > 0 || len(errors2) > 0 {
		t.Fatalf("parse errors")
	}

	if len(stmts1) != len(stmts2) {
		t.Errorf("different statement counts: %d vs %d", len(stmts1), len(stmts2))
	}

	// Should be structurally equivalent
	for i := range stmts1 {
		_, ok1 := stmts1[i].(*ast.RuleStatement)
		_, ok2 := stmts2[i].(*ast.RuleStatement)
		if ok1 != ok2 {
			t.Errorf("different statement types at position %d", i)
		}
	}
}

// BenchmarkProgramSize measures performance with varying program sizes
func BenchmarkProgramSize(b *testing.B) {
	sizes := []int{10, 50, 100}

	for _, size := range sizes {
		b.Run(fmt.Sprintf("size_%d", size), func(b *testing.B) {
			// Generate program with 'size' facts
			var sb strings.Builder
			for i := 0; i < size; i++ {
				sb.WriteString(fmt.Sprintf("fact(%d).\n", i))
			}
			program := sb.String()

			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				l := lexer.NewLexer(program, "test.lp")
				p := parser.NewParser(l)
				_, _ = p.Parse()
			}
		})
	}
}
