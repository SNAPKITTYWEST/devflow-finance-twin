#ifndef KERNEL_AST_H
#define KERNEL_AST_H

#include "token.h"

/* Dense AST for expression-oriented + structured language */

typedef enum {
    AST_MODULE,
    AST_ROUTINE,
    AST_BLOCK,
    AST_DECL,
    AST_ASSIGN,
    AST_IF,
    AST_WHILE,
    AST_FOR,
    AST_RETURN,
    AST_EXIT,
    AST_EXPR_STMT,
    AST_PARALLEL,
    AST_SYNC,
    AST_BARRIER,
    AST_LABEL,
    AST_GOTO,

    /* Expressions */
    AST_IDENT,
    AST_NUMBER,
    AST_BINARY,
    AST_UNARY,
    AST_CALL,
    AST_INDEX,
    AST_FIELD,
    AST_BASED,
    AST_AT,
    AST_CAST,
    AST_COND, /* BLISS-style conditional expression */
    AST_BITFIELD, /* PL/M-style bit extraction */
    AST_MACRO_INV
} AstKind;

typedef enum {
    TYPE_VOID = 0,
    TYPE_WORD, /* default 32-bit machine word */
    TYPE_LONG, /* 64-bit */
    TYPE_BIT, /* 1-bit / predicate */
    TYPE_BYTE,
    TYPE_FLOAT,
    TYPE_PTR,
    TYPE_TABLE
} TypeKind;

typedef enum {
    STOR_LOCAL = 0,
    STOR_OWN, /* BLISS OWN */
    STOR_GLOBAL,
    STOR_REGISTER,
    STOR_SHARED,
    STOR_PARAM,
    STOR_CONST,
    STOR_ABSOLUTE,
    STOR_BASED
} StorageClass;

typedef struct Type {
    TypeKind kind;
    int bits; /* for BIT n or explicit width */
    struct Type *base; /* pointer / based */
    int is_unsigned;
} Type;

typedef struct AstNode AstNode;

struct AstNode {
    AstKind kind;
    int line;
    Type *type;

    union {
        struct {
            char *name;
            AstNode *decls;
            AstNode *routines;
        } module;

        struct {
            char *name;
            AstNode *params;
            AstNode *locals;
            AstNode *body;
            int is_kernel; /* entry point for GPU */
            int priority;
            int deadline;
        } routine;

        struct {
            AstNode *stmts;
        } block;

        struct {
            char *name;
            Type *type;
            StorageClass storage;
            AstNode *init;
            AstNode *based_on; /* PL/M BASED */
            long absolute; /* PL/M AT / ABSOLUTE */
            int bit_offset;
            int bit_width;
        } decl;

        struct {
            AstNode *lhs;
            AstNode *rhs;
        } assign;

        struct {
            AstNode *cond;
            AstNode *then_b;
            AstNode *else_b;
        } ifstmt;

        struct {
            AstNode *cond;
            AstNode *body;
        } whilestmt;

        struct {
            AstNode *init;
            AstNode *cond;
            AstNode *step;
            AstNode *body;
        } forstmt;

        struct {
            AstNode *expr;
        } ret;

        struct {
            AstNode *expr;
        } exprstmt;

        struct {
            int width; /* number of threads / warps */
            AstNode *body;
        } parallel;

        struct {
            int id;
            AstNode *threads;
        } barrier;

        /* Expressions */
        struct {
            char *name;
        } ident;

        struct {
            long ival;
            double fval;
            int is_float;
        } number;

        struct {
            TokenKind op;
            AstNode *left;
            AstNode *right;
        } binary;

        struct {
            TokenKind op;
            AstNode *operand;
        } unary;

        struct {
            AstNode *fn;
            AstNode *args;
        } call;

        struct {
            AstNode *base;
            AstNode *index;
        } index;

        struct {
            AstNode *expr;
            int offset;
            int width;
        } bitfield;

        struct {
            AstNode *cond;
            AstNode *then_e;
            AstNode *else_e;
        } cond;

        struct {
            AstNode *expr;
            Type *to;
        } cast;
    } u;

    AstNode *next; /* sibling list */
};

AstNode *ast_new(AstKind kind, int line);
void ast_free(AstNode *n);
void ast_print(AstNode *n, int indent);

#endif
