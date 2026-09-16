#include "ir.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Block 17: COMMON IR — a growable instruction vector independent of
 * any frontend AST. Labels are dense integer ids resolved by the
 * emitter; CALL/SPAWN reference functions by label. */

void ir_module_init(IRModule *m) {
    m->items = NULL; m->count = 0; m->cap = 0;
    m->entry = -1; m->entry_frame_size = 0;
}

void ir_module_free(IRModule *m) {
    free(m->items);
    m->items = NULL; m->count = 0; m->cap = 0;
}

static bool ir_grow(IRModule *m) {
    if (m->count < m->cap) return true;
    size_t ncap = m->cap ? m->cap * 2 : 64;
    IRInstr *n = realloc(m->items, ncap * sizeof(IRInstr));
    if (!n) return false;
    m->items = n; m->cap = ncap;
    return true;
}

size_t ir_emit(IRModule *m, IROp op, long a, long b, long c, const char *note) {
    if (!ir_grow(m)) return (size_t)-1;
    IRInstr *in = &m->items[m->count];
    in->op = op; in->a = a; in->b = b; in->c = c;
    snprintf(in->note, sizeof(in->note), "%s", note ? note : "");
    return m->count++;
}

size_t ir_emit_label(IRModule *m, long label_id) {
    return ir_emit(m, IR_LABEL, label_id, 0, 0, "label");
}

size_t ir_count(const IRModule *m) { return m->count; }

static const char *ir_op_name(IROp op) {
    static const char *names[] = {
        "NOP","LABEL","CONST","LOAD","STORE","PUSH","POP","DROP","DUP",
        "ADD","SUB","MUL","DIV","MOD","AND","OR","XOR","NOT","SHL","SHR","BOOL",
        "EQ","NE","LT","LE","GT","GE",
        "JMP","JZ","JNZ","CALL","RET","SPAWN","SEND","RECV",
        "ALT","WAIT","YIELD","ALLOC","FREE","IN","OUT","OUTS","CHAN","HALT"
    };
    if (op < 0 || op > IR_HALT) return "?";
    return names[op];
}

void ir_dump(FILE *out, const IRModule *m) {
    for (size_t i = 0; i < m->count; i++) {
        const IRInstr *in = &m->items[i];
        fprintf(out, "%04zu %-6s %ld %ld %ld %s\n", i, ir_op_name(in->op),
                in->a, in->b, in->c, in->note);
    }
}
