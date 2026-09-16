// Package ir provides the intermediate representation for ASP grounding and solving
// This file defines the IR types that represent ground atoms, rules, and constraints
package ir

import "fmt"

// ConstantType represents the type of a constant value
type ConstantType int

const (
	CONST_INT ConstantType = iota
	CONST_FLOAT
	CONST_STRING
	CONST_ATOM
)

// Constant represents a typed constant value
type Constant struct {
	Type  ConstantType
	Value interface{}
}

func (c *Constant) String() string {
	return fmt.Sprintf("%v", c.Value)
}

// GroundAtom represents a fully ground atom (base unit of ASP solver state)
type GroundAtom struct {
	ID        uint64        // Unique identifier
	Predicate string        // Predicate name (e.g., "parent")
	Args      []Constant    // Fully ground arguments
}

func (ga *GroundAtom) String() string {
	if len(ga.Args) == 0 {
		return ga.Predicate
	}
	result := ga.Predicate + "("
	for i, arg := range ga.Args {
		if i > 0 {
			result += ", "
		}
		result += fmt.Sprintf("%v", arg.Value)
	}
	result += ")"
	return result
}

// GroundLiteral represents a ground atom with sign (positive or negated)
type GroundLiteral struct {
	Positive bool        // true = atom, false = ¬atom
	Atom     *GroundAtom
}

func (gl *GroundLiteral) String() string {
	if gl.Positive {
		return gl.Atom.String()
	}
	return "not " + gl.Atom.String()
}

// RuleType represents the classification of a ground rule
type RuleType int

const (
	RULE_NORMAL RuleType = iota
	RULE_CHOICE
	RULE_CONSTRAINT
	RULE_WEAK
	RULE_FACT
)

// GroundRule represents a fully instantiated ASP rule
type GroundRule struct {
	ID        uint64           // Unique identifier
	Head      []*GroundAtom    // Disjunctive head (for choice rules, may be multiple)
	Body      []*GroundLiteral // Conjunction of literals
	Type      RuleType         // Classification of the rule
	SourcePos string           // Source position for debugging
}

func (gr *GroundRule) String() string {
	if len(gr.Head) == 0 {
		// Constraint
		result := ":- "
		for i, lit := range gr.Body {
			if i > 0 {
				result += ", "
			}
			result += lit.String()
		}
		result += "."
		return result
	}

	// Normal or choice rule
	result := ""
	for i, atom := range gr.Head {
		if i > 0 {
			result += " | "
		}
		result += atom.String()
	}
	result += " :- "
	for i, lit := range gr.Body {
		if i > 0 {
			result += ", "
		}
		result += lit.String()
	}
	result += "."
	return result
}

// Literal represents a SAT-like literal (ground atom with sign)
type Literal struct {
	Positive bool   // true = positive, false = negative
	AtomID   uint64 // Reference to ground atom ID
}

// Clause represents a disjunctive clause (SAT-like form)
type Clause struct {
	ID        uint64      // Unique identifier
	Literals  []Literal   // Disjunction of literals
	Source    *GroundRule // Original ground rule
	LearnedAt uint        // Decision level when learned (0 if from grounding)
}

// Nogood represents a constraint (clause that must have at least one false literal)
type Nogood struct {
	ID       uint64        // Unique identifier
	Literals []Literal     // Conjunction of negated literals
	Source   interface{}   // GroundRule, Aggregate, or WeakConstraint
}

// Domain represents the Herbrand universe for grounding
type Domain struct {
	Atoms              map[string][]*GroundAtom // Ground atoms by predicate
	PredicateArity     map[string]int            // Predicate name -> arity mapping
	Constants          map[string]Constant      // String representations to constants
	AtomsByID          map[uint64]*GroundAtom   // Quick lookup by ID
	NextAtomID         uint64                   // Counter for atom IDs
}

// NewDomain creates a new domain
func NewDomain() *Domain {
	return &Domain{
		Atoms:          make(map[string][]*GroundAtom),
		PredicateArity: make(map[string]int),
		Constants:      make(map[string]Constant),
		AtomsByID:      make(map[uint64]*GroundAtom),
		NextAtomID:     1,
	}
}

// RegisterAtom adds a ground atom to the domain
func (d *Domain) RegisterAtom(atom *GroundAtom) {
	if atom.ID == 0 {
		atom.ID = d.NextAtomID
		d.NextAtomID++
	}
	d.AtomsByID[atom.ID] = atom
	d.Atoms[atom.Predicate] = append(d.Atoms[atom.Predicate], atom)
}

// GetAtom retrieves a ground atom by ID
func (d *Domain) GetAtom(id uint64) (*GroundAtom, bool) {
	atom, ok := d.AtomsByID[id]
	return atom, ok
}
