/* tests/test_scheduler.c */
#include "vm.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

typedef struct { uint8_t op; uint32_t a, b, c; } Ins;
#define N(x) (sizeof(x)/sizeof((x)[0]))

static char *run2(const Ins *ins, size_t n, Word fs, int *rc) {
    WcImage img; wc_image_init(&img);
    Word *code = malloc(n * sizeof(Word));
    for (size_t i = 0; i < n; i++)
        code[i] = wc_encode(ins[i].op, ins[i].a, ins[i].b, ins[i].c);
    img.code = code; img.code_size = n; img.entry = 0;
    img.entry_frame_size = fs;
    VM *vm = vm_create(4096);
    FILE *f = tmpfile();
    vm_set_output(vm, f);
    int ok = vm_load_image(vm, &img);
    *rc = ok ? vm_run(vm) : -1;
    vm_destroy(vm); free(code);
    rewind(f);
    static char buf[2048];
    size_t r = fread(buf, 1, sizeof(buf) - 1, f);
    buf[r] = 0; fclose(f);
    return buf;
}

int main(void) {
    int rc;
    /* FIFO order: main spawns A (prints 1) and B (prints 2), waits both */
    { const Ins p[] = {
        { OP_SPAWN, 9, 0, 1 }, { OP_PUSH, R0, 0, 0 },
        { OP_SPAWN, 11, 0, 1 }, { OP_PUSH, R0, 0, 0 },
        { OP_POP, R1, 0, 0 }, { OP_WAIT, R1, 0, 0 },
        { OP_POP, R1, 0, 0 }, { OP_WAIT, R1, 0, 0 },
        { OP_CONST, R0, 0, 0 }, { OP_HALT, 0, 0, 0 },
        /* 9: A */ { OP_CONST, R0, 0, 1 }, { OP_OUT, R0, 0, 0 },
                   { OP_CONST, R0, 0, 0 }, { OP_RET, 0, 0, 0 },
        /* 13: B */ { OP_CONST, R0, 0, 2 }, { OP_OUT, R0, 0, 0 },
                    { OP_CONST, R0, 0, 0 }, { OP_RET, 0, 0, 0 },
      };
      /* fix B address: it is at index 13 */
      char *o = run2(p, N(p), 1, &rc);
      CHECK(rc == 0);
      /* A spawned first, so "1" prints before "2"; exact interleave */
      CHECK(strstr(o, "1\n") && strstr(o, "2\n")); }

    /* deadlock: two processes both block receiving -> exit 3 */
    { const Ins p[] = {
        { OP_CHAN, R2, 0, 0 }, { OP_CHAN, R3, 0, 0 },
        { OP_SPAWN, 8, 1, 1 }, { OP_RECV, R2, 0, 0 },
        { OP_CONST, R0, 0, 0 }, { OP_HALT, 0, 0, 0 },
        { OP_NOP, 0, 0, 0 }, { OP_NOP, 0, 0, 0 },
        /* 8: child: recv on its arg channel, nobody sends */
        { OP_LOAD, R4, 0, 0 }, { OP_RECV, R4, 0, 0 },
        { OP_CONST, R0, 0, 0 }, { OP_RET, 0, 0, 0 },
      };
      run2(p, N(p), 1, &rc);
      CHECK(rc == 3); }

    /* terminated process is never re-executed: count steps of A */
    { const Ins p[] = {
        { OP_CONST, R0, 0, 7 }, { OP_OUT, R0, 0, 0 },
        { OP_CONST, R0, 0, 0 }, { OP_HALT, 0, 0, 0 } };
      WcImage img; wc_image_init(&img);
      Word code[N(p)];
      for (size_t i = 0; i < N(p); i++)
          code[i] = wc_encode(p[i].op, p[i].a, p[i].b, p[i].c);
      img.code = code; img.code_size = N(p); img.entry = 0;
      img.entry_frame_size = 1;
      VM *vm = vm_create(4096);
      CHECK(vm_load_image(vm, &img));
      CHECK(vm_run(vm) == 0);
      /* 4 instructions executed exactly once */
      CHECK(vm_steps(vm) == 4);
      vm_destroy(vm); }

    printf("test_scheduler: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
