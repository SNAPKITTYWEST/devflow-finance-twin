package incremental

import (
	"devflow-finance-twin/asp/propagation"
	"fmt"
	"sort"
	"sync"
	"time"
)

// ScopeManager provides advanced scope lifecycle management and invariant checking.
type ScopeManager struct {
	scopes     []*Scope
	mu         sync.RWMutex
	maxDepth   int
	onPushHook func(*Scope) error
	onPopHook  func(*Scope) error
}

// Scope represents a single scope level with associated metadata.
type Scope struct {
	Level          int
	CreatedAt      time.Time
	Rules          []interface{}
	Assumptions    []propagation.Unit
	Parent         *Scope
	LearnedCount   int
	ConflictCount  int
	SolveCount     int
}

// NewScopeManager creates a scope management system with depth limits.
func NewScopeManager(maxDepth int) *ScopeManager {
	return &ScopeManager{
		scopes:   make([]*Scope, 0),
		maxDepth: maxDepth,
	}
}

// PushScope creates and registers a new scope with validation.
func (sm *ScopeManager) PushScope(parent *Scope, rules []interface{}, assumptions []propagation.Unit) (*Scope, error) {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if len(sm.scopes) >= sm.maxDepth {
		return nil, fmt.Errorf("scope manager: max depth %d exceeded", sm.maxDepth)
	}

	scope := &Scope{
		Level:       len(sm.scopes),
		CreatedAt:   time.Now(),
		Rules:       append([]interface{}{}, rules...),
		Assumptions: append([]propagation.Unit{}, assumptions...),
		Parent:      parent,
		LearnedCount: 0,
		ConflictCount: 0,
		SolveCount: 0,
	}

	if sm.onPushHook != nil {
		if err := sm.onPushHook(scope); err != nil {
			return nil, fmt.Errorf("scope manager: push hook failed: %w", err)
		}
	}

	sm.scopes = append(sm.scopes, scope)
	return scope, nil
}

// PopScope removes the most recent scope and returns its parent.
func (sm *ScopeManager) PopScope() (*Scope, error) {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if len(sm.scopes) == 0 {
		return nil, fmt.Errorf("scope manager: no scope to pop")
	}

	scope := sm.scopes[len(sm.scopes)-1]
	sm.scopes = sm.scopes[:len(sm.scopes)-1]

	if sm.onPopHook != nil {
		if err := sm.onPopHook(scope); err != nil {
			return nil, fmt.Errorf("scope manager: pop hook failed: %w", err)
		}
	}

	if len(sm.scopes) == 0 {
		return nil, nil
	}

	return sm.scopes[len(sm.scopes)-1], nil
}

// CurrentScope returns the active scope or nil.
func (sm *ScopeManager) CurrentScope() *Scope {
	sm.mu.RLock()
	defer sm.mu.RUnlock()

	if len(sm.scopes) == 0 {
		return nil
	}
	return sm.scopes[len(sm.scopes)-1]
}

// Depth returns current scope nesting depth.
func (sm *ScopeManager) Depth() int {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	return len(sm.scopes)
}

// ScopeStack returns a copy of the scope stack (for inspection).
func (sm *ScopeManager) ScopeStack() []*Scope {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	return append([]*Scope{}, sm.scopes...)
}

// SetPushHook registers a callback for scope push events.
func (sm *ScopeManager) SetPushHook(hook func(*Scope) error) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	sm.onPushHook = hook
}

// SetPopHook registers a callback for scope pop events.
func (sm *ScopeManager) SetPopHook(hook func(*Scope) error) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	sm.onPopHook = hook
}

// AssumeHandler manages assumption lifecycle and conflict resolution.
type AssumeHandler struct {
	active     []propagation.Unit
	inactive   []propagation.Unit
	mu         sync.RWMutex
	scopeStack [][]propagation.Unit
}

// NewAssumeHandler creates a new assumption handler.
func NewAssumeHandler() *AssumeHandler {
	return &AssumeHandler{
		active:     make([]propagation.Unit, 0),
		inactive:   make([]propagation.Unit, 0),
		scopeStack: make([][]propagation.Unit, 0),
	}
}

// Add adds an assumption to the active set.
func (ah *AssumeHandler) Add(unit propagation.Unit) error {
	if unit == 0 {
		return fmt.Errorf("assume: zero unit invalid")
	}

	ah.mu.Lock()
	defer ah.mu.Unlock()

	// Check for conflicting assumptions
	negUnit := negate(unit)
	for _, active := range ah.active {
		if active == negUnit {
			return fmt.Errorf("assume: conflicting assumption %d vs %d", unit, negUnit)
		}
	}

	ah.active = append(ah.active, unit)
	return nil
}

