package incremental

import (
	"devflow-finance-twin/asp/propagation"
	"fmt"
	"sort"
	"strings"
	"time"
)

// SolverConfig encapsulates configuration for incremental solving.
type SolverConfig struct {
	MaxScopeDepth          int
	MaxLearnedClauses      int
	EvictionPolicy         string // "lru", "lfu", "activity"
	ConflictHistorySize    int
	EnableProgressTracking bool
	Timeout                time.Duration
	HeuristicType          string // "vsids", "activity", "occurrence"
}

// DefaultConfig returns sensible default configuration.
func DefaultConfig() *SolverConfig {
	return &SolverConfig{
		MaxScopeDepth:          100,
		MaxLearnedClauses:      10000,
		EvictionPolicy:         "activity",
		ConflictHistorySize:    1000,
		EnableProgressTracking: true,
		Timeout:                0, // No timeout
		HeuristicType:          "activity",
	}
}

// Validator checks configuration for errors and inconsistencies.
func (sc *SolverConfig) Validate() error {
	if sc.MaxScopeDepth <= 0 {
		return fmt.Errorf("config: MaxScopeDepth must be positive")
	}

	if sc.MaxLearnedClauses < 100 {
		return fmt.Errorf("config: MaxLearnedClauses should be at least 100")
	}

	validPolicies := map[string]bool{"lru": true, "lfu": true, "activity": true}
	if !validPolicies[sc.EvictionPolicy] {
		return fmt.Errorf("config: invalid EvictionPolicy %q", sc.EvictionPolicy)
	}

	if sc.ConflictHistorySize < 0 {
		return fmt.Errorf("config: ConflictHistorySize cannot be negative")
	}

	validHeuristics := map[string]bool{"vsids": true, "activity": true, "occurrence": true}
	if !validHeuristics[sc.HeuristicType] {
		return fmt.Errorf("config: invalid HeuristicType %q", sc.HeuristicType)
	}

	return nil
}

// BuilderPattern allows fluent configuration building.
func (sc *SolverConfig) WithMaxScopeDepth(d int) *SolverConfig {
	sc.MaxScopeDepth = d
	return sc
}

func (sc *SolverConfig) WithMaxLearnedClauses(m int) *SolverConfig {
	sc.MaxLearnedClauses = m
	return sc
}

func (sc *SolverConfig) WithEvictionPolicy(p string) *SolverConfig {
	sc.EvictionPolicy = p
	return sc
}

func (sc *SolverConfig) WithTimeout(t time.Duration) *SolverConfig {
	sc.Timeout = t
	return sc
}

// SolutionContext wraps a solution with metadata.
type SolutionContext struct {
	Assignment       map[int]bool
	ScopeLevel       int
	SolveTime        time.Duration
	ConflictCount    int
	DecisionCount    int
	LearnedClauses   int
	IsOptimal        bool
	ProvenUnsolvable bool
	Timestamp        time.Time
}

// IsValid checks if the solution represents a valid model.
func (sc *SolutionContext) IsValid() bool {
	return sc.Assignment != nil || sc.ProvenUnsolvable
}

// Size returns the number of true atoms in the solution.
func (sc *SolutionContext) Size() int {
	if sc.Assignment == nil {
		return 0
	}

	count := 0
	for _, v := range sc.Assignment {
		if v {
			count++
		}
	}

	return count
}

// String returns a human-readable representation.
func (sc *SolutionContext) String() string {
	if sc.ProvenUnsolvable {
		return fmt.Sprintf("UNSAT (scope %d, %d conflicts)", sc.ScopeLevel, sc.ConflictCount)
	}

	if sc.Assignment == nil {
		return fmt.Sprintf("UNKNOWN (scope %d)", sc.ScopeLevel)
	}

	return fmt.Sprintf("SAT (scope %d, %d atoms, %v solve time)", sc.ScopeLevel, sc.Size(), sc.SolveTime)
}

// DeltaAnalyzer tracks differences between consecutive solutions.
type DeltaAnalyzer struct {
	previous *SolutionContext
	current  *SolutionContext
}

// NewDeltaAnalyzer creates a delta tracking system.
func NewDeltaAnalyzer() *DeltaAnalyzer {
	return &DeltaAnalyzer{}
}

