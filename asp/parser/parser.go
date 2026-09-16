package parser

import (
	"fmt"
	"strconv"

	"devflow-finance-twin/asp/ast"
	"devflow-finance-twin/asp/lexer"
)

// Parser implements recursive descent parsing for ASP programs
type Parser struct {
	lexer      *lexer.Lexer
	current    lexer.Token
	peek       lexer.Token
	errors     []string
	ruleCounter uint64
}

// NewParser creates a new parser instance
func NewParser(l *lexer.Lexer) *Parser {
	p := &Parser{
		lexer:  l,
		errors: make([]string, 0),
	}
	p.advance() // prime current token
	p.advance() // prime peek token
	return p
}

// ============================================================
// TOKEN MANAGEMENT
// ============================================================

// advance moves to the next token
func (p *Parser) advance() {
	p.current = p.peek
	p.peek = p.lexer.NextToken()
}

// expect advances if current matches expected token type, otherwise errors
func (p *Parser) expect(t lexer.TokenType) bool {
	if p.current.Type != t {
		p.error(fmt.Sprintf("expected %s, got %s", tokenName(t), tokenName(p.current.Type)))
		return false
	}
	p.advance()
	return true
}

// match checks if current token is of given type without advancing
func (p *Parser) match(t lexer.TokenType) bool {
	return p.current.Type == t
}

// matchPeek checks if next token (peek) is of given type
func (p *Parser) matchPeek(t lexer.TokenType) bool {
	return p.peek.Type == t
}

// error records a parse error with position information
func (p *Parser) error(msg string) {
	fullMsg := fmt.Sprintf("%s: %s", p.current.Position, msg)
	p.errors = append(p.errors, fullMsg)
}

// recoverFromError skips tokens until it finds a likely recovery point
func (p *Parser) recoverFromError() {
	// Skip tokens until we find something that looks like statement start
	// (atom or dot or EOF)
	for p.current.Type != lexer.TOKEN_EOF &&
		p.current.Type != lexer.TOKEN_DOT &&
		p.current.Type != lexer.TOKEN_ATOM &&
		p.current.Type != lexer.TOKEN_HASH {
		p.advance()
	}
}

// ============================================================
// MAIN PARSING ENTRY POINT
// ============================================================

// Parse parses the entire ASP program and returns list of statements
func (p *Parser) Parse() ([]ast.Statement, []string) {
	statements := make([]ast.Statement, 0)

	for p.current.Type != lexer.TOKEN_EOF {
		stmt := p.parseStatement()
		if stmt != nil {
			statements = append(statements, stmt)
		}

		// If we have errors, try to recover
		if len(p.errors) > 0 && p.current.Type != lexer.TOKEN_EOF {
			p.recoverFromError()
		}
	}

	return statements, p.errors
}

// ============================================================
// STATEMENT PARSING
// ============================================================

// parseStatement parses one fact, rule, constraint, or directive
func (p *Parser) parseStatement() ast.Statement {
	startPos := p.current.Position

	// Handle directives: #show, #hide, #assert, etc.
	if p.match(lexer.TOKEN_HASH) {
		return p.parseDirective()
	}

	// Handle constraints: :- body.
	if p.match(lexer.TOKEN_RULE) {
		return p.parseConstraint()
	}

	// Parse head
	head := p.parseHead()
	if head == nil {
		p.error("expected rule head or fact")
		p.recoverFromError()
		return nil
	}

	// Check what follows the head
	ruleType := ast.RULE_FACT
	var body []*ast.Literal

	// Rule: head :- body.
	if p.match(lexer.TOKEN_RULE) {
		p.advance() // consume :-
		ruleType = ast.RULE_NORMAL

		body = p.parseBody()
		if body == nil {
			p.error("expected rule body after :-")
			p.recoverFromError()
			return nil
		}
	}

	// Expect dot to end statement
	if !p.expect(lexer.TOKEN_DOT) {
		p.error("expected . at end of statement")
		p.recoverFromError()
		return nil
	}

	// Create rule
	p.ruleCounter++
	rule := &ast.Rule{
		ID:   p.ruleCounter,
		Head: head,
		Body: body,
		Type: ruleType,
		Pos:  startPos,
	}

	return &ast.RuleStatement{
		Rule: rule,
		Pos:  startPos,
	}
}

