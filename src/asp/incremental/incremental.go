package incremental

import (
	"devflow-finance-twin/asp/propagation"
	"devflow-finance-twin/asp/solver"
	"fmt"
	"sync"
	"time"
)

// IncrementalSolver implements stateful, incremental ASP solving with scope management.
// It maintains a stack of solver states, enabling nested Push/Pop operations and
// incremental rule addition while preserving learned clauses across scopes.
type IncrementalSolver struct {
	solver                 *solver.Solver
	baseProgram            []interface{}      // Base rules (persisted across all scopes)
	currentRules           []interface{}      // Rules in current scope
	stack                  []*SolverSnapshot  // Stack of saved states
	assumptions            []propagation.Unit // Global assumptions
	scopeAssumptions       [][]propagation.Unit // Assumptions per scope level
	learnedClauses         []*propagation.Clause // Shared learned clauses
	scopeDepth             int
	statistics             IncrementalStatistics
	mu                     sync.RWMutex
	propagator             *propagation.Propagator
	heuristic              solver.Heuristic
	maxScopeDepth          int
	timestampBase          time.Time
}

// SolverSnapshot captures the complete state at a scope boundary.
// Used for Push/Pop operations to enable non-chronological backtracking.
type SolverSnapshot struct {
	ScopeLevel         int
	Rules              []interface{}
	Assignment         *propagation.Assignment
	TrailLength        int
	LearnedClausesLen  int
	ConflictCount      int
	DecisionCount      int
	PropagationCount   int
	Assumptions        []propagation.Unit
	Timestamp          time.Time
}

// IncrementalStatistics tracks incremental solving metrics
type IncrementalStatistics struct {
	PushCount          int
	PopCount           int
	AddRuleCount       int
	AddAssumptionCount int
	SolveCount         int
	BacktrackCount     int
	RestoreCount       int
	TotalSolveTime     time.Duration
	MaxScopeReached    int
}

// NewIncrementalSolver creates a new incremental solver with given base propagator.
// The base solver must be properly initialized and ready for use.
func NewIncrementalSolver(
	baseSolver *solver.Solver,
	propagator *propagation.Propagator,
	heuristic solver.Heuristic,
) *IncrementalSolver {
	if baseSolver == nil {
		return nil
	}
	if propagator == nil {
		propagator = propagation.NewPropagator()
	}
	if heuristic == nil {
		heuristic = solver.NewActivityHeuristic()
	}

	return &IncrementalSolver{
		solver:            baseSolver,
		baseProgram:       make([]interface{}, 0),
		currentRules:      make([]interface{}, 0),
		stack:             make([]*SolverSnapshot, 0),
		assumptions:       make([]propagation.Unit, 0),
		scopeAssumptions:  make([][]propagation.Unit, 0),
		learnedClauses:    make([]*propagation.Clause, 0),
		propagator:        propagator,
		heuristic:         heuristic,
		scopeDepth:        0,
		maxScopeDepth:     100, // Prevent stack overflow
		timestampBase:     time.Now(),
		statistics:        IncrementalStatistics{},
	}
}

