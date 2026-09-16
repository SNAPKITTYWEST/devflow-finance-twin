// Package ground implements grounding (instantiation) of ASP rules
// This converts AST rules with variables into ground rules with all possible substitutions
package ground

import (
	"fmt"
	"sort"
	"sync"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/ir"
)

// Grounder expands ASP rules into ground instances by instantiating all variables
type Grounder struct {
	mu             sync.RWMutex
	domain         *ir.Domain
	program        []ast.Statement
	groundRules    []*ir.GroundRule
	groundAtoms    map[string]*ir.GroundAtom
	rulesByHead    map[string][]*ir.GroundRule
	rulesByBody    map[string][]*ir.GroundRule
	safetyChecker  *SafetyChecker
	processedRules map[uint64]bool
	nextRuleID     uint64
	stats          *GroundingStats
}

// GroundingStats tracks statistics about the grounding process
type GroundingStats struct {
	TotalAtoms      int
	TotalRules      int
	TotalConstraints int
	ProcessingTime  int64
	DomainSize      int
}

// NewGrounder creates a new grounder instance
func NewGrounder() *Grounder {
	return &Grounder{
		domain:         ir.NewDomain(),
		program:        make([]ast.Statement, 0),
		groundRules:    make([]*ir.GroundRule, 0),
		groundAtoms:    make(map[string]*ir.GroundAtom),
		rulesByHead:    make(map[string][]*ir.GroundRule),
		rulesByBody:    make(map[string][]*ir.GroundRule),
		safetyChecker:  NewSafetyChecker(),
		processedRules: make(map[uint64]bool),
		nextRuleID:     1,
		stats:          &GroundingStats{},
	}
}

// GroundingResult represents the output of the grounding process
type GroundingResult struct {
	Rules       []*ir.GroundRule
	Atoms       []*ir.GroundAtom
	Domain      *ir.Domain
	Constraints []*ir.Nogood
	Stats       *GroundingStats
}

// Ground expands all rules in the program into ground instances
// Returns ground rules, atoms, and any grounding errors
func (g *Grounder) Ground(program []ast.Statement) ([]*ir.GroundRule, error) {
	g.mu.Lock()
	defer g.mu.Unlock()

	g.program = program
	g.groundRules = make([]*ir.GroundRule, 0)
	g.processedRules = make(map[uint64]bool)

	// Phase 1: Collect facts and discover domain
	if err := g.discoverDomain(); err != nil {
		return nil, fmt.Errorf("domain discovery failed: %w", err)
	}

	// Phase 2: Apply safety checks
	if err := g.checkSafety(); err != nil {
		return nil, fmt.Errorf("safety check failed: %w", err)
	}

	// Phase 3: Ground all rules
	if err := g.groundAllRules(); err != nil {
		return nil, fmt.Errorf("grounding failed: %w", err)
	}

	// Phase 4: Index grounded rules
	g.indexGroundedRules()

	return g.groundRules, nil
}

// discoverDomain extracts all facts and computes the Herbrand universe
func (g *Grounder) discoverDomain() error {
	facts := make(map[string][]*ast.Rule)

	// Extract all facts and collect domain information
	for _, stmt := range g.program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule

			// Register predicate arity
			if len(rule.Head.Atoms) > 0 {
				for _, headAtom := range rule.Head.Atoms {
					arity := len(headAtom.Args)
					predName := headAtom.Atom.Name
					if existing, ok := g.domain.PredicateArity[predName]; !ok {
						g.domain.PredicateArity[predName] = arity
					} else if existing != arity {
						return fmt.Errorf("predicate %s has inconsistent arity: %d vs %d",
							predName, existing, arity)
					}
				}
			}

			// Collect facts
			if rule.Type == ast.RULE_FACT || len(rule.Body) == 0 {
				if len(rule.Head.Atoms) > 0 {
					predName := rule.Head.Atoms[0].Atom.Name
					facts[predName] = append(facts[predName], rule)
				}
			}
		}
	}

	// Create ground atoms from facts
	for _, rules := range facts {
		for _, rule := range rules {
			if len(rule.Head.Atoms) > 0 {
				headAtom := rule.Head.Atoms[0]
				grAtom, err := g.createGroundAtom(headAtom.Atom.Name, headAtom.Args)
				if err != nil {
					return err
				}
				g.groundAtoms[grAtom.String()] = grAtom
				g.domain.RegisterAtom(grAtom)

				// Add fact as a ground rule
				gRule := &ir.GroundRule{
					ID:        g.nextRuleID,
					Head:      []*ir.GroundAtom{grAtom},
					Body:      make([]*ir.GroundLiteral, 0),
					Type:      ir.RULE_FACT,
					SourcePos: fmt.Sprintf("%v", rule.Pos),
				}
				g.nextRuleID++
				g.groundRules = append(g.groundRules, gRule)
				g.processedRules[rule.ID] = true
			}
		}
	}

	g.stats.DomainSize = len(g.groundAtoms)
	return nil
}

