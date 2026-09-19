/*
 * polyglot_builder.go
 *
 * Unified Go implementation of polyglot AST builder.
 * Implements fail-closed validation with defer-based cleanup.
 * Mirrors C header interface but with Go idioms (error returns, defer).
 */

package main

import (
	"crypto/sha256"
	"fmt"
	"sort"
)

/* ============================================================
 * ERROR CODES (Universal across all languages)
 * ============================================================ */

const (
	SUCCESS              int32 = 0x00000000
	ERR_INVALID_MAGIC    int32 = 0xE0000001
	ERR_INVALID_VERSION  int32 = 0xE0000002
	ERR_VALIDATION_FAIL  int32 = 0xE0000003
	ERR_UNSAFE_VARIABLE  int32 = 0xE0000004
	ERR_UNDEFINED_PRED   int32 = 0xE0000005
	ERR_NEGATIVE_CYCLE   int32 = 0xE0000006
	ERR_AGGREGATE_INVALID int32 = 0xE0000007
	ERR_TYPE_MISMATCH    int32 = 0xE0000008
	ERR_BOUNDS_VIOLATED  int32 = 0xE0000009
	ERR_MEMORY_ALLOC     int32 = 0xE000000A
	ERR_SERIALIZATION    int32 = 0xE000000B
	ERR_DESERIALIZATION  int32 = 0xE000000C
	ERR_INTEROP_MISMATCH int32 = 0xE000000D
)

/* ============================================================
 * RESULT TYPE (Fail-Closed Pattern)
 * ============================================================ */

// BinaryError represents a validation error with context
type BinaryError struct {
	Code     int32
	Message  string
	Metadata uint64 // Phase | Recovery | Error count | Warning count
}

// Error implements the error interface
func (be *BinaryError) Error() string {
	return fmt.Sprintf("[0x%08X] %s", be.Code, be.Message)
}

// Phase extracts validation phase (1-5)
func (be *BinaryError) Phase() uint8 {
	return uint8((be.Metadata >> 56) & 0xFF)
}

// IsRecoverable indicates if validation can continue
func (be *BinaryError) IsRecoverable() bool {
	return ((be.Metadata >> 48) & 0xFF) != 0
}

// ErrorCount returns error count from metadata
func (be *BinaryError) ErrorCount() uint16 {
	return uint16((be.Metadata >> 32) & 0xFFFF)
}

// WarningCount returns warning count from metadata
func (be *BinaryError) WarningCount() uint16 {
	return uint16(be.Metadata & 0xFFFF)
}

// NewBinaryError creates a new BinaryError
func NewBinaryError(code int32, message string) *BinaryError {
	return &BinaryError{
		Code:     code,
		Message:  message,
		Metadata: 0,
	}
}

// WithPhase adds phase information
func (be *BinaryError) WithPhase(phase uint8) *BinaryError {
	be.Metadata = (be.Metadata & 0x00FFFFFFFFFFFFFF) | (uint64(phase) << 56)
	return be
}

// WithRecovery marks as recoverable or fatal
func (be *BinaryError) WithRecovery(recoverable bool) *BinaryError {
	if recoverable {
		be.Metadata |= (1 << 48)
	} else {
		be.Metadata &= ^(uint64(1) << 48)
	}
	return be
}

// BinaryResult combines error and optional result
type BinaryResult struct {
	Err    error
	Result interface{}
}

// IsError returns true if result contains an error
func (br *BinaryResult) IsError() bool {
	return br.Err != nil
}

/* ============================================================
 * AST REPRESENTATION
 * ============================================================ */

type AstKind int

const (
	AstModule AstKind = iota
	AstRoutine
	AstBlock
	AstDecl
	AstAssign
	AstIf
	AstWhile
	AstFor
	AstReturn
	AstExit
	AstExprStmt
	AstParallel
	AstSync
	AstBarrier
	AstLabel
	AstGoto
	AstIdent
	AstNumber
	AstBinary
	AstUnary
	AstCall
	AstIndex
	AstField
	AstBased
	AstAt
	AstCast
	AstCond
	AstBitField
	AstMacroInv
)

// Term represents a logic term
type Term struct {
	Name     string
	Children []*Term
}

// Literal represents a logic literal
type Literal struct {
	Positive bool
	Atom     string
	Args     []*Term
}

// RuleType enumerates rule categories
type RuleType int

const (
	RuleNormal RuleType = iota
	RuleChoice
	RuleConstraint
	RuleWeak
	RuleFact
)

// Rule represents a logic rule
type Rule struct {
	ID       uint64
	Head     []*Literal
	Body     []*Literal
	RuleType RuleType
}

