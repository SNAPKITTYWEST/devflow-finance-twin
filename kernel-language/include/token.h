#ifndef KERNEL_TOKEN_H
#define KERNEL_TOKEN_H

/* Dense token definitions for the BLISS/PLM/CORAL derived language */

typedef enum {
    TOK_EOF = 0,
    TOK_IDENT,
    TOK_NUMBER,
    TOK_STRING,

    /* Keywords rooted in the three languages */
    TOK_MODULE, TOK_ROUTINE, TOK_BEGIN, TOK_END,
    TOK_IF, TOK_THEN, TOK_ELSE, TOK_FI, TOK_ELIF,
    TOK_WHILE, TOK_DO, TOK_FOR, TOK_TO, TOK_BY, TOK_OD,
    TOK_RETURN, TOK_EXIT, TOK_GOTO, TOK_LABEL,
    TOK_OWN, TOK_GLOBAL, TOK_LOCAL, TOK_BIND, TOK_EXTERNAL,
    TOK_BASED, TOK_AT, TOK_ABSOLUTE,
    TOK_WORD, TOK_BIT, TOK_BYTE, TOK_LONG, TOK_FLOAT, TOK_PRED,
    TOK_REGISTER, TOK_SHARED, TOK_GLOBALMEM, TOK_CONST, TOK_PARAM,
    TOK_PARALLEL, TOK_WARP, TOK_CTA, TOK_SYNC, TOK_BARRIER,
    TOK_DEADLINE, TOK_PRIORITY, TOK_BOUNDED,
    TOK_MACRO, TOK_ENDMACRO,
    TOK_TABLE, TOK_COMMON,
    TOK_AND, TOK_OR, TOK_NOT, TOK_XOR,
    TOK_SHL, TOK_SHR, TOK_ROL, TOK_ROR,
    TOK_TRUE, TOK_FALSE,
    TOK_NULL,

    /* Operators */
    TOK_PLUS, TOK_MINUS, TOK_STAR, TOK_SLASH, TOK_PERCENT,
    TOK_EQ, TOK_NE, TOK_LT, TOK_LE, TOK_GT, TOK_GE,
    TOK_ASSIGN, TOK_COLON, TOK_SEMI, TOK_COMMA, TOK_DOT,
    TOK_LPAREN, TOK_RPAREN, TOK_LBRACK, TOK_RBRACK,
    TOK_LBRACE, TOK_RBRACE, TOK_ARROW, TOK_AMPER, TOK_PIPE,
    TOK_CARET, TOK_TILDE, TOK_QUESTION,

    TOK_ERROR
} TokenKind;

typedef struct {
    TokenKind kind;
    const char *start;
    int length;
    int line;
    int col;
    union {
        long integer;
        double real;
    } value;
} Token;

const char *token_kind_name(TokenKind k);

#endif