// checkSafety validates that all rules satisfy safety constraints
func (g *Grounder) checkSafety() error {
	for _, stmt := range g.program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule
			if rule.Type != ast.RULE_FACT && len(rule.Body) > 0 {
				if !g.safetyChecker.IsSafe(rule) {
					return fmt.Errorf("rule safety check failed: unsafe variables in rule at %v", rule.Pos)
				}
			}
		}
	}
	return nil
}

// groundAllRules instantiates all non-fact rules
func (g *Grounder) groundAllRules() error {
	for _, stmt := range g.program {
		if rs, ok := stmt.(*ast.RuleStatement); ok && rs.Rule != nil {
			rule := rs.Rule

			// Skip already processed facts
			if g.processedRules[rule.ID] {
				continue
			}

			// Ground non-fact rules
			if rule.Type != ast.RULE_FACT && len(rule.Body) > 0 {
				groundedRules, err := g.GroundRule(rule)
				if err != nil {
					return fmt.Errorf("failed to ground rule at %v: %w", rule.Pos, err)
				}
				g.groundRules = append(g.groundRules, groundedRules...)
			}
		}
	}
	return nil
}

// GroundRule expands a single ASP rule with all valid substitutions
func (g *Grounder) GroundRule(rule *ast.Rule) ([]*ir.GroundRule, error) {
	result := make([]*ir.GroundRule, 0)

	// Extract all variables from the rule
	vars := g.extractVariables(rule)

	// If no variables, just instantiate directly
	if len(vars) == 0 {
		gRule, err := g.instantiateRule(rule, make(map[string]ast.Term))
		if err != nil {
			return nil, err
		}
		if gRule != nil {
			result = append(result, gRule)
		}
		return result, nil
	}

	// Generate all substitutions for the variables
	substitutions := g.generateSubstitutions(vars, rule)

	// Instantiate rule for each substitution
	for _, subst := range substitutions {
		gRule, err := g.instantiateRule(rule, subst)
		if err != nil {
			return nil, err
		}
		if gRule != nil {
			result = append(result, gRule)
		}
	}

	return result, nil
}

// extractVariables collects all unique variables in a rule
func (g *Grounder) extractVariables(rule *ast.Rule) []string {
	varSet := make(map[string]bool)

	// Extract from head
	if rule.Head != nil {
		for _, headAtom := range rule.Head.Atoms {
			for _, arg := range headAtom.Args {
				if v, ok := arg.(*ast.Variable); ok && v.Name != "_" {
					varSet[v.Name] = true
				}
			}
		}
	}

	// Extract from body
	for _, lit := range rule.Body {
		if lit.Atom != nil {
			for _, arg := range lit.Args {
				if v, ok := arg.(*ast.Variable); ok && v.Name != "_" {
					varSet[v.Name] = true
				}
			}
		}
		if lit.Aggregate != nil {
			for _, aggVar := range lit.Aggregate.Variables {
				if v, ok := aggVar.(*ast.Variable); ok && v.Name != "_" {
					varSet[v.Name] = true
				}
			}
		}
	}

	// Convert to sorted slice for deterministic ordering
	vars := make([]string, 0, len(varSet))
	for v := range varSet {
		vars = append(vars, v)
	}
	sort.Strings(vars)
	return vars
}

// generateSubstitutions creates all valid variable assignments from domain
func (g *Grounder) generateSubstitutions(vars []string, rule *ast.Rule) []map[string]ast.Term {
	if len(vars) == 0 {
		return []map[string]ast.Term{make(map[string]ast.Term)}
	}

	// Collect domain values for each variable
	varDomains := make(map[string][]ast.Term)
	for _, v := range vars {
		varDomains[v] = g.getVariableDomain(rule)
	}

	// Generate cartesian product of all variable domains
	return g.cartesianProduct(vars, varDomains, 0)
}

