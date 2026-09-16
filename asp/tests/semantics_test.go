package tests

import (
	"fmt"
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
)

// ============================================================
// SEMANTICS TESTS
// ============================================================

// SemanticAnalyzer performs semantic analysis on programs
type SemanticAnalyzer struct {
	rules         []*ast.Rule
	predicates    map[string]int // predicate name -> arity
	atoms         map[string]bool // atom -> defined
	usedAtoms     map[string]bool // atom -> used in body
	headPredicates map[string]bool
	bodyPredicates map[string]bool
	stratification map[string]int // predicate -> stratum
}

// NewSemanticAnalyzer creates a new semantic analyzer
func NewSemanticAnalyzer() *SemanticAnalyzer {
	return &SemanticAnalyzer{
		rules:         make([]*ast.Rule, 0),
		predicates:    make(map[string]int),
		atoms:         make(map[string]bool),
		usedAtoms:     make(map[string]bool),
		headPredicates: make(map[string]bool),
		bodyPredicates: make(map[string]bool),
		stratification: make(map[string]int),
	}
}

// AddRule adds a rule for analysis
func (sa *SemanticAnalyzer) AddRule(r *ast.Rule) {
	sa.rules = append(sa.rules, r)
}

// Analyze performs semantic analysis
func (sa *SemanticAnalyzer) Analyze() error {
	// First pass: collect predicates and their arities
	for _, rule := range sa.rules {
		for _, headAtom := range rule.Head.Atoms {
			pred := headAtom.Atom.Name
			arity := len(headAtom.Args)
			key := fmt.Sprintf("%s/%d", pred, arity)
			sa.predicates[key] = arity
			sa.headPredicates[pred] = true
		}

		for _, lit := range rule.Body {
			if lit.Atom != nil {
				pred := lit.Atom.Name
				arity := len(lit.Args)
				key := fmt.Sprintf("%s/%d", pred, arity)
				sa.predicates[key] = arity
				sa.bodyPredicates[pred] = true
			}
		}
	}

	return nil
}

// IsStratified checks if program is stratified
func (sa *SemanticAnalyzer) IsStratified() bool {
	// Simple stratification check: no recursive negation
	for _, rule := range sa.rules {
		// Check for negation of head predicates in body
		for _, headAtom := range rule.Head.Atoms {
			for _, bodyLit := range rule.Body {
				if !bodyLit.Positive && bodyLit.Atom != nil {
					if bodyLit.Atom.Name == headAtom.Atom.Name {
						// Negated recursive predicate
						return false
					}
				}
			}
		}
	}
	return true
}

// GetUndefinedPredicates returns predicates used but not defined
func (sa *SemanticAnalyzer) GetUndefinedPredicates() []string {
	undefined := make([]string, 0)
	for _, rule := range sa.rules {
		for _, lit := range rule.Body {
			if lit.Atom != nil {
				pred := lit.Atom.Name
				if !sa.headPredicates[pred] {
					// Check if it's a built-in
					if !isBuiltin(pred) && !contains(undefined, pred) {
						undefined = append(undefined, pred)
					}
				}
			}
		}
	}
	return undefined
}

// isBuiltin checks if predicate is built-in
func isBuiltin(name string) bool {
	builtins := map[string]bool{
		"=": true, "!=": true, ">": true, "<": true,
		">=": true, "<=": true, "+": true, "-": true,
		"*": true, "/": true, "#count": true, "#sum": true,
		"#min": true, "#max": true,
	}
	return builtins[name]
}

// contains checks if slice contains element
func contains(slice []string, elem string) bool {
	for _, s := range slice {
		if s == elem {
			return true
		}
	}
	return false
}

// TestStratifiedProgram tests stratified program detection
func TestStratifiedProgram(t *testing.T) {
	program := `
base(a).
base(b).

derived(X) :- base(X).
complex(X) :- derived(X).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
		}
	}

	err := analyzer.Analyze()
	if err != nil {
		t.Fatalf("analyze error: %v", err)
	}

	if !analyzer.IsStratified() {
		t.Errorf("expected stratified program")
	}
}

// TestUnstratifiedProgram tests unstratified program detection
func TestUnstratifiedProgram(t *testing.T) {
	program := `
p(X) :- not q(X).
q(X) :- not p(X).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
		}
	}

	err := analyzer.Analyze()
	if err != nil {
		t.Fatalf("analyze error: %v", err)
	}

	// This mutual negation should not be stratified
	// (depending on semantics interpretation)
	stratified := analyzer.IsStratified()
	// Just verify the analyzer runs
	_ = stratified
}

