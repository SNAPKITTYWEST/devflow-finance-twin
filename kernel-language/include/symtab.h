#ifndef KERNEL_SYMTAB_H
#define KERNEL_SYMTAB_H

#include "ast.h"
#include "ir.h"

/* Dense, scoped symbol table for the BLISS/PLM/CORAL kernel language.
   Explicit storage classes, word/bit types, BASED/AT absolute addresses.
   Used by semantic analysis and the register allocator. */

#define MAX_SCOPES 32
#define MAX_SYMBOLS 512

typedef struct Symbol {
    char *name;
    Type *type;
    StorageClass storage;
    int reg; /* assigned virtual/physical register, -1 if none */
    int pred; /* if predicate */
    long absolute; /* for AT / ABSOLUTE */
    AstNode *based_on; /* PL/M BASED expression */
    int bit_offset;
    int bit_width;
    int slot; /* stack / frame slot if spilled */
    int is_param;
    int is_defined;
    struct Symbol *next; /* hash collision chain */
} Symbol;

typedef struct Scope {
    Symbol *symbols[64]; /* simple open hash */
    struct Scope *parent;
    int depth;
} Scope;

typedef struct SymTab {
    Scope *scopes[MAX_SCOPES];
    int scope_top;
    Scope *current;
    int next_reg; /* high-water for virtual regs before allocation */
    int next_pred;
    int next_slot;
} SymTab;

void symtab_init(SymTab *st);
void symtab_push(SymTab *st);
void symtab_pop(SymTab *st);
Symbol *symtab_lookup(SymTab *st, const char *name);
Symbol *symtab_lookup_current(SymTab *st, const char *name);
Symbol *symtab_insert(SymTab *st, const char *name, Type *type, StorageClass sc);
void symtab_dump(SymTab *st, FILE *out);

/* Linear-scan style register allocator operating on the IR after codegen.
   Simple, dense, systems-style. */
void allocate_registers(IrFunc *f, SymTab *st);

#endif
