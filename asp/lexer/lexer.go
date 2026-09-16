package lexer

import (
	"unicode"
)

// Lexer tokenizes ASP source code input
type Lexer struct {
	input    string
	pos      int
	readPos  int
	ch       byte
	line     int
	column   int
	filename string
	tokens   []Token
}

// NewLexer creates a new lexer instance for the given input
func NewLexer(input, filename string) *Lexer {
	l := &Lexer{
		input:    input,
		filename: filename,
		line:     1,
		column:   1,
	}
	l.readChar()
	return l
}

// readChar advances to the next character in the input
func (l *Lexer) readChar() {
	if l.readPos >= len(l.input) {
		l.ch = 0
	} else {
		l.ch = l.input[l.readPos]
	}
	l.pos = l.readPos
	l.readPos++
}

// peekChar returns the next character without advancing the position
func (l *Lexer) peekChar() byte {
	if l.readPos >= len(l.input) {
		return 0
	}
	return l.input[l.readPos]
}

// skipWhitespace skips over spaces, tabs, and newlines
func (l *Lexer) skipWhitespace() {
	for l.ch == ' ' || l.ch == '\t' || l.ch == '\n' || l.ch == '\r' {
		if l.ch == '\n' {
			l.line++
			l.column = 1
		} else {
			l.column++
		}
		l.readChar()
	}
}

// skipComment skips a line comment starting with %
func (l *Lexer) skipComment() {
	if l.ch == '%' {
		for l.ch != '\n' && l.ch != 0 {
			l.readChar()
		}
	}
}

// readAtom reads an atom (lowercase identifier starting with lowercase letter)
func (l *Lexer) readAtom() string {
	start := l.pos
	for isAtomChar(l.ch) {
		l.readChar()
	}
	return l.input[start:l.pos]
}

// readVariable reads a variable name (uppercase identifier or underscore-prefixed)
func (l *Lexer) readVariable() string {
	start := l.pos
	for isAlphaNum(l.ch) || l.ch == '_' {
		l.readChar()
	}
	return l.input[start:l.pos]
}

// readNumber reads an integer (sequence of digits)
func (l *Lexer) readNumber() string {
	start := l.pos
	for unicode.IsDigit(rune(l.ch)) {
		l.readChar()
	}
	return l.input[start:l.pos]
}

// readString reads a quoted string literal
func (l *Lexer) readString() string {
	quote := l.ch
	l.readChar()
	start := l.pos
	for l.ch != quote && l.ch != 0 {
		l.readChar()
	}
	result := l.input[start:l.pos]
	if l.ch == quote {
		l.readChar()
	}
	return result
}

