#include "codegen.h"
#include "symtab.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *xstrdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p) memcpy(p, s, n);
    return p;
}

typedef struct {
    IrFunc *func;
    SymTab *st;
    int next_label;
} Gen;

static int fresh_label(Gen *g) {
    return g->next_label++;
}

static char *labname(int id, const char *pref) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%s%d", pref, id);
    return xstrdup(buf);
}

static int load_symbol(Gen *g, Symbol *sym) {
    if (!sym) return -1;
    if (sym->reg >= 0)
        return sym->reg;

    int dst = g->st->next_reg++;
    IrInst *i;

    if (sym->storage == STOR_ABSOLUTE) {
        int addr = g->st->next_reg++;
        i = ir_emit(g->func, IR_MOV);
        i->dst = ir_reg(addr);
        i->src0 = ir_imm(sym->absolute);
        i = ir_emit(g->func, IR_LD);
        i->dst = ir_reg(dst);
        i->src0 = ir_mem(AS_ABS, addr, 0);
        i->comment = xstrdup(sym->name);
    } else if (sym->storage == STOR_BASED && sym->based_on) {
        int base_r = sym->reg >= 0 ? sym->reg : 0;
        i = ir_emit(g->func, IR_LD);
        i->dst = ir_reg(dst);
        i->src0 = ir_mem(AS_GLOBAL, base_r, 0);
        i->comment = xstrdup(sym->name);
    } else if (sym->storage == STOR_SHARED) {
        i = ir_emit(g->func, IR_LD);
        i->dst = ir_reg(dst);
        i->src0 = ir_mem(AS_SHARED, 0, sym->slot * 4);
        i->comment = xstrdup(sym->name);
    } else if (sym->storage == STOR_GLOBAL || sym->storage == STOR_PARAM) {
        i = ir_emit(g->func, IR_LD);
        i->dst = ir_reg(dst);
        i->src0 = ir_mem(sym->storage == STOR_PARAM ? AS_PARAM : AS_GLOBAL,
                         0, sym->slot * 4);
        i->comment = xstrdup(sym->name);
    } else {
        sym->reg = dst;
    }
    return dst;
}

static void store_symbol(Gen *g, Symbol *sym, int src_reg) {
    if (!sym) return;
    IrInst *i;
    if (sym->reg >= 0 && sym->storage != STOR_SHARED &&
        sym->storage != STOR_GLOBAL && sym->storage != STOR_ABSOLUTE) {
        i = ir_emit(g->func, IR_MOV);
        i->dst = ir_reg(sym->reg);
        i->src0 = ir_reg(src_reg);
        return;
    }
    if (sym->storage == STOR_ABSOLUTE) {
        int addr = g->st->next_reg++;
        i = ir_emit(g->func, IR_MOV);
        i->dst = ir_reg(addr);
        i->src0 = ir_imm(sym->absolute);
        i = ir_emit(g->func, IR_ST);
        i->dst = ir_mem(AS_ABS, addr, 0);
        i->src0 = ir_reg(src_reg);
    } else if (sym->storage == STOR_SHARED) {
        i = ir_emit(g->func, IR_ST);
        i->dst = ir_mem(AS_SHARED, 0, sym->slot * 4);
        i->src0 = ir_reg(src_reg);
    } else if (sym->storage == STOR_GLOBAL || sym->storage == STOR_PARAM) {
        i = ir_emit(g->func, IR_ST);
        i->dst = ir_mem(sym->storage == STOR_PARAM ? AS_PARAM : AS_GLOBAL,
                        0, sym->slot * 4);
        i->src0 = ir_reg(src_reg);
    } else {
        if (sym->reg < 0) sym->reg = g->st->next_reg++;
        i = ir_emit(g->func, IR_MOV);
        i->dst = ir_reg(sym->reg);
        i->src0 = ir_reg(src_reg);
    }
}

