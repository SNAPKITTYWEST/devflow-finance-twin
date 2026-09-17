#include "lexer.h"
#include "parser.h"
#include "codegen.h"
#include "ir.h"
#include "regalloc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        perror(path);
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(n + 1);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, n, f) != (size_t)n) {
        fclose(f);
        free(buf);
        return NULL;
    }
    buf[n] = 0;
    fclose(f);
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <source.kl> [-emit-ir] [-dump-ast] [-regalloc]\n", argv[0]);
        return 1;
    }
    int emit_ir = 0, dump_ast = 0, do_regalloc = 0;
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-emit-ir") == 0) emit_ir = 1;
        if (strcmp(argv[i], "-dump-ast") == 0) dump_ast = 1;
        if (strcmp(argv[i], "-regalloc") == 0) do_regalloc = 1;
    }

    char *src = read_file(argv[1]);
    if (!src) return 1;

    Lexer lex;
    lexer_init(&lex, src);

    Parser parser;
    parser_init(&parser, &lex);

    AstNode *mod = parse_module(&parser);
    if (parser.had_error) {
        fprintf(stderr, "compilation failed\n");
        free(src);
        return 1;
    }

    if (dump_ast) {
        printf("=== AST ===\n");
        ast_print(mod, 0);
    }

    IrModule *ir = codegen(mod);

    if (do_regalloc) {
        for (IrFunc *f = ir->funcs; f; f = f->next)
            graph_color_allocate(f);
    }

    if (emit_ir || !dump_ast) {
        printf("=== KERNEL IR (SM_86 oriented) ===\n");
        ir_print(ir, stdout);
    }

    ir_free(ir);
    free(src);
    return 0;
}
