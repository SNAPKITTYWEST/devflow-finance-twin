# ASP Engine Architecture Specification

**Version:** 1.0  
**System:** Answer Set Programming (ASP) Solver  
**Implementation Language:** Go  
**Total Target LOC:** ~50–75K  
**Date:** 2026-09-13

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Module Inventory](#module-inventory)
3. [Dependency DAG](#dependency-dag)
4. [Type Specifications](#type-specifications)
5. [Interface Contracts](#interface-contracts)
6. [Initialization Order](#initialization-order)
7. [Cross-Module Integration](#cross-module-integration)
8. [Error Handling Strategy](#error-handling-strategy)

---

## Executive Summary

This ASP solver is a modular, layered architecture composed of 12 core packages plus CLI and test suites. The design enforces strict dependency ordering to enable:

- **Composability**: Each module is independently testable
- **Reusability**: Higher layers never directly depend on multiple lower layers
- **Maintainability**: Clear boundaries and responsibility assignments
- **Extensibility**: Well-defined interfaces for custom heuristics, propagators, and optimizations

**Layer Structure:**
- **Lexical/Syntactic (lexer → parser):** Source text → AST
- **Semantic (ast, semantics, symbols):** AST validation and symbol management
- **Intermediate Representation (ir, normalize):** Domain-independent constraint form
- **Grounding (ground, symbols):** Instantiation to ground atoms
- **Constraint System (constraints, propagation):** Clause/nogood generation and BCP
- **Solver (solver, aggregates, optimization):** CDCL search with conflict analysis
- **Incremental & Models (incremental, models):** Stateful solving, model enumeration
- **Public API (api, cli):** User-facing interfaces

---

## Module Inventory

| Module | LOC Target | Purpose | Key Responsibility |
|--------|-----------|---------|-------------------|
| **lexer** | 2–3K | Tokenization | Convert source text → token stream |
| **parser** | 3–5K | Parsing | Convert token stream → AST |
| **ast** | 2–3K | AST Definitions | Type definitions for program structures |
| **semantics** | 1–2K | Semantic Analysis | Validation, safety checks, diagnostics |
| **symbols** | 1–2K | Symbol Management | Interning, symbol table, ID mapping |
| **ir** | 2–3K | Constraint IR | Ground atoms, clauses, nogoods |
| **normalize** | 1–2K | Rule Normalization | Choice expansion, rule rewriting |
| **ground** | 5–8K | Grounding | Herbrand universe discovery, instantiation |
| **constraints** | 2–3K | Constraint Generation | Convert rules → clauses, nogoods |
| **propagation** | 2–4K | Unit Propagation | BCP, watched literals, implications |
| **solver** | 8–12K | Core Solver | CDCL search, backtracking, learning |
| **aggregates** | 1–2K | Aggregate Handling | Sum/count/min/max semantics |
| **optimization** | 1–2K | Weak Constraints | Minimize/maximize rules |
| **incremental** | 1–2K | Incremental Solving | Push/pop, assumption handling |
| **models** | 1–2K | Model Enumeration | Stable model verification, iteration |
| **api** | 1–2K | Public API | Unified entry points (Parse, Compile, Solve) |
| **cli** | 1–2K | Command Line | REPL, file input, output formatting |
| **tests** | 5–10K | Test Suite | Unit, integration, regression tests |

**Total: ~50–75K LOC**

---

## Dependency DAG

### Graph Structure (Text Visualization)

```
                    ┌─── api ─────────────────────────────┐
                    │                                       │
                    │                                       ▼
                    │                                      cli
                    │
         ┌──────────┼──────────┬──────────┬──────────────┐
         │          │          │          │              │
         ▼          ▼          ▼          ▼              ▼
      optimization incremental models propagation solver
         │          │          │          │              │
         │          └──┬───────┴──────┬───┴──────────────┤
         │             │              │                  │
         │             ▼              ▼                  ▼
         │          ground         constraints      aggregates
         │             │              │                  │
         │             ├──┬───────────┴──────────────────┘
         │             │  │
         │    ┌────────┘  │
         │    │           │
         ▼    ▼           ▼
      normalize ◄─────── ir
         │                │
         └─────┬──────────┤
               │          │
         symbols │      semantics
               │  │       │
         ┌──────┤  └───────┴───────┐
         │      │                  │
         ▼      ▼                  ▼
       parser ◄─ lexer ──────────  ast
         │
         └─ no transitive deps
```

### Dependency Matrix

```
Module          | Depends On
─────────────────────────────────────────────────────
lexer           | (none)
parser          | lexer
ast             | (none)
semantics       | ast
symbols         | (none)
ir              | ast
normalize       | ir
ground          | ir, normalize, symbols
constraints     | ir
propagation     | constraints
solver          | propagation, constraints
aggregates      | constraints
optimization    | solver
incremental     | solver, ground
models          | solver
api             | lexer, parser, ast, semantics, symbols, ir, normalize, 
                | ground, constraints, propagation, solver, aggregates,
                | optimization, incremental, models
cli             | api
tests           | all (for integration testing)
```

### Acyclicity Proof

The DAG is organized in **layers with strictly increasing dependency levels**:

- **Layer 0 (no deps):** `lexer`, `ast`, `symbols`
- **Layer 1 (deps on Layer 0):** `parser` (← lexer), `semantics` (← ast), `ir` (← ast)
- **Layer 2 (deps on Layer 1):** `normalize` (← ir)
- **Layer 3 (deps on Layer 2):** `ground` (← ir, normalize, symbols)
- **Layer 4 (deps on Layer 3):** `constraints` (← ir)
- **Layer 5 (deps on Layer 4):** `propagation` (← constraints)
- **Layer 6 (deps on Layer 5):** `solver` (← propagation, constraints), `aggregates` (← constraints)
- **Layer 7 (deps on Layer 6):** `optimization` (← solver), `incremental` (← solver, ground), `models` (← solver)
- **Layer 8 (aggregates all):** `api` (← all previous)
- **Layer 9 (top-level):** `cli` (← api)

**No backward edges exist.** ✓

---

## Type Specifications

### `lexer/` Package

**Primary Types:**

```
type Token struct {
    Type      TokenType   // Token classification
    Lexeme    string      // Raw source text
    Position  Position    // Source location (line, col)
}

type TokenType int
const (
    TOKEN_EOF           TokenType = iota
    TOKEN_ATOM          // a, foo, pred_name
    TOKEN_VARIABLE      // X, Var, _
    TOKEN_INTEGER       // 123, -45
    TOKEN_LPAREN        // (
    TOKEN_RPAREN        // )
    TOKEN_LBRACKET      // [
    TOKEN_RBRACKET      // ]
    TOKEN_LBRACE        // {
    TOKEN_RBRACE        // }
    TOKEN_DOT           // .
    TOKEN_COMMA         // ,
    TOKEN_RULE          // :-
    TOKEN_CHOICE        // {…}|…
    TOKEN_PIPE          // |
    TOKEN_NOT           // not
    TOKEN_AGGREGATE     // #count, #sum, #min, #max
    TOKEN_CONSTRAINT    // :~
    TOKEN_CMP           // =, !=, <, >, <=, >=
    TOKEN_PLUS          // +
    TOKEN_MINUS         // -
    TOKEN_MULT          // *
    TOKEN_DIV           // /
    TOKEN_MOD           // mod
    TOKEN_ANONYMOUS     // _
    TOKEN_STRING        // "…"
    TOKEN_COMMENT       // % …
    // ... (complete set)
)

type Position struct {
    Line   int
    Column int
    Offset int
}
```

### `parser/` Package (AST Factory)

**Primary Types:**

```
type Program struct {
    Statements []Statement
    Directives []Directive
}

type Statement interface {
    statement() // Marker interface
}

// Concrete statement types:
type RuleStatement struct {
    Rule *ast.Rule
}

type ChoiceStatement struct {
    Rule *ast.Rule  // Choice rule: head | body
}

type Directive struct {
    Type      string      // "show", "hide", "assert", etc.
    Arguments []ast.Term
}

type Diagnostics struct {
    Errors   []ParseError
    Warnings []ParseWarning
}

type ParseError struct {
    Message  string
    Position Position
    Context  string
}
```

### `ast/` Package (Semantic Domain)

**Primary Node Hierarchy:**

```
type Node interface {
    node()  // Marker
}

// ─── Terms ───
type Term interface {
    Node
    term()
}

type Atom struct {
    Name string
}

type Variable struct {
    Name string
}

type Constant struct {
    Type  ConstantType  // INT, FLOAT, STRING
    Value interface{}
}

type ConstantType int
const (
    CONST_INT ConstantType = iota
    CONST_FLOAT
    CONST_STRING
)

type Compound struct {
    Functor string
    Args    []Term
}

// ─── Literals ───
type Literal struct {
    Positive bool        // true = positive, false = negation-as-failure
    Atom     *Atom
    Args     []Term
    Aggregate *Aggregate  // if applicable
}

// ─── Rules ───
type Rule struct {
    Head      *Head
    Body      *Body
    Choice    *Choice      // if choice rule
    Weak      *WeakConstraint  // if weak constraint
}

type Head struct {
    Literals []*Literal
}

type Body struct {
    Literals []*Literal
}

type Choice struct {
    Elements []*ChoiceElement
    LowerBound int
    UpperBound int
}

type ChoiceElement struct {
    Atom *Atom
    Args []Term
    Weight int
}

// ─── Aggregates ───
type Aggregate struct {
    Type      AggregateType  // COUNT, SUM, MIN, MAX
    Elements  []*AggregateElement
    Condition *Literal
}

type AggregateType int
const (
    AGG_COUNT AggregateType = iota
    AGG_SUM
    AGG_MIN
    AGG_MAX
    AGG_AVG
)

type AggregateElement struct {
    Selector *Atom     // Instance variable
    Terms    []Term
    Weight   *Constant // For weighted aggregates
}

// ─── Weak Constraints ───
type WeakConstraint struct {
    Body      *Body
    Priority  int
    Weight    int
}
```

### `semantics/` Package

**Primary Types:**

```
type Validator struct {
    symbols *symbols.Table
    rules   []*ast.Rule
}

type CheckResult struct {
    IsValid  bool
    Errors   []ValidationError
    Warnings []ValidationWarning
}

type ValidationError struct {
    Code     string  // "unsafe_var", "negative_cycle", "undefined_pred"
    Rule     *ast.Rule
    Literal  *ast.Literal
    Message  string
}

type SafetyCheck interface {
    Check(rule *ast.Rule, symbols *symbols.Table) (*CheckResult, error)
}
```

### `symbols/` Package

**Primary Types:**

```
type Table struct {
    atoms      map[string]AtomID
    vars       map[string]VarID
    predicates map[string]PredicateID
    mu         sync.RWMutex
}

type AtomID uint32
type VarID uint32
type PredicateID uint32

type Symbol struct {
    ID    interface{}  // AtomID, VarID, or PredicateID
    Name  string
    Type  SymbolType
}

type SymbolType int
const (
    SYM_ATOM SymbolType = iota
    SYM_VARIABLE
    SYM_PREDICATE
    SYM_CONSTANT
)
```

### `ir/` Package (Intermediate Representation)

**Primary Types:**

```
// Ground atom: base unit of ASP solver state
type GroundAtom struct {
    ID        uint64      // Unique identifier
    Predicate string      // Predicate name
    Args      []Constant  // Fully ground arguments
}

type Constant struct {
    Type  ConstantType  // INT, FLOAT, STRING, ATOM
    Value interface{}
}

// Ground literal: GroundAtom with sign
type GroundLiteral struct {
    Positive bool        // true = atom, false = ¬atom
    Atom     *GroundAtom
}

// Ground rule: fully instantiated AST rule → clause/nogood
type GroundRule struct {
    ID   uint64
    Head []GroundAtom    // Disjunctive head (choice rules)
    Body []GroundLiteral // Conjunction of literals
    Type RuleType        // NORMAL, CHOICE, CONSTRAINT, WEAK
}

type RuleType int
const (
    RULE_NORMAL RuleType = iota
    RULE_CHOICE
    RULE_CONSTRAINT
    RULE_WEAK
)

// Clause: converted ground rule → SAT-like form
type Clause struct {
    ID       uint64
    Literals []Literal
    Source   *GroundRule
    LearnedAt uint
}

type Literal struct {
    Positive bool
    AtomID   uint64
}

// Nogood: constraint (clause that must have ≥1 false literal)
type Nogood struct {
    ID        uint64
    Literals  []Literal
    Source    interface{}  // GroundRule, Aggregate, WeakConstraint
}

type Constraint interface {
    Head() interface{}           // Atom(s) being constrained
    Body() []GroundLiteral       // Triggering conditions
    Propagate(assignment Assignment) ([]GroundAtom, error)
}
```

### `normalize/` Package

**Primary Types:**

```
type Normalizer struct {
    rules []*ast.Rule
}

type NormalizationResult struct {
    ChoiceExpanded  []*ir.GroundRule  // Expanded choice rules
    Rewritten       []*ir.GroundRule  // Rewritten normal rules
    Constraints     []*ir.Nogood
    Diagnostics     []string
}
```

### `ground/` Package (Grounding Engine)

**Primary Types:**

```
type Grounder struct {
    atoms       map[string][]Term
    rules       []*ast.Rule
    symbols     *symbols.Table
    index       *Index
    domain      *Domain
    safetyCheck *SafetyChecker
}

type Domain struct {
    Atoms          map[string][]Term    // Herbrand universe
    PredicateArity map[string]int
    Constants      map[string]Constant
}

type Index struct {
    byHead   map[string][]*Clause       // Rules indexed by head predicate
    byBody   map[string][]*Clause       // Rules indexed by body predicates
    literals map[uint64][]*Clause
}

type GroundingResult struct {
    Rules       []*ir.GroundRule
    Atoms       []*ir.GroundAtom
    Constraints []*ir.Nogood
    Domain      *Domain
}

type SafetyChecker struct {
    rules []*ast.Rule
}
```

### `constraints/` Package

**Primary Types:**

```
type PropagationRule struct {
    Head     *ir.GroundAtom
    Body     []*ir.GroundLiteral
    Nogoods  []*ir.Nogood
}

type AggregateRule struct {
    Aggregate *ast.Aggregate
    Nogoods   []*ir.Nogood  // Propagation rules for aggregate
}

type NoGoodGenerator struct {
    rules  []*ir.GroundRule
}

type GenerationResult struct {
    Clauses  []*ir.Clause
    Nogoods  []*ir.Nogood
}
```

### `propagation/` Package

**Primary Types:**

```
type Propagator struct {
    clauses    []*ir.Clause
    nogoods    []*ir.Nogood
    watchers   map[uint64][]*WatchedClause
    assignment *Assignment
    trail      *Trail
}

type WatchedClause struct {
    Clause     *ir.Clause
    WatchedIdx [2]int      // Indices of watched literals
}

type Trail struct {
    Assignments []*AtomAssignment
    Level       uint
}

type AtomAssignment struct {
    AtomID    uint64
    Value     bool            // true = True, false = False
    Level     uint
    Reason    *ir.Clause      // BCP reason
    DecidedAt uint
}

type ImplicationGraph struct {
    Nodes  map[uint64]*ImplicationNode
    Edges  map[uint64][]uint64
}

type ImplicationNode struct {
    AtomID   uint64
    Value    bool
    Reason   *ir.Clause
    Antecedents []uint64
}

type PropagationResult struct {
    Conflict *ir.Clause   // nil if consistent, clause that failed if conflict
    Learned  []*ir.Clause // Learned clauses from conflict analysis
}
```

### `solver/` Package (Core CDCL Engine)

**Primary Types:**

```
type Solver struct {
    clauses       []*ir.Clause
    nogoods       []*ir.Nogood
    assignment    *Assignment
    propagator    *propagation.Propagator
    conflict      *ConflictAnalyzer
    search        *SearchStrategy
    heuristic     Heuristic
    trail         *Trail
    assumptions   []uint64
    state         SolverState
}

type SolverState int
const (
    STATE_INITIAL SolverState = iota
    STATE_SOLVING
    STATE_SATISFIABLE
    STATE_UNSATISFIABLE
)

type Assignment struct {
    Atoms map[uint64]bool         // AtomID → value
    Level uint                    // Current decision level
}

type ConflictAnalyzer struct {
    graph *ImplicationGraph
}

type SearchStrategy struct {
    decisions []*Decision
    backtrack *BacktrackInfo
}

type Decision struct {
    AtomID  uint64
    Value   bool
    Level   uint
    Reason  string  // "heuristic", "forced", "assumption"
}

type BacktrackInfo struct {
    FromLevel uint
    ToLevel   uint
    Reason    *ir.Clause
}

type Heuristic interface {
    SelectVariable(assignment *Assignment) (uint64, error)
    SelectValue(atomID uint64) bool
    OnConflict(conflict *ir.Clause)
    OnLearn(clause *ir.Clause)
}

// VSIDS (Variable State Independent Decaying Sum) heuristic
type VSIDSHeuristic struct {
    activity map[uint64]float64
    decay    float64
}

// DOM (Dynamic, Occurrence, Moving) heuristic
type DOMHeuristic struct {
    occurrences map[uint64]int
    phase       map[uint64]bool
}

type SolveResult struct {
    Status    SolverStatus
    Model     *Model          // if SATISFIABLE
    Conflict  *ir.Clause      // if UNSATISFIABLE
    Stats     SolverStatistics
}

type SolverStatus int
const (
    STATUS_SATISFIABLE SolverStatus = iota
    STATUS_UNSATISFIABLE
    STATUS_UNKNOWN
    STATUS_TIMEOUT
)

type SolverStatistics struct {
    DecisionCount     uint64
    ConflictCount     uint64
    LearnedClauseCount uint64
    PropagationCount  uint64
    RestartCount      uint64
    ElapsedTime       time.Duration
}
```

### `aggregates/` Package

**Primary Types:**

```
type AggregateConstraint struct {
    Aggregate  *ast.Aggregate
    Nogoods    []*ir.Nogood
}

type CountConstraint struct {
    Variable      string
    Elements      []*AggregateElement
    Bound         int
    Comparison    ComparisonOp
}

type ComparisonOp int
const (
    CMP_EQ ComparisonOp = iota
    CMP_NEQ
    CMP_LT
    CMP_LE
    CMP_GT
    CMP_GE
)

type SumConstraint struct {
    Variable   string
    Elements   []*WeightedElement
    Bound      int
    Comparison ComparisonOp
}

type WeightedElement struct {
    Weight int
    Atom   *ast.Atom
    Args   []ast.Term
}
```

### `optimization/` Package

**Primary Types:**

```
type Optimizer struct {
    weakConstraints []*ast.WeakConstraint
    solver          *Solver
}

type OptimizationResult struct {
    BestModel    *Model
    Optimum      int
    AllModels    []*Model
    Satisfaction map[*Model]int  // Model → total weight
}
```

### `incremental/` Package

**Primary Types:**

```
type IncrementalSolver struct {
    baseState  *SolverSnapshot
    stack      []*SolverSnapshot
    solver     *Solver
    assumptions []uint64
}

type SolverSnapshot struct {
    Clauses     []*ir.Clause
    Nogoods     []*ir.Nogood
    Assignment  *Assignment
    Trail       *Trail
}

type IncrementalOp int
const (
    OP_PUSH IncrementalOp = iota
    OP_POP
    OP_ADD_RULE
    OP_ADD_ASSUMPTION
)
```

### `models/` Package

**Primary Types:**

```
type Model struct {
    TrueAtoms   map[uint64]bool       // AtomID → true (atoms in model)
    Rules       []*ir.GroundRule
    Atoms       []*ir.GroundAtom
    IsStable    bool
}

type ModelEnumerator struct {
    solver      *Solver
    models      []*Model
    blocking    []*ir.Clause         // Clauses to block previous models
}

type VerificationResult struct {
    IsStable   bool
    Violations []string  // Rules/constraints violated
}
```

### `api/` Package (Public Interface)

**Primary Types:**

```
type Config struct {
    Timeout       time.Duration
    MaxModels     int
    Heuristic     string  // "vsids", "dom", "custom"
    OptimizationMode OptimizationMode
    Incremental   bool
}

type OptimizationMode int
const (
    OPT_NONE OptimizationMode = iota
    OPT_MINIMIZE
    OPT_MAXIMIZE
)

type CompileResult struct {
    Program     *ast.Program
    Diagnostics *Diagnostics
    IsValid     bool
}

type ExecutionResult struct {
    Status  ExecutionStatus
    Models  []*Model
    Optimum int
    Stats   *ExecutionStatistics
}

type ExecutionStatus int
const (
    EXEC_SUCCESS ExecutionStatus = iota
    EXEC_UNSAT
    EXEC_TIMEOUT
    EXEC_ERROR
)

type ExecutionStatistics struct {
    ParseTime        time.Duration
    GroundingTime    time.Duration
    SolvingTime      time.Duration
    TotalTime        time.Duration
    TotalAtoms       uint64
    TotalRules       uint64
    TotalConstraints uint64
}
```

---

## Interface Contracts

### `lexer.Lexer` Interface

```go
type Lexer interface {
    // Scan reads the next token from the source.
    // Returns Token and any lexical error.
    Scan() (*Token, error)

    // NextToken advances to the next token and returns it.
    // Convenience wrapper combining Scan + position advancement.
    NextToken() (*Token, error)

    // Peek looks at the next token without advancing.
    Peek() (*Token, error)

    // Position returns the current source position.
    Position() Position

    // SetInput changes the input source.
    SetInput(source string) error

    // HasMore returns true if more tokens remain.
    HasMore() bool
}
```

**Implementation Contract:**
- Must handle all token types defined in `TokenType` enum
- Must track line/column for error reporting
- Must skip comments and whitespace correctly
- Must handle strings with escape sequences
- Must report lexical errors (unclosed strings, invalid chars) with position info

---

### `parser.Parser` Interface

```go
type Parser interface {
    // Parse reads the token stream and produces an AST.
    // Returns the AST Program, diagnostics (errors/warnings), and any fatal error.
    Parse(lexer Lexer) (*Program, *Diagnostics, error)

    // ParseRule parses a single rule from the lexer.
    ParseRule(lexer Lexer) (*ast.Rule, error)

    // ParseTerm parses a single term (atom, variable, compound, constant).
    ParseTerm(lexer Lexer) (ast.Term, error)

    // ParseBody parses a rule body (conjunction of literals).
    ParseBody(lexer Lexer) (*ast.Body, error)

    // Diagnostics returns accumulated parsing diagnostics.
    Diagnostics() *Diagnostics
}
```

**Implementation Contract:**
- Must produce an AST that satisfies `ast.Program` structure
- Must recover from parse errors and continue parsing (collect errors, don't bail)
- Must validate token types and sequences match grammar
- Must handle operator precedence correctly
- Must fill Position fields for all AST nodes
- Must report line/column info in all diagnostics

---

### `semantics.Validator` Interface

```go
type Validator interface {
    // Validate checks the program for semantic correctness.
    // Returns validation result with errors/warnings.
    Validate(program *ast.Program, symbols *symbols.Table) (*CheckResult, error)

    // CheckRule validates a single rule.
    CheckRule(rule *ast.Rule) (*CheckResult, error)

    // CheckSafety verifies rule safety (no unsafe variables).
    CheckSafety(rule *ast.Rule) bool

    // CheckNegativeCycle detects problematic negative cycles.
    CheckNegativeCycle() (*CheckResult, error)

    // Diagnostics returns accumulated validation diagnostics.
    Diagnostics() *Diagnostics
}
```

**Implementation Contract:**
- Must detect unsafe variables (appear in head or positive body only, never in negative body)
- Must detect undefined predicates
- Must detect negative cycles in dependency graph
- Must validate aggregate syntax and semantics
- Must validate choice rule bounds
- Must report errors with rule/literal reference
- Must not reject valid ASP programs

---

### `symbols.Table` Interface

```go
type Table interface {
    // RegisterAtom interns an atom string, returns its AtomID.
    RegisterAtom(name string) (AtomID, error)

    // RegisterVariable interns a variable string, returns its VarID.
    RegisterVariable(name string) (VarID, error)

    // RegisterPredicate interns a predicate (name/arity), returns PredicateID.
    RegisterPredicate(name string, arity int) (PredicateID, error)

    // LookupAtom retrieves an AtomID by name.
    LookupAtom(name string) (AtomID, bool)

    // LookupVariable retrieves a VarID by name.
    LookupVariable(name string) (VarID, bool)

    // LookupPredicate retrieves a PredicateID by (name, arity).
    LookupPredicate(name string, arity int) (PredicateID, bool)

    // GetAtomName retrieves the name for an AtomID.
    GetAtomName(id AtomID) (string, bool)

    // GetVariableName retrieves the name for a VarID.
    GetVariableName(id VarID) (string, bool)

    // GetPredicateName retrieves the name for a PredicateID.
    GetPredicateName(id PredicateID) (string, bool)

    // Freeze locks the symbol table (no new symbols allowed).
    Freeze()

    // IsFrozen checks if the table is frozen.
    IsFrozen() bool

    // Clear resets the symbol table.
    Clear()

    // Snapshot returns a copy of the current state.
    Snapshot() *Table
}
```

**Implementation Contract:**
- Must intern strings consistently (same string → same ID)
- Must be thread-safe for concurrent reads
- Must support rollback to previous snapshots
- Must maintain 1:1 mapping between IDs and names
- Must generate unique IDs within each category (atoms, vars, predicates)

---

### `ground.Grounder` Interface

```go
type Grounder interface {
    // Ground instantiates rules over the Herbrand universe.
    // Returns ground rules, atoms, and constraints.
    Ground(program *ast.Program, symbols *symbols.Table) (*GroundingResult, error)

    // ComputeDomain discovers the Herbrand universe.
    ComputeDomain(program *ast.Program) (*Domain, error)

    // GetIndex returns the predicate/literal index for fast lookup.
    GetIndex() *Index

    // CheckSafety performs safety checks on rules.
    CheckSafety() (*CheckResult, error)

    // Statistics returns grounding statistics (atoms, rules, etc.).
    Statistics() *GroundingStats
}
```

**Implementation Contract:**
- Must compute the complete Herbrand universe (all ground atoms)
- Must instantiate every rule for all possible ground substitutions
- Must handle negation-as-failure correctly in instantiation
- Must detect and handle infinite domains gracefully (error/timeout)
- Must produce only reachable ground atoms
- Must maintain indexing for efficient constraint propagation

---

### `propagation.Propagator` Interface

```go
type Propagator interface {
    // Propagate performs unit propagation under current assignment.
    // Returns implications (new unit clauses) and any conflict.
    Propagate(assignment *Assignment) (*PropagationResult, error)

    // SetClause adds a clause to the propagation engine.
    SetClause(clause *ir.Clause) error

    // SetNogood adds a nogood constraint.
    SetNogood(nogood *ir.Nogood) error

    // OnDecision notifies the propagator of a decision.
    OnDecision(atomID uint64, value bool) error

    // Explain generates the implication graph for conflict analysis.
    Explain(atomID uint64) (*ImplicationGraph, error)

    // Reset clears internal state (e.g., watched literals).
    Reset() error
}
```

**Implementation Contract:**
- Must detect all unit propagation implications
- Must detect conflicts correctly (both clause and nogood violations)
- Must use watched literals for efficient clause scanning
- Must maintain implication graph for conflict analysis
- Must support backtracking (undo decisions and implications)
- Must not create duplicate implications

---

### `solver.Solver` Interface

```go
type Solver interface {
    // Solve performs SAT/ASP solving.
    // Returns satisfiability status, model (if satisfiable), and statistics.
    Solve() (*SolveResult, error)

    // SolveWith solves with additional assumptions (hard constraints).
    SolveWith(assumptions []uint64) (*SolveResult, error)

    // AddClause adds a new clause to the solver.
    AddClause(clause *ir.Clause) error

    // AddNogood adds a new nogood constraint.
    AddNogood(nogood *ir.Nogood) error

    // GetModel returns the current satisfying assignment (after Solve).
    GetModel() (*Model, error)

    // SetHeuristic changes the variable selection heuristic.
    SetHeuristic(h Heuristic) error

    // Reset clears the solver state.
    Reset() error

    // Statistics returns solver statistics (decisions, conflicts, etc.).
    Statistics() *SolverStatistics
}
```

**Implementation Contract:**
- Must implement CDCL (Conflict-Driven Clause Learning) algorithm
- Must perform unit propagation via Propagator
- Must handle backtracking and trail management
- Must detect unsatisfiability and prove it
- Must learn clauses from conflicts
- Must support variable heuristics (VSIDS, DOM, etc.)
- Must handle incremental assumptions

---

### `models.ModelEnumerator` Interface

```go
type ModelEnumerator interface {
    // EnumerateModels finds all stable models.
    // Yields models one at a time (iterator pattern).
    EnumerateModels(program *ast.Program) (*ModelIterator, error)

    // VerifyModel checks if a proposed model is stable.
    VerifyModel(model *Model) (*VerificationResult, error)

    // Statistics returns enumeration statistics.
    Statistics() *EnumerationStats
}

type ModelIterator interface {
    // Next retrieves the next model.
    // Returns nil when exhausted.
    Next() (*Model, error)

    // HasNext checks if more models remain.
    HasNext() bool

    // Count returns total models found so far.
    Count() int
}
```

**Implementation Contract:**
- Must enumerate all and only stable models
- Must not enumerate duplicate models
- Must verify model stability (reduct satisfaction)
- Must support iterative enumeration (don't require loading all models into memory)
- Must handle non-termination gracefully (timeout/limit)

---

### `incremental.IncrementalSolver` Interface

```go
type IncrementalSolver interface {
    // Push creates a new scope level on the assumption stack.
    Push() error

    // Pop returns to the previous scope level.
    Pop() error

    // AddRule adds a new rule to the current scope.
    AddRule(rule *ast.Rule) error

    // AddAssumption adds a hard assumption (must be true).
    AddAssumption(atomID uint64) error

    // Solve performs solving in the current scope.
    Solve() (*SolveResult, error)

    // GetModel returns the model in the current scope.
    GetModel() (*Model, error)

    // ScopeDepth returns the current scope level.
    ScopeDepth() int
}
```

**Implementation Contract:**
- Must maintain a stack of solver states
- Must support arbitrary Push/Pop nesting
- Must make assumptions visible in all nested scopes
- Must revert rules when popping
- Must share learned clauses across scopes (when valid)
- Must not lose state information when pushing

---

### `api.PublicAPI` Interface

```go
type PublicAPI interface {
    // Parse reads source code and produces an AST.
    Parse(source string) (*CompileResult, error)

    // Compile parses and performs semantic checks.
    Compile(source string, config *Config) (*CompileResult, error)

    // Solve performs full solve: parse → ground → solve.
    Solve(source string, config *Config) (*ExecutionResult, error)

    // SolveProgram solves a pre-compiled program.
    SolveProgram(program *ast.Program, config *Config) (*ExecutionResult, error)

    // Optimize finds models minimizing/maximizing weak constraints.
    Optimize(source string, mode OptimizationMode, config *Config) (*ExecutionResult, error)

    // EnumerateModels finds all stable models.
    EnumerateModels(source string) (*ModelEnumerator, error)

    // SetConfig updates the solver configuration.
    SetConfig(config *Config) error

    // GetConfig returns the current configuration.
    GetConfig() *Config
}
```

**Implementation Contract:**
- Must provide unified entry point for all use cases
- Must handle errors gracefully and report diagnostics
- Must support both batch and incremental workflows
- Must return timing and statistics
- Must validate configuration parameters
- Must support concurrent calls (thread-safe)

---

## Initialization Order

### Phase 1: Foundation (No Dependencies)

1. **symbols.Table**: Initialize global symbol interning
2. **lexer.Lexer**: Set up tokenization state, keywords table
3. **ast.Node**: Register AST node types (internal type system)

### Phase 2: Parsing & Syntax

4. **parser.Parser**: Initialize with Lexer and AST builder
5. **semantics.Validator**: Initialize with symbol table reference

### Phase 3: Intermediate Representation

6. **ir.GroundAtom**: Set up atom ID space, initialize counters
7. **normalize.Normalizer**: Initialize rule transformer
8. **symbols.Table**: Freeze symbol table (no new symbols after grounding)

### Phase 4: Grounding

9. **ground.Domain**: Compute Herbrand universe
10. **ground.Index**: Build predicate/literal index
11. **ground.SafetyChecker**: Verify rule safety
12. **ground.Grounder**: Instantiate all ground rules

### Phase 5: Constraint System

13. **constraints.NoGoodGenerator**: Create nogoods from ground rules
14. **ir.Clause**: Build CNF representation

### Phase 6: Solving Infrastructure

15. **propagation.Propagator**: Initialize watched literals, implication graph
16. **aggregates.AggregateConstraint**: Set up aggregate propagation rules
17. **solver.Assignment**: Initialize variable/value assignment tracking
18. **solver.ConflictAnalyzer**: Set up conflict analysis engine
19. **solver.Heuristic**: Initialize variable heuristic (VSIDS, DOM, etc.)
20. **solver.Solver**: Assemble complete CDCL solver

### Phase 7: High-Level Services

21. **optimization.Optimizer**: Set up weak constraint handler
22. **incremental.IncrementalSolver**: Prepare incremental solving state
23. **models.ModelEnumerator**: Initialize model enumeration
24. **api.PublicAPI**: Wire all components together
25. **cli.CLI**: Attach to API for user interaction

**Dependency Invariant:** Phase N only depends on Phases 1–(N-1).

---

## Cross-Module Integration

### Data Flow: From Source to Solving

```
Source Code
    ↓
  lexer.Scan()          [tokenize]
    ↓
  parser.Parse()        [token → AST]
    ↓
  semantics.Validate()  [check safety, define check]
    ↓
  symbols.Table         [intern atoms, predicates]
    ↓
  normalize.Normalize() [expand choices, rewrite rules]
    ↓
  ground.Domain         [compute Herbrand universe]
    ↓
  ground.Grounder       [instantiate all ground rules]
    ↓
  constraints.Generate()  [convert to clauses/nogoods]
    ↓
  propagation.Propagator  [set up BCP, watched literals]
    ↓
  solver.Solver         [execute CDCL search]
    ↓
  models.Enumerator     [enumerate stable models]
    ↓
Model / Optimum / UNSAT
```

### Key Integration Points

#### **1. Lexer ↔ Parser**
- Parser calls `Lexer.NextToken()` in a loop
- Lexer reports `TokenType` for grammar recognition
- Error recovery: Parser handles `TOKEN_ERROR` gracefully

#### **2. Parser ↔ AST**
- Parser constructs AST nodes (`Rule`, `Literal`, `Aggregate`, etc.)
- AST provides type hierarchy for pattern matching
- Position fields flow from Lexer → Parser → AST for diagnostics

#### **3. AST ↔ Semantics**
- Validator traverses AST to check safety, cycles, undefined predicates
- Returns ValidationError with rule/literal references for error reporting
- Validator uses Symbol Table to resolve predicate names

#### **4. Semantics ↔ Symbols**
- Validator calls `symbols.Table.RegisterPredicate()` during traversal
- Symbols are frozen after validation (prevents late additions)
- Table provides AtomID/VarID for next phases

#### **5. Normalize ↔ IR**
- Normalizer expands choice rules: `{a; b} :- body.` → multiple rules
- Produces `ir.GroundRule` even before grounding (rules in normal form)
- Rewritten rules have consistent head/body structure

#### **6. IR ↔ Ground**
- Grounder reads normalized rules from IR
- Computes domain using term/atom analysis
- Produces fully instantiated `ir.GroundRule` objects
- Attached indexed Index for fast clause lookup

#### **7. Ground ↔ Constraints**
- ConstraintGenerator converts each GroundRule → Clause(s)
- Head disjunction `a | b :- c.` → clauses: `a ∨ b ∨ ¬c`, etc.
- Aggregate constraints become complex nogood sets

#### **8. Constraints ↔ Propagation**
- Propagator loads clauses/nogoods from ConstraintGenerator
- Sets up watched literals for efficient unit propagation
- Reports conflicts (unsatisfied clauses) back to solver

#### **9. Propagation ↔ Solver**
- Solver calls `Propagator.Propagate(assignment)` after each decision
- Propagator returns implications (new unit assignments)
- Conflicts trigger conflict analysis in Solver

#### **10. Solver ↔ ConflictAnalyzer**
- Conflict analysis walks implication graph from Propagator
- Learns clauses and adds them back to Propagator
- Generates backtrack level from analysis

#### **11. Solver ↔ Heuristic**
- Solver calls `Heuristic.SelectVariable()` to choose next decision
- Heuristic uses activity/occurrence data from conflicts/learns
- Updates on conflict (CbB) and learn events

#### **12. Solver ↔ Aggregates**
- Aggregate constraints are checked by Propagator
- Aggregate nogood sets are added to clause set
- On assignment change, aggregates recalculate bounds

#### **13. Solver ↔ Optimization**
- After solving to SAT, Optimizer blocks current model
- Adds weak constraints as nogoods/clauses
- Re-invokes Solver until UNSAT (found optimum)

#### **14. Solver ↔ Incremental**
- IncrementalSolver wraps Solver, maintains stack of snapshots
- `Push()` saves Solver state; `Pop()` restores previous state
- `AddRule()` adds to top-of-stack, affects Solve in that scope

#### **15. Solver ↔ Models**
- After SAT from Solver, ModelEnumerator verifies stability (model is stable model)
- Enumerator adds blocking clause and re-invokes Solver
- Loop until UNSAT (all models enumerated)

#### **16. API ↔ All Components**
- PublicAPI orchestrates phases: Parse → Compile → Ground → Solve
- Error handling: collects diagnostics from each phase
- Timing: wraps each phase call with time measurement

#### **17. CLI ↔ API**
- CLI parses command-line arguments into Config
- Calls appropriate API method (Solve, Optimize, Enumerate)
- Formats and prints Model/results to stdout

### Error Propagation Strategy

```
Lexer Error
    ↓
Parser (collects, continues)
    ↓
ParseError[] → Diagnostics
    ↓
(if fatal, report and stop)
    ↓
    └→ Semantics
       │
       └→ ValidationError[] → Diagnostics
          │
          (if fatal, report and stop)
          │
          └→ Ground
             │
             └→ GroundingError → stop
                │
                └→ Constraints
                   │
                   └→ Solver
                      │
                      └→ SolveResult (SAT/UNSAT/ERROR)
```

---

## Error Handling Strategy

### Error Categories

#### **1. Lexical Errors** (lexer package)
- Unclosed string: `"unterminated`
- Invalid escape sequence: `"\x"`
- Invalid token: `@`
- Line/column reported
- **Handling**: Log and skip to next valid token

#### **2. Syntactic Errors** (parser package)
- Missing `.` at end of rule
- Unmatched parentheses
- Invalid operator usage
- **Handling**: Error recovery (panic modes), continue parsing to collect multiple errors

#### **3. Semantic Errors** (semantics package)
- Unsafe variables (in head/positive, not in negative)
- Undefined predicates
- Negative cycles in dependency graph
- Aggregate syntax errors
- **Handling**: Collect all errors, report at end, mark program as invalid

#### **4. Grounding Errors** (ground package)
- Infinite domain (unbounded variables)
- Safety violation prevents instantiation
- **Handling**: Timeout after N atoms; report error with rule context

#### **5. Constraint Generation Errors** (constraints package)
- Invalid aggregate bounds
- Conflicting constraint semantics
- **Handling**: Report and skip problematic rule

#### **6. Solving Errors** (solver package)
- Timeout during search
- Resource exhaustion (memory)
- Heuristic failure
- **Handling**: Return STATUS_TIMEOUT/ERROR with partial statistics

### Error Types & Contracts

```go
// Base error interface
type Error interface {
    error
    Code() string           // Machine-readable error code
    Position() *Position    // Source location (if applicable)
    Context() string        // Snippet of source around error
    Severity() Severity     // ERROR, WARNING, INFO
}

type Severity int
const (
    SEV_ERROR Severity = iota
    SEV_WARNING
    SEV_INFO
)

// Specific error types (per package)
type LexError struct {
    Code      string
    Position  Position
    Message   string
    Lexeme    string
}

type ParseError struct {
    Code      string
    Position  Position
    Expected  TokenType
    Actual    Token
    Context   string
}

type ValidationError struct {
    Code      string
    Rule      *ast.Rule
    Literal   *ast.Literal
    Message   string
}

type GroundingError struct {
    Code      string
    Rule      *ast.Rule
    Message   string
}

type SolvingError struct {
    Code      string
    Message   string
}
```

---

## Summary Table: Module Responsibilities

| Module | Responsibility | Input | Output | Key Contract |
|--------|-----------------|-------|--------|--------------|
| **lexer** | Tokenization | Source string | Token stream | Accurate positions, complete token types |
| **parser** | Syntax analysis | Token stream | AST | Error recovery, detailed diagnostics |
| **ast** | Type definitions | — | Type hierarchy | Complete coverage of ASP constructs |
| **semantics** | Semantic validation | AST | Diagnostics | Detect unsafe vars, cycles, undefined preds |
| **symbols** | Symbol interning | Names | IDs | 1:1 mapping, thread-safe |
| **ir** | Constraint IR | AST | Ground rules, clauses, nogoods | Canonical representation |
| **normalize** | Rule transformation | IR rules | Normalized rules | Correct choice expansion |
| **ground** | Instantiation | AST, domain | Ground rules, atoms | Complete Herbrand universe |
| **constraints** | Constraint generation | Ground rules | Clauses, nogoods | Correct semantics |
| **propagation** | Unit propagation | Clauses, assignment | Implications, conflicts | Fast, correct BCP |
| **solver** | CDCL search | Clauses, nogoods | SAT/UNSAT decision, model | Proven correctness, efficiency |
| **aggregates** | Aggregate handling | Aggregates | Propagation rules | Correct semantics, efficient |
| **optimization** | Weak constraints | Weak constraints, model | Optimum | Correct minimization/maximization |
| **incremental** | Stateful solving | Stack operations | Scoped solving | Correct push/pop, shared learning |
| **models** | Model enumeration | Solver | All stable models | Correctness of stable model check |
| **api** | Public interface | — | Unified API | Clean, complete, documented |
| **cli** | User interaction | Command-line args | Formatted output | Usable interface, good error messages |

---

## Conclusion

This 12-component architecture provides:

1. **Clear Separation of Concerns**: Each module has one responsibility
2. **Testability**: Modules can be tested independently
3. **Composability**: Data flows in strict dependency order
4. **Extensibility**: Interfaces enable custom heuristics, propagators, optimizers
5. **Performance**: Layering allows optimization at each level (indexing, watched literals, learning)
6. **Maintainability**: Well-defined contracts make changes safe and localized

**No implementation code included.** Specification serves as blueprint for implementation phase.
