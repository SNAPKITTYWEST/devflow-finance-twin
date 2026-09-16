package solver

import (
	"devflow-finance-twin/asp/propagation"
	"fmt"
	"sort"
)

// ConflictAnalyzer performs conflict analysis and generates learned clauses
type ConflictAnalyzer struct {
	implicationGraph map[propagation.Unit]*ImplicationNode
	learnedClauses   []*propagation.Clause
	analyzer         *ConflictGraph
}

// ImplicationNode represents a variable and its reasons in the implication graph
type ImplicationNode struct {
	Unit    propagation.Unit
	Reasons []propagation.Unit
	Level   int
	Mark    bool
}

// ConflictGraph builds and analyzes implication graphs
type ConflictGraph struct {
	nodes map[propagation.Unit]*ImplicationNode
}

// NewConflictAnalyzer creates a new conflict analyzer
func NewConflictAnalyzer() *ConflictAnalyzer {
	return &ConflictAnalyzer{
		implicationGraph: make(map[propagation.Unit]*ImplicationNode),
		learnedClauses:   make([]*propagation.Clause, 0),
		analyzer:         &ConflictGraph{nodes: make(map[propagation.Unit]*ImplicationNode)},
	}
}

// AnalyzeConflict performs 1UIP conflict analysis
// Returns learned nogood and backtrack level
func (ca *ConflictAnalyzer) AnalyzeConflict(
	conflict propagation.Nogood,
	propagator *propagation.Propagator,
) (propagation.Nogood, int, error) {
	assignment := propagator.GetAssignment()
	currentLevel := propagator.GetDecisionLevel()

	// Initialize frontier with conflict literals
	frontier := make([]propagation.Unit, len(conflict.Literals))
	copy(frontier, conflict.Literals)

	// Track analyzed literals to avoid reprocessing
	analyzed := make(map[propagation.Unit]bool)
	learned := make([]propagation.Unit, 0)
	counter := 0

	// Clear marks
	for unit := range ca.implicationGraph {
		ca.implicationGraph[unit].Mark = false
	}

	for len(frontier) > 0 {
		lit := frontier[0]
		frontier = frontier[1:]

		if analyzed[lit] {
			continue
		}
		analyzed[lit] = true
		counter++

		unit := propagation.Unit(abs(int(lit)))
		node := ca.implicationGraph[unit]

		if node == nil {
			// Unassigned or decision variable
			learned = append(learned, negate(lit))
			continue
		}

		level := assignment.GetLevel(unit)

		if level < currentLevel {
			// Variable from earlier level
			learned = append(learned, negate(lit))
		} else if level == currentLevel {
			// Variable from current level - add reasons to frontier
			if node.Reasons != nil {
				frontier = append(frontier, node.Reasons...)
			}
		}

		// Check for 1UIP
		if len(frontier) == 0 {
			// First UIP found
			learned = append(learned, negate(lit))
			break
		}

		counterOfCurrentLevel := 0
		for _, f := range frontier {
			u := propagation.Unit(abs(int(f)))
			l := assignment.GetLevel(u)
			if l == currentLevel {
				counterOfCurrentLevel++
			}
		}

		if counterOfCurrentLevel == 0 {
			break
		}
	}

	// Determine backtrack level (2nd highest level in learned)
	backtrackLevel := 0
	if len(learned) > 1 {
		levels := make([]int, 0)
		seenLevels := make(map[int]bool)

		for _, lit := range learned {
			unit := propagation.Unit(abs(int(lit)))
			level := assignment.GetLevel(unit)
			if !seenLevels[level] {
				levels = append(levels, level)
				seenLevels[level] = true
			}
		}

		sort.Ints(levels)

		if len(levels) > 1 {
			backtrackLevel = levels[len(levels)-2]
		} else if len(levels) == 1 {
			backtrackLevel = 0
		}
	}

	learnedNogood := propagation.Nogood{
		Literals: learned,
		Level:    backtrackLevel,
	}

	// Create clause for database
	clause := propagation.NewClause(learned, true)
	ca.learnedClauses = append(ca.learnedClauses, clause)

	return learnedNogood, backtrackLevel, nil
}

