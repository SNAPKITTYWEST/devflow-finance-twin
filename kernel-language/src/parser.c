#include "parser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void error_at(Parser *P, Token *t, const char *msg) {
    if (P->panic) return;
    P->panic = 1;
    P->had_error = 1;
    fprintf(stderr, "parse error line %d: %s (near '%.*s')\n",
            t->line, msg, t->length, t->start);
}

static void error(Parser *P, const char *msg) {
    error_at(P, &P->current, msg);
}

static void advance(Parser *P) {
    P->previous = P->current;
    for (;;) {
        P->current = lexer_next(P->lex);
        if (P->current.kind != TOK_ERROR) break;
        error_at(P, &P->current, "unexpected character");
    }
}

static int check(Parser *P, TokenKind k) {
    return P->current.kind == k;
}

static int match(Parser *P, TokenKind k) {
    if (!check(P, k)) return 0;
    advance(P);
    return 1;
}

static void consume(Parser *P, TokenKind k, const char *msg) {
    if (P->current.kind == k) {
        advance(P);
        return;
    }
    error(P, msg);
}

static char *copy_lexeme(Token *t) {
    char *s = malloc(t->length + 1);
    memcpy(s, t->start, t->length);
    s[t->length] = 0;
    return s;
}

AstNode *ast_new(AstKind kind, int line) {
    AstNode *n = calloc(1, sizeof(AstNode));
    n->kind = kind;
    n->line = line;
    return n;
}

/* Forward declarations */
static AstNode *expression(Parser *P);
static AstNode *statement(Parser *P);
static AstNode *declaration(Parser *P);
static AstNode *block(Parser *P);

/* ---------- Expressions (BLISS-oriented) ---------- */

static AstNode *primary(Parser *P) {
    if (match(P, TOK_NUMBER)) {
        AstNode *n = ast_new(AST_NUMBER, P->previous.line);
        n->u.number.ival = P->previous.value.integer;
        return n;
    }
    if (match(P, TOK_TRUE) || match(P, TOK_FALSE)) {
        AstNode *n = ast_new(AST_NUMBER, P->previous.line);
        n->u.number.ival = (P->previous.kind == TOK_TRUE);
        return n;
    }
    if (match(P, TOK_IDENT)) {
        AstNode *n = ast_new(AST_IDENT, P->previous.line);
        n->u.ident.name = copy_lexeme(&P->previous);
        /* function call or indexing */
        if (match(P, TOK_LPAREN)) {
            AstNode *call = ast_new(AST_CALL, n->line);
            call->u.call.fn = n;
            AstNode *args = NULL, *tail = NULL;
            if (!check(P, TOK_RPAREN)) {
                do {
                    AstNode *a = expression(P);
                    if (!args) args = tail = a;
                    else { tail->next = a; tail = a; }
                } while (match(P, TOK_COMMA));
            }
            consume(P, TOK_RPAREN, "expect ')' after arguments");
            call->u.call.args = args;
            return call;
        }
        if (match(P, TOK_LBRACK)) {
            AstNode *idx = ast_new(AST_INDEX, n->line);
            idx->u.index.base = n;
            idx->u.index.index = expression(P);
            consume(P, TOK_RBRACK, "expect ']'");
            return idx;
        }
        return n;
    }
    if (match(P, TOK_LPAREN)) {
        AstNode *e = expression(P);
        consume(P, TOK_RPAREN, "expect ')' after expression");
        return e;
    }
    error(P, "expect expression");
    return NULL;
}

static AstNode *unary(Parser *P) {
    if (match(P, TOK_MINUS) || match(P, TOK_NOT) || match(P, TOK_TILDE) ||
        match(P, TOK_AMPER) || match(P, TOK_STAR)) {
        TokenKind op = P->previous.kind;
        AstNode *n = ast_new(AST_UNARY, P->previous.line);
        n->u.unary.op = op;
        n->u.unary.operand = unary(P);
        return n;
    }
    /* PL/M style bit field: BIT(expr, offset, width) */
    if (match(P, TOK_BIT)) {
        consume(P, TOK_LPAREN, "expect '(' after BIT");
        AstNode *e = expression(P);
        consume(P, TOK_COMMA, "expect ','");
        AstNode *off = expression(P);
        consume(P, TOK_COMMA, "expect ','");
        AstNode *wid = expression(P);
        consume(P, TOK_RPAREN, "expect ')'");
        AstNode *n = ast_new(AST_BITFIELD, e->line);
        n->u.bitfield.expr = e;
        n->u.bitfield.offset = (int)off->u.number.ival;
        n->u.bitfield.width = (int)wid->u.number.ival;
        return n;
    }
    return primary(P);
}

