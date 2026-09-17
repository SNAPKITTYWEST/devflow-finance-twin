#include "lexer.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int is_ident_start(int c) {
    return isalpha(c) || c == '_' || c == '%';
}

static int is_ident_cont(int c) {
    return isalnum(c) || c == '_' || c == '%';
}

static void skip_ws_and_comments(Lexer *L) {
    for (;;) {
        while (*L->cur == ' ' || *L->cur == '\t' || *L->cur == '\r') {
            L->cur++;
            L->col++;
        }
        if (*L->cur == '\n') {
            L->cur++;
            L->line++;
            L->col = 1;
            continue;
        }
        /* BLISS-style ! comment to end of line, also // and /* */
        if (*L->cur == '!' || (*L->cur == '/' && L->cur[1] == '/')) {
            while (*L->cur && *L->cur != '\n') L->cur++;
            continue;
        }
        if (*L->cur == '/' && L->cur[1] == '*') {
            L->cur += 2;
            while (*L->cur && !(*L->cur == '*' && L->cur[1] == '/')) {
                if (*L->cur == '\n') { L->line++; L->col = 1; }
                else L->col++;
                L->cur++;
            }
            if (*L->cur) L->cur += 2;
            continue;
        }
        break;
    }
}

static Token make_token(Lexer *L, TokenKind k) {
    Token t;
    t.kind = k;
    t.start = L->start;
    t.length = (int)(L->cur - L->start);
    t.line = L->line;
    t.col = L->col - t.length;
    t.value.integer = 0;
    return t;
}

static Token make_int(Lexer *L, long v) {
    Token t = make_token(L, TOK_NUMBER);
    t.value.integer = v;
    return t;
}

static TokenKind keyword(const char *s, int len) {
    struct { const char *spelling; TokenKind kind; } table[] = {
        {"MODULE", TOK_MODULE}, {"ROUTINE", TOK_ROUTINE},
        {"BEGIN", TOK_BEGIN}, {"END", TOK_END},
        {"IF", TOK_IF}, {"THEN", TOK_THEN}, {"ELSE", TOK_ELSE},
        {"FI", TOK_FI}, {"ELIF", TOK_ELIF},
        {"WHILE", TOK_WHILE}, {"DO", TOK_DO}, {"FOR", TOK_FOR},
        {"TO", TOK_TO}, {"BY", TOK_BY}, {"OD", TOK_OD},
        {"RETURN", TOK_RETURN}, {"EXIT", TOK_EXIT},
        {"GOTO", TOK_GOTO}, {"LABEL", TOK_LABEL},
        {"OWN", TOK_OWN}, {"GLOBAL", TOK_GLOBAL}, {"LOCAL", TOK_LOCAL},
        {"BIND", TOK_BIND}, {"EXTERNAL", TOK_EXTERNAL},
        {"BASED", TOK_BASED}, {"AT", TOK_AT}, {"ABSOLUTE", TOK_ABSOLUTE},
        {"WORD", TOK_WORD}, {"BIT", TOK_BIT}, {"BYTE", TOK_BYTE},
        {"LONG", TOK_LONG}, {"FLOAT", TOK_FLOAT}, {"PRED", TOK_PRED},
        {"REGISTER", TOK_REGISTER}, {"SHARED", TOK_SHARED},
        {"GLOBALMEM", TOK_GLOBALMEM}, {"CONST", TOK_CONST},
        {"PARAM", TOK_PARAM},
        {"PARALLEL", TOK_PARALLEL}, {"WARP", TOK_WARP}, {"CTA", TOK_CTA},
        {"SYNC", TOK_SYNC}, {"BARRIER", TOK_BARRIER},
        {"DEADLINE", TOK_DEADLINE}, {"PRIORITY", TOK_PRIORITY},
        {"BOUNDED", TOK_BOUNDED},
        {"MACRO", TOK_MACRO}, {"ENDMACRO", TOK_ENDMACRO},
        {"TABLE", TOK_TABLE}, {"COMMON", TOK_COMMON},
        {"AND", TOK_AND}, {"OR", TOK_OR}, {"NOT", TOK_NOT}, {"XOR", TOK_XOR},
        {"SHL", TOK_SHL}, {"SHR", TOK_SHR}, {"ROL", TOK_ROL}, {"ROR", TOK_ROR},
        {"TRUE", TOK_TRUE}, {"FALSE", TOK_FALSE},
        {"NULL", TOK_NULL},
        {0, 0}
    };
    for (int i = 0; table[i].spelling; i++) {
        if ((int)strlen(table[i].spelling) == len &&
            strncmp(table[i].spelling, s, len) == 0)
            return table[i].kind;
    }
    return TOK_IDENT;
}

void lexer_init(Lexer *L, const char *source) {
    L->src = source;
    L->cur = source;
    L->start = source;
    L->line = 1;
    L->col = 1;
    L->has_lookahead = 0;
}

