// Package parser implements a recursive descent parser for Answer Set Programming (ASP) syntax.
//
// The parser transforms a stream of tokens from the lexer into an Abstract Syntax Tree (AST)
// that represents the structure and semantics of an ASP program.
//
// # Supported ASP Syntax
//
// Facts:
//	bird(tweety).
//	parent(john, mary).
//
// Rules:
//	flies(X) :- bird(X), not abnormal(X).
//	sibling(X, Y) :- parent(Z, X), parent(Z, Y).
//
// Constraints:
//	:- negative_body.
//	:- not peaceful, conflict.
//
// Negation as failure:
//	safe(X) :- not dangerous(X).
//
// Comparison constraints:
//	old(X) :- age(X, Y), Y > 65.
//	match(X, Y) :- value(X, V), value(Y, V).
//
// Choice rules:
//	{ p(X) : item(X) } = 1.
//	{ color(X, C) : color(C) } = 1.
//
// Aggregates:
//	#count { X : person(X) } >= 2.
//	#sum { C,X : cost(X,C) } = N.
//	#min { X : value(X) } = M.
//	#max { X : value(X) } = M.
//
// Directives:
//	#show person/1.
//	#hide fact/0.
//	#assert rule(X).
//
// Disjunctive rules:
//	a(X) | b(X) :- c(X).
//	p | q | r.
//
// # Parser Usage
//
// Create a parser from a lexer:
//
//	l := lexer.NewLexer(source, "program.lp")
//	p := parser.NewParser(l)
//	statements, errors := p.Parse()
//
// The Parse() function returns:
//   - statements: a slice of AST Statement nodes (RuleStatement or Directive)
//   - errors: a slice of error messages if parsing fails
//
// # Error Handling
//
// The parser implements error recovery to continue parsing after encountering errors.
// All errors are collected in the errors slice returned by Parse().
// Use HasErrors() to check if any errors occurred.
//
// # AST Structure
//
// The resulting AST uses types from the ast package:
//   - Statement: top-level program element
//   - RuleStatement: wraps a Rule
//   - Rule: represents a fact, rule, constraint, or choice rule
//   - Head: rule head (atoms or choice)
//   - Literal: body element (atom, comparison, or aggregate)
//   - Term: logical term (atom, variable, constant, compound)
//   - Aggregate: aggregate expression (#count, #sum, etc.)
//   - Directive: special directive like #show, #hide
package parser
