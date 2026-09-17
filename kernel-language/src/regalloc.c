#include "regalloc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Dense interference-graph builder + greedy colouring.
   Live ranges are computed by a simple backward scan.
   No SSA, no LLVM, no external libraries. */

static void live_at(IrFunc *f, int *live, int n, IrInst *from) {
    memset(live, 0, n * sizeof(int));
    int seen_from = 0;
    for (IrInst *i = f->first; i; i = i->next) {
        if (i == from) seen_from = 1;
        if (!seen_from) continue;
        if (i->src0.kind == OP_REG && i->src0.reg < n) live[i->src0.reg] = 1;
        if (i->src1.kind == OP_REG && i->src1.reg < n) live[i->src1.reg] = 1;
        if (i->src2.kind == OP_REG && i->src2.reg < n) live[i->src2.reg] = 1;
        if (i->dst.kind == OP_REG && i->dst.reg < n) live[i->dst.reg] = 1;
    }
}

void build_interference(IrFunc *f, InterferenceGraph *g) {
    memset(g, 0, sizeof(*g));
    g->n_vregs = f->num_regs + 2;
    if (g->n_vregs > MAX_VREGS) g->n_vregs = MAX_VREGS;

    int live[MAX_VREGS];
    for (IrInst *i = f->first; i; i = i->next) {
        live_at(f, live, g->n_vregs, i);
        for (int a = 0; a < g->n_vregs; a++) {
            if (!live[a]) continue;
            for (int b = a + 1; b < g->n_vregs; b++) {
                if (!live[b]) continue;
                g->adj[a][b] = g->adj[b][a] = 1;
            }
        }
        if (i->dst.kind == OP_REG && i->dst.reg < g->n_vregs) {
            int d = i->dst.reg;
            for (int a = 0; a < g->n_vregs; a++)
                if (live[a] && a != d)
                    g->adj[d][a] = g->adj[a][d] = 1;
        }
    }

    for (int v = 0; v < g->n_vregs; v++) {
        int deg = 0;
        for (int u = 0; u < g->n_vregs; u++)
            if (g->adj[v][u]) deg++;
        g->degree[v] = deg;
        g->color[v] = -1;
        g->spill_cost[v] = 1 + deg;
        g->coalesced[v] = v;
    }
}

void color_graph(InterferenceGraph *g, int n_pregs) {
    int order[MAX_VREGS];
    for (int i = 0; i < g->n_vregs; i++) order[i] = i;

    /* insertion sort by degree descending */
    for (int i = 1; i < g->n_vregs; i++) {
        int key = order[i];
        int j = i - 1;
        while (j >= 0 && g->degree[order[j]] < g->degree[key]) {
            order[j+1] = order[j];
            j--;
        }
        order[j+1] = key;
    }

    for (int oi = 0; oi < g->n_vregs; oi++) {
        int v = order[oi];
        if (g->coalesced[v] != v) continue;

        char used[MAX_PREGS];
        memset(used, 0, sizeof(used));
        for (int u = 0; u < g->n_vregs; u++) {
            if (!g->adj[v][u]) continue;
            int c = g->color[g->coalesced[u]];
            if (c >= 0 && c < n_pregs) used[c] = 1;
        }
        int chosen = -1;
        for (int c = 0; c < n_pregs; c++)
            if (!used[c]) { chosen = c; break; }
        g->color[v] = chosen;
    }
}

void apply_colors(IrFunc *f, InterferenceGraph *g) {
    for (IrInst *i = f->first; i; i = i->next) {
        IrOperand *ops[4] = { &i->dst, &i->src0, &i->src1, &i->src2 };
        for (int k = 0; k < 4; k++) {
            if (ops[k]->kind != OP_REG) continue;
            int v = ops[k]->reg;
            if (v < 0 || v >= g->n_vregs) continue;
            int col = g->color[g->coalesced[v]];
            if (col >= 0)
                ops[k]->reg = col;
            else if (!i->comment) {
                char buf[48];
                snprintf(buf, sizeof(buf), "SPILL v%d", v);
                i->comment = strdup(buf);
            }
        }
    }
    f->num_regs = MAX_PREGS;
}

void graph_color_allocate(IrFunc *f) {
    if (!f || !f->first) return;
    InterferenceGraph g;
    build_interference(f, &g);
    color_graph(&g, MAX_PREGS);
    apply_colors(f, &g);
}