Token lexer_next(Lexer *L) {
    if (L->has_lookahead) {
        L->has_lookahead = 0;
        return L->lookahead;
    }

    skip_ws_and_comments(L);
    L->start = L->cur;

    if (*L->cur == 0)
        return make_token(L, TOK_EOF);

    char c = *L->cur++;
    L->col++;

    /* identifiers and keywords */
    if (is_ident_start(c)) {
        while (is_ident_cont(*L->cur)) { L->cur++; L->col++; }
        TokenKind k = keyword(L->start, (int)(L->cur - L->start));
        return make_token(L, k);
    }

    /* numbers */
    if (isdigit(c)) {
        long v = c - '0';
        while (isdigit(*L->cur)) {
            v = v * 10 + (*L->cur - '0');
            L->cur++;
            L->col++;
        }
        return make_int(L, v);
    }

    /* string literals */
    if (c == '"') {
        while (*L->cur && *L->cur != '"') {
            if (*L->cur == '\n') { L->line++; L->col = 1; }
            else L->col++;
            L->cur++;
        }
        if (*L->cur) L->cur++;
        return make_token(L, TOK_STRING);
    }

    /* two-character operators */
    if (*L->cur) {
        char c2 = *L->cur;
        if (c == '=' && c2 == '=') { L->cur++; L->col++; return make_token(L, TOK_EQ); }
        if (c == '!' && c2 == '=') { L->cur++; L->col++; return make_token(L, TOK_NE); }
        if (c == '<' && c2 == '=') { L->cur++; L->col++; return make_token(L, TOK_LE); }
        if (c == '>' && c2 == '=') { L->cur++; L->col++; return make_token(L, TOK_GE); }
        if (c == '<' && c2 == '<') { L->cur++; L->col++; return make_token(L, TOK_SHL); }
        if (c == '>' && c2 == '>') { L->cur++; L->col++; return make_token(L, TOK_SHR); }
        if (c == '-' && c2 == '>') { L->cur++; L->col++; return make_token(L, TOK_ARROW); }
    }

    /* single-character operators */
    switch (c) {
    case '+': return make_token(L, TOK_PLUS);
    case '-': return make_token(L, TOK_MINUS);
    case '*': return make_token(L, TOK_STAR);
    case '/': return make_token(L, TOK_SLASH);
    case '%': return make_token(L, TOK_PERCENT);
    case '=': return make_token(L, TOK_ASSIGN);
    case '<': return make_token(L, TOK_LT);
    case '>': return make_token(L, TOK_GT);
    case ':': return make_token(L, TOK_COLON);
    case ';': return make_token(L, TOK_SEMI);
    case ',': return make_token(L, TOK_COMMA);
    case '.': return make_token(L, TOK_DOT);
    case '(': return make_token(L, TOK_LPAREN);
    case ')': return make_token(L, TOK_RPAREN);
    case '[': return make_token(L, TOK_LBRACK);
    case ']': return make_token(L, TOK_RBRACK);
    case '{': return make_token(L, TOK_LBRACE);
    case '}': return make_token(L, TOK_RBRACE);
    case '&': return make_token(L, TOK_AMPER);
    case '|': return make_token(L, TOK_PIPE);
    case '^': return make_token(L, TOK_CARET);
    case '~': return make_token(L, TOK_TILDE);
    case '?': return make_token(L, TOK_QUESTION);
    }

    return make_token(L, TOK_ERROR);
}

Token lexer_peek(Lexer *L) {
    if (!L->has_lookahead) {
        L->lookahead = lexer_next(L);
        L->has_lookahead = 1;
    }
    return L->lookahead;
}

void lexer_error(Lexer *L, const char *msg) {
    fprintf(stderr, "lexer error line %d: %s\n", L->line, msg);
}

const char *token_kind_name(TokenKind k) {
    static const char *names[] = {
        "EOF", "IDENT", "NUMBER", "STRING",
        "MODULE", "ROUTINE", "BEGIN", "END",
        "IF", "THEN", "ELSE", "FI", "ELIF",
        "WHILE", "DO", "FOR", "TO", "BY", "OD",
        "RETURN", "EXIT", "GOTO", "LABEL",
        "OWN", "GLOBAL", "LOCAL", "BIND", "EXTERNAL",
        "BASED", "AT", "ABSOLUTE",
        "WORD", "BIT", "BYTE", "LONG", "FLOAT", "PRED",
        "REGISTER", "SHARED", "GLOBALMEM", "CONST", "PARAM",
        "PARALLEL", "WARP", "CTA", "SYNC", "BARRIER",
        "DEADLINE", "PRIORITY", "BOUNDED",
        "MACRO", "ENDMACRO",
        "TABLE", "COMMON",
        "AND", "OR", "NOT", "XOR",
        "SHL", "SHR", "ROL", "ROR",
        "TRUE", "FALSE",
        "NULL",
        "PLUS", "MINUS", "STAR", "SLASH", "PERCENT",
        "EQ", "NE", "LT", "LE", "GT", "GE",
        "ASSIGN", "COLON", "SEMI", "COMMA", "DOT",
        "LPAREN", "RPAREN", "LBRACK", "RBRACK",
        "LBRACE", "RBRACE", "ARROW", "AMPER", "PIPE",
        "CARET", "TILDE", "QUESTION",
        "ERROR"
    };
    if (k >= 0 && k <= TOK_ERROR) return names[k];
    return "?";
}