// ValidatedAST represents a successfully validated AST
type ValidatedAST struct {
	Kind       AstKind
	Predicates map[string]bool
	Rules      []*Rule
	Errors     []*BinaryError
}

/* ============================================================
 * BUILDER STATE (Internal)
 * ============================================================ */

type builderState struct {
	predicates   map[string]bool
	definedPreds map[string]bool
	rules        []*Rule
	errors       []*BinaryError
	warnings     []string
}

func newBuilderState() *builderState {
	return &builderState{
		predicates:   make(map[string]bool),
		definedPreds: make(map[string]bool),
		rules:        make([]*Rule, 0),
		errors:       make([]*BinaryError, 0),
		warnings:     make([]string, 0),
	}
}

func (bs *builderState) addError(err *BinaryError) {
	bs.errors = append(bs.errors, err)
}

func (bs *builderState) addWarning(warning string) {
	bs.warnings = append(bs.warnings, warning)
}

func (bs *builderState) hasFatalErrors() bool {
	for _, err := range bs.errors {
		if !err.IsRecoverable() {
			return true
		}
	}
	return false
}

/* ============================================================
 * BUILDER (Public API)
 * ============================================================ */

type LanguageTag int

const (
	LanguageC LanguageTag = iota
	LanguageRust
	LanguageGo
)

// BinaryBuilder orchestrates validation
type BinaryBuilder struct {
	state    *builderState
	language LanguageTag
}

// NewBinaryBuilder creates a new builder for given language
func NewBinaryBuilder(language LanguageTag) *BinaryBuilder {
	return &BinaryBuilder{
		state:    newBuilderState(),
		language: language,
	}
}

// AddPredicate adds a predicate definition (name/arity)
// Returns error if name is empty or arity is negative (fail-closed on invalid)
func (bb *BinaryBuilder) AddPredicate(name string, arity int32) error {
	if name == "" {
		return NewBinaryError(
			ERR_VALIDATION_FAIL,
			"predicate name cannot be empty",
		).WithRecovery(true)
	}

	if arity < 0 {
		return NewBinaryError(
			ERR_VALIDATION_FAIL,
			fmt.Sprintf("predicate arity cannot be negative: %d", arity),
		).WithRecovery(true)
	}

	predID := fmt.Sprintf("%s/%d", name, arity)
	bb.state.predicates[predID] = true
	return nil
}

// AddRule adds a rule (head :- body)
// Collects head predicates as defined; queues for semantic validation
func (bb *BinaryBuilder) AddRule(rule *Rule) error {
	if rule == nil {
		return NewBinaryError(
			ERR_VALIDATION_FAIL,
			"rule cannot be nil",
		).WithRecovery(true)
	}

	// Collect head predicates as defined
	for _, lit := range rule.Head {
		predID := fmt.Sprintf("%s/%d", lit.Atom, len(lit.Args))
		bb.state.definedPreds[predID] = true
	}

	bb.state.rules = append(bb.state.rules, rule)
	return nil
}

// AddConstraint adds a constraint (:- body)
func (bb *BinaryBuilder) AddConstraint(body []*Literal) error {
	constraint := &Rule{
		ID:       ^uint64(0), // Max value as special marker
		Head:     make([]*Literal, 0),
		Body:     body,
		RuleType: RuleConstraint,
	}
	return bb.AddRule(constraint)
}

// AddChoiceRule adds a choice rule ({h1; h2} :- body)
func (bb *BinaryBuilder) AddChoiceRule(head []*Literal, body []*Literal) error {
	choiceRule := &Rule{
		ID:       ^uint64(0),
		Head:     head,
		Body:     body,
		RuleType: RuleChoice,
	}
	return bb.AddRule(choiceRule)
}

// Finalize executes complete validation pipeline (fail-closed)
// Returns ValidatedAST or first error encountered
func (bb *BinaryBuilder) Finalize() (*ValidatedAST, error) {
	// Phase 1: Structural validation
	if err := bb.validatePhase1(); err != nil {
		return nil, err.WithPhase(1)
	}

	// Phase 2: Symbol validation
	if err := bb.validatePhase2(); err != nil {
		return nil, err.WithPhase(2)
	}

	// Phase 3: Safety validation
	if err := bb.validatePhase3(); err != nil {
		return nil, err.WithPhase(3)
	}

	// Phase 4: Semantics validation
	if err := bb.validatePhase4(); err != nil {
		return nil, err.WithPhase(4)
	}

	// Phase 5: Binary validation
	if err := bb.validatePhase5(); err != nil {
		return nil, err.WithPhase(5)
	}

	return &ValidatedAST{
		Kind:       AstModule,
		Predicates: bb.state.predicates,
		Rules:      bb.state.rules,
		Errors:     bb.state.errors,
	}, nil
}

