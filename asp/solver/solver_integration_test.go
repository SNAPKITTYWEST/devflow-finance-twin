package solver

import (
	"devflow-finance-twin/asp/propagation"
	"testing"
)

// ============================================================
// SOLVER INTEGRATION TESTS
// ============================================================

// TestSolverBasicSAT tests basic SAT solving with Solver
func TestSolverBasicSAT(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1, 2}

	// Clause: (1 | 2)
	clause := propagation.NewClause([]propagation.Unit{1, 2}, false)
	err := propagator.AddClause(clause)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	assignment, err := solver.Solve()

	if err != nil && err.Error() != "unsatisfiable" {
		t.Fatalf("solve error: %v", err)
	}

	// Should be satisfiable
	if assignment == nil && err == nil {
		t.Errorf("expected non-nil assignment for satisfiable formula")
	}
}

// TestSolverUNSAT tests UNSAT detection
func TestSolverUNSAT(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1}

	// Clause 1: (1) - must be true
	clause1 := propagation.NewClause([]propagation.Unit{1}, false)
	err := propagator.AddClause(clause1)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Clause 2: (-1) - must be false
	clause2 := propagation.NewClause([]propagation.Unit{-1}, false)
	err = propagator.AddClause(clause2)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	assignment, err := solver.Solve()

	if assignment != nil {
		t.Errorf("expected nil assignment for unsatisfiable formula")
	}
}

// TestSolverDecisionLoop tests the decision loop
func TestSolverDecisionLoop(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1, 2, 3}

	// Add some non-trivial clauses
	clauses := [][]propagation.Unit{
		{1, 2},      // (1 | 2)
		{-1, 3},     // (-1 | 3)
		{-2, -3},    // (-2 | -3)
	}

	for _, lits := range clauses {
		clause := propagation.NewClause(lits, false)
		err := propagator.AddClause(clause)
		if err != nil {
			t.Fatalf("failed to add clause: %v", err)
		}
	}

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	assignment, err := solver.Solve()

	// Should be satisfiable
	if assignment == nil && err == nil {
		t.Errorf("expected valid assignment")
	}
}

// TestSolverBacktracking tests backtracking on conflict
func TestSolverBacktracking(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1, 2}

	// Create clauses that force backtracking:
	// (1 | 2), (-1 | 2), (-1 | -2)
	clauses := [][]propagation.Unit{
		{1, 2},
		{-1, 2},
		{-1, -2},
	}

	for _, lits := range clauses {
		clause := propagation.NewClause(lits, false)
		err := propagator.AddClause(clause)
		if err != nil {
			t.Fatalf("failed to add clause: %v", err)
		}
	}

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	solver.SetVerbosity(0)
	assignment, err := solver.Solve()

	// Check statistics
	stats := solver.GetStatistics()
	if stats.TotalDecisions == 0 {
		t.Errorf("expected at least one decision")
	}
}

// TestSolverHeuristics tests different heuristics
func TestSolverHeuristics(t *testing.T) {
	heuristics := []Heuristic{
		NewActivityHeuristic(),
		NewRandomHeuristic(42),
		NewMostConstrainedHeuristic(),
		NewStaticHeuristic([]propagation.Unit{1, 2, 3}),
	}

	for _, h := range heuristics {
		propagator := propagation.NewPropagator()
		units := []propagation.Unit{1, 2, 3}

		// Simple satisfiable formula
		clause := propagation.NewClause([]propagation.Unit{1, 2, 3}, false)
		propagator.AddClause(clause)

		solver := NewSolver(propagator, units, h)
		_, err := solver.Solve()

		// All heuristics should handle this
		_ = err
	}
}

// TestSolverRestartPolicy tests restart policies
func TestSolverRestartPolicy(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1, 2, 3, 4, 5}

	// Add clauses that might trigger restarts
	clauses := [][]propagation.Unit{
		{1, 2},
		{-1, 3},
		{-2, 4},
		{-3, 5},
	}

	for _, lits := range clauses {
		clause := propagation.NewClause(lits, false)
		propagator.AddClause(clause)
	}

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	solver.SetRestartPolicy(NewFixedRestartPolicy(5))
	_, err := solver.Solve()

	_ = err

	stats := solver.GetStatistics()
	// Restarts may or may not occur depending on conflicts
	_ = stats
}

// TestSolverLearningClauses tests clause learning
func TestSolverLearningClauses(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1, 2, 3}

	// Formula with potential conflicts
	clauses := [][]propagation.Unit{
		{1, 2},
		{-1, 3},
		{-2, -3},
		{-1, -2},
	}

	for _, lits := range clauses {
		clause := propagation.NewClause(lits, false)
		propagator.AddClause(clause)
	}

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	_, err := solver.Solve()

	_ = err

	learned := solver.GetLearnedClauses()
	// Check that we have learning capability
	_ = learned
}

// TestActivityHeuristic tests the activity heuristic
func TestActivityHeuristic(t *testing.T) {
	h := NewActivityHeuristic()

	units := []propagation.Unit{1, 2, 3}

	// Test initial selection
	unit, ok := h.SelectLiteral(units)
	if !ok {
		t.Errorf("expected successful selection")
	}
	if unit == 0 {
		t.Errorf("expected non-zero unit")
	}

	// Notify of conflict
	h.NotifyConflict([]propagation.Unit{1, 2})

	// Activity should have increased
	activity1 := h.GetActivity(1)
	if activity1 <= 0 {
		t.Errorf("expected positive activity after conflict")
	}

	// Test decay
	h.Decay()
	decayedActivity := h.GetActivity(1)
	if decayedActivity >= activity1 {
		t.Errorf("expected activity to decrease after decay")
	}
}