// getVariableDomain returns all constants that can be bound to variables
func (g *Grounder) getVariableDomain(rule *ast.Rule) []ast.Term {
	domainSet := make(map[string]ast.Term)

	// Collect all constants from facts
	for _, atom := range g.domain.Atoms {
		for _, groundAtom := range atom {
			for _, arg := range groundAtom.Args {
				switch arg.Type {
				case ir.CONST_INT:
					const_ := &ast.Constant{
						Type:  ast.CONST_INT,
						Value: arg.Value,
					}
					domainSet[fmt.Sprintf("%v", arg.Value)] = const_
				case ir.CONST_STRING:
					const_ := &ast.Constant{
						Type:  ast.CONST_STRING,
						Value: arg.Value,
					}
					domainSet[fmt.Sprintf("%v", arg.Value)] = const_
				case ir.CONST_ATOM:
					atom := &ast.Atom{
						Name: fmt.Sprintf("%v", arg.Value),
					}
					domainSet[fmt.Sprintf("%v", arg.Value)] = atom
				}
			}
		}
	}

	// Convert to slice
	domain := make([]ast.Term, 0, len(domainSet))
	for _, term := range domainSet {
		domain = append(domain, term)
	}
	return domain
}

// cartesianProduct generates all combinations of variable assignments
func (g *Grounder) cartesianProduct(vars []string, domains map[string][]ast.Term, index int) []map[string]ast.Term {
	if index == len(vars) {
		return []map[string]ast.Term{make(map[string]ast.Term)}
	}

	v := vars[index]
	varDomain := domains[v]
	if len(varDomain) == 0 {
		// No domain values, skip variable
		return g.cartesianProduct(vars, domains, index+1)
	}

	subResults := g.cartesianProduct(vars, domains, index+1)
	result := make([]map[string]ast.Term, 0)

	for _, term := range varDomain {
		for _, subResult := range subResults {
			// Create new substitution with current variable assignment
			newSubst := make(map[string]ast.Term)
			for k, v := range subResult {
				newSubst[k] = v
			}
			newSubst[v] = term
			result = append(result, newSubst)
		}
	}
	return result
}

// instantiateRule creates a ground rule by applying a substitution
func (g *Grounder) instantiateRule(rule *ast.Rule, subst map[string]ast.Term) (*ir.GroundRule, error) {
	// Ground head atoms
	headAtoms := make([]*ir.GroundAtom, 0)
	if rule.Head != nil {
		for _, headAtom := range rule.Head.Atoms {
			gAtom, err := g.groundTerms(headAtom.Atom.Name, headAtom.Args, subst)
			if err != nil {
				return nil, err
			}
			if gAtom != nil {
				headAtoms = append(headAtoms, gAtom)
			}
		}
	}

	// Ground body literals
	bodyLiterals := make([]*ir.GroundLiteral, 0)
	for _, lit := range rule.Body {
		gLit, err := g.GroundLiteral(lit, subst)
		if err != nil {
			return nil, err
		}
		if gLit != nil {
			bodyLiterals = append(bodyLiterals, gLit)
		}
	}

	// Create ground rule
	gRule := &ir.GroundRule{
		ID:        g.nextRuleID,
		Head:      headAtoms,
		Body:      bodyLiterals,
		Type:      g.mapRuleType(rule.Type),
		SourcePos: fmt.Sprintf("%v", rule.Pos),
	}
	g.nextRuleID++
	g.stats.TotalRules++

	return gRule, nil
}

// groundTerms converts a predicate and arguments to a ground atom using substitution
func (g *Grounder) groundTerms(predName string, args []ast.Term, subst map[string]ast.Term) (*ir.GroundAtom, error) {
	groundArgs := make([]ir.Constant, 0)

	for _, arg := range args {
		groundArg, err := g.applySubstitution(arg, subst)
		if err != nil {
			return nil, err
		}
		if groundArg == nil {
			return nil, nil // Contains unbound variable
		}
		groundArgs = append(groundArgs, *groundArg)
	}

	return g.createGroundAtom(predName, args, groundArgs)
}

// createGroundAtom constructs a ground atom and registers it in the domain
func (g *Grounder) createGroundAtom(predName string, origArgs []ast.Term, groundArgs ...[]ir.Constant) (*ir.GroundAtom, error) {
	if len(groundArgs) == 0 {
		// Convert original AST terms to IR constants
		irArgs := make([]ir.Constant, 0)
		for _, arg := range origArgs {
			irArg, err := g.termToConstant(arg)
			if err != nil {
				return nil, err
			}
			if irArg == nil {
				return nil, nil
			}
			irArgs = append(irArgs, *irArg)
		}
		groundArgs = [][]ir.Constant{irArgs}
	}

	atom := &ir.GroundAtom{
		Predicate: predName,
		Args:      groundArgs[0],
	}

	// Reuse or create atom
	atomStr := atom.String()
	if existing, ok := g.groundAtoms[atomStr]; ok {
		return existing, nil
	}

	atom.ID = g.domain.NextAtomID
	g.domain.NextAtomID++
	g.groundAtoms[atomStr] = atom
	g.domain.RegisterAtom(atom)
	g.stats.TotalAtoms++

	return atom, nil
}

