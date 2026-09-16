package propagation

import (
	"fmt"
)

// Unit represents a single proposition or atom identifier
type Unit int

// Assignment represents variable assignments during solving
type Assignment struct {
	value      map[Unit]bool // true = satisfied, false = unsatisfied, absent = unassigned
	assignedAt map[Unit]int  // decision level when assigned
}

// NewAssignment creates a new assignment tracker
func NewAssignment() *Assignment {
	return &Assignment{
		value:      make(map[Unit]bool),
		assignedAt: make(map[Unit]int),
	}
}

// Assign sets a unit to a truth value at given decision level
func (a *Assignment) Assign(unit Unit, value bool, level int) error {
	if _, exists := a.value[unit]; exists {
		// Already assigned; check for conflict
		if a.value[unit] != value {
			return fmt.Errorf("conflict: unit %d already assigned to %v, attempted %v", unit, a.value[unit], value)
		}
		return nil
	}
	a.value[unit] = value
	a.assignedAt[unit] = level
	return nil
}

// IsAssigned checks if a unit has been assigned
func (a *Assignment) IsAssigned(unit Unit) bool {
	_, exists := a.value[unit]
	return exists
}

// GetValue returns the assigned value for a unit
func (a *Assignment) GetValue(unit Unit) (bool, bool) {
	val, exists := a.value[unit]
	return val, exists
}

// GetLevel returns the decision level at which a unit was assigned
func (a *Assignment) GetLevel(unit Unit) int {
	level, exists := a.assignedAt[unit]
	if !exists {
		return -1
	}
	return level
}

// Unassign removes an assignment (used during backtracking)
func (a *Assignment) Unassign(unit Unit) {
	delete(a.value, unit)
	delete(a.assignedAt, unit)
}

// Copy creates a shallow copy of assignments
func (a *Assignment) Copy() *Assignment {
	newVal := make(map[Unit]bool)
	newLevel := make(map[Unit]int)
	for k, v := range a.value {
		newVal[k] = v
	}
	for k, v := range a.assignedAt {
		newLevel[k] = v
	}
	return &Assignment{
		value:      newVal,
		assignedAt: newLevel,
	}
}

// Clause represents a disjunctive clause (disjunction of literals)
type Clause struct {
	Literals []Unit // Positive unit = positive literal, negative = negated
	Learned  bool
	Activity float64
}

// NewClause creates a new clause
func NewClause(lits []Unit, learned bool) *Clause {
	return &Clause{
		Literals: lits,
		Learned:  learned,
		Activity: 0.0,
	}
}

// IsSatisfied checks if clause is satisfied under current assignment
func (c *Clause) IsSatisfied(a *Assignment) bool {
	for _, lit := range c.Literals {
		unit := Unit(abs(int(lit)))
		positive := lit > 0
		if val, assigned := a.GetValue(unit); assigned {
			if val == positive {
				return true
			}
		}
	}
	return false
}

// UnitPropagation finds unit to propagate (when clause has single unassigned)
func (c *Clause) UnitToPropagate(a *Assignment) (Unit, bool) {
	unassignedCount := 0
	var unassignedLit Unit

	for _, lit := range c.Literals {
		unit := Unit(abs(int(lit)))
		positive := lit > 0

		if !a.IsAssigned(unit) {
			unassignedCount++
			unassignedLit = lit
			if unassignedCount > 1 {
				return 0, false
			}
		} else {
			val, _ := a.GetValue(unit)
			// If literal is satisfied, clause is satisfied
			if val == positive {
				return 0, false
			}
		}
	}

	if unassignedCount == 1 {
		return unassignedLit, true
	}
	return 0, false
}

// Nogood represents a conflict clause (learned constraint)
type Nogood struct {
	Literals []Unit
	Level    int // Decision level when learned
}

// Propagator handles constraint propagation
type Propagator struct {
	clauses      []*Clause
	assignment   *Assignment
	trail        []Unit           // Trail of assignments in order
	decisionLevel int
	watchLists   map[Unit][]int   // Index of clauses watched per literal
	implications []Unit           // Implications to propagate
}

// NewPropagator creates a new propagator
func NewPropagator() *Propagator {
	return &Propagator{
		clauses:      make([]*Clause, 0),
		assignment:   NewAssignment(),
		trail:        make([]Unit, 0),
		decisionLevel: 0,
		watchLists:   make(map[Unit][]int),
		implications: make([]Unit, 0),
	}
}