// RecordImplication records an implication in the graph
func (ca *ConflictAnalyzer) RecordImplication(
	unit propagation.Unit,
	reasons []propagation.Unit,
	level int,
) {
	node := &ImplicationNode{
		Unit:    unit,
		Reasons: reasons,
		Level:   level,
		Mark:    false,
	}
	ca.implicationGraph[unit] = node
}

// ClearImplicationGraph resets the implication graph
func (ca *ConflictAnalyzer) ClearImplicationGraph() {
	ca.implicationGraph = make(map[propagation.Unit]*ImplicationNode)
	ca.analyzer.nodes = make(map[propagation.Unit]*ImplicationNode)
}

// GetLearnedClauses returns all learned clauses
func (ca *ConflictAnalyzer) GetLearnedClauses() []*propagation.Clause {
	return ca.learnedClauses
}

// ResolveLiteral performs resolution between two clauses
func (ca *ConflictAnalyzer) ResolveLiteral(
	clause1 []propagation.Unit,
	clause2 []propagation.Unit,
	resolveVar propagation.Unit,
) []propagation.Unit {
	result := make([]propagation.Unit, 0)
	seen := make(map[propagation.Unit]bool)

	// Add literals from clause1 except resolveVar
	for _, lit := range clause1 {
		unit := propagation.Unit(abs(int(lit)))
		if unit != resolveVar && !seen[unit] {
			result = append(result, lit)
			seen[unit] = true
		}
	}

	// Add literals from clause2 except negation of resolveVar
	for _, lit := range clause2 {
		unit := propagation.Unit(abs(int(lit)))
		if unit != resolveVar && !seen[unit] {
			result = append(result, lit)
			seen[unit] = true
		}
	}

	return result
}

// Minimization reduces learned clause by removing redundant literals
func (ca *ConflictAnalyzer) MinimizeClause(
	clause []propagation.Unit,
	propagator *propagation.Propagator,
) []propagation.Unit {
	assignment := propagator.GetAssignment()
	minimized := make([]propagation.Unit, 0)
	canRemove := make(map[propagation.Unit]bool)

	// Identify literals that can be removed
	for _, lit := range clause {
		unit := propagation.Unit(abs(int(lit)))
		if ca.isSideEffect(unit, clause, propagator) {
			canRemove[unit] = true
		}
	}

	// Build minimized clause
	for _, lit := range clause {
		unit := propagation.Unit(abs(int(lit)))
		if !canRemove[unit] {
			minimized = append(minimized, lit)
			continue
		}

		// Check if removal would break satisfaction
		allOthersSatisfied := true
		for _, otherLit := range minimized {
			otherUnit := propagation.Unit(abs(int(otherLit)))
			if val, ok := assignment.GetValue(otherUnit); ok {
				positive := otherLit > 0
				if !(val == positive) {
					allOthersSatisfied = false
					break
				}
			}
		}

		if allOthersSatisfied {
			continue // Safe to skip this literal
		}
		minimized = append(minimized, lit)
	}

	return minimized
}

// isSideEffect checks if removing a literal would make clause false
func (ca *ConflictAnalyzer) isSideEffect(
	unit propagation.Unit,
	clause []propagation.Unit,
	propagator *propagation.Propagator,
) bool {
	// Conservative: always keep literals for now
	// In a full implementation, would trace implications
	return false
}

// BuildImplicationGraph constructs graph from propagation trail
func (ca *ConflictAnalyzer) BuildImplicationGraph(
	trail []propagation.Unit,
	propagator *propagation.Propagator,
	implications map[propagation.Unit][]propagation.Unit,
) {
	ca.ClearImplicationGraph()
	assignment := propagator.GetAssignment()

	for unit, reasons := range implications {
		level := assignment.GetLevel(unit)
		ca.RecordImplication(unit, reasons, level)
	}
}

// ConflictStatistics tracks conflict analysis metrics
type ConflictStatistics struct {
	TotalConflicts    int
	LearnedClauses    int
	AverageClauseSize float64
	BacktrackLevels   []int
	DecisionLevels    []int
}

// AnalyzeStatistics computes statistics about conflicts
func (ca *ConflictAnalyzer) AnalyzeStatistics() ConflictStatistics {
	stats := ConflictStatistics{
		TotalConflicts: len(ca.learnedClauses),
		LearnedClauses: len(ca.learnedClauses),
		BacktrackLevels: make([]int, 0),
		DecisionLevels:  make([]int, 0),
	}

	totalSize := 0
	for _, clause := range ca.learnedClauses {
		totalSize += len(clause.Literals)
		stats.BacktrackLevels = append(stats.BacktrackLevels, clause.Activity)
	}

	if len(ca.learnedClauses) > 0 {
		stats.AverageClauseSize = float64(totalSize) / float64(len(ca.learnedClauses))
	}

	return stats
}

