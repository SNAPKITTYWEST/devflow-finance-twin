#ifndef KERNEL_IR_H
#define KERNEL_IR_H

/* KERNEL IR – the instruction set designed earlier.
   Register-based, word-oriented, explicit address spaces,
   warp collectives, barriers. Hand-lowered from the language. */

typedef enum {
    IR_NOP = 0,
    IR_MOV,
    IR_ADD, IR_SUB, IR_MUL, IR_DIV, IR_MAD,
    IR_AND, IR_OR, IR_XOR, IR_NOT,
    IR_SHL, IR_SHR, IR_ROL, IR_ROR,
    IR_MIN, IR_MAX, IR_ABS, IR_NEG,
    IR_SETP, /* compare -> predicate */
    IR_SELP, /* select by predicate */
    IR_LD, IR_ST,
    IR_ATOM,
    IR_BRA, IR_BRA_P, IR_CALL, IR_RET, IR_EXIT,
    IR_BAR_SYNC,
    IR_SHFL, IR_VOTE, IR_REDUX,
    IR_CVT,
    IR_LABEL,
    IR_COMMENT
} IrOpcode;

typedef enum {
    AS_REG = 0,
    AS_SHARED,
    AS_GLOBAL,
    AS_CONST,
    AS_LOCAL,
    AS_PARAM,
    AS_ABS
} AddrSpace;

typedef struct IrOperand {
    enum { OP_NONE, OP_REG, OP_IMM, OP_PRED, OP_LABEL, OP_MEM } kind;
    int reg; /* virtual register number */
    long imm;
    int pred;
    char *label;
    AddrSpace as;
    int mem_base; /* register holding address */
    int mem_off;
} IrOperand;

typedef struct IrInst {
    IrOpcode op;
    IrOperand dst;
    IrOperand src0;
    IrOperand src1;
    IrOperand src2;
    int pred; /* optional guarding predicate */
    char *comment;
    struct IrInst *next;
} IrInst;

typedef struct IrFunc {
    char *name;
    int is_kernel;
    int num_regs;
    int num_preds;
    IrInst *first;
    IrInst *last;
    struct IrFunc *next;
} IrFunc;

typedef struct IrModule {
    IrFunc *funcs;
} IrModule;

IrModule *ir_new_module(void);
IrFunc *ir_new_func(IrModule *m, const char *name, int is_kernel);
IrInst *ir_emit(IrFunc *f, IrOpcode op);
void ir_print(IrModule *m, FILE *out);
void ir_free(IrModule *m);

/* helpers */
IrOperand ir_reg(int r);
IrOperand ir_imm(long v);
IrOperand ir_pred(int p);
IrOperand ir_mem(AddrSpace as, int base, int off);

#endif
