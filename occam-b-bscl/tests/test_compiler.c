/* tests/test_compiler.c */
#include "compiler.h"
#include "vm.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

static int compile_ok(const char *src) {
    Compiler c; compiler_init(&c);
    WcImage img; wc_image_init(&img);
    bool ok = compile_source(&c, src, "test.b", &img);
    int errs = c.diags.error_count;
    wc_image_free(&img); compiler_free(&c);
    return ok && errs == 0;
}

static char *run_src(const char *src, int *rc) {
    Compiler c; compiler_init(&c);
    WcImage img; wc_image_init(&img);
    static char buf[8192];
    if (!compile_source(&c, src, "test.b", &img)) {
        *rc = -1; strcpy(buf, "<compile error>");
        wc_image_free(&img); compiler_free(&c);
        return buf;
    }
    VM *vm = vm_create(65536);
    FILE *f = tmpfile();
    vm_set_output(vm, f);
    vm_load_image(vm, &img);
    *rc = vm_run(vm);
    vm_destroy(vm);
    rewind(f);
    size_t r = fread(buf, 1, sizeof(buf) - 1, f);
    buf[r] = 0; fclose(f);
    wc_image_free(&img); compiler_free(&c);
    return buf;
}

int main(void) {
    int rc;
    /* arithmetic */
    char *o = run_src("main() { x = 10; y = 20; z = x + y; out(z); }", &rc);
    CHECK(rc == 0 && strcmp(o, "30\n") == 0);

    /* recursion: factorial(5) = 120 */
    o = run_src("fact(n) { if (n < 2) { return 1; } return n * fact(n - 1); }"
                "main() { out(fact(5)); }", &rc);
    CHECK(rc == 0 && strcmp(o, "120\n") == 0);

    /* iteration: fib(10) = 55 */
    o = run_src("fib(n) { a = 0; b = 1; i = 0; while (i < n) { t = a + b; "
                "a = b; b = t; i = i + 1; } return a; }"
                "main() { out(fib(10)); }", &rc);
    CHECK(rc == 0 && strcmp(o, "55\n") == 0);

    /* channels + spawn + wait, deterministic output */
    o = run_src(
        "producer(c) { i = 0; while (i < 5) { send(c, i * 10); i = i + 1; } }\n"
        "main() { c = chan(); p = spawn producer(c); i = 0; "
        "while (i < 5) { out(recv(c)); i = i + 1; } wait(p); }", &rc);
    CHECK(rc == 0 && strcmp(o, "0\n10\n20\n30\n40\n") == 0);

    /* alt2 deterministic left-first selection */
    o = run_src("main() { a = chan(); b = chan(); send(a, 11); send(b, 22);"
                " r = alt2(a, b); out(r >> 32); out(r & 4294967295); }", &rc);
    CHECK(rc == 0 && strcmp(o, "0\n11\n") == 0);

    /* BSCL structured control */
    o = run_src("main() { i = 0; loop { i = i + 1; } until (i >= 4); out(i);"
                " when (i == 4) { out(99); } }", &rc);
    CHECK(rc == 0 && strcmp(o, "4\n99\n") == 0);

    /* strings */
    o = run_src("main() { print(\"hello, wordcode\"); out(42); }", &rc);
    CHECK(rc == 0 && strcmp(o, "hello, wordcode\n42\n") == 0);

    /* ---- negative tests: compiler must fail closed ---- */
    CHECK(!compile_ok("main() { x = y + 1; }")); /* undefined var */
    CHECK(!compile_ok("main() { x = 1; send(x, 2); }")); /* send on word */
    CHECK(!compile_ok("main() { x = 1; y = recv(x); }")); /* recv on word */
    CHECK(!compile_ok("f(a) { return a; } main() { out(f(1, 2)); }")); /* argc */
    CHECK(!compile_ok("main() { out(nosuch()); }")); /* unknown fn */
    CHECK(!compile_ok("main() { x = ; }")); /* syntax */
    CHECK(!compile_ok("f() { return 1; } g() { return 2; }"))/* no main */;

    /* runtime fault: division by zero */
    o = run_src("main() { x = 1; y = 0; out(x / y); }", &rc);
    CHECK(rc == 4);

    /* explicit wait join ordering */
    o = run_src("child() { return 7; } main() { p = spawn child();"
                " wait(p); print(\"joined\"); }", &rc);
    CHECK(rc == 0 && strcmp(o, "joined\n") == 0);

    printf("test_compiler: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