// Update records a new solution and compares to previous.
func (da *DeltaAnalyzer) Update(solution *SolutionContext) {
	da.previous = da.current
	da.current = solution
}

// Delta returns the changes from previous to current solution.
func (da *DeltaAnalyzer) Delta() DeltaResult {
	result := DeltaResult{
		Added:      make([]int, 0),
		Removed:    make([]int, 0),
		Unchanged:  make([]int, 0),
		PreviousSize: 0,
		CurrentSize:  0,
	}

	if da.previous == nil || da.previous.Assignment == nil {
		// First solution or previous was UNSAT
		if da.current != nil && da.current.Assignment != nil {
			for atom, val := range da.current.Assignment {
				if val {
					result.Added = append(result.Added, atom)
				}
			}
		}
		result.CurrentSize = len(result.Added)
		return result
	}

	if da.current == nil || da.current.Assignment == nil {
		// Current is UNSAT, previous was SAT
		for atom, val := range da.previous.Assignment {
			if val {
				result.Removed = append(result.Removed, atom)
			}
		}
		result.PreviousSize = len(result.Removed)
		return result
	}

	// Both are solutions, compute delta
	prevSet := make(map[int]bool)
	currSet := make(map[int]bool)

	for atom, val := range da.previous.Assignment {
		if val {
			prevSet[atom] = true
		}
	}

	for atom, val := range da.current.Assignment {
		if val {
			currSet[atom] = true
		}
	}

	// Find added
	for atom := range currSet {
		if !prevSet[atom] {
			result.Added = append(result.Added, atom)
		} else {
			result.Unchanged = append(result.Unchanged, atom)
		}
	}

	// Find removed
	for atom := range prevSet {
		if !currSet[atom] {
			result.Removed = append(result.Removed, atom)
		}
	}

	sort.Ints(result.Added)
	sort.Ints(result.Removed)
	sort.Ints(result.Unchanged)

	result.PreviousSize = len(prevSet)
	result.CurrentSize = len(currSet)

	return result
}

// DeltaResult represents solution changes.
type DeltaResult struct {
	Added       []int
	Removed     []int
	Unchanged   []int
	PreviousSize int
	CurrentSize int
}

// String returns a formatted delta report.
func (dr *DeltaResult) String() string {
	var sb strings.Builder

	sb.WriteString(fmt.Sprintf("Solution Delta: %d → %d atoms\n", dr.PreviousSize, dr.CurrentSize))
	sb.WriteString(fmt.Sprintf("  Added:   %d atoms: %v\n", len(dr.Added), dr.Added))
	sb.WriteString(fmt.Sprintf("  Removed: %d atoms: %v\n", len(dr.Removed), dr.Removed))
	sb.WriteString(fmt.Sprintf("  Unchanged: %d atoms\n", len(dr.Unchanged)))

	return sb.String()
}

// HistoryBuffer maintains a sliding window of solver states.
type HistoryBuffer struct {
	snapshots []*SolverSnapshot
	maxSize   int
	index     int
	mu        sync.RWMutex
}

// NewHistoryBuffer creates a bounded history buffer.
func NewHistoryBuffer(maxSize int) *HistoryBuffer {
	if maxSize <= 0 {
		maxSize = 100
	}

	return &HistoryBuffer{
		snapshots: make([]*SolverSnapshot, 0, maxSize),
		maxSize:   maxSize,
		index:     0,
	}
}

// Push adds a snapshot to the buffer.
func (hb *HistoryBuffer) Push(snapshot *SolverSnapshot) {
	hb.mu.Lock()
	defer hb.mu.Unlock()

	if len(hb.snapshots) < hb.maxSize {
		hb.snapshots = append(hb.snapshots, snapshot)
	} else {
		hb.snapshots[hb.index] = snapshot
		hb.index = (hb.index + 1) % hb.maxSize
	}
}

// Get retrieves a snapshot by offset from most recent.
// offset=0 is most recent, offset=1 is previous, etc.
func (hb *HistoryBuffer) Get(offset int) *SolverSnapshot {
	hb.mu.RLock()
	defer hb.mu.RUnlock()

	if offset < 0 || offset >= len(hb.snapshots) {
		return nil
	}

	// Calculate actual index (circular buffer aware)
	actualIdx := (hb.index - 1 - offset) % len(hb.snapshots)
	if actualIdx < 0 {
		actualIdx += len(hb.snapshots)
	}

	return hb.snapshots[actualIdx]
}

