#include "ir.h"
#include "compiler.h"
#include "types.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Block 20 (backend half): IR -> Wordcode.
 * Two passes: (1) assign code addresses to labels, (2) emit packed
 * instructions, resolving labels, CALL/SPAWN frame sizes and ALT
 * timeout offsets. Fails closed on unresolved labels or bad targets. */

static int ir_to_wc(IROp op) {
    switch (op) {
    case IR_NOP: return OP_NOP; case IR_CONST: return OP_CONST;
    case IR_LOAD: return OP_LOAD; case IR_STORE: return OP_STORE;
    case IR_PUSH: return OP_PUSH; case IR_POP: return OP_POP;
    case IR_DROP: return OP_DROP; case IR_DUP: return OP_DUP;
    case IR_ADD: return OP_ADD; case IR_SUB: return OP_SUB;
    case IR_MUL: return OP_MUL; case IR_DIV: return OP_DIV;
    case IR_MOD: return OP_MOD; case IR_AND: return OP_AND;
    case IR_OR: return OP_OR; case IR_XOR: return OP_XOR;
    case IR_NOT: return OP_NOT; case IR_SHL: return OP_SHL;
    case IR_SHR: return OP_SHR; case IR_BOOL: return OP_BOOL;
    case IR_EQ: return OP_EQ; case IR_NE: return OP_NE;
    case IR_LT: return OP_LT; case IR_LE: return OP_LE;
    case IR_GT: return OP_GT; case IR_GE: return OP_GE;
    case IR_JMP: return OP_JMP; case IR_JZ: return OP_JZ;
    case IR_JNZ: return OP_JNZ; case IR_CALL: return OP_CALL;
    case IR_RET: return OP_RET; case IR_SPAWN: return OP_SPAWN;
    case IR_SEND: return OP_SEND; case IR_RECV: return OP_RECV;
    case IR_ALT: return OP_ALT; case IR_WAIT: return OP_WAIT;
    case IR_YIELD: return OP_YIELD; case IR_ALLOC: return OP_ALLOC;
    case IR_FREE: return OP_FREE; case IR_IN: return OP_IN;
    case IR_OUT: return OP_OUT; case IR_OUTS: return OP_OUTS;
    case IR_CHAN: return OP_CHAN; case IR_HALT: return OP_HALT;
    default: return -1;
    }
}

static const FuncEnt *func_by_label(const FuncTab *ft, long label) {
    for (size_t i = 0; i < ft->count; i++)
        if (ft->fns[i].label == label) return &ft->fns[i];
    return NULL;
}

bool emit_wordcode(IRModule *m, FuncTab *ft, Compiler *comp,
                   WcImage *img, DiagList *dg) {
    /* pass 1: label addresses */
    size_t addr = 0, nlabels = 0;
    for (size_t i = 0; i < m->count; i++) {
        if (m->items[i].op == IR_LABEL) {
            if (m->items[i].a + 1 > (long)nlabels) nlabels = (size_t)(m->items[i].a + 1);
        } else addr++;
    }
    long *laddr = calloc(nlabels ? nlabels : 1, sizeof(long));
    if (!laddr) { diag_add(dg, D_ERROR, "<emit>", 0, 0, "out of memory"); return false; }
    addr = 0;
    for (size_t i = 0; i < m->count; i++) {
        if (m->items[i].op == IR_LABEL) laddr[m->items[i].a] = (long)addr;
        else addr++;
    }
    size_t code_words = addr;
    Word *code = calloc(code_words ? code_words : 1, sizeof(Word));
    if (!code) { free(laddr); diag_add(dg, D_ERROR, "<emit>", 0, 0, "out of memory"); return false; }

    /* pass 2: emit */
    addr = 0;
    bool ok = true;
    for (size_t i = 0; i < m->count && ok; i++) {
        IRInstr *in = &m->items[i];
        if (in->op == IR_LABEL) continue;
        int wop = ir_to_wc(in->op);
        if (wop < 0) {
            diag_add(dg, D_ERROR, "<emit>", 0, 0, "no wordcode for IR op %d", in->op);
            ok = false; break;
        }
        uint32_t a = (uint32_t)in->a, b = (uint32_t)in->b, c = (uint32_t)in->c;
        switch (in->op) {
        case IR_CONST: /* a=reg, b=imm40 */
            code[addr++] = wc_encode(OP_CONST, a, (uint32_t)(in->b >> 20),
                                     (uint32_t)(in->b & 0xFFFFF));
            continue;
        case IR_JMP: case IR_JZ: case IR_JNZ:
            if (in->a < 0 || (size_t)in->a >= nlabels) { ok = false;
                diag_add(dg, D_ERROR, "<emit>", 0, 0, "jump to undefined label %ld", in->a); break; }
            a = (uint32_t)laddr[in->a];
            break;
        case IR_CALL: case IR_SPAWN: { /* a=func label, b=argc */
            const FuncEnt *f = func_by_label(ft, in->a);
            if (!f) { ok = false;
                diag_add(dg, D_ERROR, "<emit>", 0, 0, "call to unresolved function '%s'", in->note); break; }
            a = (uint32_t)laddr[in->a];
            c = (uint32_t)f->frame_size;
            break; }
        case IR_ALT: /* c = timeout label -> rel offset */
            if (in->c < 0 || (size_t)in->c >= nlabels) { ok = false;
                diag_add(dg, D_ERROR, "<emit>", 0, 0, "ALT timeout label undefined"); break; }
            c = (uint32_t)(laddr[in->c] - (long)addr - 1);
            break;
        default: break;
        }
        if (!ok) break;
        code[addr++] = wc_encode((uint8_t)wop, a, b, c);
    }
    free(laddr);
    if (!ok) { free(code); return false; }

    int mi = functab_lookup(ft, "main");
    if (mi < 0) { free(code);
        diag_add(dg, D_ERROR, "<emit>", 0, 0, "no main function"); return false; }

    wc_image_free(img);
    img->code = code; img->code_size = code_words;
    img->data = comp->data ? malloc(comp->len * sizeof(Word)) : NULL;
    if (comp->len) memcpy(img->data, comp->data, comp->len * sizeof(Word));
    img->data_size = comp->len;
    img->entry = 0;
    /* entry address: find main's label */
    for (size_t i = 0; i < m->count; i++)
        if (m->items[i].op == IR_LABEL && m->items[i].a == ft->fns[mi].label)
            img->entry = 0; /* patched below */
    /* recompute via laddr would be cleaner; do a mini pass: */
    {
        size_t ad = 0;
        for (size_t i = 0; i < m->count; i++) {
            if (m->items[i].op == IR_LABEL) {
                if (m->items[i].a == ft->fns[mi].label) { img->entry = ad; break; }
            } else ad++;
        }
    }
    img->entry_frame_size = ft->fns[mi].frame_size;
    if (img->entry >= img->code_size) {
        diag_add(dg, D_ERROR, "<emit>", 0, 0, "main entry out of range");
        return false;
    }
    return true;
}