// parseDirective parses directives like #show, #hide, #assert
func (p *Parser) parseDirective() ast.Statement {
	startPos := p.current.Position
	p.advance() // consume #

	// Get directive name
	if !p.match(lexer.TOKEN_ATOM) {
		p.error("expected directive name after #")
		p.recoverFromError()
		return nil
	}

	directiveName := p.current.Lexeme
	p.advance()

	// Parse arguments (optional)
	args := make([]ast.Term, 0)
	if p.match(lexer.TOKEN_LPAREN) {
		p.advance() // consume (
		for !p.match(lexer.TOKEN_RPAREN) && p.current.Type != lexer.TOKEN_EOF {
			term := p.parseTerm()
			if term == nil {
				p.error("expected term in directive")
				break
			}
			args = append(args, term)

			if !p.match(lexer.TOKEN_RPAREN) {
				if !p.expect(lexer.TOKEN_COMMA) {
					break
				}
			}
		}
		p.expect(lexer.TOKEN_RPAREN)
	}

	// Expect dot
	if !p.expect(lexer.TOKEN_DOT) {
		p.error("expected . at end of directive")
	}

	return &ast.Directive{
		Type:      directiveName,
		Arguments: args,
		Pos:       startPos,
	}
}

// parseConstraint parses a constraint :- body.
func (p *Parser) parseConstraint() ast.Statement {
	startPos := p.current.Position
	p.advance() // consume :-

	body := p.parseBody()
	if body == nil {
		p.error("expected constraint body after :-")
		p.recoverFromError()
		return nil
	}

	if !p.expect(lexer.TOKEN_DOT) {
		p.error("expected . at end of constraint")
	}

	// Create constraint rule with empty head
	p.ruleCounter++
	rule := &ast.Rule{
		ID:   p.ruleCounter,
		Head: &ast.Head{Atoms: make([]*ast.HeadAtom, 0), Type: ast.HEAD_NORMAL, Pos: startPos},
		Body: body,
		Type: ast.RULE_CONSTRAINT,
		Pos:  startPos,
	}

	return &ast.RuleStatement{
		Rule: rule,
		Pos:  startPos,
	}
}

// ============================================================
// HEAD PARSING
// ============================================================

// parseHead parses rule head (atom, compound, or choice rule)
func (p *Parser) parseHead() *ast.Head {
	startPos := p.current.Position

	// Check for choice rule: { ... }
	if p.match(lexer.TOKEN_LBRACE) {
		return p.parseChoiceHead()
	}

	// Normal head: atom or atom(args)
	atoms := make([]*ast.HeadAtom, 0)

	for {
		atom := p.parseHeadAtom()
		if atom == nil {
			if len(atoms) == 0 {
				return nil // Failed to parse first atom
			}
			break // End of head atoms
		}
		atoms = append(atoms, atom)

		// Check for disjunction: atom | atom
		if !p.match(lexer.TOKEN_PIPE) {
			break
		}
		p.advance() // consume |
	}

	if len(atoms) == 0 {
		return nil
	}

	headType := ast.HEAD_NORMAL
	if len(atoms) > 1 {
		headType = ast.HEAD_DISJUNCTIVE
	}

	return &ast.Head{
		Atoms: atoms,
		Type:  headType,
		Pos:   startPos,
	}
}

