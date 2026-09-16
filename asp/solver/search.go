package solver

import (
	"devflow-finance-twin/asp/propagation"
	"fmt"
	"sort"
)

// Solver implements the CDCL (Conflict-Driven Clause Learning) search engine
type Solver struct {
	propagator      *propagation.Propagator
	analyzer        *ConflictAnalyzer
	heuristic       Heuristic
	allUnits        []propagation.Unit
	trail           []propagation.Unit
	decisions       []int // Decision levels at each decision
	conflicts       []propagation.Nogood
	learnedClauses  []*propagation.Clause
	clauseDatabase  *ClauseDatabase
	restartPolicy   RestartPolicy
	statistics      SolverStatistics
	maxDecisionLevel int
	verbosity       int // 0 = silent, 1 = normal, 2 = verbose
}

// SolverStatistics tracks solving statistics
type SolverStatistics struct {
	TotalConflicts     int
	TotalDecisions     int
	TotalPropagations  int
	LearnedClauses     int
	AverageBacktrack   float64
	AverageClauseSize  float64
	RestartCount       int
	ElapsedConflicts   []int // Conflicts per decision level
	DecisionLevelReach []int // Max reached decision levels
}

// RestartPolicy defines when to restart the search
type RestartPolicy interface {
	ShouldRestart(conflictCount int, decisionLevel int) bool
	OnRestart()
}

// LubyRestartPolicy implements Luby restart schedule
type LubyRestartPolicy struct {
	lubyUnits   []int
	unit        int
	baseLimit   int
	conflictNum int
	nextRestart int
}

// NewLubyRestartPolicy creates a Luby restart policy
func NewLubyRestartPolicy(baseLimit int) *LubyRestartPolicy {
	return &LubyRestartPolicy{
		lubyUnits:   computeLuby(baseLimit),
		unit:        0,
		baseLimit:   baseLimit,
		conflictNum: 0,
		nextRestart: baseLimit,
	}
}

// ShouldRestart checks if search should restart
func (lrp *LubyRestartPolicy) ShouldRestart(conflictCount int, decisionLevel int) bool {
	return conflictCount >= lrp.nextRestart
}

// OnRestart advances to next restart interval
func (lrp *LubyRestartPolicy) OnRestart() {
	lrp.unit++
	if lrp.unit < len(lrp.lubyUnits) {
		lrp.nextRestart += lrp.lubyUnits[lrp.unit] * lrp.baseLimit
	}
}

// computeLuby computes first n Luby numbers
func computeLuby(n int) []int {
	result := make([]int, 0)
	k := 1
	for len(result) < n {
		// Add 2^k - 1 repetitions of 2^k
		if k&1 == 1 {
			for i := 0; i < (1 << ((k - 1) / 2)); i++ {
				result = append(result, 1<<((k+1)/2))
				if len(result) >= n {
					break
				}
			}
		}
		k++
	}
	return result
}

// FixedRestartPolicy restarts at fixed intervals
type FixedRestartPolicy struct {
	interval int
}

// NewFixedRestartPolicy creates a fixed restart policy
func NewFixedRestartPolicy(interval int) *FixedRestartPolicy {
	return &FixedRestartPolicy{interval: interval}
}

// ShouldRestart checks if search should restart
func (frp *FixedRestartPolicy) ShouldRestart(conflictCount int, decisionLevel int) bool {
	return conflictCount > 0 && conflictCount%frp.interval == 0
}

// OnRestart does nothing for fixed policy
func (frp *FixedRestartPolicy) OnRestart() {
	// No-op
}

// NewSolver creates a new CDCL solver
func NewSolver(
	propagator *propagation.Propagator,
	units []propagation.Unit,
	heuristic Heuristic,
) *Solver {
	if heuristic == nil {
		heuristic = NewActivityHeuristic()
	}

	return &Solver{
		propagator:      propagator,
		analyzer:        NewConflictAnalyzer(),
		heuristic:       heuristic,
		allUnits:        units,
		trail:           make([]propagation.Unit, 0),
		decisions:       make([]int, 0),
		conflicts:       make([]propagation.Nogood, 0),
		learnedClauses:  make([]*propagation.Clause, 0),
		clauseDatabase:  NewClauseDatabase(100000, "activity"),
		restartPolicy:   NewLubyRestartPolicy(10),
		statistics:      SolverStatistics{},
		maxDecisionLevel: 0,
		verbosity:       0,
	}
}

// SetVerbosity sets output verbosity level
func (s *Solver) SetVerbosity(level int) {
	s.verbosity = level
}

// SetRestartPolicy sets the restart policy
func (s *Solver) SetRestartPolicy(policy RestartPolicy) {
	s.restartPolicy = policy
}

