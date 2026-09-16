// Package ground provides substitution and term manipulation utilities
package ground

import (
	"fmt"
	"reflect"
	"sort"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/ir"
)

// Substitution represents a mapping from variables to terms
type Substitution struct {
	bindings map[string]ast.Term
	sorted   []string
}

// NewSubstitution creates an empty substitution
func NewSubstitution() *Substitution {
	return &Substitution{
		bindings: make(map[string]ast.Term),
		sorted:   make([]string, 0),
	}
}

// Bind adds a variable-term binding
func (s *Substitution) Bind(variable string, term ast.Term) error {
	if variable == "_" {
		return fmt.Errorf("cannot bind anonymous variable")
	}

	// Check for conflict
	if existing, ok := s.bindings[variable]; ok {
		if !s.termsEqual(existing, term) {
			return fmt.Errorf("conflicting binding for %s: %v vs %v", variable, existing, term)
		}
		return nil
	}

	s.bindings[variable] = term
	s.invalidateSorted()
	return nil
}

// Get retrieves a binding
func (s *Substitution) Get(variable string) (ast.Term, bool) {
	term, ok := s.bindings[variable]
	return term, ok
}

// Has checks if a variable is bound
func (s *Substitution) Has(variable string) bool {
	_, ok := s.bindings[variable]
	return ok
}

// Apply substitutes variables in a term
func (s *Substitution) Apply(term ast.Term) ast.Term {
	switch t := term.(type) {
	case *ast.Variable:
		if t.Name == "_" {
			return t
		}
		if bound, ok := s.bindings[t.Name]; ok {
			// Follow chains
			return s.Apply(bound)
		}
		return t

	case *ast.Compound:
		appliedArgs := make([]ast.Term, len(t.Args))
		changed := false
		for i, arg := range t.Args {
			applied := s.Apply(arg)
			appliedArgs[i] = applied
			if !reflect.DeepEqual(arg, applied) {
				changed = true
			}
		}
		if !changed {
			return t
		}
		return &ast.Compound{
			Functor: t.Functor,
			Args:    appliedArgs,
			Pos:     t.Pos,
		}

	case *ast.Constant:
		return t

	case *ast.Atom:
		return t

	default:
		return term
	}
}

// ApplyToLiteral applies substitution to a literal
func (s *Substitution) ApplyToLiteral(lit *ast.Literal) *ast.Literal {
	if lit == nil {
		return nil
	}

	appliedArgs := make([]ast.Term, len(lit.Args))
	changed := false

	for i, arg := range lit.Args {
		applied := s.Apply(arg)
		appliedArgs[i] = applied
		if !reflect.DeepEqual(arg, applied) {
			changed = true
		}
	}

	if !changed {
		return lit
	}

	return &ast.Literal{
		Positive:  lit.Positive,
		Atom:      lit.Atom,
		Args:      appliedArgs,
		Aggregate: lit.Aggregate,
		Pos:       lit.Pos,
	}
}

