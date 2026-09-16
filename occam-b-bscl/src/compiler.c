#include "compiler.h"
#include "parser.h"
#include "types.h"
#include "wordcode.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

extern bool emit_wordcode(IRModule *m, FuncTab *ft, Compiler *comp,
                          WcImage *img, DiagList *dg);

/* Block 20: COMPILER — source -> lexer -> parser -> AST -> typecheck
 * -> IR -> Wordcode. Diagnostics carry file/line/column; any error
 * fails the compilation (fail-closed). */

void compiler_init(Compiler *c) {
    c->data = NULL; c->len = 0; c->cap = 0;
    diag_list_init(&c->diags);
}

void compiler_free(Compiler *c) {
    free(c->data);
    c->data = NULL; c->len = 0; c->cap = 0;
    diag_list_free(&c->diags);
}

static size_t data_append_bytes(Compiler *c, const char *s) {
    size_t off = c->len * 8;
    size_t n = strlen(s);
    for (size_t i = 0; i < n; i++) {
        size_t byte = off + i;
        size_t widx = byte / 8;
        while (widx >= c->cap) {
            size_t ncap = c->cap ? c->cap * 2 : 8;
            Word *nd = realloc(c->data, ncap * sizeof(Word));
            if (!nd) return off;
            memset(nd + c->cap, 0, (ncap - c->cap) * sizeof(Word));
            c->data = nd; c->cap = ncap;
        }
        if (widx >= c->len) { c->data[widx] = 0; c->len = widx + 1; }
        c->data[widx] |= ((Word)(unsigned char)s[i]) << ((byte % 8) * 8);
    }
    return off;
}

/* ---------------- AST -> IR ---------------- */

typedef struct {
    IRModule *m;
    FuncTab *ft;
    Compiler *comp;
    DiagList *dg;
    const char *file;
    SymTab locals;
    long labels;
    long break_stack[32];
    size_t nbreak;
    bool failed;
} Gen;

static long newlabel(Gen *g) { return g->labels++; }

static void gen_err(Gen *g, const Node *n, const char *msg) {
    diag_add(g->dg, D_ERROR, g->file, n->line, n->col, "%s", msg);
    g->failed = true;
}

static void emit(Gen *g, IROp op, long a, long b, long c, const char *note) {
    ir_emit(g->m, op, a, b, c, note);
}

static void gen_expr(Gen *g, Node *n);

/* comparisons set ZF=1 when TRUE; JZ jumps when ZF set */
static void materialize_bool(Gen *g) {
    long t = newlabel(g), e = newlabel(g);
    emit(g, IR_JZ, t, 0, 0, NULL);
    emit(g, IR_CONST, R0, 0, 0, NULL);
    emit(g, IR_JMP, e, 0, 0, NULL);
    ir_emit_label(g->m, t);
    emit(g, IR_CONST, R0, 1, 0, NULL);
    ir_emit_label(g->m, e);
}

/* emit condition: leaves ZF set iff the condition is true */
static void gen_cond(Gen *g, Node *n) {
    int op = (n && n->kind == N_BIN) ? (int)n->ival : 0;
    switch (op) {
    case TK_EQ: case TK_NE: case TK_LT: case TK_LE: case TK_GT: case TK_GE:
        gen_expr(g, n->a);
        emit(g, IR_PUSH, R0, 0, 0, NULL);
        gen_expr(g, n->b);
        emit(g, IR_POP, R1, 0, 0, NULL);
        switch (op) {
        case TK_EQ: emit(g, IR_EQ, R1, R0, 0, NULL); break;
        case TK_NE: emit(g, IR_NE, R1, R0, 0, NULL); break;
        case TK_LT: emit(g, IR_LT, R1, R0, 0, NULL); break;
        case TK_LE: emit(g, IR_LE, R1, R0, 0, NULL); break;
        case TK_GT: emit(g, IR_GT, R1, R0, 0, NULL); break;
        default: emit(g, IR_GE, R1, R0, 0, NULL); break;
        }
        return;
    default:
        gen_expr(g, n);
        emit(g, IR_CONST, R1, 0, 0, NULL);
        emit(g, IR_NE, R0, R1, 0, NULL); /* ZF=1 iff R0 != 0 */
        return;
    }
}

static void gen_args_push(Gen *g, Node *args, size_t *argc) {
    *argc = 0;
    for (Node *a = args; a; a = a->next) {
        gen_expr(g, a);
        emit(g, IR_PUSH, R0, 0, 0, NULL);
        (*argc)++;
    }
}

