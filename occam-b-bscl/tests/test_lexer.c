/* tests/test_lexer.c */
#include "lexer.h"
#include "diagnostics.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

int main(void) {
    DiagList dg; diag_list_init(&dg);
    TokenStream ts;
    const char *src =
        "main() { x = 0x10 + 42; s = \"hi\"; // comment\n y = 'a'; }\n";
    CHECK(lexer_tokenize(src, "t.b", &ts, &dg));
    CHECK(ts.count > 10);
    /* token 4 should be hex 16 */
    CHECK(ts.toks[4].kind == TK_INT && ts.toks[4].ival == 16);
    CHECK(dg.error_count == 0);
    /* bad character is a deterministic diagnostic */
    DiagList dg2; diag_list_init(&dg2);
    TokenStream ts2;
    CHECK(!lexer_tokenize("x = 1 @ 2;", "bad.b", &ts2, &dg2));
    CHECK(dg2.error_count == 1);
    CHECK(strstr(dg2.items[0].msg, "unexpected character") != NULL);
    CHECK(dg2.items[0].line == 1);
    /* unterminated string */
    DiagList dg3; diag_list_init(&dg3);
    TokenStream ts3;
    CHECK(!lexer_tokenize("\"oops", "u.b", &ts3, &dg3));
    token_stream_free(&ts); token_stream_free(&ts2); token_stream_free(&ts3);
    diag_list_free(&dg); diag_list_free(&dg2); diag_list_free(&dg3);
    printf("test_lexer: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