/* Operator precedence climbing */
static AstNode *binary(Parser *P, int min_prec) {
    AstNode *left = unary(P);

    for (;;) {
        TokenKind op = P->current.kind;
        int prec = -1;
        int is_right_assoc = 0;

        switch (op) {
        case TOK_PLUS: case TOK_MINUS: prec = 1; break;
        case TOK_STAR: case TOK_SLASH: case TOK_PERCENT: prec = 2; break;
        case TOK_SHL: case TOK_SHR: prec = 3; break;
        case TOK_AND: prec = 4; break;
        case TOK_XOR: prec = 5; break;
        case TOK_OR: prec = 6; break;
        case TOK_EQ: case TOK_NE: case TOK_LT: case TOK_LE:
        case TOK_GT: case TOK_GE: prec = 7; break;
        case TOK_AND: prec = 8; break;
        case TOK_OR: prec = 9; break;
        default: break;
        }

        if (prec < min_prec) break;
        advance(P);

        AstNode *right = binary(P, prec + 1);
        AstNode *bin = ast_new(AST_BINARY, left->line);
        bin->u.binary.op = op;
        bin->u.binary.left = left;
        bin->u.binary.right = right;
        left = bin;
    }

    return left;
}

static AstNode *expression(Parser *P) {
    return binary(P, 0);
}

/* ---------- Statements ---------- */

static AstNode *declaration(Parser *P) {
    StorageClass sc = STOR_LOCAL;
    Type *ty = calloc(1, sizeof(Type));
    ty->kind = TYPE_WORD;

    if (match(P, TOK_LOCAL)) sc = STOR_LOCAL;
    else if (match(P, TOK_OWN)) sc = STOR_OWN;
    else if (match(P, TOK_GLOBAL)) sc = STOR_GLOBAL;
    else if (match(P, TOK_REGISTER)) sc = STOR_REGISTER;
    else if (match(P, TOK_SHARED)) sc = STOR_SHARED;
    else if (match(P, TOK_PARAM)) sc = STOR_PARAM;
    else if (match(P, TOK_CONST)) sc = STOR_CONST;
    else if (match(P, TOK_ABSOLUTE)) sc = STOR_ABSOLUTE;
    else if (match(P, TOK_BASED)) sc = STOR_BASED;

    if (match(P, TOK_WORD)) ty->kind = TYPE_WORD;
    else if (match(P, TOK_LONG)) ty->kind = TYPE_LONG;
    else if (match(P, TOK_BIT)) {
        ty->kind = TYPE_BIT;
        if (match(P, TOK_LPAREN)) {
            ty->bits = (int)expression(P)->u.number.ival;
            consume(P, TOK_RPAREN, "expect ')'");
        }
    }
    else if (match(P, TOK_BYTE)) ty->kind = TYPE_BYTE;
    else if (match(P, TOK_FLOAT)) ty->kind = TYPE_FLOAT;
    else if (match(P, TOK_PRED)) { ty->kind = TYPE_BIT; ty->bits = 1; }

    if (!match(P, TOK_IDENT)) {
        error(P, "expect variable name");
        return NULL;
    }
    char *name = copy_lexeme(&P->previous);

    AstNode *n = ast_new(AST_DECL, P->previous.line);
    n->u.decl.name = name;
    n->u.decl.type = ty;
    n->u.decl.storage = sc;

    if (match(P, TOK_ASSIGN)) {
        n->u.decl.init = expression(P);
    }

    match(P, TOK_SEMI);
    return n;
}