// ApplyToRule applies substitution to a rule
func (s *Substitution) ApplyToRule(rule *ast.Rule) *ast.Rule {
	if rule == nil {
		return nil
	}

	// Apply to head
	var appliedHead *ast.Head
	if rule.Head != nil {
		appliedHeadAtoms := make([]*ast.HeadAtom, len(rule.Head.Atoms))
		changed := false

		for i, headAtom := range rule.Head.Atoms {
			appliedArgs := make([]ast.Term, len(headAtom.Args))
			atomChanged := false

			for j, arg := range headAtom.Args {
				applied := s.Apply(arg)
				appliedArgs[j] = applied
				if !reflect.DeepEqual(arg, applied) {
					atomChanged = true
				}
			}

			if atomChanged {
				changed = true
				appliedHeadAtoms[i] = &ast.HeadAtom{
					Atom: headAtom.Atom,
					Args: appliedArgs,
					Pos:  headAtom.Pos,
				}
			} else {
				appliedHeadAtoms[i] = headAtom
			}
		}

		if changed {
			appliedHead = &ast.Head{
				Atoms: appliedHeadAtoms,
				Type:  rule.Head.Type,
				Pos:   rule.Head.Pos,
			}
		} else {
			appliedHead = rule.Head
		}
	}

	// Apply to body
	appliedBody := make([]*ast.Literal, len(rule.Body))
	bodyChanged := false

	for i, lit := range rule.Body {
		applied := s.ApplyToLiteral(lit)
		appliedBody[i] = applied
		if !reflect.DeepEqual(lit, applied) {
			bodyChanged = true
		}
	}

	if appliedHead == rule.Head && !bodyChanged {
		return rule
	}

	if appliedHead == nil {
		appliedHead = rule.Head
	}

	return &ast.Rule{
		ID:   rule.ID,
		Head: appliedHead,
		Body: appliedBody,
		Type: rule.Type,
		Pos:  rule.Pos,
	}
}

// Compose combines two substitutions
func (s *Substitution) Compose(other *Substitution) *Substitution {
	result := NewSubstitution()

	// Add all bindings from s, applied through other
	for v, t := range s.bindings {
		result.bindings[v] = other.Apply(t)
	}

	// Add bindings from other that are not in s
	for v, t := range other.bindings {
		if _, exists := result.bindings[v]; !exists {
			result.bindings[v] = t
		}
	}

	result.invalidateSorted()
	return result
}

// Restrict creates a new substitution with only given variables
func (s *Substitution) Restrict(variables []string) *Substitution {
	result := NewSubstitution()
	for _, v := range variables {
		if term, ok := s.bindings[v]; ok {
			result.bindings[v] = term
		}
	}
	result.invalidateSorted()
	return result
}

// Size returns the number of bindings
func (s *Substitution) Size() int {
	return len(s.bindings)
}

// IsEmpty checks if substitution is empty
func (s *Substitution) IsEmpty() bool {
	return len(s.bindings) == 0
}

// Variables returns all bound variables in sorted order
func (s *Substitution) Variables() []string {
	if len(s.sorted) == 0 {
		s.sorted = make([]string, 0, len(s.bindings))
		for v := range s.bindings {
			s.sorted = append(s.sorted, v)
		}
		sort.Strings(s.sorted)
	}
	return s.sorted
}

// Copy creates a deep copy of the substitution
func (s *Substitution) Copy() *Substitution {
	result := NewSubstitution()
	for v, t := range s.bindings {
		result.bindings[v] = t
	}
	result.sorted = append([]string{}, s.sorted...)
	return result
}

// String returns string representation
func (s *Substitution) String() string {
	if s.IsEmpty() {
		return "{}"
	}

	result := "{"
	vars := s.Variables()
	for i, v := range vars {
		if i > 0 {
			result += ", "
		}
		result += fmt.Sprintf("%s/%v", v, s.bindings[v])
	}
	result += "}"
	return result
}

// termsEqual checks if two terms are equal
func (s *Substitution) termsEqual(t1, t2 ast.Term) bool {
	switch v1 := t1.(type) {
	case *ast.Variable:
		v2, ok := t2.(*ast.Variable)
		return ok && v1.Name == v2.Name

	case *ast.Constant:
		v2, ok := t2.(*ast.Constant)
		return ok && v1.Type == v2.Type && v1.Value == v2.Value

	case *ast.Atom:
		v2, ok := t2.(*ast.Atom)
		return ok && v1.Name == v2.Name

	case *ast.Compound:
		v2, ok := t2.(*ast.Compound)
		if !ok || v1.Functor != v2.Functor || len(v1.Args) != len(v2.Args) {
			return false
		}
		for i, arg := range v1.Args {
			if !s.termsEqual(arg, v2.Args[i]) {
				return false
			}
		}
		return true

	default:
		return reflect.DeepEqual(t1, t2)
	}
}