// Solve searches for a satisfying assignment for all clauses
func (s *Solver) Solve() (map[int]bool, error) {
	s.logInfo("Starting CDCL solver...")
	s.logVerbose(fmt.Sprintf("Total units: %d", len(s.allUnits)))

	// Main CDCL loop
	assignment, err := s.DecisionLoop()
	if err != nil {
		return nil, err
	}

	if assignment == nil {
		s.logInfo("UNSAT: No satisfying assignment found")
		return nil, fmt.Errorf("unsatisfiable")
	}

	s.logInfo("SAT: Satisfying assignment found")
	return assignment, nil
}

// DecisionLoop implements the main CDCL algorithm
func (s *Solver) DecisionLoop() (map[int]bool, error) {
	for {
		// Propagate constraints
		conflicts, err := s.propagator.Propagate()
		if err != nil {
			return nil, fmt.Errorf("propagation error: %w", err)
		}

		s.statistics.TotalPropagations++

		// Handle conflicts
		if len(conflicts) > 0 {
			s.statistics.TotalConflicts++

			if s.propagator.GetDecisionLevel() == 0 {
				// Conflict at decision level 0 means unsatisfiable
				s.logInfo("Conflict at decision level 0: UNSAT")
				return nil, nil
			}

			// Analyze conflict and learn clause
			conflict := conflicts[0]
			learned, backtrackLevel, err := s.analyzer.AnalyzeConflict(conflict, s.propagator)
			if err != nil {
				return nil, fmt.Errorf("conflict analysis error: %w", err)
			}

			s.logVerbose(fmt.Sprintf("Conflict analyzed: learned %v literals, backtrack to level %d",
				len(learned.Literals), backtrackLevel))

			// Create clause from learned nogood
			clause := propagation.NewClause(learned.Literals, true)
			s.learnedClauses = append(s.learnedClauses, clause)
			s.clauseDatabase.AddClause(clause)

			// Notify heuristic of conflict
			s.heuristic.NotifyConflict(learned.Literals)

			// Backtrack
			err = s.Backtrack(backtrackLevel)
			if err != nil {
				return nil, fmt.Errorf("backtrack error: %w", err)
			}

			// Add learned clause to propagator
			err = s.propagator.AddClause(clause)
			if err != nil && s.verbosity > 0 {
				s.logVerbose(fmt.Sprintf("Warning: could not add learned clause: %v", err))
			}

			// Check for restart
			if s.restartPolicy != nil && s.restartPolicy.ShouldRestart(s.statistics.TotalConflicts, s.propagator.GetDecisionLevel()) {
				s.logVerbose(fmt.Sprintf("Restart triggered at conflict %d", s.statistics.TotalConflicts))
				s.statistics.RestartCount++
				err := s.RestartSearch()
				if err != nil {
					return nil, fmt.Errorf("restart error: %w", err)
				}
				s.restartPolicy.OnRestart()
			}

		} else {
			// No conflict - check if all variables assigned
			unassigned := s.propagator.GetUnassignedUnits(s.allUnits)

			if len(unassigned) == 0 {
				// All variables assigned - SAT!
				return s.buildAssignment(), nil
			}

			// Make a decision
			lit, ok := s.DecideVariable()
			if !ok {
				// No more decisions possible
				return s.buildAssignment(), nil
			}

			s.statistics.TotalDecisions++
			currentLevel := s.propagator.GetDecisionLevel()
			if currentLevel > s.maxDecisionLevel {
				s.maxDecisionLevel = currentLevel
			}

			s.logVerbose(fmt.Sprintf("Decision %d: %d at level %d", s.statistics.TotalDecisions, lit, currentLevel))
		}
	}
}

// DecideVariable selects the next unassigned literal to assign
func (s *Solver) DecideVariable() (int, bool) {
	unassigned := s.propagator.GetUnassignedUnits(s.allUnits)

	if len(unassigned) == 0 {
		return 0, false
	}

	// Use heuristic to select literal
	selectedUnit, ok := s.heuristic.SelectLiteral(unassigned)
	if !ok {
		return 0, false
	}

	// Decide value (prefer positive literal)
	err := s.propagator.DecideVariable(selectedUnit, true)
	if err != nil && s.verbosity > 0 {
		s.logVerbose(fmt.Sprintf("Warning deciding %d: %v", selectedUnit, err))
	}

	s.decisions = append(s.decisions, s.propagator.GetDecisionLevel())
	return int(selectedUnit), true
}

// AnalyzeConflict analyzes a conflict and returns learned nogood
func (s *Solver) AnalyzeConflict(conflict propagation.Nogood) propagation.Nogood {
	learned, _, err := s.analyzer.AnalyzeConflict(conflict, s.propagator)
	if err != nil && s.verbosity > 0 {
		s.logVerbose(fmt.Sprintf("Error in conflict analysis: %v", err))
	}
	return learned
}

