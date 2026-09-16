package tests

import (
	"testing"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
)

// ============================================================
// PARSER TESTS
// ============================================================

// TestParseAtom tests parsing of simple atoms
func TestParseAtom(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    string
		wantErr bool
	}{
		{
			name:  "simple atom",
			input: "atom.",
			want:  "atom",
		},
		{
			name:  "atom with underscore",
			input: "my_atom.",
			want:  "my_atom",
		},
		{
			name:  "atom with numbers",
			input: "atom123.",
			want:  "atom123",
		},
		{
			name:    "invalid atom uppercase",
			input:   "Atom.",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr {
				if len(errors) == 0 {
					t.Errorf("expected parse error, got none")
				}
				return
			}

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
				return
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement, got %d", len(stmts))
				return
			}

			stmt, ok := stmts[0].(*ast.RuleStatement)
			if !ok {
				t.Errorf("expected RuleStatement, got %T", stmts[0])
				return
			}

			if len(stmt.Rule.Head.Atoms) == 0 {
				t.Errorf("expected head atoms")
				return
			}

			atom := stmt.Rule.Head.Atoms[0]
			if atom.Atom.Name != tt.want {
				t.Errorf("expected atom %q, got %q", tt.want, atom.Atom.Name)
			}
		})
	}
}

// TestParseRule tests parsing of rules with body literals
func TestParseRule(t *testing.T) {
	tests := []struct {
		name         string
		input        string
		headAtoms    int
		bodyLiterals int
		wantErr      bool
	}{
		{
			name:         "simple rule",
			input:        "head :- body.",
			headAtoms:    1,
			bodyLiterals: 1,
		},
		{
			name:         "rule with multiple body literals",
			input:        "head :- body1, body2, body3.",
			headAtoms:    1,
			bodyLiterals: 3,
		},
		{
			name:         "rule with negation",
			input:        "flies(X) :- bird(X), not abnormal(X).",
			headAtoms:    1,
			bodyLiterals: 2,
		},
		{
			name:         "multiple head atoms",
			input:        "head1 | head2 :- body.",
			headAtoms:    2,
			bodyLiterals: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr {
				if len(errors) == 0 {
					t.Errorf("expected parse error, got none")
				}
				return
			}

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
				return
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement, got %d", len(stmts))
				return
			}

			stmt, ok := stmts[0].(*ast.RuleStatement)
			if !ok {
				t.Errorf("expected RuleStatement, got %T", stmts[0])
				return
			}

			if len(stmt.Rule.Head.Atoms) != tt.headAtoms {
				t.Errorf("expected %d head atoms, got %d", tt.headAtoms, len(stmt.Rule.Head.Atoms))
			}

			if len(stmt.Rule.Body) != tt.bodyLiterals {
				t.Errorf("expected %d body literals, got %d", tt.bodyLiterals, len(stmt.Rule.Body))
			}
		})
	}
}

// TestParseConstraint tests parsing of constraints
func TestParseConstraint(t *testing.T) {
	tests := []struct {
		name         string
		input        string
		bodyLiterals int
		wantErr      bool
	}{
		{
			name:         "simple constraint",
			input:        ":- negative_body.",
			bodyLiterals: 1,
		},
		{
			name:         "constraint with multiple literals",
			input:        ":- lit1, lit2, lit3.",
			bodyLiterals: 3,
		},
		{
			name:         "constraint with negation",
			input:        ":- not allowed(X), active(X).",
			bodyLiterals: 2,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr {
				if len(errors) == 0 {
					t.Errorf("expected parse error, got none")
				}
				return
			}

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
				return
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement, got %d", len(stmts))
				return
			}

			stmt, ok := stmts[0].(*ast.RuleStatement)
			if !ok {
				t.Errorf("expected RuleStatement, got %T", stmts[0])
				return
			}

			if len(stmt.Rule.Body) != tt.bodyLiterals {
				t.Errorf("expected %d body literals, got %d", tt.bodyLiterals, len(stmt.Rule.Body))
			}
		})
	}
}

// TestParseAggregate tests parsing of aggregate expressions
func TestParseAggregate(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{
			name:  "count aggregate",
			input: "ok :- #count{} = 0.",
		},
		{
			name:  "sum aggregate",
			input: "ok :- #sum{X : num(X)} > 5.",
		},
		{
			name:  "min aggregate",
			input: "ok :- #min{} >= 1.",
		},
		{
			name:  "max aggregate",
			input: "ok :- #max{} <= 10.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr {
				if len(errors) == 0 {
					t.Errorf("expected parse error, got none")
				}
				return
			}

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
				return
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement, got %d", len(stmts))
			}
		})
	}
}

// TestParseChoiceRule tests parsing of choice rules
func TestParseChoiceRule(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{
			name:  "simple choice rule",
			input: "{choose(X)} :- domain(X).",
		},
		{
			name:  "choice rule with bounds",
			input: "1 {choose(X)} 2 :- domain(X).",
		},
		{
			name:  "multiple choice atoms",
			input: "{a; b; c}.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr {
				if len(errors) == 0 {
					t.Errorf("expected parse error, got none")
				}
				return
			}

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
				return
			}

			if len(stmts) != 1 {
				t.Errorf("expected 1 statement, got %d", len(stmts))
			}
		})
	}
}

// TestParseOptimization tests parsing of optimization directives
func TestParseOptimization(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{
			name:  "minimize directive",
			input: "#minimize{X : cost(X)}.",
		},
		{
			name:  "maximize directive",
			input: "#maximize{X : value(X)}.",
		},
		{
			name:  "show directive",
			input: "#show predicate/1.",
		},
		{
			name:  "hide directive",
			input: "#hide internal/0.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.NewLexer(tt.input, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if tt.wantErr {
				if len(errors) == 0 {
					t.Errorf("expected parse error, got none")
				}
				return
			}

			if len(errors) > 0 {
				t.Errorf("parse error: %v", errors)
				return
			}

			if len(stmts) >= 1 {
				// Valid parse
			}
		})
	}
}

// TestParseComplexProgram tests parsing of complex ASP programs
func TestParseComplexProgram(t *testing.T) {
	input := `
% Facts
bird(tweety).
bird(woody).

% Rules
flies(X) :- bird(X), not abnormal(X).
abnormal(X) :- penguin(X).

% Choice rule
{pet(X)} :- cat(X).

% Constraints
:- flies(X), not allowed(X).

% Optimization
#minimize{X : pet(X)}.
`

	l := lexer.NewLexer(input, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse error: %v", errors)
	}

	if len(stmts) < 5 {
		t.Errorf("expected at least 5 statements, got %d", len(stmts))
	}
}