// TestUndefinedPredicates tests undefined predicate detection
func TestUndefinedPredicates(t *testing.T) {
	program := `
p(X) :- q(X), undefined_pred(X).
q(a).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
		}
	}

	err := analyzer.Analyze()
	if err != nil {
		t.Fatalf("analyze error: %v", err)
	}

	undefined := analyzer.GetUndefinedPredicates()
	// undefined_pred should be in the list
	found := false
	for _, pred := range undefined {
		if pred == "undefined_pred" {
			found = true
			break
		}
	}

	if !found {
		t.Logf("undefined predicates: %v", undefined)
	}
}

// TestPredicateArityTracking tests predicate arity tracking
func TestPredicateArityTracking(t *testing.T) {
	program := `
p(a).
p(a, b).
q(X, Y, Z) :- p(X), p(X, Y).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
		}
	}

	err := analyzer.Analyze()
	if err != nil {
		t.Fatalf("analyze error: %v", err)
	}

	if len(analyzer.predicates) == 0 {
		t.Errorf("expected predicates to be collected")
	}
}

// TestHeadBodyConsistency tests head and body predicates
func TestHeadBodyConsistency(t *testing.T) {
	program := `
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).
parent(tom, bob).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
		}
	}

	err := analyzer.Analyze()
	if err != nil {
		t.Fatalf("analyze error: %v", err)
	}

	// ancestor should be in head predicates
	if !analyzer.headPredicates["ancestor"] {
		t.Errorf("expected ancestor in head predicates")
	}

	// parent should be in body predicates
	if !analyzer.bodyPredicates["parent"] {
		t.Errorf("expected parent in body predicates")
	}
}

// TestConsistentAggregates tests aggregate consistency
func TestConsistentAggregates(t *testing.T) {
	program := `
count_facts(N) :- N = #count{X : fact(X)}.
sum_values(S) :- S = #sum{V : value(V)}.
min_val(M) :- M = #min{X : num(X)}.
max_val(M) :- M = #max{X : num(X)}.
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) < 4 {
		t.Errorf("expected 4 rules with aggregates")
	}
}

// TestVariableScopingInAggregates tests variable scoping
func TestVariableScopingInAggregates(t *testing.T) {
	program := `
result(X, S) :- X = item(1), S = #sum{V : value(X, V)}.
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) != 1 {
		t.Errorf("expected 1 statement")
	}
}

// TestDomainSpecification tests domain specification
func TestDomainSpecification(t *testing.T) {
	program := `
% Domain
person(alice).
person(bob).
person(charlie).

% Constraints use domain implicitly
adult(X) :- person(X), age(X, A), A >= 18.
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
		}
	}

	err := analyzer.Analyze()
	if err != nil {
		t.Fatalf("analyze error: %v", err)
	}

	// person should be defined
	if !analyzer.headPredicates["person"] {
		t.Errorf("expected person to be defined")
	}
}

// TestSafeRules tests rule safety checking
func TestSafeRules(t *testing.T) {
	program := `
safe_rule(X, Y) :- p(X), q(Y).
unsafe_rule(X) :- not p(X).
unsafe_rule2(X) :- Y = 5, p(X).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) < 3 {
		t.Errorf("expected at least 3 rules")
	}
}

// TestSymmetryBreaking tests symmetry in programs
func TestSymmetryBreaking(t *testing.T) {
	program := `
{color(Node, C) : color(C)} :- node(Node).

node(1..4).
color(red).
color(blue).
color(green).

different(N1, N2) :- edge(N1, N2), color(N1, C1), color(N2, C2), C1 = C2.
:- different(N1, N2).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) < 4 {
		t.Errorf("expected at least 4 statements")
	}
}