// All returns all snapshots in order (oldest to newest).
func (hb *HistoryBuffer) All() []*SolverSnapshot {
	hb.mu.RLock()
	defer hb.mu.RUnlock()

	result := make([]*SolverSnapshot, len(hb.snapshots))
	copy(result, hb.snapshots)
	return result
}

// Clear empties the history buffer.
func (hb *HistoryBuffer) Clear() {
	hb.mu.Lock()
	defer hb.mu.Unlock()

	hb.snapshots = make([]*SolverSnapshot, 0, hb.maxSize)
	hb.index = 0
}

// Size returns number of stored snapshots.
func (hb *HistoryBuffer) Size() int {
	hb.mu.RLock()
	defer hb.mu.RUnlock()

	return len(hb.snapshots)
}

// BatchSolver groups multiple solving operations with shared context.
type BatchSolver struct {
	solver     *IncrementalSolver
	config     *SolverConfig
	results    []SolutionContext
	startTime  time.Time
	statistics *BatchStatistics
	mu         sync.RWMutex
}

// BatchStatistics tracks aggregate batch solving metrics.
type BatchStatistics struct {
	TotalSolves      int
	SuccessfulSolves int
	FailedSolves     int
	TotalTime        time.Duration
	AverageSolveTime time.Duration
	MaxSolveTime     time.Duration
	MinSolveTime     time.Duration
}

// NewBatchSolver creates a batch solving context.
func NewBatchSolver(solver *IncrementalSolver, config *SolverConfig) *BatchSolver {
	return &BatchSolver{
		solver:     solver,
		config:     config,
		results:    make([]SolutionContext, 0),
		startTime:  time.Now(),
		statistics: &BatchStatistics{},
	}
}

// SolveAll executes multiple solve operations in sequence.
func (bs *BatchSolver) SolveAll(operations []SolveOperation) error {
	bs.mu.Lock()
	defer bs.mu.Unlock()

	for _, op := range operations {
		startOp := time.Now()

		// Execute operation (push rules, solve, pop, etc.)
		var result map[int]bool
		var err error

		if len(op.Rules) > 0 {
			_ = bs.solver.Add(op.Rules)
		}

		if len(op.Assumptions) > 0 {
			result, err = bs.solver.SolveWith(op.Assumptions)
		} else {
			result, err = bs.solver.Solve()
		}

		elapsed := time.Since(startOp)

		// Record result
		context := SolutionContext{
			Assignment:       result,
			ScopeLevel:       bs.solver.ScopeDepth(),
			SolveTime:        elapsed,
			IsOptimal:        op.IsOptimal,
			ProvenUnsolvable: err != nil && err.Error() == "unsatisfiable",
			Timestamp:        time.Now(),
		}

		bs.results = append(bs.results, context)

		// Update statistics
		bs.statistics.TotalSolves++
		bs.statistics.TotalTime += elapsed

		if context.ProvenUnsolvable || err != nil {
			bs.statistics.FailedSolves++
		} else {
			bs.statistics.SuccessfulSolves++
		}

		if bs.statistics.TotalSolves == 1 {
			bs.statistics.MinSolveTime = elapsed
			bs.statistics.MaxSolveTime = elapsed
		} else {
			if elapsed > bs.statistics.MaxSolveTime {
				bs.statistics.MaxSolveTime = elapsed
			}
			if elapsed < bs.statistics.MinSolveTime {
				bs.statistics.MinSolveTime = elapsed
			}
		}

		// Optional: pop after each solve for clean state
		if op.PopAfter && bs.solver.ScopeDepth() > 0 {
			_ = bs.solver.Pop()
		}
	}

	// Compute average
	if bs.statistics.TotalSolves > 0 {
		bs.statistics.AverageSolveTime = bs.statistics.TotalTime / time.Duration(bs.statistics.TotalSolves)
	}

	return nil
}

// GetResults returns all accumulated results.
func (bs *BatchSolver) GetResults() []SolutionContext {
	bs.mu.RLock()
	defer bs.mu.RUnlock()

	return append([]SolutionContext{}, bs.results...)
}

