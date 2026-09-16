package solver

import (
	"devflow-finance-twin/asp/propagation"
	"math"
	"sort"
)

// Heuristic interface for variable selection strategies
type Heuristic interface {
	// SelectLiteral selects next literal from unassigned units
	SelectLiteral(unassigned []propagation.Unit) (propagation.Unit, bool)

	// NotifyConflict notifies heuristic of a conflict for activity bump
	NotifyConflict(units []propagation.Unit)

	// Decay reduces activity scores for all variables (for recency bias)
	Decay()

	// GetActivity returns activity score for a unit
	GetActivity(unit propagation.Unit) float64
}

// ActivityHeuristic implements VSIDS-like heuristic (Variable State Independent Decaying Sum)
type ActivityHeuristic struct {
	activity      map[propagation.Unit]float64
	increment     float64
	decayFactor   float64
	conflictCount int
	lastDecay     int
	decayInterval int
}

// NewActivityHeuristic creates a new activity-based heuristic
func NewActivityHeuristic() *ActivityHeuristic {
	return &ActivityHeuristic{
		activity:      make(map[propagation.Unit]float64),
		increment:     1.0,
		decayFactor:   0.95,
		conflictCount: 0,
		lastDecay:     0,
		decayInterval: 100, // Decay every 100 conflicts
	}
}

// SelectLiteral selects the unassigned variable with highest activity
func (ah *ActivityHeuristic) SelectLiteral(unassigned []propagation.Unit) (propagation.Unit, bool) {
	if len(unassigned) == 0 {
		return 0, false
	}

	maxActivity := math.Inf(-1)
	selectedUnit := propagation.Unit(0)
	selectedIdx := -1

	for i, unit := range unassigned {
		activity := ah.GetActivity(unit)
		if activity > maxActivity {
			maxActivity = activity
			selectedUnit = unit
			selectedIdx = i
		}
	}

	if selectedIdx >= 0 {
		return selectedUnit, true
	}

	// Fallback: return first unassigned
	return unassigned[0], true
}

// NotifyConflict increments activity of involved units
func (ah *ActivityHeuristic) NotifyConflict(units []propagation.Unit) {
	for _, unit := range units {
		if unit == 0 {
			continue
		}
		absUnit := propagation.Unit(abs(int(unit)))
		ah.activity[absUnit] += ah.increment
	}

	ah.conflictCount++

	// Periodic decay to prevent activity overflow
	if ah.conflictCount-ah.lastDecay >= ah.decayInterval {
		ah.Decay()
		ah.lastDecay = ah.conflictCount
	}
}

// Decay reduces all activity scores
func (ah *ActivityHeuristic) Decay() {
	for unit := range ah.activity {
		ah.activity[unit] *= ah.decayFactor
	}
	ah.increment *= (1.0 / ah.decayFactor)
}

// GetActivity returns activity score for a unit
func (ah *ActivityHeuristic) GetActivity(unit propagation.Unit) float64 {
	absUnit := propagation.Unit(abs(int(unit)))
	if activity, exists := ah.activity[absUnit]; exists {
		return activity
	}
	return 0.0
}

// RandomHeuristic selects variables randomly (for comparison/debugging)
type RandomHeuristic struct {
	seed int64
}

// NewRandomHeuristic creates a random heuristic
func NewRandomHeuristic(seed int64) *RandomHeuristic {
	return &RandomHeuristic{seed: seed}
}

// SelectLiteral selects a random unassigned variable
func (rh *RandomHeuristic) SelectLiteral(unassigned []propagation.Unit) (propagation.Unit, bool) {
	if len(unassigned) == 0 {
		return 0, false
	}

	// Simple pseudo-random selection based on seed
	idx := int(rh.seed) % len(unassigned)
	rh.seed = (rh.seed*1103515245 + 12345) % (1 << 31)
	return unassigned[idx], true
}

// NotifyConflict does nothing for random heuristic
func (rh *RandomHeuristic) NotifyConflict(units []propagation.Unit) {
	// No-op for random
}

// Decay does nothing for random heuristic
func (rh *RandomHeuristic) Decay() {
	// No-op for random
}

// GetActivity returns 0 for random heuristic
func (rh *RandomHeuristic) GetActivity(unit propagation.Unit) float64 {
	return 0.0
}

// MostConstrainedHeuristic selects variables involved in most clauses
type MostConstrainedHeuristic struct {
	clauseCount map[propagation.Unit]int
}