static int gen_expr(Gen *g, AstNode *e) {
    if (!e) return -1;
    switch (e->kind) {
    case AST_NUMBER: {
        int r = g->st->next_reg++;
        IrInst *i = ir_emit(g->func, IR_MOV);
        i->dst = ir_reg(r);
        i->src0 = ir_imm(e->u.number.ival);
        return r;
    }
    case AST_IDENT: {
        Symbol *sym = symtab_lookup(g->st, e->u.ident.name);
        if (!sym) {
            int r = g->st->next_reg++;
            IrInst *i = ir_emit(g->func, IR_MOV);
            i->dst = ir_reg(r);
            i->src0 = ir_imm(0);
            i->comment = xstrdup(e->u.ident.name);
            return r;
        }
        return load_symbol(g, sym);
    }
    case AST_BINARY: {
        int left = gen_expr(g, e->u.binary.left);
        int right = gen_expr(g, e->u.binary.right);
        int dst = g->st->next_reg++;
        IrOpcode op = IR_ADD;
        int is_cmp = 0;
        switch (e->u.binary.op) {
        case TOK_PLUS: op = IR_ADD; break;
        case TOK_MINUS: op = IR_SUB; break;
        case TOK_STAR: op = IR_MUL; break;
        case TOK_SLASH: op = IR_DIV; break;
        case TOK_AND: op = IR_AND; break;
        case TOK_OR: op = IR_OR; break;
        case TOK_XOR: op = IR_XOR; break;
        case TOK_SHL: op = IR_SHL; break;
        case TOK_SHR: op = IR_SHR; break;
        case TOK_EQ: case TOK_NE: case TOK_LT: case TOK_LE:
        case TOK_GT: case TOK_GE:
            is_cmp = 1;
            break;
        default: break;
        }
        if (is_cmp) {
            int p = g->st->next_pred++;
            IrInst *i = ir_emit(g->func, IR_SETP);
            i->dst = ir_pred(p);
            i->src0 = ir_reg(left);
            i->src1 = ir_reg(right);
            const char *cm = "eq";
            if (e->u.binary.op == TOK_NE) cm = "ne";
            else if (e->u.binary.op == TOK_LT) cm = "lt";
            else if (e->u.binary.op == TOK_LE) cm = "le";
            else if (e->u.binary.op == TOK_GT) cm = "gt";
            else if (e->u.binary.op == TOK_GE) cm = "ge";
            i->comment = xstrdup(cm);
            return p;
        }
        IrInst *i = ir_emit(g->func, op);
        i->dst = ir_reg(dst);
        i->src0 = ir_reg(left);
        i->src1 = ir_reg(right);
        return dst;
    }
    case AST_UNARY: {
        int src = gen_expr(g, e->u.unary.operand);
        int dst = g->st->next_reg++;
        IrOpcode op = (e->u.unary.op == TOK_NOT || e->u.unary.op == TOK_TILDE)
                      ? IR_NOT : IR_NEG;
        IrInst *i = ir_emit(g->func, op);
        i->dst = ir_reg(dst);
        i->src0 = ir_reg(src);
        return dst;
    }
    case AST_COND: {
        int c = gen_expr(g, e->u.cond.cond);
        int l_else = fresh_label(g);
        int l_end = fresh_label(g);
        IrInst *br = ir_emit(g->func, IR_BRA_P);
        br->src0 = ir_pred(c);
        br->src1.kind = OP_LABEL;
        br->src1.label = labname(l_else, "Lelse");
        int t = gen_expr(g, e->u.cond.then_e);
        int dst = g->st->next_reg++;
        IrInst *mv1 = ir_emit(g->func, IR_MOV);
        mv1->dst = ir_reg(dst);
        mv1->src0 = ir_reg(t);
        IrInst *j = ir_emit(g->func, IR_BRA);
        j->src0.kind = OP_LABEL;
        j->src0.label = labname(l_end, "Lend");
        IrInst *lab1 = ir_emit(g->func, IR_LABEL);
        lab1->src0.kind = OP_LABEL;
        lab1->src0.label = labname(l_else, "Lelse");
        int f = gen_expr(g, e->u.cond.else_e);
        IrInst *mv2 = ir_emit(g->func, IR_MOV);
        mv2->dst = ir_reg(dst);
        mv2->src0 = ir_reg(f);
        IrInst *lab2 = ir_emit(g->func, IR_LABEL);
        lab2->src0.kind = OP_LABEL;
        lab2->src0.label = labname(l_end, "Lend");
        return dst;
    }
    case AST_BITFIELD: {
        int src = gen_expr(g, e->u.bitfield.expr);
        int tmp = g->st->next_reg++;
        IrInst *sh = ir_emit(g->func, IR_SHR);
        sh->dst = ir_reg(tmp);
        sh->src0 = ir_reg(src);
        sh->src1 = ir_imm(e->u.bitfield.offset);
        int mask = (1 << e->u.bitfield.width) - 1;
        int dst = g->st->next_reg++;
        IrInst *an = ir_emit(g->func, IR_AND);
        an->dst = ir_reg(dst);
        an->src0 = ir_reg(tmp);
        an->src1 = ir_imm(mask);
        return dst;
    }
    case AST_CALL: {
        int nargs = 0;
        for (AstNode *a = e->u.call.args; a; a = a->next) nargs++;
        int *args = malloc(nargs * sizeof(int));
        int idx = 0;
        for (AstNode *a = e->u.call.args; a; a = a->next)
            args[idx++] = gen_expr(g, a);
        int dst = g->st->next_reg++;
        IrInst *call = ir_emit(g->func, IR_CALL);
        call->dst = ir_reg(dst);
        call->src0.kind = OP_LABEL;
        call->src0.label = xstrdup(e->u.call.fn->u.ident.name);
        free(args);
        return dst;
    }
    default:
        break;
    }
    return -1;
}

