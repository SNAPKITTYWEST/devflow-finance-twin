package lexer

// TokenType enum for ASP tokens
type TokenType int

const (
	TOKEN_EOF TokenType = iota
	TOKEN_ERROR
	TOKEN_ATOM          // tweety
	TOKEN_VARIABLE      // X, Y
	TOKEN_INTEGER       // 123
	TOKEN_STRING        // "text"
	TOKEN_LPAREN        // (
	TOKEN_RPAREN        // )
	TOKEN_LBRACKET      // [
	TOKEN_RBRACKET      // ]
	TOKEN_LBRACE        // {
	TOKEN_RBRACE        // }
	TOKEN_DOT           // .
	TOKEN_COMMA         // ,
	TOKEN_PIPE          // |
	TOKEN_RULE          // :-
	TOKEN_NOT           // not
	TOKEN_MINUS         // -
	TOKEN_PLUS          // +
	TOKEN_SLASH         // /
	TOKEN_STAR          // *
	TOKEN_EQ            // =
	TOKEN_NEQ           // !=
	TOKEN_LT            // <
	TOKEN_LE            // <=
	TOKEN_GT            // >
	TOKEN_GE            // >=
	TOKEN_HASH          // # (for aggregates)
	TOKEN_COUNT         // count
	TOKEN_SUM           // sum
	TOKEN_MIN           // min
	TOKEN_MAX           // max
	TOKEN_CHOICE        // choice
	TOKEN_AGGREGATE     // aggregate
)

// Position tracks source location for error reporting
type Position struct {
	Filename string
	Line     int
	Column   int
	Offset   int
}

// Token represents a lexical unit in ASP source code
type Token struct {
	Type     TokenType
	Lexeme   string
	Value    interface{}
	Position Position
}
