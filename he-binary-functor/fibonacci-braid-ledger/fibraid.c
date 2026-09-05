/* fibraid.c — Fibonacci-indexed braid ledger
 * dense, static, deterministic, fixed-width
 * MAXN=20 MAXS=8 MAXW=16
 */
#include <stdint.h>
#include <string.h>

#define MAXN 20
#define MAXS 8
#define MAXW 16
#define NENT 32

typedef enum {
    OK=0, BAD_IDX, BAD_GEN, WORD_OVF, STATE_INV, SEAL_INV, CHAIN_INV, FULL
} err_t;

typedef int8_t gen_t;

typedef struct {
    gen_t w[MAXW];
    uint8_t len;
} word_t;

typedef struct {
    uint8_t n;
    uint32_t prev;
    uint8_t op;
    word_t word;
    uint32_t state;
    uint32_t seal;
} entry_t;

typedef struct {
    entry_t e[NENT];
    uint16_t nent;
    uint32_t head;
} ledger_t;

static const uint32_t fibtab[MAXN+1] = {
    0,1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765
};

static err_t fib(uint8_t n, uint32_t *out) {
    if (n > MAXN) return BAD_IDX;
    *out = fibtab[n];
    return OK;
}

static err_t gen_ok(gen_t g) {
    int a = g > 0 ? g : -g;
    return (a >= 1 && a < MAXS) ? OK : BAD_GEN;
}

static err_t word_append(word_t *w, gen_t g) {
    if (w->len >= MAXW) return WORD_OVF;
    if (gen_ok(g) != OK) return BAD_GEN;
    if (w->len > 0 && w->w[w->len-1] == -g) { w->len--; return OK; }
    w->w[w->len++] = g;
    return OK;
}

static void word_inv(word_t *w) {
    for (int i = 0; i < w->len/2; i++) {
        gen_t t = w->w[i];
        w->w[i] = -w->w[w->len-1-i];
        w->w[w->len-1-i] = -t;
    }
    if (w->len & 1) w->w[w->len/2] = -w->w[w->len/2];
}

static gen_t fib_gen(uint8_t n) {
    uint32_t f;
    fib(n, &f);
    int k = (f % (MAXS-1)) + 1;
    return (f & 1) ? (gen_t)k : (gen_t)(-k);
}

static uint32_t mix(uint32_t a, uint32_t b) {
    return a ^ (b + 0x9e3779b9 + (a<<6) + (a>>2));
}

static uint32_t seal_entry(uint32_t prev_seal, const entry_t *e) {
    uint32_t s = prev_seal;
    s = mix(s, e->n);
    s = mix(s, e->prev);
    s = mix(s, e->op);
    s = mix(s, e->state);
    for (int i = 0; i < e->word.len; i++)
        s = mix(s, (uint32_t)(int32_t)e->word.w[i]);
    return s;
}

static uint32_t apply(uint32_t st, const word_t *w, uint8_t op) {
    uint32_t x = st;
    if (op == 2) return 0;
    for (int i = 0; i < w->len; i++) {
        int g = w->w[i];
        x = mix(x, (uint32_t)(int32_t)g);
    }
    if (op == 1) x = ~x;
    return x;
}

err_t ledger_append(ledger_t *L, uint8_t n, uint8_t op, const word_t *w_in) {
    if (L->nent >= NENT) return FULL;
    if (n > MAXN) return BAD_IDX;

    entry_t *e = &L->e[L->nent];
    memset(e, 0, sizeof(*e));
    e->n = n;
    e->op = op;
    e->prev = (L->nent == 0) ? 0 : L->e[L->nent-1].state;

    e->word.len = 0;
    for (int i = 0; i < w_in->len; i++) {
        err_t r = word_append(&e->word, w_in->w[i]);
        if (r != OK) return r;
    }

    e->state = apply(e->prev, &e->word, op);
    e->seal = seal_entry(L->head, e);

    if (L->nent > 0 && e->prev != L->e[L->nent-1].state)
        return CHAIN_INV;

    L->head = e->seal;
    L->nent++;
    return OK;
}

err_t ledger_check(const ledger_t *L) {
    uint32_t h = 0;
    for (uint16_t i = 0; i < L->nent; i++) {
        const entry_t *e = &L->e[i];
        if (e->n > MAXN) return BAD_IDX;
        for (int j = 0; j < e->word.len; j++)
            if (gen_ok(e->word.w[j]) != OK) return BAD_GEN;
        if (i > 0 && e->prev != L->e[i-1].state) return CHAIN_INV;
        uint32_t s = seal_entry(h, e);
        if (s != e->seal) return SEAL_INV;
        h = s;
    }
    return OK;
}

err_t ledger_step_fib(ledger_t *L, uint8_t n, uint8_t op) {
    word_t w = {0};
    gen_t g = fib_gen(n);
    err_t r = word_append(&w, g);
    if (r != OK) return r;
    return ledger_append(L, n, op, &w);
}