static void gen_stmt(Gen *g, AstNode *s) {
    if (!s) return;
    switch (s->kind) {
    case AST_ASSIGN: {
        int rhs = gen_expr(g, s->u.assign.rhs);
        Symbol *sym = symtab_lookup(g->st, s->u.assign.lhs->u.ident.name);
        store_symbol(g, sym, rhs);
        break;
    }
    case AST_IF: {
        int c = gen_expr(g, s->u.ifstmt.cond);
        int l_else = fresh_label(g);
        int l_end = fresh_label(g);
        IrInst *br = ir_emit(g->func, IR_BRA_P);
        br->src0 = ir_pred(c);
        br->src1.kind = OP_LABEL;
        br->src1.label = labname(l_else, "Lelse");
        /* then block */
        for (AstNode *st = s->u.ifstmt.then_b->u.block.stmts; st; st = st->next)
            gen_stmt(g, st);
        IrInst *j = ir_emit(g->func, IR_BRA);
        j->src0.kind = OP_LABEL;
        j->src0.label = labname(l_end, "Lend");
        /* else label */
        IrInst *lab1 = ir_emit(g->func, IR_LABEL);
        lab1->src0.kind = OP_LABEL;
        lab1->src0.label = labname(l_else, "Lelse");
        if (s->u.ifstmt.else_b) {
            for (AstNode *st = s->u.ifstmt.else_b->u.block.stmts; st; st = st->next)
                gen_stmt(g, st);
        }
        /* end label */
        IrInst *lab2 = ir_emit(g->func, IR_LABEL);
        lab2->src0.kind = OP_LABEL;
        lab2->src0.label = labname(l_end, "Lend");
        break;
    }
    case AST_WHILE: {
        int l_top = fresh_label(g);
        int l_end = fresh_label(g);
        IrInst *lab = ir_emit(g->func, IR_LABEL);
        lab->src0.kind = OP_LABEL;
        lab->src0.label = labname(l_top, "Ltop");
        int c = gen_expr(g, s->u.whilestmt.cond);
        IrInst *br = ir_emit(g->func, IR_BRA_P);
        br->src0 = ir_pred(c);
        br->src1.kind = OP_LABEL;
        br->src1.label = labname(l_end, "Lend");
        for (AstNode *st = s->u.whilestmt.body->u.block.stmts; st; st = st->next)
            gen_stmt(g, st);
        IrInst *j = ir_emit(g->func, IR_BRA);
        j->src0.kind = OP_LABEL;
        j->src0.label = labname(l_top, "Ltop");
        IrInst *lab2 = ir_emit(g->func, IR_LABEL);
        lab2->src0.kind = OP_LABEL;
        lab2->src0.label = labname(l_end, "Lend");
        break;
    }
    case AST_FOR: {
        gen_stmt(g, s->u.forstmt.init);
        int l_top = fresh_label(g);
        int l_end = fresh_label(g);
        IrInst *lab = ir_emit(g->func, IR_LABEL);
        lab->src0.kind = OP_LABEL;
        lab->src0.label = labname(l_top, "Ltop");
        int c = gen_expr(g, s->u.forstmt.cond);
        IrInst *br = ir_emit(g->func, IR_BRA_P);
        br->src0 = ir_pred(c);
        br->src1.kind = OP_LABEL;
        br->src1.label = labname(l_end, "Lend");
        for (AstNode *st = s->u.forstmt.body->u.block.stmts; st; st = st->next)
            gen_stmt(g, st);
        if (s->u.forstmt.step)
            gen_expr(g, s->u.forstmt.step);
        IrInst *j = ir_emit(g->func, IR_BRA);
        j->src0.kind = OP_LABEL;
        j->src0.label = labname(l_top, "Ltop");
        IrInst *lab2 = ir_emit(g->func, IR_LABEL);
        lab2->src0.kind = OP_LABEL;
        lab2->src0.label = labname(l_end, "Lend");
        break;
    }
    case AST_PARALLEL: {
        IrInst *bar = ir_emit(g->func, IR_BAR_SYNC);
        bar->src0 = ir_imm(0);
        break;
    }
    case AST_BARRIER: {
        IrInst *bar = ir_emit(g->func, IR_BAR_SYNC);
        bar->src0 = ir_imm(s->u.barrier.id);
        break;
    }
    case AST_RETURN: {
        if (s->u.ret.expr) {
            int r = gen_expr(g, s->u.ret.expr);
            IrInst *i = ir_emit(g->func, IR_MOV);
            i->dst = ir_reg(0);
            i->src0 = ir_reg(r);
        }
        ir_emit(g->func, IR_RET);
        break;
    }
    case AST_EXIT: {
        ir_emit(g->func, IR_EXIT);
        break;
    }
    case AST_EXPR_STMT: {
        if (s->u.exprstmt.expr)
            gen_expr(g, s->u.exprstmt.expr);
        break;
    }
    case AST_BLOCK: {
        for (AstNode *st = s->u.block.stmts; st; st = st->next)
            gen_stmt(g, st);
        break;
    }
    case AST_LABEL: {
        IrInst *lab = ir_emit(g->func, IR_LABEL);
        lab->src0.kind = OP_LABEL;
        lab->src0.label = xstrdup(s->u.ident.name);
        break;
    }
    case AST_GOTO: {
        IrInst *j = ir_emit(g->func, IR_BRA);
        j->src0.kind = OP_LABEL;
        j->src0.label = xstrdup(s->u.ident.name);
        break;
    }
    default:
        break;
    }
}