// NextToken returns the next token from the input
func (l *Lexer) NextToken() Token {
	l.skipWhitespace()

	// Skip comments
	for l.ch == '%' {
		l.skipComment()
		l.skipWhitespace()
	}

	pos := Position{l.filename, l.line, l.column, l.pos}

	switch l.ch {
	case 0:
		return Token{TOKEN_EOF, "", nil, pos}
	case '(':
		l.readChar()
		return Token{TOKEN_LPAREN, "(", nil, pos}
	case ')':
		l.readChar()
		return Token{TOKEN_RPAREN, ")", nil, pos}
	case '[':
		l.readChar()
		return Token{TOKEN_LBRACKET, "[", nil, pos}
	case ']':
		l.readChar()
		return Token{TOKEN_RBRACKET, "]", nil, pos}
	case '{':
		l.readChar()
		return Token{TOKEN_LBRACE, "{", nil, pos}
	case '}':
		l.readChar()
		return Token{TOKEN_RBRACE, "}", nil, pos}
	case '.':
		l.readChar()
		return Token{TOKEN_DOT, ".", nil, pos}
	case ',':
		l.readChar()
		return Token{TOKEN_COMMA, ",", nil, pos}
	case '|':
		l.readChar()
		return Token{TOKEN_PIPE, "|", nil, pos}
	case '-':
		if l.peekChar() == '-' {
			l.readChar()
			l.readChar()
			if l.ch == '>' {
				l.readChar()
				return Token{TOKEN_MINUS, "-->", nil, pos}
			}
			return Token{TOKEN_MINUS, "--", nil, pos}
		}
		if l.peekChar() == '>' {
			l.readChar()
			l.readChar()
			return Token{TOKEN_MINUS, "->", nil, pos}
		}
		l.readChar()
		return Token{TOKEN_MINUS, "-", nil, pos}
	case ':':
		if l.peekChar() == '-' {
			l.readChar()
			l.readChar()
			return Token{TOKEN_RULE, ":-", nil, pos}
		}
		l.readChar()
		return Token{TOKEN_ERROR, ":", nil, pos}
	case '!':
		if l.peekChar() == '=' {
			l.readChar()
			l.readChar()
			return Token{TOKEN_NEQ, "!=", nil, pos}
		}
		l.readChar()
		return Token{TOKEN_ERROR, "!", nil, pos}
	case '=':
		l.readChar()
		return Token{TOKEN_EQ, "=", nil, pos}
	case '<':
		if l.peekChar() == '=' {
			l.readChar()
			l.readChar()
			return Token{TOKEN_LE, "<=", nil, pos}
		}
		l.readChar()
		return Token{TOKEN_LT, "<", nil, pos}
	case '>':
		if l.peekChar() == '=' {
			l.readChar()
			l.readChar()
			return Token{TOKEN_GE, ">=", nil, pos}
		}
		l.readChar()
		return Token{TOKEN_GT, ">", nil, pos}
	case '+':
		l.readChar()
		return Token{TOKEN_PLUS, "+", nil, pos}
	case '*':
		l.readChar()
		return Token{TOKEN_STAR, "*", nil, pos}
	case '/':
		l.readChar()
		return Token{TOKEN_SLASH, "/", nil, pos}
	case '#':
		l.readChar()
		return Token{TOKEN_HASH, "#", nil, pos}
	case '"':
		s := l.readString()
		return Token{TOKEN_STRING, s, s, pos}
	default:
		if unicode.IsUpper(rune(l.ch)) || l.ch == '_' {
			v := l.readVariable()
			return Token{TOKEN_VARIABLE, v, v, pos}
		}
		if unicode.IsLower(rune(l.ch)) {
			a := l.readAtom()
			tt := keywordType(a)
			return Token{tt, a, a, pos}
		}
		if unicode.IsDigit(rune(l.ch)) {
			n := l.readNumber()
			return Token{TOKEN_INTEGER, n, n, pos}
		}
		l.readChar()
		return Token{TOKEN_ERROR, string(l.ch), nil, pos}
	}
}

// keywordType returns the appropriate token type for a keyword or returns TOKEN_ATOM
func keywordType(s string) TokenType {
	switch s {
	case "not":
		return TOKEN_NOT
	case "count":
		return TOKEN_COUNT
	case "sum":
		return TOKEN_SUM
	case "min":
		return TOKEN_MIN
	case "max":
		return TOKEN_MAX
	case "choice":
		return TOKEN_CHOICE
	case "aggregate":
		return TOKEN_AGGREGATE
	default:
		return TOKEN_ATOM
	}
}

// isAtomChar checks if a byte is valid in an atom (lowercase letter, digit, or underscore)
func isAtomChar(ch byte) bool {
	return unicode.IsLower(rune(ch)) || unicode.IsDigit(rune(ch)) || ch == '_'
}

// isAlphaNum checks if a byte is alphanumeric
func isAlphaNum(ch byte) bool {
	return unicode.IsLetter(rune(ch)) || unicode.IsDigit(rune(ch))
}

// ScanAll scans the entire input and returns all tokens as a slice
func (l *Lexer) ScanAll() []Token {
	for {
		tok := l.NextToken()
		l.tokens = append(l.tokens, tok)
		if tok.Type == TOKEN_EOF {
			break
		}
	}
	return l.tokens
}
