#ifndef KERNEL_REGALLOC_H
#define KERNEL_REGALLOC_H

#include "ir.h"
#include "symtab.h"

/* Custom graph-coloring register allocator.
   No LLVM. Dense, systems-style interference graph + greedy coloring
   with coalescing hints. Targets the physical register file of SM_86. */

#define MAX_VREGS 256
#define MAX_PREGS 64 /* Ampere practical upper bound we colour into */

typedef struct {
    int n_vregs;
    int adj[MAX_VREGS][MAX_VREGS]; /* interference matrix (symmetric) */
    int degree[MAX_VREGS];
    int color[MAX_VREGS]; /* physical register or -1 spilled */
    int spill_cost[MAX_VREGS];
    int coalesced[MAX_VREGS]; /* simple coalescing */
} InterferenceGraph;

void build_interference(IrFunc *f, InterferenceGraph *g);
void color_graph(InterferenceGraph *g, int n_pregs);
void apply_colors(IrFunc *f, InterferenceGraph *g);
void graph_color_allocate(IrFunc *f); /* full pipeline */

#endif