// Canonicalize converts clause to canonical form (sorted)
func Canonicalize(clause []propagation.Unit) []propagation.Unit {
	result := make([]propagation.Unit, len(clause))
	copy(result, clause)
	sort.Slice(result, func(i, j int) bool {
		return abs(int(result[i])) < abs(int(result[j]))
	})
	return result
}

// ClauseSubsumes checks if clause1 subsumes clause2
func ClauseSubsumes(clause1, clause2 []propagation.Unit) bool {
	if len(clause1) > len(clause2) {
		return false
	}

	for _, lit1 := range clause1 {
		found := false
		for _, lit2 := range clause2 {
			if lit1 == lit2 {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}

	return true
}

// ClauseDatabase manages learned clauses with deletion policies
type ClauseDatabase struct {
	clauses      []*propagation.Clause
	locked       map[int]bool
	deletePolicy string // "activity", "lbd", "size"
	maxClauses   int
	activity     float64
}

// NewClauseDatabase creates a clause database
func NewClauseDatabase(maxClauses int, deletePolicy string) *ClauseDatabase {
	return &ClauseDatabase{
		clauses:      make([]*propagation.Clause, 0),
		locked:       make(map[int]bool),
		deletePolicy: deletePolicy,
		maxClauses:   maxClauses,
		activity:     1.0,
	}
}

// AddClause adds a clause to the database
func (cd *ClauseDatabase) AddClause(clause *propagation.Clause) {
	cd.clauses = append(cd.clauses, clause)
	clause.Activity = cd.activity

	if len(cd.clauses) > cd.maxClauses {
		cd.DeleteInactiveClauseActivity()
	}
}

// DeleteInactiveClauseActivity removes inactive clauses (activity-based)
func (cd *ClauseDatabase) DeleteInactiveClauseActivity() {
	if len(cd.clauses) <= cd.maxClauses {
		return
	}

	// Sort by activity
	sort.Slice(cd.clauses, func(i, j int) bool {
		return cd.clauses[i].Activity > cd.clauses[j].Activity
	})

	// Keep top maxClauses
	cd.clauses = cd.clauses[:cd.maxClauses]
}

// DeleteInactiveClauseLBD removes clauses with high LBD
func (cd *ClauseDatabase) DeleteInactiveClauseLBD() {
	if len(cd.clauses) <= cd.maxClauses {
		return
	}

	// Sort by age (as proxy for LBD)
	sort.Slice(cd.clauses, func(i, j int) bool {
		return cd.clauses[i].Activity < cd.clauses[j].Activity
	})

	// Remove older half
	newLen := len(cd.clauses) / 2
	cd.clauses = cd.clauses[:newLen]
}

// DecayActivities reduces activity of all clauses
func (cd *ClauseDatabase) DecayActivities() {
	for _, clause := range cd.clauses {
		clause.Activity *= 0.999
	}
}

// GetClauses returns all clauses
func (cd *ClauseDatabase) GetClauses() []*propagation.Clause {
	return cd.clauses
}

// IncreaseActivity increases activity of clause at index
func (cd *ClauseDatabase) IncreaseActivity(idx int) {
	if idx >= 0 && idx < len(cd.clauses) {
		cd.clauses[idx].Activity += cd.activity
	}
}

// UpdateActivityIncrement updates base activity increment
func (cd *ClauseDatabase) UpdateActivityIncrement(factor float64) {
	cd.activity *= factor
}

// Helper functions

func negate(lit propagation.Unit) propagation.Unit {
	if lit > 0 {
		return -lit
	}
	return -lit
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// LiteralsToString converts literals to debug string
func LiteralsToString(lits []propagation.Unit) string {
	result := "["
	for i, lit := range lits {
		if i > 0 {
			result += ", "
		}
		if lit > 0 {
			result += fmt.Sprintf("x%d", lit)
		} else {
			result += fmt.Sprintf("¬x%d", -lit)
		}
	}
	result += "]"
	return result
}