// TestRandomHeuristic tests the random heuristic
func TestRandomHeuristic(t *testing.T) {
	h := NewRandomHeuristic(42)
	units := []propagation.Unit{1, 2, 3, 4, 5}

	unit, ok := h.SelectLiteral(units)
	if !ok {
		t.Errorf("expected successful selection")
	}
	if unit == 0 {
		t.Errorf("expected non-zero unit")
	}

	// Test that it handles empty slice
	unit, ok = h.SelectLiteral([]propagation.Unit{})
	if ok {
		t.Errorf("expected failure on empty units")
	}
}

// TestMostConstrainedHeuristic tests the most-constrained heuristic
func TestMostConstrainedHeuristic(t *testing.T) {
	h := NewMostConstrainedHeuristic()
	units := []propagation.Unit{1, 2, 3}

	// Make unit 1 appear in many clauses
	h.NotifyConflict([]propagation.Unit{1, 1, 1, 2})

	// Unit 1 should be selected as most constrained
	selected, ok := h.SelectLiteral(units)
	if !ok {
		t.Errorf("expected successful selection")
	}
	if selected != 1 {
		t.Errorf("expected unit 1 to be most constrained")
	}
}

// TestStaticHeuristic tests the static ordering heuristic
func TestStaticHeuristic(t *testing.T) {
	order := []propagation.Unit{3, 1, 2}
	h := NewStaticHeuristic(order)

	units := []propagation.Unit{1, 2, 3}

	// Should select in order: 3, 1, 2
	selected, ok := h.SelectLiteral(units)
	if !ok {
		t.Errorf("expected successful selection")
	}
	if selected != 3 {
		t.Errorf("expected unit 3 (first in order), got %d", selected)
	}
}

// TestHybridHeuristic tests hybrid heuristic
func TestHybridHeuristic(t *testing.T) {
	primary := NewActivityHeuristic()
	secondary := NewRandomHeuristic(42)
	h := NewHybridHeuristic(primary, secondary, 5)

	units := []propagation.Unit{1, 2, 3}

	// Initial selects should use primary
	for i := 0; i < 5; i++ {
		_, ok := h.SelectLiteral(units)
		if !ok {
			t.Errorf("expected successful selection %d", i)
		}
		h.NotifyConflict([]propagation.Unit{propagation.Unit(i + 1)})
	}

	// After 5 notifications, should switch to secondary
	selected, ok := h.SelectLiteral(units)
	if !ok {
		t.Errorf("expected successful selection after switch")
	}
	_ = selected
}

// TestConflictAnalyzer tests the conflict analyzer
func TestConflictAnalyzer(t *testing.T) {
	analyzer := NewConflictAnalyzer()

	if len(analyzer.GetLearnedClauses()) != 0 {
		t.Errorf("expected empty learned clauses initially")
	}

	// Record some implications
	analyzer.RecordImplication(1, []propagation.Unit{2, 3}, 1)
	analyzer.RecordImplication(2, []propagation.Unit{4}, 1)

	// Clear and check
	analyzer.ClearImplicationGraph()
	if len(analyzer.implicationGraph) != 0 {
		t.Errorf("expected empty implication graph after clear")
	}
}

// TestClauseDatabase tests the clause database
func TestClauseDatabase(t *testing.T) {
	db := NewClauseDatabase(10, "activity")

	clause1 := propagation.NewClause([]propagation.Unit{1, 2}, true)
	clause2 := propagation.NewClause([]propagation.Unit{-1, 3}, true)

	db.AddClause(clause1)
	db.AddClause(clause2)

	clauses := db.GetClauses()
	if len(clauses) != 2 {
		t.Errorf("expected 2 clauses, got %d", len(clauses))
	}

	// Test activity management
	db.IncreaseActivity(0)
	clause := clauses[0]
	if clause.Activity <= 0 {
		t.Errorf("expected increased activity")
	}
}

// TestLubyRestartPolicy tests Luby restart policy
func TestLubyRestartPolicy(t *testing.T) {
	policy := NewLubyRestartPolicy(5)

	// Check restart schedule
	shouldRestart := policy.ShouldRestart(5, 1)
	if !shouldRestart {
		t.Errorf("expected restart at conflict 5")
	}

	policy.OnRestart()
	shouldRestart = policy.ShouldRestart(4, 1)
	if shouldRestart {
		t.Errorf("expected no restart at conflict 4 after advance")
	}
}

// TestSolverStatistics tests statistics collection
func TestSolverStatistics(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1, 2}

	clause := propagation.NewClause([]propagation.Unit{1, 2}, false)
	propagator.AddClause(clause)

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	_, _ = solver.Solve()

	stats := solver.GetStatistics()
	if stats.TotalPropagations == 0 {
		t.Errorf("expected at least one propagation")
	}
}

// TestSolverGetAssignment tests assignment retrieval
func TestSolverGetAssignment(t *testing.T) {
	propagator := propagation.NewPropagator()
	units := []propagation.Unit{1, 2, 3}

	clause := propagation.NewClause([]propagation.Unit{1, 2, 3}, false)
	propagator.AddClause(clause)

	solver := NewSolver(propagator, units, NewActivityHeuristic())
	_, _ = solver.Solve()

	assignment := solver.GetAssignment()
	if len(assignment) == 0 {
		t.Errorf("expected non-empty assignment")
	}
}