static void gen_call(Gen *g, Node *n) {
    if (strcmp(n->name, "chan") == 0) { emit(g, IR_CHAN, R0, 0, 0, NULL); return; }
    if (strcmp(n->name, "in") == 0) { emit(g, IR_IN, R0, 0, 0, NULL); return; }
    if (strcmp(n->name, "recv") == 0) { gen_expr(g, n->a); emit(g, IR_RECV, R0, 0, 0, NULL); return; }
    if (strcmp(n->name, "out") == 0) { gen_expr(g, n->a); emit(g, IR_OUT, R0, 0, 0, NULL); return; }
    if (strcmp(n->name, "wait") == 0) { gen_expr(g, n->a); emit(g, IR_WAIT, R0, 0, 0, NULL); return; }
    if (strcmp(n->name, "print") == 0) {
        size_t off = data_append_bytes(g->comp, n->a->str);
        emit(g, IR_OUTS, (long)off, (long)strlen(n->a->str), 0, NULL);
        return;
    }
    if (strcmp(n->name, "send") == 0) {
        gen_expr(g, n->a); /* channel */
        emit(g, IR_PUSH, R0, 0, 0, NULL);
        gen_expr(g, n->a->next); /* value */
        emit(g, IR_POP, R1, 0, 0, NULL);
        emit(g, IR_SEND, R1, R0, 0, NULL);
        return;
    }
    if (strcmp(n->name, "alt2") == 0) {
        gen_expr(g, n->a); /* c1 -> R0 */
        emit(g, IR_PUSH, R0, 0, 0, NULL);
        gen_expr(g, n->a->next); /* c2 -> R0 */
        emit(g, IR_POP, R1, 0, 0, NULL); /* R1=c1, R0=c2 */
        emit(g, IR_PUSH, R0, 0, 0, NULL);
        emit(g, IR_POP, R2, 0, 0, NULL);
        long lto = newlabel(g), ldone = newlabel(g);
        emit(g, IR_ALT, R1, R2, lto, NULL);
        emit(g, IR_JMP, ldone, 0, 0, NULL);
        ir_emit_label(g->m, lto);
        emit(g, IR_CONST, R0, 0, 0, NULL); /* timeout: value 0 */
        emit(g, IR_CONST, R1, 2, 0, NULL); /* index 2 */
        ir_emit_label(g->m, ldone);
        emit(g, IR_CONST, R2, 32, 0, NULL);
        emit(g, IR_SHL, R1, R2, 0, NULL); /* R1 = index << 32 */
        emit(g, IR_OR, R0, R1, 0, NULL); /* R0 = idx|value */
        return;
    }
    /* user function */
    size_t argc;
    gen_args_push(g, n->a, &argc);
    int fi = functab_lookup(g->ft, n->name);
    if (fi < 0) { gen_err(g, n, "call to unknown function"); return; }
    emit(g, IR_CALL, g->ft->fns[fi].label, (long)argc, 0, n->name);
}

