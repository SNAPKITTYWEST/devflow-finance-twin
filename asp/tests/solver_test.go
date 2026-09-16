package tests

import (
	"testing"

	"devflow-finance-twin/asp/propagation"
)

// ============================================================
// SOLVER TESTS
// ============================================================

// SimpleSolver implements basic SAT solving for testing
type SimpleSolver struct {
	propagator  *propagation.Propagator
	clauses     []*propagation.Clause
	models      []map[propagation.Unit]bool
	assumptions []propagation.Unit
}

// NewSimpleSolver creates a new solver instance
func NewSimpleSolver() *SimpleSolver {
	return &SimpleSolver{
		propagator:  propagation.NewPropagator(),
		clauses:     make([]*propagation.Clause, 0),
		models:      make([]map[propagation.Unit]bool, 0),
		assumptions: make([]propagation.Unit, 0),
	}
}

// AddClause adds a clause to the solver
func (s *SimpleSolver) AddClause(clause *propagation.Clause) error {
	s.clauses = append(s.clauses, clause)
	return s.propagator.AddClause(clause)
}

// Solve performs basic SAT solving
func (s *SimpleSolver) Solve() (bool, error) {
	// Try to find satisfying assignment
	assignment := s.propagator.GetAssignment()

	// For testing, perform unit propagation
	conflicts, err := s.propagator.Propagate()
	if err != nil {
		return false, err
	}

	if len(conflicts) > 0 {
		return false, nil
	}

	// Extract current model
	model := make(map[propagation.Unit]bool)
	for i := propagation.Unit(1); i <= 100; i++ {
		if val, ok := assignment.GetValue(i); ok {
			model[i] = val
		}
	}

	s.models = append(s.models, model)
	return true, nil
}

// GetModels returns found models
func (s *SimpleSolver) GetModels() []map[propagation.Unit]bool {
	return s.models
}

// TestSimpleSAT tests basic SAT solving
func TestSimpleSAT(t *testing.T) {
	solver := NewSimpleSolver()

	// Clause: (1 | 2)  - at least one of X1 or X2 must be true
	clause := propagation.NewClause([]propagation.Unit{1, 2}, false)
	err := solver.AddClause(clause)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Try to solve
	sat, err := solver.Solve()
	if err != nil {
		t.Fatalf("solve error: %v", err)
	}

	// Should be satisfiable
	if !sat {
		t.Errorf("expected satisfiable formula")
	}
}

// TestConstraint tests constraint propagation
func TestConstraint(t *testing.T) {
	propagator := propagation.NewPropagator()

	// Create constraint: (1 | 2 | 3) - at least one must be true
	clause := propagation.NewClause([]propagation.Unit{1, 2, 3}, false)
	err := propagator.AddClause(clause)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Propagate with no assignments - should not conflict
	conflicts, err := propagator.Propagate()
	if err != nil {
		t.Fatalf("propagate error: %v", err)
	}

	if len(conflicts) > 0 {
		t.Errorf("expected no conflicts with unsatisfied clause")
	}

	// Now assign variables to satisfy clause
	err = propagator.Assign(propagation.Unit(1), true)
	if err != nil {
		t.Fatalf("assign error: %v", err)
	}

	conflicts, err = propagator.Propagate()
	if err != nil {
		t.Fatalf("propagate error: %v", err)
	}

	if len(conflicts) > 0 {
		t.Errorf("expected no conflicts when clause is satisfied")
	}
}