// parseChoiceHead parses a choice rule: { atom(X) : condition } = N
func (p *Parser) parseChoiceHead() *ast.Head {
	startPos := p.current.Position
	p.advance() // consume {

	atoms := make([]*ast.HeadAtom, 0)

	// Parse atoms inside braces
	for !p.match(lexer.TOKEN_RBRACE) && p.current.Type != lexer.TOKEN_EOF {
		atom := p.parseHeadAtom()
		if atom == nil {
			p.error("expected atom in choice rule")
			break
		}
		atoms = append(atoms, atom)

		if !p.match(lexer.TOKEN_RBRACE) {
			if !p.expect(lexer.TOKEN_COMMA) {
				break
			}
		}
	}

	p.expect(lexer.TOKEN_RBRACE)

	// Optional: : condition (to be parsed later as body literal)
	// For now, we'll skip this for simplicity and let semantic analysis handle it

	// Optional: = N or >= N etc. (cardinality constraint)
	// This can be attached to the head as metadata

	return &ast.Head{
		Atoms: atoms,
		Type:  ast.HEAD_CHOICE,
		Pos:   startPos,
	}
}

// parseHeadAtom parses a single atom in head position
func (p *Parser) parseHeadAtom() *ast.HeadAtom {
	if !p.match(lexer.TOKEN_ATOM) {
		return nil
	}

	atomName := p.current.Lexeme
	pos := p.current.Position
	p.advance()

	args := make([]ast.Term, 0)

	// Parse arguments if present
	if p.match(lexer.TOKEN_LPAREN) {
		p.advance() // consume (
		for !p.match(lexer.TOKEN_RPAREN) && p.current.Type != lexer.TOKEN_EOF {
			term := p.parseTerm()
			if term == nil {
				p.error("expected term in head atom arguments")
				break
			}
			args = append(args, term)

			if !p.match(lexer.TOKEN_RPAREN) {
				if !p.expect(lexer.TOKEN_COMMA) {
					break
				}
			}
		}
		p.expect(lexer.TOKEN_RPAREN)
	}

	return &ast.HeadAtom{
		Atom: &ast.Atom{Name: atomName, Pos: pos},
		Args: args,
		Pos:  pos,
	}
}

// ============================================================
// BODY PARSING
// ============================================================

// parseBody parses rule body (conjunction of literals)
func (p *Parser) parseBody() []*ast.Literal {
	literals := make([]*ast.Literal, 0)

	for {
		lit := p.parseLiteral()
		if lit == nil {
			break
		}
		literals = append(literals, lit)

		// Body atoms are separated by commas
		if !p.match(lexer.TOKEN_COMMA) {
			break
		}
		p.advance() // consume ,
	}

	if len(literals) == 0 {
		return nil
	}

	return literals
}

// ============================================================
// LITERAL PARSING
// ============================================================

// parseLiteral parses a single literal (positive or negated atom with optional aggregate)
func (p *Parser) parseLiteral() *ast.Literal {
	pos := p.current.Position
	positive := true

	// Check for negation: not atom
	if p.match(lexer.TOKEN_NOT) {
		positive = false
		p.advance() // consume not
	}

	// Check for aggregate: #count, #sum, #min, #max
	if p.match(lexer.TOKEN_HASH) {
		return p.parseAggregateLiteral(pos, positive)
	}

	// Check for comparison/constraint: term = term, X > 5, etc.
	if p.match(lexer.TOKEN_LPAREN) ||
		p.match(lexer.TOKEN_VARIABLE) ||
		p.match(lexer.TOKEN_INTEGER) ||
		p.match(lexer.TOKEN_STRING) {
		return p.parseComparisonLiteral(pos, positive)
	}

	// Regular atom literal: atom or atom(args)
	if !p.match(lexer.TOKEN_ATOM) {
		if !positive {
			p.error("expected atom or aggregate after 'not'")
		}
		return nil
	}

	atomName := p.current.Lexeme
	atom := &ast.Atom{Name: atomName, Pos: pos}
	p.advance()

	args := make([]ast.Term, 0)

	// Parse arguments if present
	if p.match(lexer.TOKEN_LPAREN) {
		p.advance() // consume (
		for !p.match(lexer.TOKEN_RPAREN) && p.current.Type != lexer.TOKEN_EOF {
			term := p.parseTerm()
			if term == nil {
				p.error("expected term in atom arguments")
				break
			}
			args = append(args, term)

			if !p.match(lexer.TOKEN_RPAREN) {
				if !p.expect(lexer.TOKEN_COMMA) {
					break
				}
			}
		}
		p.expect(lexer.TOKEN_RPAREN)
	}

	return &ast.Literal{
		Positive: positive,
		Atom:     atom,
		Args:     args,
		Pos:      pos,
	}
}