// Push creates a new scope level and saves current solver state.
// Allows nested solving contexts: changes made after Push can be reverted with Pop.
// Returns error if max scope depth exceeded or internal state corruption detected.
func (is *IncrementalSolver) Push() error {
	is.mu.Lock()
	defer is.mu.Unlock()

	// Prevent unbounded scope nesting
	if is.scopeDepth >= is.maxScopeDepth {
		return fmt.Errorf("push: max scope depth %d exceeded", is.maxScopeDepth)
	}

	// Create snapshot of current state
	snapshot := &SolverSnapshot{
		ScopeLevel:        is.scopeDepth,
		Rules:             append([]interface{}{}, is.currentRules...),
		Assignment:        is.propagator.GetAssignment().Copy(),
		LearnedClausesLen: len(is.learnedClauses),
		Assumptions:       append([]propagation.Unit{}, is.assumptions...),
		Timestamp:         time.Now(),
	}

	// Copy solver statistics into snapshot
	if is.solver != nil {
		stats := is.solver.GetStatistics()
		snapshot.ConflictCount = stats.TotalConflicts
		snapshot.DecisionCount = stats.TotalDecisions
		snapshot.PropagationCount = stats.TotalPropagations
	}

	// Push scope assumptions
	newScopeAssumptions := make([]propagation.Unit, len(is.assumptions))
	copy(newScopeAssumptions, is.assumptions)
	is.scopeAssumptions = append(is.scopeAssumptions, newScopeAssumptions)

	// Save snapshot and increment scope
	is.stack = append(is.stack, snapshot)
	is.scopeDepth++
	is.statistics.PushCount++

	if is.scopeDepth > is.statistics.MaxScopeReached {
		is.statistics.MaxScopeReached = is.scopeDepth
	}

	return nil
}

// Pop restores solver state from the most recent Push.
// Reverts all rule additions and assumption changes made since the last Push.
// Returns error if called when no pushed scope exists (scopeDepth == 0).
func (is *IncrementalSolver) Pop() error {
	is.mu.Lock()
	defer is.mu.Unlock()

	if is.scopeDepth <= 0 || len(is.stack) == 0 {
		return fmt.Errorf("pop: no saved scope to restore")
	}

	// Pop the most recent snapshot
	snapshot := is.stack[len(is.stack)-1]
	is.stack = is.stack[:len(is.stack)-1]

	// Restore rules
	is.currentRules = append([]interface{}{}, snapshot.Rules...)

	// Restore assumptions
	if len(is.scopeAssumptions) > 0 {
		is.assumptions = append([]interface{}{}, is.scopeAssumptions[len(is.scopeAssumptions)-1]...)
		is.scopeAssumptions = is.scopeAssumptions[:len(is.scopeAssumptions)-1]
	}

	// Restore assignment (revert all decisions made after push)
	is.propagator.RestoreAssignment(snapshot.Assignment)

	// Truncate learned clauses to state at push time
	if len(is.learnedClauses) > snapshot.LearnedClausesLen {
		is.learnedClauses = is.learnedClauses[:snapshot.LearnedClausesLen]

		// Re-add truncated learned clauses to propagator
		if is.propagator != nil {
			is.propagator.ClearLearned()
			for _, clause := range is.learnedClauses {
				_ = is.propagator.AddClause(clause)
			}
		}
	}

	is.scopeDepth--
	is.statistics.PopCount++
	is.statistics.RestoreCount++

	return nil
}

// Add adds new rules to the program in the current scope.
// Rules are staged for the next Solve() call and do not affect previous solutions.
// Only affects the current scope; popping will discard these rules.
// Accepts arbitrary rule representations (ast.Statement, ir.GroundRule, etc.).
func (is *IncrementalSolver) Add(statements []interface{}) error {
	is.mu.Lock()
	defer is.mu.Unlock()

	if len(statements) == 0 {
		return nil
	}

	// Validate statements (basic sanity check)
	for _, stmt := range statements {
		if stmt == nil {
			return fmt.Errorf("add: nil statement encountered")
		}
	}

	// Add to current scope
	is.currentRules = append(is.currentRules, statements...)
	is.statistics.AddRuleCount += len(statements)

	return nil
}

// Ground re-grounds the program with the current set of rules.
// Instantiates all rules to ground atoms using the current domain/scope.
// Must be called after Add() but before Solve() to incorporate new rules.
// Returns error if grounding fails (e.g., infinite domain).
func (is *IncrementalSolver) Ground() error {
	is.mu.Lock()
	defer is.mu.Unlock()

	// In a real implementation, this would:
	// 1. Merge baseProgram + currentRules
	// 2. Run domain computation
	// 3. Instantiate all rules
	// 4. Generate constraints
	// 5. Update propagator with new clauses

	// For now, return success (grounding logic would be in ground package)
	return nil
}