static void gen_expr(Gen *g, Node *n) {
    if (!n || g->failed) return;
    switch (n->kind) {
    case N_INT:
        if (n->ival > 0xFFFFFFFFFFULL) { gen_err(g, n, "integer literal exceeds 40-bit immediate"); return; }
        emit(g, IR_CONST, R0, (long)n->ival, 0, NULL);
        return;
    case N_VAR:
        emit(g, IR_LOAD, R0, (long)n->ival, 0, n->name);
        return;
    case N_UNARY:
        if (n->ival == '-') {
            gen_expr(g, n->a);
            emit(g, IR_PUSH, R0, 0, 0, NULL);
            emit(g, IR_CONST, R0, 0, 0, NULL);
            emit(g, IR_POP, R1, 0, 0, NULL);
            emit(g, IR_SUB, R0, R1, 0, NULL);
        } else if (n->ival == '~') {
            gen_expr(g, n->a);
            emit(g, IR_NOT, R0, 0, 0, NULL);
        } else { /* '!' : R0 = (x == 0) */
            gen_expr(g, n->a);
            emit(g, IR_CONST, R1, 0, 0, NULL);
            emit(g, IR_EQ, R0, R1, 0, NULL);
            materialize_bool(g);
        }
        return;
    case N_BIN: {
        int op = (int)n->ival;
        if (op == TK_ANDAND || op == TK_OROR) {
            gen_expr(g, n->a);
            emit(g, IR_BOOL, R0, 0, 0, NULL);
            emit(g, IR_PUSH, R0, 0, 0, NULL);
            gen_expr(g, n->b);
            emit(g, IR_BOOL, R0, 0, 0, NULL);
            emit(g, IR_POP, R1, 0, 0, NULL);
            emit(g, op == TK_ANDAND ? IR_AND : IR_OR, R1, R0, 0, NULL);
            emit(g, IR_CONST, R0, 0, 0, NULL);
            emit(g, IR_ADD, R0, R1, 0, NULL);
            return;
        }
        gen_expr(g, n->a);
        emit(g, IR_PUSH, R0, 0, 0, NULL);
        gen_expr(g, n->b);
        emit(g, IR_POP, R1, 0, 0, NULL); /* R1 = left, R0 = right */
        switch (op) {
        case TK_EQ: case TK_NE: case TK_LT: case TK_LE: case TK_GT: case TK_GE:
            switch (op) {
            case TK_EQ: emit(g, IR_EQ, R1, R0, 0, NULL); break;
            case TK_NE: emit(g, IR_NE, R1, R0, 0, NULL); break;
            case TK_LT: emit(g, IR_LT, R1, R0, 0, NULL); break;
            case TK_LE: emit(g, IR_LE, R1, R0, 0, NULL); break;
            case TK_GT: emit(g, IR_GT, R1, R0, 0, NULL); break;
            default: emit(g, IR_GE, R1, R0, 0, NULL); break;
            }
            materialize_bool(g);
            return;
        case TK_PLUS: emit(g, IR_ADD, R1, R0, 0, NULL); break;
        case TK_MINUS: emit(g, IR_SUB, R1, R0, 0, NULL); break;
        case TK_STAR: emit(g, IR_MUL, R1, R0, 0, NULL); break;
        case TK_SLASH: emit(g, IR_DIV, R1, R0, 0, NULL); break;
        case TK_PERCENT: emit(g, IR_MOD, R1, R0, 0, NULL); break;
        case TK_AMP: emit(g, IR_AND, R1, R0, 0, NULL); break;
        case TK_PIPE: emit(g, IR_OR, R1, R0, 0, NULL); break;
        case TK_CARET: emit(g, IR_XOR, R1, R0, 0, NULL); break;
        case TK_SHL: emit(g, IR_SHL, R1, R0, 0, NULL); break;
        default: emit(g, IR_SHR, R1, R0, 0, NULL); break;
        }
        emit(g, IR_CONST, R0, 0, 0, NULL);
        emit(g, IR_ADD, R0, R1, 0, NULL); /* R0 = R1 */
        return;
    }
    case N_CALL:
        gen_call(g, n);
        return;
    case N_SPAWN: {
        size_t argc;
        gen_args_push(g, n->a, &argc);
        int fi = functab_lookup(g->ft, n->name);
        if (fi < 0) { gen_err(g, n, "spawn of unknown process"); return; }
        emit(g, IR_SPAWN, g->ft->fns[fi].label, (long)argc, 0, n->name);
        return;
    }
    default:
        gen_err(g, n, "node not valid in expression");
        return;
    }
}