// parseComparisonLiteral parses comparison constraints: X = Y, N > 5, etc.
func (p *Parser) parseComparisonLiteral(pos lexer.Position, positive bool) *ast.Literal {
	// Parse left side
	left := p.parseTerm()
	if left == nil {
		p.error("expected term in comparison")
		return nil
	}

	// Check for comparison operator
	op := ""
	switch p.current.Type {
	case lexer.TOKEN_EQ:
		op = "="
	case lexer.TOKEN_NEQ:
		op = "!="
	case lexer.TOKEN_LT:
		op = "<"
	case lexer.TOKEN_LE:
		op = "<="
	case lexer.TOKEN_GT:
		op = ">"
	case lexer.TOKEN_GE:
		op = ">="
	default:
		// Not a comparison literal
		return &ast.Literal{
			Positive: positive,
			Atom:     &ast.Atom{Name: "builtin", Pos: pos},
			Args:     []ast.Term{left},
			Pos:      pos,
		}
	}

	p.advance() // consume operator

	// Parse right side
	right := p.parseTerm()
	if right == nil {
		p.error("expected term on right side of comparison")
		return nil
	}

	// Create comparison as a special literal
	return &ast.Literal{
		Positive: positive,
		Atom:     &ast.Atom{Name: op, Pos: pos},
		Args:     []ast.Term{left, right},
		Pos:      pos,
	}
}

// parseAggregateLiteral parses aggregate with optional comparison
func (p *Parser) parseAggregateLiteral(pos lexer.Position, positive bool) *ast.Literal {
	p.advance() // consume #

	// Get aggregate type
	var aggOp ast.AggregateOp
	switch p.current.Type {
	case lexer.TOKEN_COUNT:
		aggOp = ast.AGG_COUNT
	case lexer.TOKEN_SUM:
		aggOp = ast.AGG_SUM
	case lexer.TOKEN_MIN:
		aggOp = ast.AGG_MIN
	case lexer.TOKEN_MAX:
		aggOp = ast.AGG_MAX
	default:
		p.error("expected aggregate type (count, sum, min, max)")
		return nil
	}
	p.advance() // consume aggregate type

	// Parse aggregate body { ... : ... }
	agg := p.parseAggregate()
	if agg == nil {
		p.error("expected aggregate expression")
		return nil
	}
	agg.Op = aggOp
	agg.Pos = pos

	// Check for bound: >= N, < M, = K, etc.
	if isComparisonOperator(p.current.Type) {
		bound := p.parseAggregateBound()
		if bound != nil {
			agg.Bound = bound
		}
	}

	return &ast.Literal{
		Positive:  positive,
		Aggregate: agg,
		Pos:       pos,
	}
}

// ============================================================
// TERM PARSING
// ============================================================

