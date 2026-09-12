/* tests/test_vm.c */
#include "vm.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

typedef struct { uint8_t op; uint32_t a, b, c; } Ins;
#define N(x) (sizeof(x)/sizeof((x)[0]))

static int run_prog(const Ins *ins, size_t n, Word framesize, FILE *out) {
    WcImage img; wc_image_init(&img);
    Word *code = malloc(n * sizeof(Word));
    for (size_t i = 0; i < n; i++)
        code[i] = wc_encode(ins[i].op, ins[i].a, ins[i].b, ins[i].c);
    img.code = code; img.code_size = n;
    img.entry = 0; img.entry_frame_size = framesize;
    VM *vm = vm_create(4096);
    vm_set_output(vm, out ? out : stdout);
    int ok = vm_load_image(vm, &img);
    int rc = ok ? vm_run(vm) : -1;
    vm_destroy(vm);
    free(code);
    return rc;
}

static char *run_capture(const Ins *ins, size_t n, Word fs, int *rc) {
    FILE *f = tmpfile();
    *rc = run_prog(ins, n, fs, f);
    rewind(f);
    static char buf[4096];
    size_t r = fread(buf, 1, sizeof(buf) - 1, f);
    buf[r] = 0;
    fclose(f);
    return buf;
}

int main(void) {
    int rc;
    /* arithmetic + OUT */
    { const Ins p[] = {
        { OP_CONST, R0, 0, 10 }, { OP_CONST, R1, 0, 20 },
        { OP_ADD, R0, R1, 0 }, { OP_OUT, R0, 0, 0 },
        { OP_CONST, R0, 0, 0 }, { OP_HALT, 0, 0, 0 } };
      char *o = run_capture(p, N(p), 1, &rc);
      CHECK(rc == 0 && strcmp(o, "30\n") == 0); }

    /* division by zero faults (exit 4) */
    { const Ins p[] = {
        { OP_CONST, R0, 0, 1 }, { OP_CONST, R1, 0, 0 },
        { OP_DIV, R0, R1, 0 }, { OP_CONST, R0, 0, 0 },
        { OP_HALT, 0, 0, 0 } };
      run_capture(p, N(p), 1, &rc);
      CHECK(rc == 4); }

    /* stack underflow */
    { const Ins p[] = { { OP_POP, R0, 0, 0 }, { OP_HALT, 0, 0, 0 } };
      run_capture(p, N(p), 1, &rc);
      CHECK(rc == 4); }

    /* stack overflow (SP beyond 1024-word stack) */
    { const Ins p[] = {
        { OP_CONST, R0, 0, 1 }, { OP_PUSH, R0, 0, 0 },
        { OP_JMP, 1, 0, 0 } };
      run_capture(p, N(p), 1, &rc);
      CHECK(rc == 4); }

    /* memory: alloc/free ok; double free faults; OOB word access */
    { Memory *m = mem_create(256);
      WordAddress a = mem_allocate(m, 8);
      CHECK(a != 0);
      CHECK(mem_write_word(m, a + 7, 42));
      Word v; CHECK(mem_read_word(m, a + 7, &v) && v == 42);
      CHECK(!mem_read_word(m, 9999, &v)); /* bounds */
      CHECK(mem_release(m, a));
      CHECK(!mem_release(m, a)); /* double free */
      mem_destroy(m); }

    /* invalid register access inside VM faults */
    { const Ins p[] = {
        { OP_CONST, 200, 0, 1 }, { OP_CONST, R0, 0, 0 },
        { OP_HALT, 0, 0, 0 } };
      run_capture(p, N(p), 1, &rc);
      CHECK(rc == 4); }

    /* PC out of range */
    { const Ins p[] = { { OP_JMP, 9999, 0, 0 } };
      run_capture(p, N(p), 1, &rc);
      CHECK(rc == 4); }

    /* OUTS bounds */
    { const Ins p[] = {
        { OP_OUTS, 0, 1000, 0 }, { OP_CONST, R0, 0, 0 },
        { OP_HALT, 0, 0, 0 } };
      run_capture(p, N(p), 1, &rc);
      CHECK(rc == 4); }

    printf("test_vm: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