// Remove deactivates an assumption.
func (ah *AssumeHandler) Remove(unit propagation.Unit) {
	ah.mu.Lock()
	defer ah.mu.Unlock()

	for i, u := range ah.active {
		if u == unit {
			ah.active = append(ah.active[:i], ah.active[i+1:]...)
			ah.inactive = append(ah.inactive, unit)
			return
		}
	}
}

// Active returns the current active assumptions.
func (ah *AssumeHandler) Active() []propagation.Unit {
	ah.mu.RLock()
	defer ah.mu.RUnlock()
	return append([]propagation.Unit{}, ah.active...)
}

// PushScope saves the current assumption state.
func (ah *AssumeHandler) PushScope() {
	ah.mu.Lock()
	defer ah.mu.Unlock()

	ah.scopeStack = append(ah.scopeStack, append([]propagation.Unit{}, ah.active...))
}

// PopScope restores assumptions from before PushScope.
func (ah *AssumeHandler) PopScope() error {
	ah.mu.Lock()
	defer ah.mu.Unlock()

	if len(ah.scopeStack) == 0 {
		return fmt.Errorf("assume: no saved scope to restore")
	}

	ah.active = append([]propagation.Unit{}, ah.scopeStack[len(ah.scopeStack)-1]...)
	ah.scopeStack = ah.scopeStack[:len(ah.scopeStack)-1]
	return nil
}

// ConflictManager tracks and analyzes conflicts across scopes.
type ConflictManager struct {
	conflicts  []Conflict
	mu         sync.RWMutex
	maxHistory int
}

// Conflict represents a single conflict event with context.
type Conflict struct {
	ID           uint64
	ScopeLevel   int
	Timestamp    time.Time
	ClauseLits   []propagation.Unit
	LearnedSize  int
	BacktrackTo  int
	FailingUnit  propagation.Unit
}

// NewConflictManager creates a conflict tracking system.
func NewConflictManager(maxHistory int) *ConflictManager {
	return &ConflictManager{
		conflicts:  make([]Conflict, 0),
		maxHistory: maxHistory,
	}
}

// Record logs a conflict.
func (cm *ConflictManager) Record(scopeLevel, learnedSize, backtrackTo int, lits []propagation.Unit, failingUnit propagation.Unit) {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	conflict := Conflict{
		ID:          uint64(len(cm.conflicts)),
		ScopeLevel:  scopeLevel,
		Timestamp:   time.Now(),
		ClauseLits:  append([]propagation.Unit{}, lits...),
		LearnedSize: learnedSize,
		BacktrackTo: backtrackTo,
		FailingUnit: failingUnit,
	}

	cm.conflicts = append(cm.conflicts, conflict)

	// Trim history if exceeded
	if len(cm.conflicts) > cm.maxHistory {
		cm.conflicts = cm.conflicts[len(cm.conflicts)-cm.maxHistory:]
	}
}

// History returns recent conflicts (up to limit).
func (cm *ConflictManager) History(limit int) []Conflict {
	cm.mu.RLock()
	defer cm.mu.RUnlock()

	if limit <= 0 || limit > len(cm.conflicts) {
		limit = len(cm.conflicts)
	}

	result := make([]Conflict, limit)
	copy(result, cm.conflicts[len(cm.conflicts)-limit:])
	return result
}

// ConflictStatistics returns analyzed conflict patterns.
func (cm *ConflictManager) ConflictStatistics() map[string]interface{} {
	cm.mu.RLock()
	defer cm.mu.RUnlock()

	if len(cm.conflicts) == 0 {
		return map[string]interface{}{
			"total":          0,
			"avgClauseSize":  0.0,
			"maxBacktrack":   0,
			"avgBacktrack":   0.0,
			"byScope":        make(map[int]int),
		}
	}

	totalClauseSize := 0
	maxBacktrack := 0
	totalBacktrack := 0
	scopeCount := make(map[int]int)

	for _, c := range cm.conflicts {
		totalClauseSize += c.LearnedSize
		if c.BacktrackTo > maxBacktrack {
			maxBacktrack = c.BacktrackTo
		}
		totalBacktrack += c.BacktrackTo
		scopeCount[c.ScopeLevel]++
	}

	return map[string]interface{}{
		"total":         len(cm.conflicts),
		"avgClauseSize": float64(totalClauseSize) / float64(len(cm.conflicts)),
		"maxBacktrack":  maxBacktrack,
		"avgBacktrack":  float64(totalBacktrack) / float64(len(cm.conflicts)),
		"byScope":       scopeCount,
	}
}

// IncrementalLearning manages learned clause reuse across scopes.
type IncrementalLearning struct {
	clauses        []*LearnedClauseInfo
	mu             sync.RWMutex
	maxClauses     int
	evictionPolicy string // "lru", "lfu", "activity"
	accessCount    map[uint64]int
}

