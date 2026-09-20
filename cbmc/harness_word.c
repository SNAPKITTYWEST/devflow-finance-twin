#include <assert.h>
#include <stdint.h>

#define MAX_STRAND 4
#define MAX_WORD   8

typedef int8_t Gen;

int     gen_ok(Gen g);
int     word_ok(const Gen *w, uint8_t len);
uint8_t reduce(Gen *w, uint8_t len);

void harness_gen_ok_bounds(void) {
    assert(gen_ok(0) == 0);
    assert(gen_ok(1) == 1);
    assert(gen_ok(-1) == 1);
    assert(gen_ok(MAX_STRAND - 1) == 1);
    assert(gen_ok(-(MAX_STRAND - 1)) == 1);
    assert(gen_ok(MAX_STRAND) == 0);
    assert(gen_ok(-MAX_STRAND) == 0);
    assert(gen_ok(127) == 0);
    assert(gen_ok(-128) == 0);
}

void harness_reduce_shrinks(void) {
    Gen w[MAX_WORD] = {1, -1, 2, 2, -2, 3, 0, 0};
    uint8_t len = 6;
    uint8_t out = reduce(w, len);
    assert(out <= len);
}

void harness_reduce_empty(void) {
    Gen w[MAX_WORD] = {0};
    uint8_t out = reduce(w, 0);
    assert(out == 0);
}

void harness_word_ok_rejects_zero(void) {
    Gen w[MAX_WORD] = {1, 0, 2};
    int ok = word_ok(w, 3);
    assert(ok == 0);
}

void harness_word_ok_accepts_valid(void) {
    Gen w[MAX_WORD] = {1, 2, -1, 3};
    int ok = word_ok(w, 4);
    assert(ok == 1);
}

void harness_reduce_cancels_inverses(void) {
    Gen w[MAX_WORD] = {2, -2};
    uint8_t out = reduce(w, 2);
    assert(out == 0);
}