// NewMostConstrainedHeuristic creates a most-constrained heuristic
func NewMostConstrainedHeuristic() *MostConstrainedHeuristic {
	return &MostConstrainedHeuristic{
		clauseCount: make(map[propagation.Unit]int),
	}
}

// SelectLiteral selects the most constrained variable
func (mch *MostConstrainedHeuristic) SelectLiteral(unassigned []propagation.Unit) (propagation.Unit, bool) {
	if len(unassigned) == 0 {
		return 0, false
	}

	sort.Slice(unassigned, func(i, j int) bool {
		countI := mch.clauseCount[unassigned[i]]
		countJ := mch.clauseCount[unassigned[j]]
		return countI > countJ
	})

	return unassigned[0], true
}

// NotifyConflict updates clause counts
func (mch *MostConstrainedHeuristic) NotifyConflict(units []propagation.Unit) {
	for _, unit := range units {
		if unit == 0 {
			continue
		}
		absUnit := propagation.Unit(abs(int(unit)))
		mch.clauseCount[absUnit]++
	}
}

// Decay periodically resets clause counts
func (mch *MostConstrainedHeuristic) Decay() {
	// Reduce all counts by half for recency bias
	for unit := range mch.clauseCount {
		mch.clauseCount[unit] = mch.clauseCount[unit] / 2
	}
}

// GetActivity returns clause count as activity
func (mch *MostConstrainedHeuristic) GetActivity(unit propagation.Unit) float64 {
	absUnit := propagation.Unit(abs(int(unit)))
	return float64(mch.clauseCount[absUnit])
}

// StaticHeuristic selects variables in fixed order
type StaticHeuristic struct {
	order   []propagation.Unit
	orderIdx int
}

// NewStaticHeuristic creates a static ordering heuristic
func NewStaticHeuristic(order []propagation.Unit) *StaticHeuristic {
	return &StaticHeuristic{
		order:    order,
		orderIdx: 0,
	}
}

// SelectLiteral selects next variable in static order
func (sh *StaticHeuristic) SelectLiteral(unassigned []propagation.Unit) (propagation.Unit, bool) {
	if len(unassigned) == 0 {
		return 0, false
	}

	// Linear scan for next unassigned in order
	for _, orderedUnit := range sh.order {
		for _, unassignedUnit := range unassigned {
			if orderedUnit == unassignedUnit {
				return orderedUnit, true
			}
		}
	}

	// Fallback: return first unassigned if order doesn't match
	return unassigned[0], true
}

// NotifyConflict does nothing for static heuristic
func (sh *StaticHeuristic) NotifyConflict(units []propagation.Unit) {
	// No-op
}

// Decay does nothing for static heuristic
func (sh *StaticHeuristic) Decay() {
	// No-op
}

// GetActivity returns 0 for static heuristic
func (sh *StaticHeuristic) GetActivity(unit propagation.Unit) float64 {
	return 0.0
}

// HybridHeuristic combines multiple strategies
type HybridHeuristic struct {
	primary   Heuristic
	secondary Heuristic
	switchAt  int
	switchCtr int
}

// NewHybridHeuristic creates a hybrid heuristic
func NewHybridHeuristic(primary, secondary Heuristic, switchAt int) *HybridHeuristic {
	return &HybridHeuristic{
		primary:   primary,
		secondary: secondary,
		switchAt:  switchAt,
		switchCtr: 0,
	}
}

// SelectLiteral delegates to primary or secondary based on conflict count
func (hh *HybridHeuristic) SelectLiteral(unassigned []propagation.Unit) (propagation.Unit, bool) {
	if hh.switchCtr < hh.switchAt {
		return hh.primary.SelectLiteral(unassigned)
	}
	return hh.secondary.SelectLiteral(unassigned)
}

// NotifyConflict increments counter and notifies both heuristics
func (hh *HybridHeuristic) NotifyConflict(units []propagation.Unit) {
	hh.switchCtr++
	hh.primary.NotifyConflict(units)
	hh.secondary.NotifyConflict(units)
}

// Decay calls decay on both heuristics
func (hh *HybridHeuristic) Decay() {
	hh.primary.Decay()
	hh.secondary.Decay()
}

// GetActivity returns primary activity
func (hh *HybridHeuristic) GetActivity(unit propagation.Unit) float64 {
	return hh.primary.GetActivity(unit)
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