// parseTerm parses a term (atom, constant, variable, compound, or parenthesized expression)
func (p *Parser) parseTerm() ast.Term {
	startPos := p.current.Position

	switch p.current.Type {
	case lexer.TOKEN_ATOM:
		atomName := p.current.Lexeme
		p.advance()

		// Check for compound term: atom(args)
		if p.match(lexer.TOKEN_LPAREN) {
			p.advance() // consume (
			args := make([]ast.Term, 0)

			for !p.match(lexer.TOKEN_RPAREN) && p.current.Type != lexer.TOKEN_EOF {
				term := p.parseTerm()
				if term == nil {
					p.error("expected term in compound arguments")
					break
				}
				args = append(args, term)

				if !p.match(lexer.TOKEN_RPAREN) {
					if !p.expect(lexer.TOKEN_COMMA) {
						break
					}
				}
			}
			p.expect(lexer.TOKEN_RPAREN)

			return &ast.Compound{
				Functor: atomName,
				Args:    args,
				Pos:     startPos,
			}
		}

		// Simple atom
		return &ast.Atom{Name: atomName, Pos: startPos}

	case lexer.TOKEN_VARIABLE:
		varName := p.current.Lexeme
		p.advance()
		return &ast.Variable{Name: varName, Pos: startPos}

	case lexer.TOKEN_INTEGER:
		value := p.current.Lexeme
		n, _ := strconv.ParseInt(value, 10, 64)
		p.advance()
		return &ast.Constant{
			Type:  ast.CONST_INT,
			Value: n,
			Pos:   startPos,
		}

	case lexer.TOKEN_STRING:
		value := p.current.Lexeme
		p.advance()
		return &ast.Constant{
			Type:  ast.CONST_STRING,
			Value: value,
			Pos:   startPos,
		}

	case lexer.TOKEN_LPAREN:
		// Parenthesized term or arithmetic expression
		p.advance() // consume (
		term := p.parseTerm()
		if term == nil {
			p.error("expected term in parentheses")
			return nil
		}

		// Check for binary operator: +, -, *, /
		if isBinaryOperator(p.current.Type) {
			return p.parseArithmeticExpression(term, startPos)
		}

		p.expect(lexer.TOKEN_RPAREN)
		return term

	case lexer.TOKEN_MINUS:
		// Negative number or prefix operator
		p.advance()
		term := p.parseTerm()
		if term == nil {
			p.error("expected term after -")
			return nil
		}

		// If it's a constant, negate it
		if c, ok := term.(*ast.Constant); ok && c.Type == ast.CONST_INT {
			c.Value = -(c.Value.(int64))
			return c
		}

		// Otherwise create unary minus compound
		return &ast.Compound{
			Functor: "-",
			Args:    []ast.Term{term},
			Pos:     startPos,
		}

	default:
		return nil
	}
}

// parseArithmeticExpression parses binary arithmetic operations
func (p *Parser) parseArithmeticExpression(left ast.Term, startPos lexer.Position) ast.Term {
	for isBinaryOperator(p.current.Type) {
		op := p.current.Lexeme
		p.advance()

		right := p.parseTerm()
		if right == nil {
			break
		}

		left = &ast.Compound{
			Functor: op,
			Args:    []ast.Term{left, right},
			Pos:     startPos,
		}
	}
	return left
}

// isBinaryOperator checks if token is a binary operator
func isBinaryOperator(t lexer.TokenType) bool {
	return t == lexer.TOKEN_PLUS ||
		t == lexer.TOKEN_MINUS ||
		t == lexer.TOKEN_STAR ||
		t == lexer.TOKEN_SLASH
}

// isComparisonOperator checks if token is a comparison operator
func isComparisonOperator(t lexer.TokenType) bool {
	return t == lexer.TOKEN_EQ ||
		t == lexer.TOKEN_NEQ ||
		t == lexer.TOKEN_LT ||
		t == lexer.TOKEN_LE ||
		t == lexer.TOKEN_GT ||
		t == lexer.TOKEN_GE
}

// ============================================================
// AGGREGATE PARSING
// ============================================================