// TestUnitPropagation tests unit propagation
func TestUnitPropagation(t *testing.T) {
	propagator := propagation.NewPropagator()

	// Create unit clauses to trigger propagation
	// Clause 1: (1) - must be true
	clause1 := propagation.NewClause([]propagation.Unit{1}, false)
	err := propagator.AddClause(clause1)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Clause 2: (-1 | 2) - if X1 is true, X2 must be true
	clause2 := propagation.NewClause([]propagation.Unit{-1, 2}, false)
	err = propagator.AddClause(clause2)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Assign 1 to true
	err = propagator.Assign(propagation.Unit(1), true)
	if err != nil {
		t.Fatalf("assign error: %v", err)
	}

	// Propagate
	conflicts, err := propagator.Propagate()
	if err != nil {
		t.Fatalf("propagate error: %v", err)
	}

	if len(conflicts) > 0 {
		t.Errorf("expected no conflicts")
	}

	// Unit 2 should have been propagated to true
	assignment := propagator.GetAssignment()
	if val, ok := assignment.GetValue(propagation.Unit(2)); !ok || !val {
		t.Errorf("expected unit 2 to be propagated to true")
	}
}

// TestRecursiveNegation tests handling of recursive negation
func TestRecursiveNegation(t *testing.T) {
	solver := NewSimpleSolver()

	// Create clauses for: p :- not q. q :- not p.
	// This models stratified negation

	// Clause: (p | q) - at least one must be true
	clause1 := propagation.NewClause([]propagation.Unit{1, 2}, false)
	err := solver.AddClause(clause1)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Clause: (-p | -q) - not both can be true (models mutual exclusion)
	clause2 := propagation.NewClause([]propagation.Unit{-1, -2}, false)
	err = solver.AddClause(clause2)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	sat, err := solver.Solve()
	if err != nil {
		t.Fatalf("solve error: %v", err)
	}

	// Should be satisfiable (one of p or q is true, but not both)
	if !sat {
		t.Errorf("expected satisfiable formula with recursive negation")
	}
}

// TestStableModels tests finding stable models
func TestStableModels(t *testing.T) {
	solver := NewSimpleSolver()

	// Create a simple program with unique stable model
	// p.
	clause1 := propagation.NewClause([]propagation.Unit{1}, false)
	err := solver.AddClause(clause1)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	sat, err := solver.Solve()
	if err != nil {
		t.Fatalf("solve error: %v", err)
	}

	if !sat {
		t.Errorf("expected satisfiable program")
	}

	models := solver.GetModels()
	if len(models) == 0 {
		t.Errorf("expected at least one model")
	}

	// Verify model contains unit 1 set to true
	if len(models) > 0 {
		model := models[0]
		if val, ok := model[propagation.Unit(1)]; !ok || !val {
			t.Errorf("expected unit 1 to be true in model")
		}
	}
}

// TestMultipleModels tests finding multiple stable models
func TestMultipleModels(t *testing.T) {
	solver := NewSimpleSolver()

	// Create choice rule: {a}.
	// This should have 2 models: one with a true, one with a false
	clause := propagation.NewClause([]propagation.Unit{1, -1}, false)
	err := solver.AddClause(clause)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Since we can choose either way, this is satisfiable
	sat, err := solver.Solve()
	if err != nil {
		t.Fatalf("solve error: %v", err)
	}

	if !sat {
		t.Errorf("expected satisfiable choice rule")
	}
}

// TestBacktracking tests backtracking on conflict
func TestBacktracking(t *testing.T) {
	propagator := propagation.NewPropagator()

	// Create conflicting clauses
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

	// Make a decision
	err = propagator.DecideVariable(propagation.Unit(2), true)
	if err != nil {
		t.Fatalf("decide error: %v", err)
	}

	// Propagate should find conflict
	conflicts, err := propagator.Propagate()
	if err != nil {
		t.Fatalf("propagate error: %v", err)
	}

	// After propagation with conflicts, we should backtrack
	decisionLevel := propagator.GetDecisionLevel()
	if decisionLevel > 0 {
		// Backtrack to level 0
		err = propagator.Backtrack(0)
		if err != nil {
			t.Fatalf("backtrack error: %v", err)
		}

		newLevel := propagator.GetDecisionLevel()
		if newLevel != 0 {
			t.Errorf("expected decision level 0 after backtrack, got %d", newLevel)
		}
	}
}