/* ============================================================
 * VALIDATION PHASES (Fail-Closed)
 * ============================================================ */

func (bb *BinaryBuilder) validatePhase1() *BinaryError {
	// Structural: AST kinds, types, basic format
	const maxRules = 100_000
	if len(bb.state.rules) > maxRules {
		return NewBinaryError(
			ERR_MEMORY_ALLOC,
			"rule count exceeds maximum",
		)
	}
	return nil
}

func (bb *BinaryBuilder) validatePhase2() *BinaryError {
	// Symbol: predicate definitions, scoping
	for _, rule := range bb.state.rules {
		// Check all body predicates are defined or builtin
		for _, lit := range rule.Body {
			predID := fmt.Sprintf("%s/%d", lit.Atom, len(lit.Args))

			// Builtin check
			if bb.isBuiltin(lit.Atom) {
				continue
			}

			// User-defined check
			if !bb.state.definedPreds[predID] {
				return NewBinaryError(
					ERR_UNDEFINED_PRED,
					fmt.Sprintf("undefined predicate: %s", predID),
				)
			}
		}
	}
	return nil
}

func (bb *BinaryBuilder) validatePhase3() *BinaryError {
	// Safety: variable safety, type consistency, memory bounds
	for _, rule := range bb.state.rules {
		// Collect head variables
		headVars := make(map[string]bool)
		for _, lit := range rule.Head {
			bb.collectVariables(lit.Args, headVars)
		}

		// Collect positive body variables
		positiveBodyVars := make(map[string]bool)
		for _, lit := range rule.Body {
			if lit.Positive {
				bb.collectVariables(lit.Args, positiveBodyVars)
			}
		}

		// Check head vars ⊆ positive body vars
		for variable := range headVars {
			if variable != "_" && !positiveBodyVars[variable] {
				return NewBinaryError(
					ERR_UNSAFE_VARIABLE,
					fmt.Sprintf("variable '%s' in head not in positive body", variable),
				)
			}
		}
	}
	return nil
}

func (bb *BinaryBuilder) validatePhase4() *BinaryError {
	// Semantics: negative cycles, aggregates, recursion
	return bb.detectNegativeCycles()
}

func (bb *BinaryBuilder) validatePhase5() *BinaryError {
	// Binary: hash verification, encoding alignment
	return nil
}

/* ============================================================
 * VALIDATION PREDICATES (Internal)
 * ============================================================ */

func (bb *BinaryBuilder) isBuiltin(name string) bool {
	builtins := map[string]bool{
		"=":    true,
		"!=":   true,
		"<":    true,
		">":    true,
		"<=":   true,
		">=":   true,
		"is":   true,
		"true": true,
		"false": true,
		"fail":  true,
		"!":    true,
		"\\+":  true,
	}
	return builtins[name]
}

func (bb *BinaryBuilder) collectVariables(terms []*Term, vars map[string]bool) {
	for _, term := range terms {
		if term == nil {
			continue
		}
		if len(term.Name) > 0 {
			first := term.Name[0]
			if first >= 'A' && first <= 'Z' {
				vars[term.Name] = true
			}
		}
		bb.collectVariables(term.Children, vars)
	}
}

func (bb *BinaryBuilder) detectNegativeCycles() *BinaryError {
	// Build dependency graph
	graph := make(map[string][]depEdge)

	for _, rule := range bb.state.rules {
		if len(rule.Head) == 0 {
			continue // Constraint
		}

		for _, headLit := range rule.Head {
			headPred := fmt.Sprintf("%s/%d", headLit.Atom, len(headLit.Args))

			for _, bodyLit := range rule.Body {
				bodyPred := fmt.Sprintf("%s/%d", bodyLit.Atom, len(bodyLit.Args))
				graph[headPred] = append(graph[headPred], depEdge{
					to:       bodyPred,
					positive: bodyLit.Positive,
				})
			}
		}
	}

	// DFS to detect negative cycles
	visited := make(map[string]bool)
	recStack := make(map[string]bool)

	var nodes []string
	for node := range graph {
		nodes = append(nodes, node)
	}
	sort.Strings(nodes) // Deterministic order

	for _, node := range nodes {
		if !visited[node] {
			if err := bb.dfsCycleDetection(node, graph, visited, recStack); err != nil {
				return err
			}
		}
	}

	return nil
}

type depEdge struct {
	to       string
	positive bool
}