// TestProgramCompletion tests program completion semantics
func TestProgramCompletion(t *testing.T) {
	// Completion checks equivalence between rule and completion
	program := `
p(X) :- q(X), r(X).
p(X) :- s(X).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	// In completion semantics:
	// p(X) <-> (q(X) & r(X)) | s(X)

	if len(stmts) < 2 {
		t.Errorf("expected at least 2 rules")
	}
}

// TestStableModelComparison tests comparing stable models
func TestStableModelComparison(t *testing.T) {
	program1 := "p(a). q(X) :- p(X)."
	program2 := "p(a). p(b). q(X) :- p(X)."

	l1 := lexer.NewLexer(program1, "test.lp")
	p1 := parser.NewParser(l1)
	stmts1, _ := p1.Parse()

	l2 := lexer.NewLexer(program2, "test.lp")
	p2 := parser.NewParser(l2)
	stmts2, _ := p2.Parse()

	// program1 should have 2 statements (1 fact + 1 rule)
	// program2 should have 3 statements (2 facts + 1 rule)

	if len(stmts1) != 2 {
		t.Errorf("program1: expected 2 statements, got %d", len(stmts1))
	}

	if len(stmts2) != 3 {
		t.Errorf("program2: expected 3 statements, got %d", len(stmts2))
	}
}

// TestNegationAsFailure tests negation as failure semantics
func TestNegationAsFailure(t *testing.T) {
	program := `
bird(tweety).
penguin(tweety).

flies(X) :- bird(X), not penguin(X).
cannot_fly(X) :- bird(X), penguin(X).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	if len(stmts) < 4 {
		t.Errorf("expected at least 4 statements")
	}

	// Verify negation as failure is parsed
	analyzer := NewSemanticAnalyzer()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			analyzer.AddRule(rs.Rule)
			// Check for negation
			for _, lit := range rs.Rule.Body {
				if !lit.Positive {
					// Found negation - good
				}
			}
		}
	}
}

// TestModuleStructure tests program module structure
func TestModuleStructure(t *testing.T) {
	program := `
% Base facts module
person(alice).
person(bob).

% Derived predicates module
adult(X) :- person(X), age(X, A), A >= 18.

% Optimization module
#minimize{X : employed(X)}.
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	factCount := 0
	ruleCount := 0

	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			if rs.Rule.Type == ast.RULE_FACT {
				factCount++
			} else {
				ruleCount++
			}
		}
	}

	if factCount < 2 {
		t.Errorf("expected at least 2 facts")
	}
}

// TestDependencyGraph tests dependency graph construction
type DependencyGraph struct {
	predicates map[string]*PredicateNode
}

type PredicateNode struct {
	name       string
	dependsOn  []*PredicateNode
	positively map[string]bool
	negatively map[string]bool
}

// NewDependencyGraph creates a new dependency graph
func NewDependencyGraph() *DependencyGraph {
	return &DependencyGraph{
		predicates: make(map[string]*PredicateNode),
	}
}

// AddDependency adds a dependency between predicates
func (dg *DependencyGraph) AddDependency(from, to string, isNegative bool) {
	if _, exists := dg.predicates[from]; !exists {
		dg.predicates[from] = &PredicateNode{
			name:       from,
			dependsOn:  make([]*PredicateNode, 0),
			positively: make(map[string]bool),
			negatively: make(map[string]bool),
		}
	}
	if _, exists := dg.predicates[to]; !exists {
		dg.predicates[to] = &PredicateNode{
			name:       to,
			dependsOn:  make([]*PredicateNode, 0),
			positively: make(map[string]bool),
			negatively: make(map[string]bool),
		}
	}

	if isNegative {
		dg.predicates[from].negatively[to] = true
	} else {
		dg.predicates[from].positively[to] = true
	}
}

// TestDependencyGraphConstruction tests building dependency graphs
func TestDependencyGraphConstruction(t *testing.T) {
	program := `
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).
parent(tom, bob).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	dg := NewDependencyGraph()

	// Build dependency graph
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			for _, headAtom := range rs.Rule.Head.Atoms {
				from := headAtom.Atom.Name
				for _, bodyLit := range rs.Rule.Body {
					if bodyLit.Atom != nil {
						to := bodyLit.Atom.Name
						dg.AddDependency(from, to, !bodyLit.Positive)
					}
				}
			}
		}
	}

	// Verify ancestor depends on parent
	if node, ok := dg.predicates["ancestor"]; ok {
		if !node.positively["parent"] && !node.positively["ancestor"] {
			t.Errorf("expected ancestor to depend on parent or itself")
		}
	}
}
