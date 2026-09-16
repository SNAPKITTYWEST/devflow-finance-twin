package ast

import "fmt"

// Position represents source code location for error reporting
type Position struct {
	File   string
	Line   int
	Column int
	Offset int
}

func (p Position) String() string {
	return fmt.Sprintf("%s:%d:%d", p.File, p.Line, p.Column)
}

// Node is the base interface for all AST nodes
type Node interface {
	node() // Marker interface
}

// ============================================================
// TERMS
// ============================================================

// Term represents a logic term (atom, variable, compound, constant)
type Term interface {
	Node
	term() // Marker interface
}

// Atom represents a logical atom (e.g., 'foo', 'parent')
type Atom struct {
	Name string
	Pos  Position
}

func (a *Atom) node() {}
func (a *Atom) term() {}

// Variable represents a logic variable (e.g., X, Var, _)
type Variable struct {
	Name string
	Pos  Position
}

func (v *Variable) node() {}
func (v *Variable) term() {}

// Constant represents typed constants (INT, FLOAT, STRING)
type Constant struct {
	Type  ConstantType
	Value interface{}
	Pos   Position
}

type ConstantType int

const (
	CONST_INT ConstantType = iota
	CONST_FLOAT
	CONST_STRING
)

func (c *Constant) node() {}
func (c *Constant) term() {}

// Compound represents compound terms (e.g., f(a, b, c))
type Compound struct {
	Functor string
	Args    []Term
	Pos     Position
}

func (c *Compound) node() {}
func (c *Compound) term() {}

// ============================================================
// LITERALS
// ============================================================

// Literal represents a positive or negated atom with optional aggregate
type Literal struct {
	Positive  bool         // true = atom, false = negation-as-failure
	Atom      *Atom
	Args      []Term
	Aggregate *Aggregate
	Pos       Position
}

func (l *Literal) node() {}

// ============================================================
// AGGREGATES
// ============================================================

// AggregateOp represents aggregate operation type
type AggregateOp string

const (
	AGG_COUNT AggregateOp = "count"
	AGG_SUM   AggregateOp = "sum"
	AGG_MIN   AggregateOp = "min"
	AGG_MAX   AggregateOp = "max"
)

// Aggregate represents aggregate expressions (#count, #sum, etc.)
type Aggregate struct {
	Op       AggregateOp
	Variables []Term
	Condition *Literal
	Bound     *AggregateBound
	Pos       Position
}

func (a *Aggregate) node() {}

// AggregateBound represents aggregate bounds (e.g., N { count } M)
type AggregateBound struct {
	Lower     *Term
	Upper     *Term
	Pos       Position
}

// ============================================================
// HEADS
// ============================================================

// Head represents rule head (normal or choice)
type Head struct {
	Atoms    []*HeadAtom
	Type     HeadType
	Pos      Position
}

type HeadType int

const (
	HEAD_NORMAL HeadType = iota
	HEAD_CHOICE
	HEAD_DISJUNCTIVE
)

// HeadAtom represents individual atom in rule head
type HeadAtom struct {
	Atom *Atom
	Args []Term
	Pos  Position
}

// ============================================================
// RULES
// ============================================================

// Rule represents a logic rule (facts, rules, choice rules, constraints)
type Rule struct {
	ID       uint64
	Head     *Head
	Body     []*Literal
	Type     RuleType
	Pos      Position
}

type RuleType int

const (
	RULE_NORMAL RuleType = iota
	RULE_CHOICE
	RULE_CONSTRAINT
	RULE_WEAK
	RULE_FACT
)

func (r *Rule) node() {}

// ============================================================
// STATEMENTS
// ============================================================

// Statement is base interface for program statements
type Statement interface {
	Node
	statement() // Marker interface
}

// RuleStatement wraps a rule in the statement interface
type RuleStatement struct {
	Rule *Rule
	Pos  Position
}

func (rs *RuleStatement) node()      {}
func (rs *RuleStatement) statement() {}

// Directive represents directives like #show, #hide, #assert
type Directive struct {
	Type      string
	Arguments []Term
	Pos       Position
}

func (d *Directive) node()      {}
func (d *Directive) statement() {}

// ============================================================
// PROGRAM
// ============================================================

// Program represents a complete ASP program
type Program struct {
	Statements []Statement
	Directives []Directive
	Pos        Position
}

func (p *Program) node() {}