static AstNode *statement(Parser *P) {
    /* IF */
    if (match(P, TOK_IF)) {
        AstNode *n = ast_new(AST_IF, P->previous.line);
        n->u.ifstmt.cond = expression(P);
        consume(P, TOK_THEN, "expect THEN");
        n->u.ifstmt.then_b = block(P);
        if (match(P, TOK_ELSE)) {
            n->u.ifstmt.else_b = block(P);
        }
        consume(P, TOK_FI, "expect FI");
        return n;
    }

    /* WHILE */
    if (match(P, TOK_WHILE)) {
        AstNode *n = ast_new(AST_WHILE, P->previous.line);
        n->u.whilestmt.cond = expression(P);
        consume(P, TOK_DO, "expect DO");
        n->u.whilestmt.body = block(P);
        consume(P, TOK_OD, "expect OD");
        return n;
    }

    /* FOR */
    if (match(P, TOK_FOR)) {
        AstNode *n = ast_new(AST_FOR, P->previous.line);
        n->u.forstmt.init = declaration(P);
        consume(P, TOK_TO, "expect TO");
        n->u.forstmt.cond = expression(P);
        if (match(P, TOK_BY)) {
            n->u.forstmt.step = expression(P);
        }
        consume(P, TOK_DO, "expect DO");
        n->u.forstmt.body = block(P);
        consume(P, TOK_OD, "expect OD");
        return n;
    }

    /* PARALLEL */
    if (match(P, TOK_PARALLEL)) {
        AstNode *n = ast_new(AST_PARALLEL, P->previous.line);
        n->u.parallel.width = (int)expression(P)->u.number.ival;
        consume(P, TOK_DO, "expect DO");
        n->u.parallel.body = block(P);
        consume(P, TOK_OD, "expect OD");
        return n;
    }

    /* BARRIER */
    if (match(P, TOK_BARRIER)) {
        AstNode *n = ast_new(AST_BARRIER, P->previous.line);
        consume(P, TOK_LPAREN, "expect '('");
        n->u.barrier.id = (int)expression(P)->u.number.ival;
        consume(P, TOK_RPAREN, "expect ')'");
        match(P, TOK_SEMI);
        return n;
    }

    /* RETURN */
    if (match(P, TOK_RETURN)) {
        AstNode *n = ast_new(AST_RETURN, P->previous.line);
        if (!check(P, TOK_END) && !check(P, TOK_SEMI) && !check(P, TOK_FI) &&
            !check(P, TOK_ELSE) && !check(P, TOK_OD)) {
            n->u.ret.expr = expression(P);
        }
        match(P, TOK_SEMI);
        return n;
    }

    /* EXIT */
    if (match(P, TOK_EXIT)) {
        AstNode *n = ast_new(AST_EXIT, P->previous.line);
        match(P, TOK_SEMI);
        return n;
    }

    /* LABEL */
    if (match(P, TOK_LABEL)) {
        AstNode *n = ast_new(AST_LABEL, P->previous.line);
        consume(P, TOK_IDENT, "expect label name");
        n->u.ident.name = copy_lexeme(&P->previous);
        consume(P, TOK_COLON, "expect ':' after label");
        return n;
    }

    /* GOTO */
    if (match(P, TOK_GOTO)) {
        AstNode *n = ast_new(AST_GOTO, P->previous.line);
        consume(P, TOK_IDENT, "expect label name");
        n->u.ident.name = copy_lexeme(&P->previous);
        match(P, TOK_SEMI);
        return n;
    }

    /* BEGIN block */
    if (match(P, TOK_BEGIN)) {
        AstNode *n = block(P);
        consume(P, TOK_END, "expect END");
        return n;
    }

    /* declaration: LOCAL/OWN/GLOBAL/... TYPE name */
    if (check(P, TOK_LOCAL) || check(P, TOK_OWN) || check(P, TOK_GLOBAL) ||
        check(P, TOK_REGISTER) || check(P, TOK_SHARED) || check(P, TOK_PARAM) ||
        check(P, TOK_CONST) || check(P, TOK_ABSOLUTE) || check(P, TOK_BASED) ||
        check(P, TOK_WORD) || check(P, TOK_LONG) || check(P, TOK_BIT) ||
        check(P, TOK_BYTE) || check(P, TOK_FLOAT) || check(P, TOK_PRED)) {
        return declaration(P);
    }

    /* expression statement (assignment or call) */
    AstNode *e = expression(P);
    if (e && e->kind == AST_IDENT && match(P, TOK_ASSIGN)) {
        AstNode *n = ast_new(AST_ASSIGN, e->line);
        n->u.assign.lhs = e;
        n->u.assign.rhs = expression(P);
        match(P, TOK_SEMI);
        return n;
    }
    /* plain expression statement */
    AstNode *n = ast_new(AST_EXPR_STMT, e ? e->line : P->current.line);
    n->u.exprstmt.expr = e;
    match(P, TOK_SEMI);
    return n;
}

static AstNode *block(Parser *P) {
    AstNode *n = ast_new(AST_BLOCK, P->current.line);
    AstNode *stmts = NULL, *tail = NULL;
    while (!check(P, TOK_END) && !check(P, TOK_FI) &&
           !check(P, TOK_ELSE) && !check(P, TOK_OD) &&
           !check(P, TOK_EOF)) {
        AstNode *s = statement(P);
        if (s) {
            if (!stmts) stmts = tail = s;
            else { tail->next = s; tail = s; }
        }
    }
    n->u.block.stmts = stmts;
    return n;
}

/* ---------- Top-level ---------- */

