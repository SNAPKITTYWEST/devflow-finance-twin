# ASP Semantics Package

## Overview

The `semantics` package provides comprehensive semantic validation for Answer Set Programming (ASP) programs. It performs multi-pass analysis to detect errors, warnings, and informational messages related to program correctness.

## Package Contents

### Core Files

1. **validator.go** (481 LOC)
   - Primary semantic analysis implementation
   - `Validator` struct with multi-pass validation
   - Core checking methods: `ValidateProgram`, `CheckSafety`, `CheckUndefined`, `CheckAggregates`
   - Diagnostic generation and reporting

2. **checker.go** (535 LOC)
   - Advanced semantic checking
   - `Checker` struct for fine-grained analysis
   - Stratification checking
   - Consistency validation
   - Aggregate usage patterns
   - Choice rule validation
   - Constraint structure validation

3. **semantics_test.go** (480 LOC)
   - Comprehensive test suite with 10 test cases
   - Test helpers for AST construction
   - Benchmark functions
   - Coverage of all validation rules

## Core Types

### Diagnostic

Represents a validation message with severity, location, and suggestions:

```go
type Diagnostic struct {
    File       string    // Source file
    Line       int       // Line number
    Column     int       // Column number
    Severity   Severity  // ERROR, WARNING, INFO
    Code       string    // Machine-readable error code
    Message    string    // Human-readable message
    Suggestion string    // Fix suggestion
    Context    string    // Source context
}
```

### Validator

Main semantic validation engine:

```go
type Validator struct {
    undefined   map[string]bool  // Undefined predicates
    defined     map[string]bool  // Defined predicates
    diagnostics []Diagnostic     // Collected diagnostics
    rules       []*ast.Rule      // Program rules
    currentFile string           // File being validated
}
```

### Checker

Advanced checker for consistency and patterns:

```go
type Checker struct {
    validator      *Validator
    rules          []*ast.Rule
    diagnostics    []Diagnostic
    dependencyMap  map[string][]string
    aggregateRules []*ast.Rule
}
```

## Validation Checks

### 1. Safety Check (`CheckSafety`)
Verifies that all variables in rule heads appear in positive body literals.

**Error Code:** `unsafe_var`
**Example:**
```
p(X) :- q(Y).  // X not in positive body → unsafe_var error
```

### 2. Undefined Predicate Check (`CheckUndefined`)
Ensures all used predicates are either defined or built-in.

**Error Code:** `undefined_pred`
**Built-ins:** `=`, `!=`, `<`, `>`, `<=`, `>=`, `is`, `true`, `false`, `fail`

### 3. Aggregate Validation (`CheckAggregates`)
Validates aggregate syntax and semantics.

**Supported Aggregates:** `#count`, `#sum`, `#min`, `#max`
**Error Codes:** 
- `invalid_aggregate_op`
- `invalid_aggregate_condition`

### 4. Negative Cycle Detection
Detects unstratifiable programs (negative cycles).

**Error Code:** `negative_cycle`
**Pattern:** Direct or indirect negation cycle

### 5. Stratification Checking (`checkStrictly`)
Verifies strict stratification property.

**Warning Code:** `non_stratifiable`
**Info Code:** `stratification_timeout`

### 6. Recursion Detection (`checkRecursion`)
Identifies left-recursive predicates.

**Info Code:** `left_recursion`

### 7. Aggregate Usage (`checkAggregateUsage`)
Validates aggregate usage patterns.

**Warning Codes:**
- `aggregate_in_choice`
- `aggregate_no_variables`

**Info Codes:**
- `sum_aggregate_unbounded`

### 8. Choice Rule Validation (`checkChoiceRules`)
Ensures proper choice rule structure.

**Info Codes:**
- `single_choice` (single-atom choice)
- `free_choice` (choice without body)

### 9. Constraint Validation (`checkConstraints`)
Validates constraint rule structure.

**Error Codes:**
- `constraint_with_head` (constraint has head)
- `empty_constraint` (constraint has no body)

### 10. Consistency Checking (`CheckConsistency`)
Detects inconsistent program patterns.

**Warning Code:** `duplicate_rule`
**Info Code:** `mixed_definition`

## Public API

### Functions

```go
// Create validator
func NewValidator() *Validator

// Perform validation
func (v *Validator) ValidateProgram(program []ast.Statement) []Diagnostic

// Check safety
func (v *Validator) CheckSafety(rule *ast.Rule) error

// Check undefined predicates
func (v *Validator) CheckUndefined(program []ast.Statement) []Diagnostic

// Check aggregates
func (v *Validator) CheckAggregates(agg *ast.Aggregate) error

// Get diagnostics
func (v *Validator) GetDiagnostics() []Diagnostic

// Query diagnostic status
func (v *Validator) HasErrors() bool
func (v *Validator) ErrorCount() int
func (v *Validator) WarningCount() int
```

### Checker Functions