// termToConstant converts an AST term to an IR constant
func (g *Grounder) termToConstant(term ast.Term) (*ir.Constant, error) {
	switch t := term.(type) {
	case *ast.Constant:
		switch t.Type {
		case ast.CONST_INT:
			return &ir.Constant{Type: ir.CONST_INT, Value: t.Value}, nil
		case ast.CONST_FLOAT:
			return &ir.Constant{Type: ir.CONST_FLOAT, Value: t.Value}, nil
		case ast.CONST_STRING:
			return &ir.Constant{Type: ir.CONST_STRING, Value: t.Value}, nil
		}
	case *ast.Atom:
		return &ir.Constant{Type: ir.CONST_ATOM, Value: t.Name}, nil
	case *ast.Variable:
		if t.Name == "_" {
			return nil, nil // Anonymous variable
		}
		return nil, fmt.Errorf("unbound variable: %s", t.Name)
	}
	return nil, fmt.Errorf("unknown term type: %T", term)
}

// applySubstitution substitutes variables in a term with binding values
func (g *Grounder) applySubstitution(term ast.Term, subst map[string]ast.Term) (*ir.Constant, error) {
	switch t := term.(type) {
	case *ast.Variable:
		if t.Name == "_" {
			return nil, nil
		}
		if bound, ok := subst[t.Name]; ok {
			return g.termToConstant(bound)
		}
		return nil, fmt.Errorf("unbound variable: %s", t.Name)
	case *ast.Constant:
		return g.termToConstant(t)
	case *ast.Atom:
		return g.termToConstant(t)
	}
	return nil, fmt.Errorf("unknown term type: %T", term)
}

// GroundLiteral grounds a single literal with variable substitution
func (g *Grounder) GroundLiteral(lit *ast.Literal, subst map[string]ast.Term) (*ir.GroundLiteral, error) {
	if lit.Atom == nil {
		return nil, nil
	}

	// Ground the atom
	atom, err := g.groundTerms(lit.Atom.Name, lit.Args, subst)
	if err != nil {
		return nil, err
	}
	if atom == nil {
		return nil, nil
	}

	return &ir.GroundLiteral{
		Positive: lit.Positive,
		Atom:     atom,
	}, nil
}

// indexGroundedRules creates indexes for efficient rule lookup
func (g *Grounder) indexGroundedRules() {
	for _, rule := range g.groundRules {
		// Index by head
		for _, headAtom := range rule.Head {
			g.rulesByHead[headAtom.Predicate] = append(g.rulesByHead[headAtom.Predicate], rule)
		}

		// Index by body predicates
		for _, bodyLit := range rule.Body {
			if bodyLit.Atom != nil {
				g.rulesByBody[bodyLit.Atom.Predicate] = append(g.rulesByBody[bodyLit.Atom.Predicate], rule)
			}
		}
	}
}

// mapRuleType converts AST rule type to IR rule type
func (g *Grounder) mapRuleType(astType ast.RuleType) ir.RuleType {
	switch astType {
	case ast.RULE_NORMAL:
		return ir.RULE_NORMAL
	case ast.RULE_CHOICE:
		return ir.RULE_CHOICE
	case ast.RULE_CONSTRAINT:
		return ir.RULE_CONSTRAINT
	case ast.RULE_WEAK:
		return ir.RULE_WEAK
	case ast.RULE_FACT:
		return ir.RULE_FACT
	default:
		return ir.RULE_NORMAL
	}
}

// GetGroundRules returns all ground rules
func (g *Grounder) GetGroundRules() []*ir.GroundRule {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.groundRules
}

// GetDomain returns the computed Herbrand universe
func (g *Grounder) GetDomain() *ir.Domain {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.domain
}

// GetStats returns grounding statistics
func (g *Grounder) GetStats() *GroundingStats {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.stats
}

// GetGroundAtomsByPredicate returns all ground atoms for a predicate
func (g *Grounder) GetGroundAtomsByPredicate(pred string) []*ir.GroundAtom {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.domain.Atoms[pred]
}

// GetRulesByHead returns all ground rules with a given head predicate
func (g *Grounder) GetRulesByHead(pred string) []*ir.GroundRule {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.rulesByHead[pred]
}

// GetRulesByBody returns all ground rules with body containing given predicate
func (g *Grounder) GetRulesByBody(pred string) []*ir.GroundRule {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.rulesByBody[pred]
}