// AddClause adds a clause to the propagator
func (p *Propagator) AddClause(c *Clause) error {
	if len(c.Literals) == 0 {
		return fmt.Errorf("empty clause")
	}

	p.clauses = append(p.clauses, c)
	idx := len(p.clauses) - 1

	// Initialize watch lists for first two literals
	if len(c.Literals) >= 1 {
		p.watchLists[c.Literals[0]] = append(p.watchLists[c.Literals[0]], idx)
	}
	if len(c.Literals) >= 2 {
		p.watchLists[c.Literals[1]] = append(p.watchLists[c.Literals[1]], idx)
	}

	return nil
}

// Propagate performs unit propagation
func (p *Propagator) Propagate() ([]Nogood, error) {
	conflicts := make([]Nogood, 0)

	for len(p.implications) > 0 {
		lit := p.implications[0]
		p.implications = p.implications[1:]

		unit := Unit(abs(int(lit)))
		positive := lit > 0

		// Check all watched clauses
		for _, clauseIdx := range p.watchLists[lit] {
			clause := p.clauses[clauseIdx]

			if clause.IsSatisfied(p.assignment) {
				continue
			}

			// Try to find another literal to watch
			found := false
			for _, otherLit := range clause.Literals {
				unit := Unit(abs(int(otherLit)))
				if !p.assignment.IsAssigned(unit) || !p.clauseConflicts(clause, otherLit) {
					found = true
					break
				}
			}

			if !found {
				// Clause is unit or conflict
				unitLit, canPropagate := clause.UnitToPropagate(p.assignment)
				if canPropagate {
					p.implications = append(p.implications, unitLit)
				} else if !clause.IsSatisfied(p.assignment) {
					// Conflict
					conflicts = append(conflicts, Nogood{
						Literals: clause.Literals,
						Level:    p.decisionLevel,
					})
				}
			}
		}
	}

	return conflicts, nil
}

// clauseConflicts checks if assigning lit to positive creates conflict
func (p *Propagator) clauseConflicts(c *Clause, lit Unit) bool {
	unit := Unit(abs(int(lit)))
	positive := lit > 0

	val, assigned := p.assignment.GetValue(unit)
	if !assigned {
		return false
	}
	return val != positive
}

// Assign assigns a unit at current decision level
func (p *Propagator) Assign(unit Unit, value bool) error {
	lit := unit
	if !value {
		lit = -unit
	}
	p.implications = append(p.implications, lit)
	return p.assignment.Assign(unit, value, p.decisionLevel)
}

// DecideVariable makes a decision on an unassigned variable
func (p *Propagator) DecideVariable(unit Unit, value bool) error {
	p.decisionLevel++
	return p.Assign(unit, value)
}

// Backtrack undoes all assignments at levels > targetLevel
func (p *Propagator) Backtrack(targetLevel int) error {
	if targetLevel < 0 {
		targetLevel = 0
	}

	unitsToBacktrack := make([]Unit, 0)

	for unit, level := range p.assignment.assignedAt {
		if level > targetLevel {
			unitsToBacktrack = append(unitsToBacktrack, unit)
		}
	}

	for _, unit := range unitsToBacktrack {
		p.assignment.Unassign(unit)
	}

	if p.decisionLevel > targetLevel {
		p.decisionLevel = targetLevel
	}

	p.implications = make([]Unit, 0)
	p.trail = make([]Unit, 0)

	return nil
}

// GetAssignment returns current assignment
func (p *Propagator) GetAssignment() *Assignment {
	return p.assignment
}

// GetDecisionLevel returns current decision level
func (p *Propagator) GetDecisionLevel() int {
	return p.decisionLevel
}

// GetTrail returns the assignment trail
func (p *Propagator) GetTrail() []Unit {
	return p.trail
}

// GetUnassignedUnits returns all unassigned units
func (p *Propagator) GetUnassignedUnits(allUnits []Unit) []Unit {
	unassigned := make([]Unit, 0)
	for _, unit := range allUnits {
		if !p.assignment.IsAssigned(unit) {
			unassigned = append(unassigned, unit)
		}
	}
	return unassigned
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