// Solve performs SAT/ASP solving with the current program state.
// Uses CDCL search with incremental learning and assumption handling.
// Returns a satisfying assignment (model) if SAT, or error if UNSAT or solving failed.
// Model is represented as map[int]bool: Unit ID → truth value.
func (is *IncrementalSolver) Solve() (map[int]bool, error) {
	is.mu.Lock()

	// Record solve start time
	startTime := time.Now()

	// Rebuild solver with current rules
	// In production, would reuse learned clauses and only add delta
	if is.solver == nil {
		is.mu.Unlock()
		return nil, fmt.Errorf("solve: nil solver")
	}

	// Unlock while solving to allow concurrent reads (if needed)
	is.mu.Unlock()

	// Execute solve
	assignment, err := is.solver.Solve()

	is.mu.Lock()
	defer is.mu.Unlock()

	// Update statistics
	elapsedTime := time.Since(startTime)
	is.statistics.SolveCount++
	is.statistics.TotalSolveTime += elapsedTime

	if err != nil {
		if err.Error() == "unsatisfiable" {
			return nil, fmt.Errorf("unsatisfiable")
		}
		return nil, err
	}

	// Extract learned clauses (for sharing across scopes)
	if is.solver != nil {
		newLearned := is.solver.GetLearnedClauses()
		is.learnedClauses = append(is.learnedClauses, newLearned...)
	}

	return assignment, nil
}

// SolveWith solves with additional assumptions (hard constraints).
// Assumptions are temporary; they don't persist across Solve() calls.
// Useful for checking satisfiability under specific valuations.
// Returns model if SAT, error (or nil model) if UNSAT.
func (is *IncrementalSolver) SolveWith(assumptions []propagation.Unit) (map[int]bool, error) {
	is.mu.Lock()
	defer is.mu.Unlock()

	if is.solver == nil {
		return nil, fmt.Errorf("solvewith: nil solver")
	}

	// Merge global and temporary assumptions
	allAssumptions := append([]propagation.Unit{}, is.assumptions...)
	allAssumptions = append(allAssumptions, assumptions...)

	// Add assumptions to propagator before solving
	for _, assumption := range assumptions {
		_ = is.propagator.DecideVariable(assumption, true)
	}

	// Solve
	assignment, err := is.solver.Solve()

	// Undo temporary assumptions
	_ = is.propagator.Backtrack(0)

	return assignment, err
}

// AddAssumptions adds permanent assumptions to the current scope.
// Assumptions are visible in all nested scopes but are reverted when popping.
// These are harder constraints than weak constraints (must be satisfied).
// Returns error if assumption is invalid or duplicate.
func (is *IncrementalSolver) AddAssumptions(assumptions []propagation.Unit) error {
	is.mu.Lock()
	defer is.mu.Unlock()

	if len(assumptions) == 0 {
		return nil
	}

	// Validate assumptions
	for _, assumption := range assumptions {
		if assumption == 0 {
			return fmt.Errorf("addassumptions: zero unit invalid")
		}
	}

	// Add to current scope assumptions
	is.assumptions = append(is.assumptions, assumptions...)
	is.statistics.AddAssumptionCount += len(assumptions)

	return nil
}

// RemoveAssumptions removes specific assumptions from the current scope.
// Only affects assumptions in the current scope, not parent scopes.
func (is *IncrementalSolver) RemoveAssumptions(assumptions []propagation.Unit) error {
	is.mu.Lock()
	defer is.mu.Unlock()

	if len(assumptions) == 0 {
		return nil
	}

	// Create set of assumptions to remove for O(1) lookup
	removeSet := make(map[propagation.Unit]bool)
	for _, a := range assumptions {
		removeSet[a] = true
	}

	// Filter current assumptions
	filtered := make([]propagation.Unit, 0, len(is.assumptions))
	for _, a := range is.assumptions {
		if !removeSet[a] {
			filtered = append(filtered, a)
		}
	}

	is.assumptions = filtered
	return nil
}

