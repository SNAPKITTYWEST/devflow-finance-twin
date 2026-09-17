#include "symtab.h"
#include "ir.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned hash_name(const char *s) {
    unsigned h = 5381;
    while (*s) h = ((h << 5) + h) + (unsigned char)*s++;
    return h;
}

void symtab_init(SymTab *st) {
    memset(st, 0, sizeof(*st));
    st->next_reg = 1;
    st->next_pred = 0;
    st->next_slot = 0;
    symtab_push(st);
}

void symtab_push(SymTab *st) {
    if (st->scope_top >= MAX_SCOPES) {
        fprintf(stderr, "symtab: scope overflow\n");
        return;
    }
    Scope *sc = calloc(1, sizeof(Scope));
    sc->parent = st->current;
    sc->depth = st->current ? st->current->depth + 1 : 0;
    st->scopes[st->scope_top++] = sc;
    st->current = sc;
}

void symtab_pop(SymTab *st) {
    if (st->scope_top <= 1) return;
    Scope *sc = st->current;
    st->current = sc->parent;
    st->scope_top--;
    for (int i = 0; i < 64; i++) {
        Symbol *s = sc->symbols[i];
        while (s) {
            Symbol *n = s->next;
            free(s->name);
            free(s);
            s = n;
        }
    }
    free(sc);
}

Symbol *symtab_lookup(SymTab *st, const char *name) {
    for (Scope *sc = st->current; sc; sc = sc->parent) {
        unsigned h = hash_name(name) & 63;
        for (Symbol *s = sc->symbols[h]; s; s = s->next)
            if (strcmp(s->name, name) == 0)
                return s;
    }
    return NULL;
}

Symbol *symtab_lookup_current(SymTab *st, const char *name) {
    if (!st->current) return NULL;
    unsigned h = hash_name(name) & 63;
    for (Symbol *s = st->current->symbols[h]; s; s = s->next)
        if (strcmp(s->name, name) == 0)
            return s;
    return NULL;
}

Symbol *symtab_insert(SymTab *st, const char *name, Type *type, StorageClass sc) {
    if (symtab_lookup_current(st, name)) {
        fprintf(stderr, "symtab: redeclaration of '%s'\n", name);
        return NULL;
    }
    Symbol *sym = calloc(1, sizeof(Symbol));
    sym->name = strdup(name);
    sym->type = type;
    sym->storage = sc;
    sym->reg = -1;
    sym->pred = -1;
    sym->slot = -1;

    if (sc == STOR_REGISTER || sc == STOR_LOCAL || sc == STOR_OWN ||
        sc == STOR_PARAM) {
        if (type && type->kind == TYPE_BIT && type->bits <= 1) {
            sym->pred = st->next_pred++;
        } else {
            sym->reg = st->next_reg++;
        }
    } else if (sc == STOR_ABSOLUTE) {
        /* no register; address is absolute */
    } else if (sc == STOR_SHARED || sc == STOR_GLOBAL || sc == STOR_CONST) {
        sym->slot = st->next_slot++;
    }

    unsigned h = hash_name(name) & 63;
    sym->next = st->current->symbols[h];
    st->current->symbols[h] = sym;
    return sym;
}

void symtab_dump(SymTab *st, FILE *out) {
    fprintf(out, "=== Symbol Table ===\n");
    for (int i = 0; i < st->scope_top; i++) {
        Scope *sc = st->scopes[i];
        fprintf(out, "Scope depth %d:\n", sc->depth);
        for (int b = 0; b < 64; b++) {
            for (Symbol *s = sc->symbols[b]; s; s = s->next) {
                fprintf(out, "  %s stor=%d reg=%d pred=%d abs=%ld slot=%d\n",
                        s->name, s->storage, s->reg, s->pred,
                        s->absolute, s->slot);
            }
        }
    }
}

/* ---------- Linear-scan register allocator ---------- */

#define PHYS_REGS 32

typedef struct {
    int vreg;
    int start;
    int end;
    int preg;
    int slot;
} LiveInterval;

