/* tests/test_parser.c */
#include "parser.h"
#include "diagnostics.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

static Node *parse(const char *src, DiagList *dg) {
    TokenStream ts;
    lexer_tokenize(src, "t.b", &ts, dg);
    Node *out = NULL;
    parse_program(&ts, dg, &out);
    token_stream_free(&ts);
    return out;
}

int main(void) {
    DiagList dg; diag_list_init(&dg);
    Node *p = parse("f(a, b) { return a * b; } "
                    "main() { x = 1 + 2 * 3; if (x > 5) { out(x); } "
                    "while (x) { x = x - 1; } }", &dg);
    CHECK(p && p->kind == N_PROGRAM);
    CHECK(p && p->a && p->a->kind == N_FUNC);
    CHECK(p && p->a->next && strcmp(p->a->next->name, "main") == 0);
    /* precedence: 1 + 2*3 parses as 1 + (2*3) */
    Node *assign = p->a->next->b->a; /* first stmt of main */
    CHECK(assign && assign->kind == N_ASSIGN);
    Node *add = assign->a;
    CHECK(add && add->kind == N_BIN && add->ival == TK_PLUS);
    CHECK(add->b && add->b->kind == N_BIN && add->b->ival == TK_STAR);
    ast_free(p);
    /* syntax error must fail */
    DiagList dg2; diag_list_init(&dg2);
    Node *bad = parse("main() { x = ; }", &dg2);
    CHECK(bad == NULL);
    CHECK(dg2.error_count > 0);
    diag_list_free(&dg); diag_list_free(&dg2);
    printf("test_parser: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
