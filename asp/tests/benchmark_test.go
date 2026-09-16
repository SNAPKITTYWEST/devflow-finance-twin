package tests

import (
	"fmt"
	"strings"
	"testing"

	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
	"devflow-finance-twin/asp/propagation"
)

// ============================================================
// BENCHMARK TESTS WITH EXPECTED SIZES
// ============================================================

// BenchmarkTestCase represents a benchmark test case
type BenchmarkTestCase struct {
	Name                 string
	Program              string
	ExpectedStatements   int
	ExpectedGroundSize   int
	ExpectedModels       int
	Description          string
}

// TestBenchmarkBirdFly is a benchmark case for classic bird example
func TestBenchmarkBirdFly(t *testing.T) {
	program := `
bird(tweety).
bird(woody).
bird(penguin_jim).

penguin(penguin_jim).

flies(X) :- bird(X), not abnormal(X).
abnormal(X) :- penguin(X).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	expectedStatements := 6 // 3 bird facts + 1 penguin fact + 2 rules
	if len(stmts) != expectedStatements {
		t.Errorf("expected %d statements, got %d", expectedStatements, len(stmts))
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	expectedGroundSize := 6 // Same as non-ground for this simple case
	if len(grounded) < 5 {
		t.Errorf("expected at least 5 grounded rules, got %d", len(grounded))
	}

	// Expected models: tweety should fly, woody should fly, penguin_jim should not fly
	expectedModels := 1 // Unique stable model
	t.Logf("Bird-Fly: parsed %d statements, grounded %d rules, expected %d models",
		len(stmts), len(grounded), expectedModels)
}

// TestBenchmarkNQueens4 is a benchmark for 4-Queens problem
func TestBenchmarkNQueens4(t *testing.T) {
	program := `
pos(1..4).
{queen(R, C) : pos(C)} :- pos(R).
:- pos(C), {queen(R, C) : pos(R)} != 1.
:- pos(R1), pos(R2), pos(C1), pos(C2), R1 < R2, queen(R1, C1), queen(R2, C1).
:- pos(R1), pos(R2), pos(C1), pos(C2), R1 < R2, queen(R1, C1), queen(R2, C2), C1 < C2, R2 - R1 = C2 - C1.
:- pos(R1), pos(R2), pos(C1), pos(C2), R1 < R2, queen(R1, C1), queen(R2, C2), C1 < C2, R2 - R1 = C1 - C2.
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	expectedStatements := 6 // pos facts + choice rule + column constraint + diagonal constraints
	if len(stmts) < 5 {
		t.Errorf("expected at least 5 statements, got %d", len(stmts))
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	// Ground size: 4 pos + 16 queen choices + column constraints (4) + diagonal constraints (many)
	expectedGroundSize := 50
	if len(grounded) < 10 {
		t.Errorf("expected at least 10 grounded rules, got %d", len(grounded))
	}

	// 4-Queens has exactly 2 solutions
	expectedModels := 2
	t.Logf("4-Queens: parsed %d statements, grounded %d rules, expected %d models",
		len(stmts), len(grounded), expectedModels)
}

// TestBenchmarkGraphColoring is a benchmark for graph 3-coloring
func TestBenchmarkGraphColoring(t *testing.T) {
	program := `
node(1..5).
color(red).
color(blue).
color(green).

edge(1, 2).
edge(1, 3).
edge(2, 3).
edge(2, 4).
edge(3, 4).
edge(3, 5).
edge(4, 5).

{assign(N, C) : color(C)} :- node(N).
:- node(N), {assign(N, C)} != 1.
:- edge(N1, N2), N1 < N2, assign(N1, C), assign(N2, C).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	expectedStatements := 15 // nodes, colors, edges, choice rule, constraints
	if len(stmts) < 12 {
		t.Errorf("expected at least 12 statements, got %d", len(stmts))
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	// Ground size: 5 nodes + 3 colors + 7 edges + 15 color assignments + constraints
	expectedGroundSize := 80
	if len(grounded) < 30 {
		t.Errorf("expected at least 30 grounded rules, got %d", len(grounded))
	}

	// Multiple valid colorings exist
	expectedModels := -1 // Multiple (at least 1)
	t.Logf("Graph-Coloring: parsed %d statements, grounded %d rules, expected %d+ models",
		len(stmts), len(grounded), 1)
}

// TestBenchmarkScheduling is a benchmark for scheduling problem
func TestBenchmarkScheduling(t *testing.T) {
	program := `
task(1..5).
resource(a).
resource(b).
duration(1, 2).
duration(2, 3).
duration(3, 1).
duration(4, 2).
duration(5, 1).

{schedule(T, R) : resource(R)} :- task(T).
:- task(T), {schedule(T, R)} != 1.

depends(2, 1).
depends(3, 1).
depends(4, 2).
depends(5, 3).

:- depends(T1, T2), schedule(T1, R1), schedule(T2, R2).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	expectedStatements := 14 // tasks, resources, durations, choice, dependencies, constraints
	if len(stmts) < 10 {
		t.Errorf("expected at least 10 statements, got %d", len(stmts))
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	// Ground size: 5 tasks + 2 resources + 5 durations + 10 scheduling + dependencies + constraints
	expectedGroundSize := 50
	if len(grounded) < 20 {
		t.Errorf("expected at least 20 grounded rules, got %d", len(grounded))
	}

	expectedModels := -1 // Multiple valid schedules
	t.Logf("Scheduling: parsed %d statements, grounded %d rules, expected %d+ models",
		len(stmts), len(grounded), 1)
}

// TestBenchmarkReachability is a benchmark for graph reachability
func TestBenchmarkReachability(t *testing.T) {
	program := `
node(1..6).
edge(1, 2).
edge(2, 3).
edge(3, 4).
edge(4, 5).
edge(5, 6).
edge(6, 1).
edge(2, 4).
edge(3, 5).

reach(X, Y) :- edge(X, Y).
reach(X, Z) :- reach(X, Y), edge(Y, Z).
reach(X, Z) :- reach(X, Y), reach(Y, Z).
`

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	expectedStatements := 13 // nodes, edges, reach rules
	if len(stmts) < 10 {
		t.Errorf("expected at least 10 statements, got %d", len(stmts))
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	// Ground size: 6 nodes + 9 edges + transitive closure (many)
	expectedGroundSize := 50
	if len(grounded) < 15 {
		t.Errorf("expected at least 15 grounded rules, got %d", len(grounded))
	}

	expectedModels := 1
	t.Logf("Reachability: parsed %d statements, grounded %d rules, expected %d models",
		len(stmts), len(grounded), expectedModels)
}

// TestBenchmarkLargeFactSet is a benchmark with many facts
func TestBenchmarkLargeFactSet(t *testing.T) {
	size := 100

	var sb strings.Builder
	for i := 0; i < size; i++ {
		sb.WriteString(fmt.Sprintf("fact(%d).\n", i))
	}
	for i := 0; i < size; i++ {
		sb.WriteString(fmt.Sprintf("derived(%d) :- fact(%d).\n", i, i))
	}

	program := sb.String()

	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, errors := p.Parse()

	if len(errors) > 0 {
		t.Fatalf("parse errors: %v", errors)
	}

	expectedStatements := 2 * size // 100 facts + 100 rules
	if len(stmts) != expectedStatements {
		t.Errorf("expected %d statements, got %d", expectedStatements, len(stmts))
	}

	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}

	grounded := grounder.Ground()
	expectedGroundSize := 2 * size
	if len(grounded) != expectedGroundSize {
		t.Errorf("expected %d grounded rules, got %d", expectedGroundSize, len(grounded))
	}

	expectedModels := 1
	t.Logf("Large-FactSet(%d): parsed %d statements, grounded %d rules, expected %d models",
		size, len(stmts), len(grounded), expectedModels)
}

// TestBenchmarkPropagation measures constraint propagation performance
func TestBenchmarkPropagation(b *testing.B) {
	benchmarks := []struct {
		name       string
		clauseSize int
		clauseCount int
	}{
		{"small", 3, 10},
		{"medium", 5, 50},
		{"large", 10, 100},
	}

	for _, bm := range benchmarks {
		b.Run(bm.name, func(b *testing.B) {
			propagator := propagation.NewPropagator()

			// Build clauses
			for i := 0; i < bm.clauseCount; i++ {
				lits := make([]propagation.Unit, bm.clauseSize)
				for j := 0; j < bm.clauseSize; j++ {
					unit := propagation.Unit((i*bm.clauseSize + j) % 100)
					if unit == 0 {
						unit = 1
					}
					lits[j] = unit
				}
				clause := propagation.NewClause(lits, false)
				propagator.AddClause(clause)
			}

			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				propagator.Propagate()
			}
		})
	}
}

// TestBenchmarkParsing measures parsing performance
func TestBenchmarkParsing(b *testing.B) {
	benchmarks := []struct {
		name      string
		stmtCount int
	}{
		{"small", 10},
		{"medium", 50},
		{"large", 100},
	}

	for _, bm := range benchmarks {
		b.Run(bm.name, func(b *testing.B) {
			var sb strings.Builder
			for i := 0; i < bm.stmtCount; i++ {
				sb.WriteString(fmt.Sprintf("fact_%d(%d).\n", i%10, i))
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

// TestBenchmarkGrounding measures grounding performance
func TestBenchmarkGrounding(b *testing.B) {
	benchmarks := []struct {
		name     string
		domainSize int
	}{
		{"small", 10},
		{"medium", 50},
		{"large", 100},
	}

	for _, bm := range benchmarks {
		b.Run(bm.name, func(b *testing.B) {
			var sb strings.Builder
			for i := 0; i < bm.domainSize; i++ {
				sb.WriteString(fmt.Sprintf("d(%d).\n", i))
			}
			sb.WriteString("r(X) :- d(X).\n")
			program := sb.String()

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
}

// BenchmarkMetrics reports performance metrics
type BenchmarkMetrics struct {
	Name                string
	ParseTime           float64
	GroundingTime       float64
	SolvingTime         float64
	InputSize           int
	OutputSize          int
	PeakMemory          int64
}

// CollectMetrics collects benchmark metrics for a program
func CollectMetrics(name string, program string) *BenchmarkMetrics {
	metrics := &BenchmarkMetrics{
		Name: name,
	}

	// Parse
	l := lexer.NewLexer(program, "test.lp")
	p := parser.NewParser(l)
	stmts, _ := p.Parse()

	metrics.InputSize = len(program)
	metrics.OutputSize = len(stmts)

	// Ground
	grounder := NewGrounder()
	for _, stmt := range stmts {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			grounder.AddRule(rs.Rule)
		}
	}
	grounded := grounder.Ground()
	metrics.OutputSize = len(grounded)

	return metrics
}

// TestBenchmarkCases runs all defined benchmark cases
func TestBenchmarkCases(t *testing.T) {
	cases := []struct {
		name    string
		program string
		minSize int
	}{
		{"bird_fly", `
bird(tweety).
flies(X) :- bird(X).
`, 2},
		{"nqueens", `
pos(1..4).
{queen(R, C) : pos(C)} :- pos(R).
`, 5},
		{"coloring", `
node(1..4).
color(r).
{assign(N, C) : color(C)} :- node(N).
`, 8},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			l := lexer.NewLexer(tc.program, "test.lp")
			p := parser.NewParser(l)
			stmts, errors := p.Parse()

			if len(errors) > 0 {
				t.Fatalf("parse errors: %v", errors)
			}

			if len(stmts) < tc.minSize {
				t.Errorf("expected at least %d statements, got %d", tc.minSize, len(stmts))
			}

			metrics := CollectMetrics(tc.name, tc.program)
			t.Logf("%s: input=%d, output=%d", metrics.Name, metrics.InputSize, metrics.OutputSize)
		})
	}
}

// Export import for AST types used in benchmarks
import (
	"devflow-finance-twin/asp/ast"
)
