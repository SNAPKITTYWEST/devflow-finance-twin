// Package asp is the public entry point for the ASP (Answer Set Programming) parser.
// External consumers should import this package; do not import sub-packages directly.
//
// Usage:
//
//	statements, errs := asp.Parse(src)
//	statements, errs := asp.ParseFile(src, "program.asp")
package asp

import (
	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
	"devflow-finance-twin/asp/parser"
)

// Re-export primary AST types so consumers need only import this package.
type (
	// Statement is the top-level interface for any parsed ASP statement.
	Statement = ast.Statement

	// Rule represents a complete ASP rule (head :- body.).
	Rule = ast.Rule

	// RuleStatement wraps a Rule as a Statement.
	RuleStatement = ast.RuleStatement

	// Directive represents a meta-directive such as #show or #const.
	Directive = ast.Directive

	// Program is a parsed collection of statements.
	Program = ast.Program

	// Literal is a positive or negative body/head literal.
	Literal = ast.Literal

	// Head represents the head of an ASP rule.
	Head = ast.Head

	// Term is the base interface for all terms (Atom, Variable, Compound, Constant).
	Term = ast.Term

	// Atom is a ground or non-ground atom name.
	Atom = ast.Atom

	// Variable is an ASP logic variable (upper-case or underscore prefix).
	Variable = ast.Variable

	// Position records source file, line, and column for error reporting.
	Position = ast.Position
)

// Parse parses an ASP source string and returns the top-level statements together
// with any parse error messages. A non-empty error slice does not prevent partial
// results from being returned.
func Parse(input string) ([]ast.Statement, []string) {
	l := lexer.NewLexer(input, "<input>")
	p := parser.NewParser(l)
	return p.Parse()
}

// ParseFile is identical to Parse but records filename in position information,
// which improves error messages when input originates from a file.
func ParseFile(input, filename string) ([]ast.Statement, []string) {
	l := lexer.NewLexer(input, filename)
	p := parser.NewParser(l)
	return p.Parse()
}
