#include "ir.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

IrModule *ir_new_module(void) {
    return calloc(1, sizeof(IrModule));
}

IrFunc *ir_new_func(IrModule *m, const char *name, int is_kernel) {
    IrFunc *f = calloc(1, sizeof(IrFunc));
    f->name = strdup(name);
    f->is_kernel = is_kernel;
    f->num_regs = 8;
    f->num_preds = 4;
    if (!m->funcs) m->funcs = f;
    else {
        IrFunc *p = m->funcs;
        while (p->next) p = p->next;
        p->next = f;
    }
    return f;
}

IrInst *ir_emit(IrFunc *f, IrOpcode op) {
    IrInst *i = calloc(1, sizeof(IrInst));
    i->op = op;
    if (!f->first) f->first = f->last = i;
    else {
        f->last->next = i;
        f->last = i;
    }
    return i;
}

IrOperand ir_reg(int r) {
    IrOperand o = {0};
    o.kind = OP_REG;
    o.reg = r;
    return o;
}

IrOperand ir_imm(long v) {
    IrOperand o = {0};
    o.kind = OP_IMM;
    o.imm = v;
    return o;
}

IrOperand ir_pred(int p) {
    IrOperand o = {0};
    o.kind = OP_PRED;
    o.pred = p;
    return o;
}

IrOperand ir_mem(AddrSpace as, int base, int off) {
    IrOperand o = {0};
    o.kind = OP_MEM;
    o.as = as;
    o.mem_base = base;
    o.mem_off = off;
    return o;
}

static const char *op_name(IrOpcode op) {
    static const char *n[] = {
        "nop","mov","add","sub","mul","div","mad",
        "and","or","xor","not","shl","shr","rol","ror",
        "min","max","abs","neg","setp","selp",
        "ld","st","atom","bra","bra.p","call","ret","exit",
        "bar.sync","shfl","vote","redux","cvt","label","comment"
    };
    return n[op];
}

static void print_operand(FILE *out, IrOperand *o) {
    switch (o->kind) {
    case OP_NONE: fprintf(out, "_"); break;
    case OP_REG: fprintf(out, "r%d", o->reg); break;
    case OP_IMM: fprintf(out, "%ld", o->imm); break;
    case OP_PRED: fprintf(out, "p%d", o->pred); break;
    case OP_LABEL: fprintf(out, "%s", o->label ? o->label : "?"); break;
    case OP_MEM:
        fprintf(out, "%s[r%d%+d]",
                o->as == AS_SHARED ? "shared" :
                o->as == AS_GLOBAL ? "global" :
                o->as == AS_PARAM ? "param" :
                o->as == AS_CONST ? "const" : "local",
                o->mem_base, o->mem_off);
        break;
    }
}

void ir_print(IrModule *m, FILE *out) {
    for (IrFunc *f = m->funcs; f; f = f->next) {
        fprintf(out, ".%s %s\n", f->is_kernel ? "entry" : "func", f->name);
        fprintf(out, " .regs %d\n .preds %d\n", f->num_regs, f->num_preds);
        for (IrInst *i = f->first; i; i = i->next) {
            if (i->op == IR_LABEL) {
                fprintf(out, "%s:\n", i->src0.label ? i->src0.label : "L");
                continue;
            }
            if (i->op == IR_COMMENT) {
                fprintf(out, " ; %s\n", i->comment ? i->comment : "");
                continue;
            }
            fprintf(out, " ");
            if (i->pred >= 0)
                fprintf(out, "@p%d ", i->pred);
            fprintf(out, "%-8s ", op_name(i->op));
            print_operand(out, &i->dst);
            if (i->src0.kind != OP_NONE) {
                fprintf(out, ", ");
                print_operand(out, &i->src0);
            }
            if (i->src1.kind != OP_NONE) {
                fprintf(out, ", ");
                print_operand(out, &i->src1);
            }
            if (i->src2.kind != OP_NONE) {
                fprintf(out, ", ");
                print_operand(out, &i->src2);
            }
            fprintf(out, "\n");
        }
        fprintf(out, "\n");
    }
}

void ir_free(IrModule *m) {
    for (IrFunc *f = m->funcs; f;) {
        IrFunc *nf = f->next;
        for (IrInst *i = f->first; i;) {
            IrInst *ni = i->next;
            free(i->comment);
            free(i);
            i = ni;
        }
        free(f->name);
        free(f);
        f = nf;
    }
    free(m);
}