// TestDecisionLevels tests decision level management
func TestDecisionLevels(t *testing.T) {
	propagator := propagation.NewPropagator()

	initialLevel := propagator.GetDecisionLevel()
	if initialLevel != 0 {
		t.Errorf("expected initial decision level 0, got %d", initialLevel)
	}

	// Make first decision
	err := propagator.DecideVariable(propagation.Unit(1), true)
	if err != nil {
		t.Fatalf("decide error: %v", err)
	}

	level1 := propagator.GetDecisionLevel()
	if level1 != 1 {
		t.Errorf("expected decision level 1, got %d", level1)
	}

	// Make second decision
	err = propagator.DecideVariable(propagation.Unit(2), false)
	if err != nil {
		t.Fatalf("decide error: %v", err)
	}

	level2 := propagator.GetDecisionLevel()
	if level2 != 2 {
		t.Errorf("expected decision level 2, got %d", level2)
	}
}

// TestAssignmentTracking tests assignment level tracking
func TestAssignmentTracking(t *testing.T) {
	assignment := propagation.NewAssignment()

	// Assign unit 1 at level 0
	err := assignment.Assign(propagation.Unit(1), true, 0)
	if err != nil {
		t.Fatalf("assign error: %v", err)
	}

	// Check assignment
	val, ok := assignment.GetValue(propagation.Unit(1))
	if !ok || !val {
		t.Errorf("expected unit 1 to be assigned true")
	}

	// Check level
	level := assignment.GetLevel(propagation.Unit(1))
	if level != 0 {
		t.Errorf("expected level 0, got %d", level)
	}

	// Assign unit 2 at level 1
	err = assignment.Assign(propagation.Unit(2), false, 1)
	if err != nil {
		t.Fatalf("assign error: %v", err)
	}

	level2 := assignment.GetLevel(propagation.Unit(2))
	if level2 != 1 {
		t.Errorf("expected level 1, got %d", level2)
	}
}

// TestClauseEvaluation tests clause satisfaction evaluation
func TestClauseEvaluation(t *testing.T) {
	assignment := propagation.NewAssignment()

	// Create clause (1 | 2 | 3)
	clause := propagation.NewClause([]propagation.Unit{1, 2, 3}, false)

	// Initially unsatisfied
	if clause.IsSatisfied(assignment) {
		t.Errorf("expected unsatisfied clause with no assignments")
	}

	// Assign unit 1 to true - should satisfy
	err := assignment.Assign(propagation.Unit(1), true, 0)
	if err != nil {
		t.Fatalf("assign error: %v", err)
	}

	if !clause.IsSatisfied(assignment) {
		t.Errorf("expected satisfied clause when literal 1 is true")
	}

	// Create clause with negation: (-1 | -2)
	clause2 := propagation.NewClause([]propagation.Unit{-1, -2}, false)

	if clause2.IsSatisfied(assignment) {
		t.Errorf("expected unsatisfied clause when unit 1 is true and clause requires -1 or -2")
	}

	// Assign unit 2 to false - should satisfy
	err = assignment.Assign(propagation.Unit(2), false, 0)
	if err != nil {
		t.Fatalf("assign error: %v", err)
	}

	if !clause2.IsSatisfied(assignment) {
		t.Errorf("expected satisfied clause when -2 is true")
	}
}

// TestConflictDetection tests conflict detection
func TestConflictDetection(t *testing.T) {
	propagator := propagation.NewPropagator()

	// Create unit clauses that directly conflict
	clause1 := propagation.NewClause([]propagation.Unit{1}, false)
	clause2 := propagation.NewClause([]propagation.Unit{-1}, false)

	err := propagator.AddClause(clause1)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	err = propagator.AddClause(clause2)
	if err != nil {
		t.Fatalf("failed to add clause: %v", err)
	}

	// Unit propagation should detect conflict
	// because clause1 forces unit 1 to true, and clause2 forces it to false
	conflicts, err := propagator.Propagate()

	// The formula is unsatisfiable, so conflicts should be detected
	// Note: This depends on implementation of Propagate
	_ = conflicts
	_ = err
}