// invalidateSorted marks sorted cache as invalid
func (s *Substitution) invalidateSorted() {
	s.sorted = nil
}

// Unifier attempts to unify two terms
type Unifier struct {
	sub Substitution
}

// NewUnifier creates a new unifier
func NewUnifier() *Unifier {
	return &Unifier{
		sub: Substitution{
			bindings: make(map[string]ast.Term),
		},
	}
}

// Unify unifies two terms, returning resulting substitution or error
func (u *Unifier) Unify(t1, t2 ast.Term) (*Substitution, error) {
	u.sub.bindings = make(map[string]ast.Term)

	if err := u.unifyTerms(t1, t2); err != nil {
		return nil, err
	}

	return u.sub.Copy(), nil
}

// unifyTerms recursively unifies terms
func (u *Unifier) unifyTerms(t1, t2 ast.Term) error {
	// Apply current substitution
	t1 = u.sub.Apply(t1)
	t2 = u.sub.Apply(t2)

	// Same term
	if reflect.DeepEqual(t1, t2) {
		return nil
	}

	// Variable cases
	if v1, ok := t1.(*ast.Variable); ok {
		if v1.Name == "_" {
			return nil
		}
		return u.bind(v1.Name, t2)
	}

	if v2, ok := t2.(*ast.Variable); ok {
		if v2.Name == "_" {
			return nil
		}
		return u.bind(v2.Name, t1)
	}

	// Compound case
	c1, ok1 := t1.(*ast.Compound)
	c2, ok2 := t2.(*ast.Compound)

	if ok1 && ok2 {
		if c1.Functor != c2.Functor || len(c1.Args) != len(c2.Args) {
			return fmt.Errorf("cannot unify %v with %v", t1, t2)
		}

		for i := range c1.Args {
			if err := u.unifyTerms(c1.Args[i], c2.Args[i]); err != nil {
				return err
			}
		}
		return nil
	}

	// Atom case
	a1, ok1 := t1.(*ast.Atom)
	a2, ok2 := t2.(*ast.Atom)

	if ok1 && ok2 {
		if a1.Name != a2.Name {
			return fmt.Errorf("cannot unify atoms %s and %s", a1.Name, a2.Name)
		}
		return nil
	}

	// Constant case
	c1, ok1 := t1.(*ast.Constant)
	c2, ok2 := t2.(*ast.Constant)

	if ok1 && ok2 {
		if c1.Type != c2.Type || c1.Value != c2.Value {
			return fmt.Errorf("cannot unify constants %v and %v", c1.Value, c2.Value)
		}
		return nil
	}

	return fmt.Errorf("cannot unify %T with %T", t1, t2)
}

// bind adds a variable-term binding with occurs check
func (u *Unifier) bind(variable string, term ast.Term) error {
	// Occurs check: prevent infinite structures
	if u.occursIn(variable, term) {
		return fmt.Errorf("occurs check failed: %s occurs in %v", variable, term)
	}

	return u.sub.Bind(variable, term)
}

// occursIn checks if variable occurs in term
func (u *Unifier) occursIn(variable string, term ast.Term) bool {
	switch t := term.(type) {
	case *ast.Variable:
		return t.Name == variable
	case *ast.Compound:
		for _, arg := range t.Args {
			if u.occursIn(variable, arg) {
				return true
			}
		}
		return false
	default:
		return false
	}
}

// GroundTermConverter converts between AST and IR terms
type GroundTermConverter struct {
	constants map[string]ir.Constant
}

// NewGroundTermConverter creates a new converter
func NewGroundTermConverter() *GroundTermConverter {
	return &GroundTermConverter{
		constants: make(map[string]ir.Constant),
	}
}

