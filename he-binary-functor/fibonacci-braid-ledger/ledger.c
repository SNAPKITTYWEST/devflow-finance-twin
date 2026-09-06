/* ledger.c — Fibonacci-indexed braid ledger */
#include <stdint.h>
#include <string.h>

#define MAXN 20
#define MAXS 4
#define MAXW 8
#define NENT 32

typedef enum { OK=0, BAD_INDEX, BAD_GEN, WORD_OVF, STATE_INV, SEAL_INV, CHAIN_INV, FULL } err_t;
typedef int8_t Gen;

typedef struct {
    Gen w[MAXW];
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

static const uint16_t FIB[MAXN+1] = {
    0,1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181,6765
};

static err_t gen_ok(Gen g) {
    uint8_t k = g < 0 ? -g : g;
    return (k >= 1 && k < MAXS) ? OK : BAD_GEN;
}

static err_t word_ok(const word_t *w) {
    if (w->len > MAXW) return WORD_OVF;
    for (uint8_t i = 0; i < w->len; i++)
        if (gen_ok(w->w[i]) != OK) return BAD_GEN;
    return OK;
}

static u8 reduce(Gen *w, u8 len) {
    u8 j = 0;
    for (u8 i = 0; i < len; i++) {
        if (j && w[j-1] == -w[i]) j--;
        else w[j++] = w[i];
    }
    return j;
}

static uint32_t transit(uint32_t prev, const Gen *w, u8 len) {
    uint32_t s = prev;
    for (u8 i = 0; i < len; i++)
        s = s * 3 + (w[i] < 0 ? -w[i] : w[i]);
    return s;
}

static uint32_t seal(uint32_t ps, const entry_t *e) {
    uint32_t s = ps ^ ((uint32_t)e->n << 16) ^ e->prev ^ e->state;
    for (u8 i = 0; i < e->word.len; i++)
        s = (s << 5) ^ (uint8_t)e->word.w[i];
    return s;
}

int append(ledger_t *L, uint8_t n, uint8_t op) {
    if (n > MAXN || n != L->nent) return BAD_INDEX;
    entry_t *e = &L->e[L->nent];
    memset(e, 0, sizeof(*e));
    e->n = n;
    e->prev = n ? L->e[n-1].state : 0;
    e->op = op;

    /* schedule: Fibonacci → braid */
    uint16_t f = FIB[n];
    e->word.len = f % (MAXW+1);
    if (e->word.len > MAXW) e->word.len = MAXW;
    for (uint8_t i = 0; i < e->word.len; i++) {
        uint8_t k = 1 + ((n+i) % (MAXS-1));
        e->word.w[i] = (i & 1) ? -k : k;
    }

    if (op == 1) { /* inverse */
        for (uint8_t i = 0; i < e->word.len; i++) e->word.w[i] = -e->word.w[i];
        for (uint8_t i = 0; i < e->word.len/2; i++) {
            Gen t = e->word.w[i];
            e->word.w[i] = e->word.w[e->word.len-1-i];
            e->word.w[e->word.len-1-i] = t;
        }
    }
    if (op == 2) e->word.len = reduce(e->word.w, e->word.len);

    if (word_ok(&e->word) != OK) return BAD_GEN;
    e->state = transit(e->prev, e->word.w, e->word.len);
    uint32_t ps = n ? L->e[n-1].seal : 0;
    e->seal = seal(ps, e);
    L->head = e->seal;
    L->nent++;
    return OK;
}

int verify(const ledger_t *L) {
    uint32_t ps = 0;
    for (uint16_t i = 0; i < L->nent; i++) {
        const entry_t *e = &L->e[i];
        if (e->n != i) return CHAIN_INV;
        if (word_ok(&e->word) != OK) return BAD_GEN;
        if (e->state != transit(e->prev, e->word.w, e->word.len)) return STATE_INV;
        if (e->seal != seal(ps, e)) return SEAL_INV;
        if (i && e->prev != L->e[i-1].state) return CHAIN_INV;
        ps = e->seal;
    }
    return OK;
}
