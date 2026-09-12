#include "compiler.h"
#include "vm.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Block 24: CLI.
 * occamb build <src> [-o out.wc] compile to a wordcode image
 * occamb run <img.wc> [--trace] execute an image
 * occamb dump <img.wc> hex dump
 * occamb disassemble <img.wc> human-readable assembly
 * occamb check <src> compile only (diagnostics)
 * occamb selftest built-in VM verification suite
 * --help --version
 * Exit codes: 0 ok, 1 usage/compile, 3 deadlock, 4 runtime fault. */

static const char *VERSION = "occamb 1.0.0 (wordcode v1)";

static char *read_text_file(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { /* short read ok */ }
    buf[sz] = 0;
    fclose(f);
    if (n) *n = (size_t)sz;
    return buf;
}

static void usage(FILE *out) {
    fprintf(out,
        "%s\n"
        "usage: occamb <command> [options]\n"
        " build <src> [-o out.wc] compile .b/.occ/.bscl to wordcode\n"
        " run <img.wc> [--trace] execute a wordcode image\n"
        " dump <img.wc> hex dump of the image\n"
        " disassemble <img.wc> wordcode disassembly\n"
        " check <src> compile only; print diagnostics\n"
        " selftest run built-in VM self-test\n"
        " --help this text\n"
        " --version version string\n", VERSION);
}

/* ---- Block 30: VM SELF-TEST ----------------------------------------
 * Hand-assembled program exercising: registers, arithmetic, branches,
 * stack, calls, memory alloc/free, channel communication, spawn,
 * WAIT join and HALT. R0 at HALT = 0 iff every check passed. */
static const struct { uint8_t op; uint32_t a, b, c; } SELFTEST[] = {
    /* arithmetic: 6*7 == 42 */
    { OP_CONST, R0, 0, 6 }, { OP_CONST, R1, 0, 7 }, { OP_MUL, R0, R1, 0 },
    { OP_CONST, R2, 0, 42 }, { OP_EQ, R0, R2, 0 }, { OP_JZ, 8, 0, 0 },
    { OP_CONST, R0, 0, 1 }, { OP_HALT, 0, 0, 0 },
    /* stack: push 5, pop into R3 */
    { OP_CONST, R0, 0, 5 }, { OP_PUSH, R0, 0, 0 }, { OP_POP, R3, 0, 0 },
    { OP_CONST, R4, 0, 5 }, { OP_EQ, R3, R4, 0 }, { OP_JZ, 16, 0, 0 },
    { OP_CONST, R0, 0, 2 }, { OP_HALT, 0, 0, 0 },
    /* call double(9) at 48 */
    { OP_CONST, R0, 0, 9 }, { OP_PUSH, R0, 0, 0 }, { OP_CALL, 48, 1, 1 },
    { OP_CONST, R2, 0, 18 }, { OP_EQ, R0, R2, 0 }, { OP_JZ, 24, 0, 0 },
    { OP_CONST, R0, 0, 3 }, { OP_HALT, 0, 0, 0 },
    /* memory: alloc 4 words, expect nonzero, free it */
    { OP_CONST, R0, 0, 4 }, { OP_ALLOC, R5, R0, 0 }, { OP_CONST, R1, 0, 0 },
    { OP_NE, R5, R1, 0 }, { OP_JZ, 31, 0, 0 },
    { OP_CONST, R0, 0, 4 }, { OP_HALT, 0, 0, 0 }, { OP_FREE, R5, 0, 0 },
    /* channels + spawn(worker at 52) + wait */
    { OP_CHAN, R6, 0, 0 }, { OP_PUSH, R6, 0, 0 }, { OP_SPAWN, 52, 1, 1 },
    { OP_PUSH, R0, 0, 0 }, { OP_CONST, R0, 0, 41 }, { OP_SEND, R6, R0, 0 },
    { OP_RECV, R6, 0, 0 }, { OP_POP, R1, 0, 0 }, { OP_WAIT, R1, 0, 0 },
    { OP_CONST, R2, 0, 42 }, { OP_EQ, R0, R2, 0 }, { OP_JZ, 46, 0, 0 },
    { OP_CONST, R0, 0, 5 }, { OP_HALT, 0, 0, 0 },
    { OP_CONST, R0, 0, 0 }, { OP_HALT, 0, 0, 0 },
    /* double(n): n*2 */
    { OP_LOAD, R0, 0, 0 }, { OP_CONST, R1, 0, 2 }, { OP_MUL, R0, R1, 0 },
    { OP_RET, 0, 0, 0 },
    /* worker(c): recv, +1, send back, exit 0 */
    { OP_LOAD, R5, 0, 0 }, { OP_RECV, R5, 0, 0 }, { OP_CONST, R1, 0, 1 },
    { OP_ADD, R0, R1, 0 }, { OP_SEND, R5, R0, 0 }, { OP_CONST, R0, 0, 0 },
    { OP_RET, 0, 0, 0 },
};