// LearnedClauseInfo wraps a clause with metadata for management.
type LearnedClauseInfo struct {
	ID              uint64
	Clause          *propagation.Clause
	LearnedAt       int              // Scope level
	AccessCount     int
	LastAccessTime  time.Time
	Activity        float64
	UsefulInScopes  map[int]bool     // Which scopes benefited from this clause
}

// NewIncrementalLearning creates a learned clause manager.
func NewIncrementalLearning(maxClauses int, policy string) *IncrementalLearning {
	return &IncrementalLearning{
		clauses:        make([]*LearnedClauseInfo, 0),
		maxClauses:     maxClauses,
		evictionPolicy: policy,
		accessCount:    make(map[uint64]int),
	}
}

// AddClause registers a learned clause for reuse.
func (il *IncrementalLearning) AddClause(clause *propagation.Clause, scopeLevel int) uint64 {
	il.mu.Lock()
	defer il.mu.Unlock()

	id := uint64(len(il.clauses))
	info := &LearnedClauseInfo{
		ID:             id,
		Clause:         clause,
		LearnedAt:      scopeLevel,
		AccessCount:    0,
		LastAccessTime: time.Now(),
		Activity:       1.0,
		UsefulInScopes: make(map[int]bool),
	}

	il.clauses = append(il.clauses, info)

	// Check if eviction needed
	if len(il.clauses) > il.maxClauses {
		il.evict()
	}

	return id
}

// evict removes low-value clauses based on policy.
func (il *IncrementalLearning) evict() {
	switch il.evictionPolicy {
	case "lru":
		il.evictLRU()
	case "lfu":
		il.evictLFU()
	case "activity":
		il.evictLowActivity()
	default:
		// Default: remove oldest
		if len(il.clauses) > 0 {
			il.clauses = il.clauses[1:]
		}
	}
}

// evictLRU removes least recently used clause.
func (il *IncrementalLearning) evictLRU() {
	if len(il.clauses) == 0 {
		return
	}

	oldest := 0
	oldestTime := il.clauses[0].LastAccessTime

	for i, info := range il.clauses {
		if info.LastAccessTime.Before(oldestTime) {
			oldest = i
			oldestTime = info.LastAccessTime
		}
	}

	il.clauses = append(il.clauses[:oldest], il.clauses[oldest+1:]...)
}

// evictLFU removes least frequently used clause.
func (il *IncrementalLearning) evictLFU() {
	if len(il.clauses) == 0 {
		return
	}

	sort.Slice(il.clauses, func(i, j int) bool {
		return il.clauses[i].AccessCount < il.clauses[j].AccessCount
	})

	il.clauses = il.clauses[1:]
}

// evictLowActivity removes lowest activity clause.
func (il *IncrementalLearning) evictLowActivity() {
	if len(il.clauses) == 0 {
		return
	}

	sort.Slice(il.clauses, func(i, j int) bool {
		return il.clauses[i].Activity < il.clauses[j].Activity
	})

	il.clauses = il.clauses[1:]
}

// GetReusableClauses returns clauses that may be beneficial in a scope.
func (il *IncrementalLearning) GetReusableClauses(scopeLevel int) []*propagation.Clause {
	il.mu.RLock()
	defer il.mu.RUnlock()

	result := make([]*propagation.Clause, 0)
	for _, info := range il.clauses {
		// Heuristic: reuse clauses learned in same or parent scopes
		if info.LearnedAt <= scopeLevel {
			result = append(result, info.Clause)
			info.AccessCount++
			info.LastAccessTime = time.Now()
		}
	}

	return result
}

// MarkUseful marks a clause as useful in a specific scope.
func (il *IncrementalLearning) MarkUseful(clauseID uint64, scopeLevel int) {
	il.mu.Lock()
	defer il.mu.Unlock()

	if int(clauseID) < len(il.clauses) {
		il.clauses[clauseID].UsefulInScopes[scopeLevel] = true
		il.clauses[clauseID].Activity *= 1.1 // Increase activity
	}
}

// helper function for negating units
func negate(unit propagation.Unit) propagation.Unit {
	if unit > 0 {
		return -unit
	}
	return -unit
}

// ProgressTracker monitors solving progress across scopes.
type ProgressTracker struct {
	startTime    time.Time
	events       []ProgressEvent
	mu           sync.RWMutex
	lastSolveTime time.Duration
}

// ProgressEvent represents a milestone in solving.
type ProgressEvent struct {
	Timestamp  time.Time
	ScopeLevel int
	EventType  string // "push", "pop", "solve_start", "solve_end", "conflict", "learn"
	Message    string
	Duration   time.Duration
}

// NewProgressTracker creates a progress tracking system.
func NewProgressTracker() *ProgressTracker {
	return &ProgressTracker{
		startTime: time.Now(),
		events:    make([]ProgressEvent, 0),
	}
}