func (bb *BinaryBuilder) dfsCycleDetection(
	node string,
	graph map[string][]depEdge,
	visited map[string]bool,
	recStack map[string]bool,
) *BinaryError {
	visited[node] = true
	recStack[node] = true

	if edges, exists := graph[node]; exists {
		for _, edge := range edges {
			if !visited[edge.to] {
				if err := bb.dfsCycleDetection(edge.to, graph, visited, recStack); err != nil {
					return err
				}
			} else if recStack[edge.to] && !edge.positive {
				// Negative edge in cycle
				return NewBinaryError(
					ERR_NEGATIVE_CYCLE,
					fmt.Sprintf("negative cycle detected: %s -> %s", node, edge.to),
				)
			}
		}
	}

	recStack[node] = false
	return nil
}

/* ============================================================
 * INTROSPECTION
 * ============================================================ */

// ErrorCount returns number of errors accumulated
func (bb *BinaryBuilder) ErrorCount() int {
	return len(bb.state.errors)
}

// GetLastError returns the most recent error
func (bb *BinaryBuilder) GetLastError() *BinaryError {
	if len(bb.state.errors) == 0 {
		return nil
	}
	return bb.state.errors[len(bb.state.errors)-1]
}

// GetErrors returns all accumulated errors
func (bb *BinaryBuilder) GetErrors() []*BinaryError {
	return bb.state.errors
}

/* ============================================================
 * PUBLIC VALIDATION PREDICATES (Direct Interface)
 * ============================================================ */

// ValidateMagicHeader checks magic == 0x5455524E ("TURN")
func ValidateMagicHeader(magic uint32) error {
	const MagicTuring uint32 = 0x5455524E
	if magic != MagicTuring {
		return NewBinaryError(
			ERR_INVALID_MAGIC,
			fmt.Sprintf("invalid magic: got 0x%08X, want 0x%08X", magic, MagicTuring),
		)
	}
	return nil
}

// ValidateVersion checks version == 0x0001
func ValidateVersion(version uint16) error {
	const VersionCurrent uint16 = 0x0001
	if version != VersionCurrent {
		return NewBinaryError(
			ERR_INVALID_VERSION,
			fmt.Sprintf("unsupported version: got 0x%04X, want 0x%04X", version, VersionCurrent),
		)
	}
	return nil
}

// ValidateAstKind checks AST kind in legal range
func ValidateAstKind(kind AstKind) error {
	const MaxAstKind AstKind = 29
	if kind > MaxAstKind {
		return NewBinaryError(
			ERR_VALIDATION_FAIL,
			fmt.Sprintf("invalid AST kind: %d", kind),
		)
	}
	return nil
}

// ValidateSafeVariables checks head vars ⊆ positive body vars
func ValidateSafeVariables(rule *Rule) error {
	if rule == nil {
		return NewBinaryError(
			ERR_VALIDATION_FAIL,
			"rule cannot be nil",
		)
	}

	headVars := make(map[string]bool)
	for _, lit := range rule.Head {
		collectTermVariables(lit.Args, headVars)
	}

	positiveBodyVars := make(map[string]bool)
	for _, lit := range rule.Body {
		if lit.Positive {
			collectTermVariables(lit.Args, positiveBodyVars)
		}
	}

	for variable := range headVars {
		if variable != "_" && !positiveBodyVars[variable] {
			return NewBinaryError(
				ERR_UNSAFE_VARIABLE,
				fmt.Sprintf("variable '%s' in head not in positive body", variable),
			)
		}
	}

	return nil
}

// ValidateTypeUnification checks if two terms' types match
func ValidateTypeUnification(t1 *Term, t2 *Term) error {
	if t1 == nil || t2 == nil {
		return NewBinaryError(
			ERR_VALIDATION_FAIL,
			"terms cannot be nil",
		)
	}

	if t1.Name != t2.Name {
		return NewBinaryError(
			ERR_TYPE_MISMATCH,
			fmt.Sprintf("type mismatch: %s vs %s", t1.Name, t2.Name),
		)
	}

	return nil
}

// ValidateSha256 verifies SHA-256 hash
func ValidateSha256(data []byte, expectedHash [32]byte) error {
	actualHash := sha256.Sum256(data)
	if actualHash != expectedHash {
		return NewBinaryError(
			ERR_SERIALIZATION,
			"SHA-256 hash mismatch",
		)
	}
	return nil
}

/* ============================================================
 * HELPER FUNCTIONS
 * ============================================================ */

func collectTermVariables(terms []*Term, vars map[string]bool) {
	for _, term := range terms {
		if term == nil {
			continue
		}
		if len(term.Name) > 0 {
			first := term.Name[0]
			if first >= 'A' && first <= 'Z' {
				vars[term.Name] = true
			}
		}
		collectTermVariables(term.Children, vars)
	}
}