```go
// Create checker
func NewChecker(v *Validator) *Checker

// Full program checking
func (c *Checker) CheckProgram(program []ast.Statement) []Diagnostic

// Consistency checking
func (c *Checker) CheckConsistency(program []ast.Statement) []Diagnostic

// Utilities
func SortDiagnostics(diags []Diagnostic)
func FormatDiagnostics(diags []Diagnostic) string
func ValidateSemantically(program []ast.Statement) ([]Diagnostic, bool)
```

## Usage Example

```go
package main

import (
    "fmt"
    "devflow-finance-twin/asp/ast"
    "devflow-finance-twin/asp/semantics"
)

func main() {
    // Create program AST
    program := []ast.Statement{
        &ast.RuleStatement{
            Rule: &ast.Rule{
                Head: &ast.Head{
                    Atoms: []*ast.HeadAtom{
                        {Atom: &ast.Atom{Name: "ancestor"}},
                    },
                },
                Body: []*ast.Literal{
                    {
                        Positive: true,
                        Atom: &ast.Atom{Name: "parent"},
                    },
                },
            },
        },
    }

    // Validate
    validator := semantics.NewValidator()
    diags := validator.ValidateProgram(program)

    // Check for errors
    if validator.HasErrors() {
        fmt.Printf("Found %d errors\n", validator.ErrorCount())
        for _, d := range diags {
            fmt.Println(d)
        }
    }

    // Use checker for additional analysis
    checker := semantics.NewChecker(validator)
    checkerDiags := checker.CheckProgram(program)
    
    // Format and print all diagnostics
    fmt.Println(semantics.FormatDiagnostics(append(diags, checkerDiags...)))
}
```

## Error Codes Reference

| Code | Severity | Meaning |
|------|----------|---------|
| `unsafe_var` | ERROR | Variable in head not in positive body |
| `undefined_pred` | ERROR | Predicate used but not defined |
| `undefined_pred_aggregate` | ERROR | Predicate in aggregate not defined |
| `negative_cycle` | ERROR | Unstratifiable through negation |
| `constraint_with_head` | ERROR | Constraint rule has head |
| `empty_constraint` | ERROR | Constraint rule has no body |
| `invalid_aggregate_op` | ERROR | Invalid aggregate operation |
| `invalid_aggregate_condition` | ERROR | Invalid aggregate condition |
| `non_stratifiable` | WARNING | Non-stratifiable recursion |
| `aggregate_in_choice` | WARNING | Aggregate in choice rule |
| `aggregate_no_variables` | WARNING | Aggregate has no variables |
| `duplicate_rule` | WARNING | Duplicate rule definition |
| `stratification_timeout` | WARNING | Stratification analysis timeout |
| `left_recursion` | INFO | Left-recursive predicate |
| `free_choice` | INFO | Free choice rule |
| `single_choice` | INFO | Single-atom choice rule |
| `sum_aggregate_unbounded` | INFO | Unbounded sum aggregate |
| `mixed_definition` | INFO | Predicate both fact and derived |

## Design Notes

### Multi-Pass Validation

The `ValidateProgram` method performs 5 passes:

1. **Predicate Collection:** Collect all defined predicates
2. **Undefined Check:** Check all predicates are defined
3. **Safety Check:** Verify head variables in positive body
4. **Aggregate Check:** Validate aggregate syntax
5. **Cycle Detection:** Check for negative cycles

### Predicate Identification

Predicates are uniquely identified by `name/arity` to handle overloading:
- `parent/2` is different from `parent/3`
- Comparison operators have variable arity

### Built-in Predicates

The package recognizes standard built-in predicates and doesn't report them as undefined:
- Arithmetic: `is`, `+`, `-`, `*`, `/`, `mod`
- Comparison: `<`, `>`, `<=`, `>=`, `=`, `!=`
- Logic: `true`, `false`, `fail`, `!`, `\+`

### Stratification Algorithm

Implements iterative stratum assignment with cycle detection. Supports up to 100 iterations before timeout.

## Performance Characteristics

- **Time Complexity:** O(n × m) where n = number of rules, m = literals per rule
- **Space Complexity:** O(n + p) where p = number of predicates
- **Typical Throughput:** 1000s of rules per second

## Testing

Run tests with:
```bash
go test -v ./semantics
```

Run benchmarks with:
```bash
go test -bench=. ./semantics
```

Test coverage includes:
- Undefined predicates (Test 1)
- Unsafe variables (Test 2)
- Safe rules (Test 3)
- Aggregates (Tests 4-5)
- Stratification (Test 6)
- Diagnostics summary (Test 7)
- Consistency (Test 8)
- Choice rules (Test 9)
- Anonymous variables (Test 10)
- Benchmarks (100-rule program)

## Integration

The semantics package integrates with:
- **Upstream:** `ast` package (AST types)
- **Downstream:** `ir`, `ground`, `constraints` packages (compilation stages)

Typically used after parsing and before grounding/constraint generation in the ASP pipeline.