// Record logs a progress event.
func (pt *ProgressTracker) Record(scopeLevel int, eventType, message string) {
	pt.mu.Lock()
	defer pt.mu.Unlock()

	elapsed := time.Since(pt.startTime)
	event := ProgressEvent{
		Timestamp:  time.Now(),
		ScopeLevel: scopeLevel,
		EventType:  eventType,
		Message:    message,
		Duration:   elapsed,
	}

	pt.events = append(pt.events, event)
}

// Elapsed returns total elapsed time since tracker creation.
func (pt *ProgressTracker) Elapsed() time.Duration {
	return time.Since(pt.startTime)
}

// SetLastSolveTime records the duration of the last solve.
func (pt *ProgressTracker) SetLastSolveTime(d time.Duration) {
	pt.mu.Lock()
	defer pt.mu.Unlock()
	pt.lastSolveTime = d
}

// GetLastSolveTime returns the duration of the last solve.
func (pt *ProgressTracker) GetLastSolveTime() time.Duration {
	pt.mu.RLock()
	defer pt.mu.RUnlock()
	return pt.lastSolveTime
}

// Events returns a copy of all recorded events.
func (pt *ProgressTracker) Events() []ProgressEvent {
	pt.mu.RLock()
	defer pt.mu.RUnlock()
	return append([]ProgressEvent{}, pt.events...)
}

// Summary returns a text summary of progress.
func (pt *ProgressTracker) Summary() string {
	pt.mu.RLock()
	defer pt.mu.RUnlock()

	if len(pt.events) == 0 {
		return "No progress events recorded"
	}

	summary := fmt.Sprintf("Progress Summary (%d events, elapsed %v):\n", len(pt.events), pt.Elapsed())

	pushCount := 0
	popCount := 0
	solveCount := 0
	conflictCount := 0

	for _, event := range pt.events {
		switch event.EventType {
		case "push":
			pushCount++
		case "pop":
			popCount++
		case "solve_start", "solve_end":
			solveCount++
		case "conflict":
			conflictCount++
		}
	}

	summary += fmt.Sprintf("  Pushes: %d, Pops: %d, Solves: %d, Conflicts: %d\n", pushCount, popCount, solveCount, conflictCount)

	return summary
}

// RuleOrganizer helps manage and organize rules hierarchically.
type RuleOrganizer struct {
	byScope    map[int][]interface{}
	globalRules []interface{}
	mu         sync.RWMutex
}

// NewRuleOrganizer creates a rule organization system.
func NewRuleOrganizer() *RuleOrganizer {
	return &RuleOrganizer{
		byScope:     make(map[int][]interface{}),
		globalRules: make([]interface{}, 0),
	}
}

// AddGlobal adds rules to the global set (persist across all scopes).
func (ro *RuleOrganizer) AddGlobal(rules []interface{}) error {
	ro.mu.Lock()
	defer ro.mu.Unlock()

	ro.globalRules = append(ro.globalRules, rules...)
	return nil
}

// AddScoped adds rules to a specific scope.
func (ro *RuleOrganizer) AddScoped(scopeLevel int, rules []interface{}) error {
	ro.mu.Lock()
	defer ro.mu.Unlock()

	if _, exists := ro.byScope[scopeLevel]; !exists {
		ro.byScope[scopeLevel] = make([]interface{}, 0)
	}

	ro.byScope[scopeLevel] = append(ro.byScope[scopeLevel], rules...)
	return nil
}

// GetRulesForScope returns all applicable rules (global + scope-specific).
func (ro *RuleOrganizer) GetRulesForScope(scopeLevel int) []interface{} {
	ro.mu.RLock()
	defer ro.mu.RUnlock()

	result := append([]interface{}{}, ro.globalRules...)

	// Add all rules from scopes up to and including current
	for level := 0; level <= scopeLevel; level++ {
		if rules, exists := ro.byScope[level]; exists {
			result = append(result, rules...)
		}
	}

	return result
}

// RemoveScope removes all rules associated with a scope.
func (ro *RuleOrganizer) RemoveScope(scopeLevel int) error {
	ro.mu.Lock()
	defer ro.mu.Unlock()

	delete(ro.byScope, scopeLevel)
	return nil
}

// Statistics returns counts of rules.
func (ro *RuleOrganizer) Statistics() map[string]int {
	ro.mu.RLock()
	defer ro.mu.RUnlock()

	stats := map[string]int{
		"global":      len(ro.globalRules),
		"scoped":      len(ro.byScope),
		"totalScoped": 0,
	}

	totalScoped := 0
	for _, rules := range ro.byScope {
		totalScoped += len(rules)
	}

	stats["totalScoped"] = totalScoped
	return stats
}