// parseAggregate parses aggregate expression { vars : condition }
func (p *Parser) parseAggregate() *ast.Aggregate {
	pos := p.current.Position

	if !p.expect(lexer.TOKEN_LBRACE) {
		p.error("expected { in aggregate")
		return nil
	}

	// Parse aggregate variables
	variables := make([]ast.Term, 0)
	for !p.match(lexer.TOKEN_PIPE) && !p.match(lexer.TOKEN_RBRACE) && p.current.Type != lexer.TOKEN_EOF {
		term := p.parseTerm()
		if term == nil {
			p.error("expected term in aggregate")
			break
		}
		variables = append(variables, term)

		if !p.match(lexer.TOKEN_PIPE) && !p.match(lexer.TOKEN_RBRACE) {
			if !p.expect(lexer.TOKEN_COMMA) {
				break
			}
		}
	}

	// Optional condition after :
	var condition *ast.Literal
	if p.match(lexer.TOKEN_PIPE) {
		p.advance() // consume |
		condition = p.parseLiteral()
	}

	if !p.expect(lexer.TOKEN_RBRACE) {
		p.error("expected } in aggregate")
		return nil
	}

	return &ast.Aggregate{
		Op:        "",  // Will be set by caller
		Variables: variables,
		Condition: condition,
		Pos:       pos,
	}
}

// parseAggregateBound parses aggregate bounds like >= 2 or 1..10
func (p *Parser) parseAggregateBound() *ast.AggregateBound {
	pos := p.current.Position

	// First bound (lower or only)
	var lower ast.Term
	var upper ast.Term

	// Comparison: >= N, < M, = K
	op := p.current.Lexeme
	p.advance()

	upper = p.parseTerm()
	if upper == nil {
		p.error("expected bound value")
		return nil
	}

	// For <= and <, the bound is upper; for >= and >, it's lower
	if op == "<=" || op == "=" {
		return &ast.AggregateBound{Lower: nil, Upper: upper, Pos: pos}
	}
	return &ast.AggregateBound{Lower: upper, Upper: nil, Pos: pos}
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

// tokenName returns string representation of token type for error messages
func tokenName(t lexer.TokenType) string {
	switch t {
	case lexer.TOKEN_EOF:
		return "EOF"
	case lexer.TOKEN_ERROR:
		return "ERROR"
	case lexer.TOKEN_ATOM:
		return "atom"
	case lexer.TOKEN_VARIABLE:
		return "variable"
	case lexer.TOKEN_INTEGER:
		return "integer"
	case lexer.TOKEN_STRING:
		return "string"
	case lexer.TOKEN_LPAREN:
		return "("
	case lexer.TOKEN_RPAREN:
		return ")"
	case lexer.TOKEN_LBRACKET:
		return "["
	case lexer.TOKEN_RBRACKET:
		return "]"
	case lexer.TOKEN_LBRACE:
		return "{"
	case lexer.TOKEN_RBRACE:
		return "}"
	case lexer.TOKEN_DOT:
		return "."
	case lexer.TOKEN_COMMA:
		return ","
	case lexer.TOKEN_PIPE:
		return "|"
	case lexer.TOKEN_RULE:
		return ":-"
	case lexer.TOKEN_NOT:
		return "not"
	case lexer.TOKEN_MINUS:
		return "-"
	case lexer.TOKEN_PLUS:
		return "+"
	case lexer.TOKEN_SLASH:
		return "/"
	case lexer.TOKEN_STAR:
		return "*"
	case lexer.TOKEN_EQ:
		return "="
	case lexer.TOKEN_NEQ:
		return "!="
	case lexer.TOKEN_LT:
		return "<"
	case lexer.TOKEN_LE:
		return "<="
	case lexer.TOKEN_GT:
		return ">"
	case lexer.TOKEN_GE:
		return ">="
	case lexer.TOKEN_HASH:
		return "#"
	case lexer.TOKEN_COUNT:
		return "count"
	case lexer.TOKEN_SUM:
		return "sum"
	case lexer.TOKEN_MIN:
		return "min"
	case lexer.TOKEN_MAX:
		return "max"
	case lexer.TOKEN_CHOICE:
		return "choice"
	case lexer.TOKEN_AGGREGATE:
		return "aggregate"
	default:
		return "unknown"
	}
}

// Errors returns any parse errors that occurred
func (p *Parser) Errors() []string {
	return p.errors
}

// HasErrors checks if any parse errors occurred
func (p *Parser) HasErrors() bool {
	return len(p.errors) > 0
}