// ToIRConstant converts AST term to IR constant
func (gtc *GroundTermConverter) ToIRConstant(term ast.Term) (*ir.Constant, error) {
	switch t := term.(type) {
	case *ast.Constant:
		irType := ir.CONST_INT
		switch t.Type {
		case ast.CONST_INT:
			irType = ir.CONST_INT
		case ast.CONST_FLOAT:
			irType = ir.CONST_FLOAT
		case ast.CONST_STRING:
			irType = ir.CONST_STRING
		}
		return &ir.Constant{Type: irType, Value: t.Value}, nil

	case *ast.Atom:
		return &ir.Constant{Type: ir.CONST_ATOM, Value: t.Name}, nil

	case *ast.Variable:
		return nil, fmt.Errorf("cannot convert unbound variable: %s", t.Name)

	default:
		return nil, fmt.Errorf("unknown term type: %T", term)
	}
}

// ToIRConstants converts a slice of AST terms to IR constants
func (gtc *GroundTermConverter) ToIRConstants(terms []ast.Term) ([]ir.Constant, error) {
	result := make([]ir.Constant, 0, len(terms))

	for _, term := range terms {
		c, err := gtc.ToIRConstant(term)
		if err != nil {
			return nil, err
		}
		result = append(result, *c)
	}

	return result, nil
}

// TermRenamer renames variables in terms
type TermRenamer struct {
	mapping map[string]string
}

// NewTermRenamer creates a new term renamer
func NewTermRenamer(mapping map[string]string) *TermRenamer {
	return &TermRenamer{
		mapping: mapping,
	}
}

// Rename renames variables in a term
func (tr *TermRenamer) Rename(term ast.Term) ast.Term {
	switch t := term.(type) {
	case *ast.Variable:
		if newName, ok := tr.mapping[t.Name]; ok {
			return &ast.Variable{Name: newName, Pos: t.Pos}
		}
		return t

	case *ast.Compound:
		renamedArgs := make([]ast.Term, len(t.Args))
		for i, arg := range t.Args {
			renamedArgs[i] = tr.Rename(arg)
		}
		return &ast.Compound{
			Functor: t.Functor,
			Args:    renamedArgs,
			Pos:     t.Pos,
		}

	default:
		return term
	}
}

// RenameLiteral renames variables in a literal
func (tr *TermRenamer) RenameLiteral(lit *ast.Literal) *ast.Literal {
	if lit == nil {
		return nil
	}

	renamedArgs := make([]ast.Term, len(lit.Args))
	for i, arg := range lit.Args {
		renamedArgs[i] = tr.Rename(arg)
	}

	return &ast.Literal{
		Positive:  lit.Positive,
		Atom:      lit.Atom,
		Args:      renamedArgs,
		Aggregate: lit.Aggregate,
		Pos:       lit.Pos,
	}
}

// RenameRule renames variables in a rule
func (tr *TermRenamer) RenameRule(rule *ast.Rule) *ast.Rule {
	if rule == nil {
		return nil
	}

	// Rename head
	var renamedHead *ast.Head
	if rule.Head != nil {
		renamedAtoms := make([]*ast.HeadAtom, len(rule.Head.Atoms))
		for i, atom := range rule.Head.Atoms {
			renamedArgs := make([]ast.Term, len(atom.Args))
			for j, arg := range atom.Args {
				renamedArgs[j] = tr.Rename(arg)
			}
			renamedAtoms[i] = &ast.HeadAtom{
				Atom: atom.Atom,
				Args: renamedArgs,
				Pos:  atom.Pos,
			}
		}
		renamedHead = &ast.Head{
			Atoms: renamedAtoms,
			Type:  rule.Head.Type,
			Pos:   rule.Head.Pos,
		}
	}

	// Rename body
	renamedBody := make([]*ast.Literal, len(rule.Body))
	for i, lit := range rule.Body {
		renamedBody[i] = tr.RenameLiteral(lit)
	}

	return &ast.Rule{
		ID:   rule.ID,
		Head: renamedHead,
		Body: renamedBody,
		Type: rule.Type,
		Pos:  rule.Pos,
	}
}