void allocate_registers(IrFunc *f, SymTab *st) {
    (void)st;
    if (!f || !f->first) return;

    int max_v = f->num_regs + 4;
    LiveInterval *iv = calloc(max_v, sizeof(LiveInterval));
    int n_iv = 0;

    int idx = 0;
    for (IrInst *i = f->first; i; i = i->next, idx++) {
        int regs[4] = {-1,-1,-1,-1};
        int nr = 0;
        if (i->dst.kind == OP_REG) regs[nr++] = i->dst.reg;
        if (i->src0.kind == OP_REG) regs[nr++] = i->src0.reg;
        if (i->src1.kind == OP_REG) regs[nr++] = i->src1.reg;
        if (i->src2.kind == OP_REG) regs[nr++] = i->src2.reg;

        for (int k = 0; k < nr; k++) {
            int r = regs[k];
            if (r < 0 || r >= max_v) continue;
            int found = -1;
            for (int j = 0; j < n_iv; j++)
                if (iv[j].vreg == r) { found = j; break; }
            if (found < 0) {
                iv[n_iv].vreg = r;
                iv[n_iv].start = idx;
                iv[n_iv].end = idx;
                iv[n_iv].preg = -1;
                iv[n_iv].slot = -1;
                n_iv++;
            } else {
                if (idx < iv[found].start) iv[found].start = idx;
                if (idx > iv[found].end) iv[found].end = idx;
            }
        }
    }

    /* Sort by start */
    for (int i = 1; i < n_iv; i++) {
        LiveInterval key = iv[i];
        int j = i - 1;
        while (j >= 0 && iv[j].start > key.start) {
            iv[j+1] = iv[j];
            j--;
        }
        iv[j+1] = key;
    }

    /* Linear scan */
    int active[PHYS_REGS];
    int n_active = 0;
    int free_pool[PHYS_REGS];
    int n_free = PHYS_REGS;
    for (int i = 0; i < PHYS_REGS; i++) free_pool[i] = i;
    int next_spill_slot = 0;

    for (int i = 0; i < n_iv; i++) {
        LiveInterval *cur = &iv[i];

        for (int a = 0; a < n_active; ) {
            int v = active[a];
            LiveInterval *liv = NULL;
            for (int k = 0; k < n_iv; k++)
                if (iv[k].vreg == v) { liv = &iv[k]; break; }
            if (liv && liv->end < cur->start) {
                if (liv->preg >= 0)
                    free_pool[n_free++] = liv->preg;
                active[a] = active[--n_active];
            } else {
                a++;
            }
        }

        if (n_free > 0) {
            cur->preg = free_pool[--n_free];
            active[n_active++] = cur->vreg;
        } else {
            int spill_idx = 0;
            int furthest = -1;
            for (int a = 0; a < n_active; a++) {
                for (int k = 0; k < n_iv; k++) {
                    if (iv[k].vreg == active[a] && iv[k].end > furthest) {
                        furthest = iv[k].end;
                        spill_idx = a;
                    }
                }
            }
            for (int k = 0; k < n_iv; k++) {
                if (iv[k].vreg == active[spill_idx]) {
                    iv[k].slot = next_spill_slot++;
                    iv[k].preg = -1;
                    break;
                }
            }
            cur->slot = next_spill_slot++;
            cur->preg = -1;
        }
    }

    /* Rewrite IR */
    for (IrInst *i = f->first; i; i = i->next) {
        IrOperand *ops[4] = {&i->dst, &i->src0, &i->src1, &i->src2};
        for (int k = 0; k < 4; k++) {
            if (ops[k]->kind != OP_REG) continue;
            int v = ops[k]->reg;
            for (int j = 0; j < n_iv; j++) {
                if (iv[j].vreg == v) {
                    if (iv[j].preg >= 0)
                        ops[k]->reg = iv[j].preg;
                    else {
                        if (!i->comment) {
                            char buf[64];
                            snprintf(buf, sizeof(buf), "spill slot %d", iv[j].slot);
                            i->comment = strdup(buf);
                        }
                    }
                    break;
                }
            }
        }
    }

    free(iv);
    f->num_regs = PHYS_REGS;
}