static void gen_stmt(Gen *g, Node *n) {
    if (!n || g->failed) return;
    switch (n->kind) {
    case N_BLOCK:
        for (Node *s = n->a; s; s = s->next) gen_stmt(g, s);
        return;
    case N_ASSIGN: {
        gen_expr(g, n->a);
        int i = symtab_lookup(&g->locals, n->name);
        if (i < 0) {
            symtab_add(&g->locals, n->name, T_WORD, (Word)g->locals.count);
            i = (int)g->locals.count - 1;
        }
        emit(g, IR_STORE, (long)g->locals.syms[i].slot, R0, 0, n->name);
        return;
    }
    case N_IF: {
        long lt = newlabel(g), le = newlabel(g), ld = newlabel(g);
        gen_cond(g, n->a);
        emit(g, IR_JZ, lt, 0, 0, NULL);
        emit(g, IR_JMP, le, 0, 0, NULL);
        ir_emit_label(g->m, lt);
        gen_stmt(g, n->b);
        emit(g, IR_JMP, ld, 0, 0, NULL);
        ir_emit_label(g->m, le);
        gen_stmt(g, n->c);
        ir_emit_label(g->m, ld);
        return;
    }
    case N_WHILE: {
        long ls = newlabel(g), lb = newlabel(g), le = newlabel(g);
        if (g->nbreak < 32) g->break_stack[g->nbreak++] = le; else gen_err(g, n, "break stack overflow");
        ir_emit_label(g->m, ls);
        gen_cond(g, n->a);
        emit(g, IR_JZ, lb, 0, 0, NULL);
        emit(g, IR_JMP, le, 0, 0, NULL);
        ir_emit_label(g->m, lb);
        gen_stmt(g, n->b);
        emit(g, IR_JMP, ls, 0, 0, NULL);
        ir_emit_label(g->m, le);
        if (g->nbreak) g->nbreak--;
        return;
    }
    case N_BREAK:
        if (g->nbreak == 0) { gen_err(g, n, "break outside loop"); return; }
        emit(g, IR_JMP, g->break_stack[g->nbreak - 1], 0, 0, NULL);
        return;
    case N_RETURN:
        if (n->a) gen_expr(g, n->a); else emit(g, IR_CONST, R0, 0, 0, NULL);
        emit(g, IR_RET, 0, 0, 0, NULL);
        return;
    case N_CALL:
    case N_SPAWN:
        gen_expr(g, n); /* result ignored; stack balanced */
        return;
    default:
        gen_err(g, n, "node not valid as statement");
        return;
    }
}

static void gen_func(Gen *g, Node *f) {
    int fi = functab_lookup(g->ft, f->name);
    symtab_init(&g->locals);
    Word slot = 0;
    for (Node *p = f->a; p; p = p->next, slot++)
        symtab_add(&g->locals, p->name, T_WORD, slot);
    g->nbreak = 0;
    ir_emit_label(g->m, g->ft->fns[fi].label);
    gen_stmt(g, f->b);
    emit(g, IR_CONST, R0, 0, 0, NULL); /* implicit return 0 */
    emit(g, IR_RET, 0, 0, 0, NULL);
}

/* ---------------- pipeline ---------------- */

bool compile_source(Compiler *c, const char *src, const char *file,
                    WcImage *img) {
    wc_image_init(img);
    TokenStream ts;
    if (!lexer_tokenize(src, file, &ts, &c->diags)) {
        token_stream_free(&ts);
        return false;
    }
    Node *prog = NULL;
    if (!parse_program(&ts, &c->diags, &prog)) {
        token_stream_free(&ts);
        return false;
    }
    token_stream_free(&ts);

    FuncTab ft;
    if (!typecheck_program(prog, &ft, &c->diags, file)) {
        ast_free(prog);
        return false;
    }

    IRModule m;
    ir_module_init(&m);
    Gen g;
    g.m = &m; g.ft = &ft; g.comp = c; g.dg = &c->diags; g.file = file;
    g.labels = 0; g.nbreak = 0; g.failed = false;
    symtab_init(&g.locals);

    for (Node *f = prog->a; f && !g.failed; f = f->next)
        gen_func(&g, f);

    bool ok = !g.failed && c->diags.error_count == 0;
    if (ok) ok = emit_wordcode(&m, &ft, c, img, &c->diags);

    ir_module_free(&m);
    ast_free(prog);
    return ok;
}

int compile_file(Compiler *c, const char *path, WcImage *img) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        diag_add(&c->diags, D_ERROR, path, 0, 0, "cannot open source file");
        return 1;
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *src = malloc((size_t)n + 1);
    if (!src) { fclose(f); return 1; }
    if (fread(src, 1, (size_t)n, f) != (size_t)n) { /* tolerate short read */ }
    src[n] = 0;
    fclose(f);

    /* dialect selection by extension (Blocks 18/19) */
    const char *dot = strrchr(path, '.');
    char *bsrc = NULL;
    bool ok;
    if (dot && strcmp(dot, ".occ") == 0) {
        ok = occam_to_b(src, &bsrc, &c->diags, path);
        if (ok) ok = compile_source(c, bsrc, path, img);
        free(bsrc);
    } else if (dot && strcmp(dot, ".bscl") == 0) {
        ok = bscl_to_b(src, &bsrc, &c->diags, path);
        if (ok) ok = compile_source(c, bsrc, path, img);
        free(bsrc);
    } else {
        ok = compile_source(c, src, path, img);
    }
    free(src);
    return ok ? 0 : 1;
}