IrModule *codegen(AstNode *module) {
    if (!module || module->kind != AST_MODULE) return NULL;

    IrModule *ir = ir_new_module();

    for (AstNode *fn = module->u.module.routines; fn; fn = fn->next) {
        if (fn->kind != AST_ROUTINE) continue;

        SymTab st;
        symtab_init(&st);

        IrFunc *func = ir_new_func(ir, fn->u.routine.name, fn->u.routine.is_kernel);
        Gen g = { .func = func, .st = &st, .next_label = 0 };

        /* enter function scope */
        symtab_push(&st);

        /* register parameters */
        for (AstNode *p = fn->u.routine.params; p; p = p->next) {
            if (p->kind == AST_DECL) {
                Symbol *sym = symtab_insert(&st, p->u.decl.name,
                    p->u.decl.type, STOR_PARAM);
                if (sym) {
                    sym->reg = st.next_reg++;
                    IrInst *i = ir_emit(func, IR_MOV);
                    i->dst = ir_reg(sym->reg);
                    i->src0 = ir_imm(0);
                    i->comment = xstrdup(sym->name);
                }
            }
        }

        /* register local declarations */
        for (AstNode *d = fn->u.routine.body->u.block.stmts; d; d = d->next) {
            if (d->kind == AST_DECL) {
                Symbol *sym = symtab_insert(&st, d->u.decl.name,
                    d->u.decl.type, d->u.decl.storage);
                if (sym && d->u.decl.init) {
                    int r = gen_expr(&g, d->u.decl.init);
                    store_symbol(&g, sym, r);
                }
            }
        }

        /* generate body statements */
        for (AstNode *s = fn->u.routine.body->u.block.stmts; s; s = s->next) {
            if (s->kind != AST_DECL)
                gen_stmt(&g, s);
        }

        /* ensure function ends with ret/exit */
        if (!func->last || (func->last->op != IR_RET && func->last->op != IR_EXIT))
            ir_emit(func, IR_EXIT);

        func->num_regs = st.next_reg;
        func->num_preds = st.next_pred;

        symtab_pop(&st);
    }

    return ir;
}