static int cmd_selftest(void) {
    WcImage img;
    wc_image_init(&img);
    size_t n = sizeof(SELFTEST) / sizeof(SELFTEST[0]);
    Word *code = malloc(n * sizeof(Word));
    for (size_t i = 0; i < n; i++)
        code[i] = wc_encode(SELFTEST[i].op, SELFTEST[i].a,
                            SELFTEST[i].b, SELFTEST[i].c);
    img.code = code; img.code_size = n;
    img.entry = 0; img.entry_frame_size = 1;
    VM *vm = vm_create(65536);
    if (!vm) { wc_image_free(&img); return 1; }
    bool loaded = vm_load_image(vm, &img);
    int rc = loaded ? vm_run(vm) : -1;
    bool pass = (rc == 0);
    printf("selftest: %s (exit=%d, steps=%llu)\n",
           pass ? "PASS" : "FAIL", rc,
           (unsigned long long)vm_steps(vm));
    if (!pass) printf(" error: %s\n", vm_error(vm));
    vm_destroy(vm);
    wc_image_free(&img);
    return pass ? 0 : 1;
}

static int cmd_build(const char *src, const char *out) {
    Compiler c;
    compiler_init(&c);
    WcImage img;
    int rc = compile_file(&c, src, &img);
    if (rc != 0) {
        diag_print(stderr, &c.diags);
        compiler_free(&c);
        return 1;
    }
    char err[128] = {0};
    FILE *f = fopen(out, "wb");
    if (!f) { fprintf(stderr, "cannot open '%s'\n", out);
              compiler_free(&c); return 1; }
    bool ok = wc_serialize(&img, f, err, sizeof(err));
    fclose(f);
    if (!ok) fprintf(stderr, "serialize: %s\n", err);
    printf("built %s -> %s (%zu code words, %zu data words)\n",
           src, out, img.code_size, img.data_size);
    wc_image_free(&img);
    compiler_free(&c);
    return ok ? 0 : 1;
}

static int load_image(const char *path, WcImage *img) {
    char err[160] = {0};
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open '%s'\n", path); return 1; }
    bool ok = wc_deserialize(img, f, err, sizeof(err));
    fclose(f);
    if (!ok) { fprintf(stderr, "%s: %s\n", path, err); return 1; }
    return 0;
}

static int cmd_run(const char *path, bool trace) {
    WcImage img;
    wc_image_init(&img);
    if (load_image(path, &img) != 0) return 1;
    VM *vm = vm_create(65536);
    if (!vm) { wc_image_free(&img); return 1; }
    vm_set_output(vm, stdout);
    if (!vm_load_image(vm, &img)) {
        fprintf(stderr, "%s\n", vm_error(vm));
        vm_destroy(vm); wc_image_free(&img); return 1;
    }
    if (trace) vm_set_trace(vm, stderr);
    int rc = vm_run(vm);
    if (rc != 0 && vm_error(vm)[0])
        fprintf(stderr, "vm: %s\n", vm_error(vm));
    vm_destroy(vm);
    wc_image_free(&img);
    return rc < 0 ? 1 : rc;
}

static int cmd_disassemble(const char *path) {
    WcImage img;
    wc_image_init(&img);
    if (load_image(path, &img) != 0) return 1;
    wc_disassemble(stdout, &img);
    wc_image_free(&img);
    return 0;
}

static int cmd_dump(const char *path) {
    size_t n;
    unsigned char *b = (unsigned char *)read_text_file(path, &n);
    if (!b) { fprintf(stderr, "cannot open '%s'\n", path); return 1; }
    for (size_t i = 0; i < n; i++) {
        if (i % 16 == 0) printf("%08zx ", i);
        printf("%02x ", b[i]);
        if (i % 16 == 15 || i == n - 1) putchar('\n');
    }
    free(b);
    return 0;
}

static int cmd_check(const char *src) {
    Compiler c;
    compiler_init(&c);
    WcImage img;
    int rc = compile_file(&c, src, &img);
    if (c.diags.count) diag_print(stderr, &c.diags);
    printf("%s: %s\n", src, rc == 0 ? "OK" : "FAILED");
    wc_image_free(&img);
    compiler_free(&c);
    return rc;
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(stderr); return 1; }
    const char *cmd = argv[1];
    if (strcmp(cmd, "--help") == 0 || strcmp(cmd, "-h") == 0) {
        usage(stdout); return 0;
    }
    if (strcmp(cmd, "--version") == 0) { puts(VERSION); return 0; }
    if (strcmp(cmd, "selftest") == 0) return cmd_selftest();
    if (strcmp(cmd, "build") == 0 && argc >= 3) {
        const char *out = "out.wc";
        for (int i = 3; i + 1 < argc + 1 && i < argc; i++)
            if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) out = argv[i + 1];
        /* build with explicit -o handling */
        out = "out.wc";
        for (int i = 3; i + 1 < argc; i++)
            if (strcmp(argv[i], "-o") == 0) out = argv[i + 1];
        return cmd_build(argv[2], out);
    }
    if (strcmp(cmd, "run") == 0 && argc >= 3) {
        bool trace = argc > 3 && strcmp(argv[3], "--trace") == 0;
        return cmd_run(argv[2], trace);
    }
    if (strcmp(cmd, "disassemble") == 0 && argc >= 3) return cmd_disassemble(argv[2]);
    if (strcmp(cmd, "dump") == 0 && argc >= 3) return cmd_dump(argv[2]);
    if (strcmp(cmd, "check") == 0 && argc >= 3) return cmd_check(argv[2]);
    fprintf(stderr, "unknown command '%s'\n", cmd);
    usage(stderr);
    return 1;
}