void parser_init(Parser *P, Lexer *L) {
    P->lex = L;
    P->had_error = 0;
    P->panic = 0;
    advance(P);
}

AstNode *parse_module(Parser *P) {
    if (!match(P, TOK_MODULE)) {
        error(P, "expect MODULE");
        return NULL;
    }
    consume(P, TOK_IDENT, "expect module name");
    AstNode *n = ast_new(AST_MODULE, P->previous.line);
    n->u.module.name = copy_lexeme(&P->previous);

    /* optional module-level annotations */
    while (check(P, TOK_PRIORITY) || check(P, TOK_DEADLINE)) {
        advance(P);
        expression(P);
    }

    AstNode *decls = NULL, *dtail = NULL;
    AstNode *funcs = NULL, *ftail = NULL;

    while (!check(P, TOK_END) && !check(P, TOK_EOF)) {
        /* priority/deadline annotations */
        int prio = 0, dl = 0;
        while (check(P, TOK_PRIORITY) || check(P, TOK_DEADLINE)) {
            if (check(P, TOK_PRIORITY)) { advance(P); prio = (int)expression(P)->u.number.ival; }
            if (check(P, TOK_DEADLINE)) { advance(P); dl = (int)expression(P)->u.number.ival; }
        }

        if (match(P, TOK_ROUTINE)) {
            consume(P, TOK_IDENT, "expect routine name");
            AstNode *fn = ast_new(AST_ROUTINE, P->previous.line);
            fn->u.routine.name = copy_lexeme(&P->previous);
            fn->u.routine.priority = prio;
            fn->u.routine.deadline = dl;

            if (match(P, TOK_KERNEL))
                fn->u.routine.is_kernel = 1;

            consume(P, TOK_BEGIN, "expect BEGIN");
            fn->u.routine.body = block(P);
            consume(P, TOK_END, "expect END");

            if (!funcs) funcs = ftail = fn;
            else { ftail->next = fn; ftail = fn; }
        } else {
            AstNode *d = declaration(P);
            if (d) {
                if (!decls) decls = dtail = d;
                else { dtail->next = d; dtail = d; }
            }
        }
    }

    consume(P, TOK_END, "expect END (module)");
    match(P, TOK_SEMI);

    n->u.module.decls = decls;
    n->u.module.routines = funcs;
    return n;
}

void ast_free(AstNode *n) {
    /* production code would recurse and free all children */
    (void)n;
}

void ast_print(AstNode *n, int indent) {
    if (!n) return;
    for (int i = 0; i < indent; i++) printf("  ");
    switch (n->kind) {
    case AST_MODULE: printf("MODULE %s\n", n->u.module.name); break;
    case AST_ROUTINE: printf("ROUTINE %s%s\n", n->u.routine.name,
        n->u.routine.is_kernel ? " [KERNEL]" : ""); break;
    case AST_BLOCK: printf("BLOCK\n"); break;
    case AST_DECL: printf("DECL %s\n", n->u.decl.name); break;
    case AST_ASSIGN: printf("ASSIGN\n"); break;
    case AST_IF: printf("IF\n"); break;
    case AST_WHILE: printf("WHILE\n"); break;
    case AST_FOR: printf("FOR\n"); break;
    case AST_RETURN: printf("RETURN\n"); break;
    case AST_EXIT: printf("EXIT\n"); break;
    case AST_PARALLEL: printf("PARALLEL %d\n", n->u.parallel.width); break;
    case AST_BARRIER: printf("BARRIER(%d)\n", n->u.barrier.id); break;
    case AST_IDENT: printf("IDENT %s\n", n->u.ident.name); break;
    case AST_NUMBER: printf("NUMBER %ld\n", n->u.number.ival); break;
    case AST_BINARY: printf("BINARY op=%d\n", n->u.binary.op); break;
    case AST_UNARY: printf("UNARY op=%d\n", n->u.unary.op); break;
    case AST_CALL: printf("CALL\n"); break;
    case AST_BITFIELD: printf("BITFIELD off=%d wid=%d\n",
        n->u.bitfield.offset, n->u.bitfield.width); break;
    default: printf("NODE kind=%d\n", n->kind); break;
    }
    /* recurse into children (simplified) */
    if (n->kind == AST_MODULE) {
        ast_print(n->u.module.decls, indent + 1);
        ast_print(n->u.module.routines, indent + 1);
    }
    if (n->kind == AST_ROUTINE)
        ast_print(n->u.routine.body, indent + 1);
    if (n->kind == AST_BLOCK)
        ast_print(n->u.block.stmts, indent + 1);
    ast_print(n->next, indent);
}
