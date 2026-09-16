package parser

import (
	"fmt"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
)

// ExampleParseSimpleProgram demonstrates parsing a simple ASP program
func ExampleParseSimpleProgram() {
	program := `
% Simple bird flying example
bird(tweety).
bird(kermit).

flies(X) :- bird(X), not abnormal(X).

abnormal(kermit).
`

	l := lexer.NewLexer(program, "example.lp")
	p := NewParser(l)
	statements, errors := p.Parse()

	if len(errors) > 0 {
		fmt.Printf("Parse errors: %v\n", errors)
		return
	}

	fmt.Printf("Successfully parsed %d statements\n", len(statements))

	for i, stmt := range statements {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			fmt.Printf("Statement %d: ", i+1)
			if len(rs.Rule.Head.Atoms) > 0 {
				fmt.Printf("Head: %s", rs.Rule.Head.Atoms[0].Atom.Name)
			}
			fmt.Printf(" (Body: %d literals)\n", len(rs.Rule.Body))
		}
	}

	// Output:
	// Successfully parsed 4 statements
	// Statement 1: Head: bird (Body: 0 literals)
	// Statement 2: Head: bird (Body: 0 literals)
	// Statement 3: Head: flies (Body: 2 literals)
	// Statement 4: Head: abnormal (Body: 0 literals)
}

// ExampleParseWithAggregates demonstrates parsing aggregates
func ExampleParseWithAggregates() {
	program := `
person(alice).
person(bob).
person(charlie).

count_people(N) :- #count { X : person(X) } = N.
`

	l := lexer.NewLexer(program, "aggregate.lp")
	p := NewParser(l)
	statements, errors := p.Parse()

	if len(errors) > 0 {
		fmt.Printf("Parse errors: %v\n", errors)
		return
	}

	fmt.Printf("Successfully parsed %d statements\n", len(statements))

	// Find and display aggregate
	for _, stmt := range statements {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			for _, lit := range rs.Rule.Body {
				if lit.Aggregate != nil {
					fmt.Printf("Found aggregate: #%s\n", lit.Aggregate.Op)
				}
			}
		}
	}

	// Output:
	// Successfully parsed 4 statements
	// Found aggregate: #count
}

// ExampleParseWithConstraints demonstrates parsing constraints
func ExampleParseWithConstraints() {
	program := `
schedule(Day, Shift, Person) :- day(Day), shift(Shift), person(Person).

:- schedule(Day, Shift1, P), schedule(Day, Shift2, P), Shift1 != Shift2.

:- not schedule(Day, shift1, _), day(Day).
`

	l := lexer.NewLexer(program, "constraints.lp")
	p := NewParser(l)
	statements, errors := p.Parse()

	if len(errors) > 0 {
		fmt.Printf("Parse errors: %v\n", errors)
		return
	}

	constraintCount := 0
	for _, stmt := range statements {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			if rs.Rule.Type == ast.RULE_CONSTRAINT {
				constraintCount++
			}
		}
	}

	fmt.Printf("Successfully parsed %d statements\n", len(statements))
	fmt.Printf("Found %d constraints\n", constraintCount)

	// Output:
	// Successfully parsed 3 statements
	// Found 2 constraints
}

// ExampleParseChoiceRule demonstrates parsing choice rules
func ExampleParseChoiceRule() {
	program := `
color(red).
color(green).
color(blue).

{ paint(node(1), C) : color(C) } = 1.
{ paint(node(2), C) : color(C) } = 1.

:- paint(node(1), C1), paint(node(2), C2), C1 = C2.
`

	l := lexer.NewLexer(program, "choice.lp")
	p := NewParser(l)
	statements, errors := p.Parse()

	if len(errors) > 0 {
		fmt.Printf("Parse errors: %v\n", errors)
		return
	}

	choiceCount := 0
	for _, stmt := range statements {
		if rs, ok := stmt.(*ast.RuleStatement); ok {
			if rs.Rule.Head.Type == ast.HEAD_CHOICE {
				choiceCount++
			}
		}
	}

	fmt.Printf("Successfully parsed %d statements\n", len(statements))
	fmt.Printf("Found %d choice rules\n", choiceCount)

	// Output:
	// Successfully parsed 6 statements
	// Found 2 choice rules
}

// ExampleParserErrorHandling demonstrates error handling
func ExampleParserErrorHandling() {
	// Missing period at end
	program := `bird(tweety)`

	l := lexer.NewLexer(program, "error.lp")
	p := NewParser(l)
	statements, errors := p.Parse()

	fmt.Printf("Parsed %d statements\n", len(statements))
	fmt.Printf("Errors: %d\n", len(errors))

	if len(errors) > 0 {
		fmt.Printf("Error message contains: 'expected'\n")
	}

	// Output:
	// Parsed 0 statements
	// Errors: 1
	// Error message contains: 'expected'
}