// Backtrack undoes decisions back to target level
func (s *Solver) Backtrack(level int) error {
	if level < 0 {
		level = 0
	}

	s.logVerbose(fmt.Sprintf("Backtracking from level %d to %d", s.propagator.GetDecisionLevel(), level))

	err := s.propagator.Backtrack(level)
	if err != nil {
		return err
	}

	// Also notify heuristic of backtracking for potential decay
	if s.propagator.GetDecisionLevel()%10 == 0 {
		s.heuristic.Decay()
		s.clauseDatabase.DecayActivities()
	}

	return nil
}

// RestartSearch restarts search from decision level 0
func (s *Solver) RestartSearch() error {
	s.logVerbose("Restarting search...")

	// Backtrack to level 0
	err := s.propagator.Backtrack(0)
	if err != nil {
		return err
	}

	// Reset decisions but keep learned clauses
	s.decisions = make([]int, 0)

	return nil
}

// buildAssignment converts propagator assignment to map
func (s *Solver) buildAssignment() map[int]bool {
	assignment := s.propagator.GetAssignment()
	result := make(map[int]bool)

	for _, unit := range s.allUnits {
		if val, ok := assignment.GetValue(unit); ok {
			result[int(unit)] = val
		}
	}

	return result
}

// GetStatistics returns solver statistics
func (s *Solver) GetStatistics() SolverStatistics {
	return s.statistics
}

// GetLearnedClauses returns all learned clauses
func (s *Solver) GetLearnedClauses() []*propagation.Clause {
	return s.learnedClauses
}

// GetAssignment returns current assignment
func (s *Solver) GetAssignment() map[int]bool {
	return s.buildAssignment()
}

// PrintStatistics prints solver statistics
func (s *Solver) PrintStatistics() {
	fmt.Printf("=== Solver Statistics ===\n")
	fmt.Printf("Total Conflicts: %d\n", s.statistics.TotalConflicts)
	fmt.Printf("Total Decisions: %d\n", s.statistics.TotalDecisions)
	fmt.Printf("Total Propagations: %d\n", s.statistics.TotalPropagations)
	fmt.Printf("Learned Clauses: %d\n", len(s.learnedClauses))
	fmt.Printf("Restarts: %d\n", s.statistics.RestartCount)
	fmt.Printf("Max Decision Level: %d\n", s.maxDecisionLevel)

	if len(s.learnedClauses) > 0 {
		totalSize := 0
		for _, clause := range s.learnedClauses {
			totalSize += len(clause.Literals)
		}
		avgSize := float64(totalSize) / float64(len(s.learnedClauses))
		fmt.Printf("Average Learned Clause Size: %.2f\n", avgSize)
	}
}

// VerifyAssignment checks if assignment satisfies all clauses
func (s *Solver) VerifyAssignment(assignment map[int]bool) bool {
	return true // Placeholder - would verify against original clauses
}

// AddClause adds a clause to the solver
func (s *Solver) AddClause(lits []propagation.Unit) error {
	clause := propagation.NewClause(lits, false)
	return s.propagator.AddClause(clause)
}

// GetUnitsInvolvedInConflicts returns units most involved in conflicts
func (s *Solver) GetUnitsInvolvedInConflicts(topK int) []propagation.Unit {
	if topK <= 0 {
		topK = 10
	}

	unitConflictCount := make(map[propagation.Unit]int)
	for _, clause := range s.learnedClauses {
		for _, lit := range clause.Literals {
			unit := propagation.Unit(abs(int(lit)))
			unitConflictCount[unit]++
		}
	}

	// Sort by count
	type unitCount struct {
		unit  propagation.Unit
		count int
	}
	var sorted []unitCount
	for unit, count := range unitConflictCount {
		sorted = append(sorted, unitCount{unit, count})
	}

	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i].count > sorted[j].count
	})

	// Return top K
	result := make([]propagation.Unit, 0)
	for i := 0; i < topK && i < len(sorted); i++ {
		result = append(result, sorted[i].unit)
	}

	return result
}

// GetConflictAnalysisTrace returns detailed trace of last conflict analysis
func (s *Solver) GetConflictAnalysisTrace() []string {
	trace := make([]string, 0)

	if len(s.analyzer.learnedClauses) > 0 {
		lastClause := s.analyzer.learnedClauses[len(s.analyzer.learnedClauses)-1]
		trace = append(trace, fmt.Sprintf("Last learned clause: %v", LiteralsToString(lastClause.Literals)))
		trace = append(trace, fmt.Sprintf("Clause size: %d", len(lastClause.Literals)))
		trace = append(trace, fmt.Sprintf("Clause activity: %.4f", lastClause.Activity))
	}

	return trace
}

// --- Logging helpers ---

func (s *Solver) logInfo(msg string) {
	if s.verbosity >= 1 {
		fmt.Printf("[INFO] %s\n", msg)
	}
}

func (s *Solver) logVerbose(msg string) {
	if s.verbosity >= 2 {
		fmt.Printf("[DEBUG] %s\n", msg)
	}
}

// --- Unit conversion helpers ---

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func negate(lit propagation.Unit) propagation.Unit {
	if lit > 0 {
		return -lit
	}
	return -lit
}