// GetStatistics returns aggregate batch statistics.
func (bs *BatchSolver) GetStatistics() *BatchStatistics {
	bs.mu.RLock()
	defer bs.mu.RUnlock()

	return &BatchStatistics{
		TotalSolves:      bs.statistics.TotalSolves,
		SuccessfulSolves: bs.statistics.SuccessfulSolves,
		FailedSolves:     bs.statistics.FailedSolves,
		TotalTime:        bs.statistics.TotalTime,
		AverageSolveTime: bs.statistics.AverageSolveTime,
		MaxSolveTime:     bs.statistics.MaxSolveTime,
		MinSolveTime:     bs.statistics.MinSolveTime,
	}
}

// SolveOperation describes a single batch solve operation.
type SolveOperation struct {
	ID          string
	Rules       []interface{}
	Assumptions []propagation.Unit
	IsOptimal   bool
	PopAfter    bool // Pop scope after solving
}

// ComparativeAnalyzer compares solutions from different solving contexts.
type ComparativeAnalyzer struct {
	solutions map[string]SolutionContext
	mu        sync.RWMutex
}

// NewComparativeAnalyzer creates a solution comparison tool.
func NewComparativeAnalyzer() *ComparativeAnalyzer {
	return &ComparativeAnalyzer{
		solutions: make(map[string]SolutionContext),
	}
}

// Record stores a solution with a label for comparison.
func (ca *ComparativeAnalyzer) Record(label string, context SolutionContext) {
	ca.mu.Lock()
	defer ca.mu.Unlock()

	ca.solutions[label] = context
}

// Compare generates a comparison report between two labeled solutions.
func (ca *ComparativeAnalyzer) Compare(label1, label2 string) (ComparisonReport, error) {
	ca.mu.RLock()
	defer ca.mu.RUnlock()

	sol1, ok1 := ca.solutions[label1]
	sol2, ok2 := ca.solutions[label2]

	if !ok1 || !ok2 {
		return ComparisonReport{}, fmt.Errorf("compare: missing solution(s): %v, %v", !ok1, !ok2)
	}

	report := ComparisonReport{
		Label1:         label1,
		Label2:         label2,
		SolveTime1:     sol1.SolveTime,
		SolveTime2:     sol2.SolveTime,
		AtomCount1:     len(sol1.Assignment),
		AtomCount2:     len(sol2.Assignment),
	}

	if sol1.SolveTime > sol2.SolveTime {
		report.FasterLabel = label2
		report.SpeedupFactor = float64(sol1.SolveTime) / float64(sol2.SolveTime)
	} else {
		report.FasterLabel = label1
		report.SpeedupFactor = float64(sol2.SolveTime) / float64(sol1.SolveTime)
	}

	// Compute solution differences
	if sol1.Assignment != nil && sol2.Assignment != nil {
		set1 := make(map[int]bool)
		set2 := make(map[int]bool)

		for atom, val := range sol1.Assignment {
			set1[atom] = val
		}
		for atom, val := range sol2.Assignment {
			set2[atom] = val
		}

		for atom := range set1 {
			if set2[atom] != set1[atom] {
				report.DifferentAtoms++
			}
		}

		for atom := range set2 {
			if _, in1 := set1[atom]; !in1 {
				report.DifferentAtoms++
			}
		}
	}

	return report, nil
}

// ComparisonReport contains solution comparison results.
type ComparisonReport struct {
	Label1         string
	Label2         string
	SolveTime1     time.Duration
	SolveTime2     time.Duration
	AtomCount1     int
	AtomCount2     int
	DifferentAtoms int
	FasterLabel    string
	SpeedupFactor  float64
}

// String returns a formatted comparison report.
func (cr *ComparisonReport) String() string {
	var sb strings.Builder

	sb.WriteString(fmt.Sprintf("Comparison: %s vs %s\n", cr.Label1, cr.Label2))
	sb.WriteString(fmt.Sprintf("  Solve Times: %v vs %v (faster: %s, %fx speedup)\n",
		cr.SolveTime1, cr.SolveTime2, cr.FasterLabel, cr.SpeedupFactor))
	sb.WriteString(fmt.Sprintf("  Atom Counts: %d vs %d\n", cr.AtomCount1, cr.AtomCount2))

	if cr.DifferentAtoms > 0 {
		sb.WriteString(fmt.Sprintf("  Different Atoms: %d\n", cr.DifferentAtoms))
	}

	return sb.String()
}

// import "sync" for compatibility

import "sync"
