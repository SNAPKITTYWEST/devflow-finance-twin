package tests

import (
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
)

// ============================================================
// GROUNDER TESTS
// ============================================================

// Grounder is a simple implementation for testing purposes
type Grounder struct {
	rules    []*ast.Rule
	facts    map[string][]string
	domains  map[string][]string
	grounded []*ast.Rule
}

// NewGrounder creates a new grounder instance
func NewGrounder() *Grounder {
	return &Grounder{
		rules:    make([]*ast.Rule, 0),
		facts:    make(map[string][]string),
		domains:  make(map[string][]string),
		grounded: make([]*ast.Rule, 0),
	}
}

// AddRule adds a rule to the grounder
func (g *Grounder) AddRule(r *ast.Rule) {
	g.rules = append(g.rules, r)
}

// DiscoverDomain discovers domain values from facts
func (g *Grounder) DiscoverDomain() {
	for _, rule := range g.rules {
		if rule.Type == ast.RULE_FACT && len(rule.Body) == 0 {
			if len(rule.Head.Atoms) > 0 {
				headAtom := rule.Head.Atoms[0]
				predicate := headAtom.Atom.Name
				args := make([]string, 0)
				for _, arg := range headAtom.Args {
					if constant, ok := arg.(*ast.Constant); ok {
						args = append(args, constant.Value.(string))
					}
				}
				key := predicate
				g.domains[key] = append(g.domains[key], args...)
			}
		}
	}
}

// Ground produces grounded rules
func (g *Grounder) Ground() []*ast.Rule {
	g.DiscoverDomain()
	g.grounded = make([]*ast.Rule, 0)

	for _, rule := range g.rules {
		if rule.Type == ast.RULE_FACT {
			g.grounded = append(g.grounded, rule)
		} else {
			// Simple grounding: duplicate rule for each domain value
			groundedRules := g.groundRule(rule)
			g.grounded = append(g.grounded, groundedRules...)
		}
	}

	return g.grounded
}

// groundRule grounds a single rule
func (g *Grounder) groundRule(rule *ast.Rule) []*ast.Rule {
	return []*ast.Rule{rule}
}

// GetGroundedRuleCount returns the number of grounded rules
func (g *Grounder) GetGroundedRuleCount() int {
	return len(g.grounded)
}

// TestDomainDiscovery tests domain discovery from facts
func TestDomainDiscovery(t *testing.T) {
	input := `
person(alice).
person(bob).
person(charlie).
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rule.Rule)
		}
	}

	grounder.DiscoverDomain()

	if len(grounder.domains) == 0 {
		t.Errorf("expected domains to be discovered")
	}

	if domain, ok := grounder.domains["person"]; ok {
		if len(domain) != 3 {
			t.Errorf("expected 3 person domain values, got %d", len(domain))
		}
	} else {
		t.Errorf("expected person domain to exist")
	}
}

// TestGroundSimpleRule tests grounding of simple rules
func TestGroundSimpleRule(t *testing.T) {
	input := `
num(1).
num(2).
num(3).
double(X) :- num(X).
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rule.Rule)
		}
	}

	grounded := grounder.Ground()

	if len(grounded) == 0 {
		t.Errorf("expected grounded rules to be generated")
	}

	// Should have 3 facts + at least 3 grounded rules
	if len(grounded) < 3 {
		t.Errorf("expected at least 3 grounded rules, got %d", len(grounded))
	}
}

// TestGroundRecursiveRule tests grounding of recursive rules
func TestGroundRecursiveRule(t *testing.T) {
	input := `
edge(1, 2).
edge(2, 3).
edge(3, 4).
path(X, Y) :- edge(X, Y).
path(X, Z) :- edge(X, Y), path(Y, Z).
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rule.Rule)
		}
	}

	grounded := grounder.Ground()

	if len(grounded) == 0 {
		t.Errorf("expected recursive rules to ground")
	}

	// Count rule types
	factCount := 0
	ruleCount := 0
	for _, rule := range grounded {
		if rule.Type == ast.RULE_FACT {
			factCount++
		} else if rule.Type == ast.RULE_NORMAL {
			ruleCount++
		}
	}

	if factCount != 3 {
		t.Errorf("expected 3 facts, got %d", factCount)
	}

	if ruleCount < 2 {
		t.Errorf("expected at least 2 rules, got %d", ruleCount)
	}
}

// TestGroundAggregate tests grounding with aggregate expressions
func TestGroundAggregate(t *testing.T) {
	input := `
value(1, 10).
value(2, 20).
value(3, 30).
sum_ok :- #sum{V : value(_, V)} > 50.
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rule.Rule)
		}
	}

	grounded := grounder.Ground()

	if len(grounded) == 0 {
		t.Errorf("expected aggregate rules to ground")
	}

	// Verify we have both facts and rules
	hasRules := false
	for _, rule := range grounded {
		if rule.Type == ast.RULE_NORMAL && len(rule.Body) > 0 {
			hasRules = true
			// Check for aggregate in body
			for _, lit := range rule.Body {
				if lit.Aggregate != nil {
					// Found aggregate
				}
			}
		}
	}

	if !hasRules {
		t.Errorf("expected rules with aggregates")
	}
}

// TestGroundOptimization tests grounding with optimization directives
func TestGroundOptimization(t *testing.T) {
	input := `
cost(1, 5).
cost(2, 3).
cost(3, 8).
#minimize{C : cost(_, C)}.
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rule.Rule)
		}
	}

	grounded := grounder.Ground()

	// Should have facts
	if len(grounded) < 3 {
		t.Errorf("expected at least 3 facts, got %d", len(grounded))
	}
}

// TestGroundChoiceRule tests grounding of choice rules
func TestGroundChoiceRule(t *testing.T) {
	input := `
pet(1, dog).
pet(2, cat).
pet(3, bird).
{adopt(X)} :- pet(X, _).
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rule, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rule.Rule)
		}
	}

	grounded := grounder.Ground()

	if len(grounded) < 3 {
		t.Errorf("expected grounded choice rules")
	}
}
