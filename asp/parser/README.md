# ASP Parser Package

A complete recursive descent parser for Answer Set Programming (ASP) syntax in Go.

## Overview

The parser package implements a full-featured parser for Answer Set Programming, transforming tokens from the lexer into an Abstract Syntax Tree (AST). It supports all major ASP constructs including facts, rules, constraints, aggregates, choice rules, and directives.

## Features

- **Recursive Descent Parsing**: Clean, maintainable parser implementation
- **Error Recovery**: Continues parsing after errors for better diagnostics
- **Position Tracking**: Full source location information for error reporting
- **Comprehensive AST**: Complete representation of all ASP language features
- **Type-Safe**: Leverages Go's type system for safe AST manipulation

## Supported Syntax

### Basic Facts and Rules

```prolog
% Facts
bird(tweety).
parent(john, mary).

% Rules
flies(X) :- bird(X), not abnormal(X).
sibling(X, Y) :- parent(Z, X), parent(Z, Y).
```

### Constraints

```prolog
% Integrity constraints
:- negative_body.
:- not peaceful, conflict.

% Comparison constraints
old(X) :- age(X, Y), Y > 65.
match(X, Y) :- value(X, V), value(Y, V).
```

### Negation as Failure

```prolog
safe(X) :- not dangerous(X).
```

### Choice Rules

```prolog
% Exactly one choice
{ p(X) : item(X) } = 1.

% At least one choice
{ color(X, C) : color(C) } >= 1.

% Multiple choices with constraint
{ paint(X, C) : color(C) } = 1 :- node(X).
```

### Aggregates

```prolog
% Count aggregate
query :- #count { X : person(X) } >= 2.

% Sum aggregate
balance(N) :- #sum { C,X : cost(X,C) } = N.

% Min/Max aggregates
min_val(M) :- #min { X : value(X) } = M.
max_val(M) :- #max { X : value(X) } = M.
```

### Disjunctive Rules

```prolog
a(X) | b(X) :- c(X).
p | q | r.
```

### Directives

```prolog
#show person/1.
#hide fact/0.
#assert rule(X).
```

## Usage

### Basic Parsing

```go
package main

import (
    "fmt"
    "devflow-finance-twin/asp/lexer"
    "devflow-finance-twin/asp/parser"
)

func main() {
    source := `
        bird(tweety).
        flies(X) :- bird(X), not abnormal(X).
        abnormal(tweety).
    `

    l := lexer.NewLexer(source, "program.lp")
    p := parser.NewParser(l)
    
    statements, errors := p.Parse()
    
    if len(errors) > 0 {
        fmt.Printf("Parse errors: %v\n", errors)
        return
    }
    
    fmt.Printf("Successfully parsed %d statements\n", len(statements))
}
```

### Accessing AST Nodes

```go
for _, stmt := range statements {
    if ruleStmt, ok := stmt.(*ast.RuleStatement); ok {
        rule := ruleStmt.Rule
        
        // Access rule head
        for _, atom := range rule.Head.Atoms {
            fmt.Printf("Head atom: %s\n", atom.Atom.Name)
        }
        
        // Access rule body
        for _, lit := range rule.Body {
            if lit.Aggregate != nil {
                fmt.Printf("Aggregate: #%s\n", lit.Aggregate.Op)
            }
        }
    }
}
```

## Parser Architecture

### Token Management

- `advance()`: Moves to the next token
- `match(TokenType)`: Checks current token without advancing
- `expect(TokenType)`: Validates and consumes a token
- Error recovery for graceful degradation

### Main Components

1. **Parse()**: Top-level entry point, returns statements and errors
2. **parseStatement()**: Parses facts, rules, constraints, directives
3. **parseHead()**: Parses rule heads (normal, choice, disjunctive)
4. **parseBody()**: Parses conjunctions of literals
5. **parseLiteral()**: Parses atoms, negation, comparisons, aggregates
6. **parseTerm()**: Parses terms (atoms, variables, constants, compounds)
7. **parseAggregate()**: Parses aggregate expressions
8. **parseDirective()**: Parses special directives

### Error Handling

The parser implements error recovery by:
- Recording all errors with source position
- Attempting to recover at statement boundaries
- Continuing to parse remaining statements
- Returning all collected errors for diagnostics

## AST Types

All parsed constructs are represented using types from the `ast` package:

- `Statement`: Top-level program element
- `RuleStatement`: Wraps a rule
- `Rule`: Fact, rule, constraint, or choice rule
- `Head`: Rule head with atoms
- `Literal`: Body element (atom, comparison, aggregate)
- `Term`: Logical terms
- `Aggregate`: Count, sum, min, max expressions
- `Directive`: Special directives

## Testing

Comprehensive test suite in `parser_test.go` covers:

- Simple facts and rules
- Complex rules with multiple body atoms
- Constraints and negation
- Compound terms and arguments
- Aggregates with bounds
- Choice rules
- Directives
- Disjunctive heads
- Error recovery
- Arithmetic expressions
- Comparison operators
- String and integer constants

Run tests with:
```bash
go test ./asp/parser/
```

## Implementation Details

### Parsing Strategy

Uses recursive descent parsing with:
- Single token lookahead (current + peek)
- Left-to-right scanning
- Operator precedence for arithmetic
- Error recovery at statement boundaries

### Performance

- Single-pass parsing: O(n) where n = number of tokens
- No backtracking required
- Efficient token stream handling
- Minimal memory overhead

### Limitations

- No user-defined operators (fixed operator set)
- No floating-point constants (integers and strings only)
- Choice rules limited to basic cardinality constraints
- No nested aggregates

## Code Statistics

- **Lines of Code**: 883 (parser.go)
- **Test Cases**: 20+
- **Supported Constructs**: 8 major ASP features
- **Functions**: 40+

## Related Packages

- `devflow-finance-twin/asp/lexer`: Tokenization
- `devflow-finance-twin/asp/ast`: AST type definitions
- `devflow-finance-twin/asp/semantics`: Semantic validation

## Future Enhancements

- User-defined operators
- Floating-point number support
- Nested aggregates
- More sophisticated error messages
- AST pretty-printing utilities