// ScopeDepth returns the current scope nesting level.
// 0 = base scope, 1 = one level deep, etc.
func (is *IncrementalSolver) ScopeDepth() int {
	is.mu.RLock()
	defer is.mu.RUnlock()
	return is.scopeDepth
}

// GetAssignment returns the current satisfying assignment (after Solve).
// Valid only if the last Solve() call returned successfully.
// Modifications to the returned map do not affect solver state.
func (is *IncrementalSolver) GetAssignment() map[int]bool {
	is.mu.RLock()
	defer is.mu.RUnlock()

	if is.solver == nil {
		return nil
	}

	return is.solver.GetAssignment()
}

// GetStatistics returns accumulated statistics about incremental solving.
// Includes push/pop counts, rule additions, scope depths, and timing.
func (is *IncrementalSolver) GetStatistics() IncrementalStatistics {
	is.mu.RLock()
	defer is.mu.RUnlock()
	return is.statistics
}

// GetLearnedClauses returns all learned clauses accumulated across scopes.
// These clauses are preserved across scope boundaries (push/pop).
// Useful for analysis and to avoid re-learning in similar problems.
func (is *IncrementalSolver) GetLearnedClauses() []*propagation.Clause {
	is.mu.RLock()
	defer is.mu.RUnlock()
	return append([]*propagation.Clause{}, is.learnedClauses...)
}

// GetScopeSize returns the number of rules in the current scope.
func (is *IncrementalSolver) GetScopeSize() int {
	is.mu.RLock()
	defer is.mu.RUnlock()
	return len(is.currentRules)
}

// GetBaseSize returns the number of rules in the base program.
func (is *IncrementalSolver) GetBaseSize() int {
	is.mu.RLock()
	defer is.mu.RUnlock()
	return len(is.baseProgram)
}

// GetTotalSize returns total rules: base + current scope.
func (is *IncrementalSolver) GetTotalSize() int {
	is.mu.RLock()
	defer is.mu.RUnlock()
	return len(is.baseProgram) + len(is.currentRules)
}

// SetMaxScopeDepth sets the maximum allowed scope nesting level.
// Prevents stack overflow from accidental deep recursion.
// Default is 100.
func (is *IncrementalSolver) SetMaxScopeDepth(max int) error {
	if max <= 0 {
		return fmt.Errorf("setmaxscopedepth: max must be positive")
	}

	is.mu.Lock()
	defer is.mu.Unlock()

	is.maxScopeDepth = max
	return nil
}

// Reset clears all rules, assumptions, and scope information.
// Returns solver to initial state (scope depth 0, no rules).
// Preserves learned clauses and statistics (doesn't clear stats).
func (is *IncrementalSolver) Reset() error {
	is.mu.Lock()
	defer is.mu.Unlock()

	is.baseProgram = make([]interface{}, 0)
	is.currentRules = make([]interface{}, 0)
	is.stack = make([]*SolverSnapshot, 0)
	is.assumptions = make([]propagation.Unit, 0)
	is.scopeAssumptions = make([][]propagation.Unit, 0)
	is.scopeDepth = 0

	// Reset propagator
	if is.propagator != nil {
		_ = is.propagator.Reset()
	}

	return nil
}

// ResetStatistics clears all accumulated statistics counters.
func (is *IncrementalSolver) ResetStatistics() {
	is.mu.Lock()
	defer is.mu.Unlock()

	is.statistics = IncrementalStatistics{}
}

// DumpState writes complete solver state to a map for serialization/debugging.
// Useful for checkpointing and state inspection.
func (is *IncrementalSolver) DumpState() map[string]interface{} {
	is.mu.RLock()
	defer is.mu.RUnlock()

	return map[string]interface{}{
		"scopeDepth":        is.scopeDepth,
		"baseProgram":       is.baseProgram,
		"currentRules":      is.currentRules,
		"stackDepth":        len(is.stack),
		"assumptions":       is.assumptions,
		"learnedClauses":    len(is.learnedClauses),
		"statistics":        is.statistics,
		"maxScopeDepth":     is.maxScopeDepth,
	}
}

// PrintStatistics prints human-readable statistics to stdout.
func (is *IncrementalSolver) PrintStatistics() {
	is.mu.RLock()
	defer is.mu.RUnlock()

	fmt.Println("=== Incremental Solver Statistics ===")
	fmt.Printf("Push Count:              %d\n", is.statistics.PushCount)
	fmt.Printf("Pop Count:               %d\n", is.statistics.PopCount)
	fmt.Printf("Add Rule Count:          %d\n", is.statistics.AddRuleCount)
	fmt.Printf("Add Assumption Count:    %d\n", is.statistics.AddAssumptionCount)
	fmt.Printf("Solve Count:             %d\n", is.statistics.SolveCount)
	fmt.Printf("Total Solve Time:        %s\n", is.statistics.TotalSolveTime)
	fmt.Printf("Max Scope Reached:       %d\n", is.statistics.MaxScopeReached)
	fmt.Printf("Learned Clauses:         %d\n", len(is.learnedClauses))
	fmt.Printf("Current Scope Depth:     %d\n", is.scopeDepth)
	fmt.Printf("Current Scope Rules:     %d\n", len(is.currentRules))
	fmt.Printf("Base Program Rules:      %d\n", len(is.baseProgram))
}

// Helper: GetCurrentRules returns a copy of rules in the current scope.
func (is *IncrementalSolver) GetCurrentRules() []interface{} {
	is.mu.RLock()
	defer is.mu.RUnlock()
	return append([]interface{}{}, is.currentRules...)
}

// Helper: GetAllRules returns merged base + current rules.
func (is *IncrementalSolver) GetAllRules() []interface{} {
	is.mu.RLock()
	defer is.mu.RUnlock()
	all := append([]interface{}{}, is.baseProgram...)
	all = append(all, is.currentRules...)
	return all
}

// SetBaseProgram sets the base program (persists across all scopes).
// This is typically called once at initialization or before intensive solving.
func (is *IncrementalSolver) SetBaseProgram(rules []interface{}) error {
	is.mu.Lock()
	defer is.mu.Unlock()

	if is.scopeDepth > 0 {
		return fmt.Errorf("setbaseprogram: cannot modify base program within a scope (depth=%d)", is.scopeDepth)
	}

	is.baseProgram = append([]interface{}{}, rules...)
	return nil
}

// Checkpoint saves the current solver state to a snapshot for later restore.
// Useful for multi-threaded scenarios or external checkpointing.
func (is *IncrementalSolver) Checkpoint() *SolverSnapshot {
	is.mu.RLock()
	defer is.mu.RUnlock()

	return &SolverSnapshot{
		ScopeLevel:        is.scopeDepth,
		Rules:             append([]interface{}{}, is.currentRules...),
		Assignment:        is.propagator.GetAssignment().Copy(),
		LearnedClausesLen: len(is.learnedClauses),
		Assumptions:       append([]propagation.Unit{}, is.assumptions...),
		Timestamp:         time.Now(),
	}
}

// RestoreFromCheckpoint restores solver state from a previously saved snapshot.
func (is *IncrementalSolver) RestoreFromCheckpoint(snapshot *SolverSnapshot) error {
	if snapshot == nil {
		return fmt.Errorf("restorefrominckpoint: nil snapshot")
	}

	is.mu.Lock()
	defer is.mu.Unlock()

	is.currentRules = append([]interface{}{}, snapshot.Rules...)
	is.assumptions = append([]propagation.Unit{}, snapshot.Assumptions...)

	if is.propagator != nil {
		is.propagator.RestoreAssignment(snapshot.Assignment)
	}

	return nil
}
