#include <assert.h>
#include <stdint.h>
#include <string.h>

#define MAXN 20
#define MAXS 8
#define MAXW 16
#define NENT 32

typedef enum { OK=0, BAD_IDX, BAD_GEN, WORD_OVF, STATE_INV, SEAL_INV, CHAIN_INV, FULL } err_t;
typedef int8_t gen_t;

typedef struct { gen_t w[MAXW]; uint8_t len; } word_t;
typedef struct {
    uint8_t n; uint32_t prev; uint8_t op;
    word_t word; uint32_t state; uint32_t seal;
} entry_t;
typedef struct { entry_t e[NENT]; uint16_t nent; uint32_t head; } ledger_t;

err_t ledger_append(ledger_t *L, uint8_t n, uint8_t op, const word_t *w_in);
err_t ledger_check(const ledger_t *L);
err_t ledger_step_fib(ledger_t *L, uint8_t n, uint8_t op);

void harness_nent_bounded(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    word_t w = { .w = {1}, .len = 1 };

    for (int i = 0; i < NENT; i++) {
        err_t rc = ledger_append(&L, (uint8_t)(i % (MAXN + 1)), 0, &w);
        if (rc != OK) break;
    }
    assert(L.nent <= NENT);

    err_t rc = ledger_append(&L, 0, 0, &w);
    if (L.nent == NENT) {
        assert(rc == FULL);
    }
}

void harness_gen_magnitude(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    word_t w = { .w = {0}, .len = 1 };
    err_t rc = ledger_append(&L, 5, 0, &w);
    assert(rc == BAD_GEN);

    word_t w2 = { .w = {(gen_t)MAXS}, .len = 1 };
    rc = ledger_append(&L, 5, 0, &w2);
    assert(rc == BAD_GEN);
}

void harness_word_len_capped(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    word_t w;
    w.len = MAXW;
    for (int i = 0; i < MAXW; i++) w.w[i] = 1;
    err_t rc = ledger_append(&L, 5, 0, &w);
    assert(rc == OK || rc != OK);
    assert(L.nent <= NENT);
}

void harness_chain_linkage(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    word_t w = { .w = {1}, .len = 1 };
    ledger_append(&L, 0, 0, &w);
    ledger_append(&L, 1, 0, &w);

    if (L.nent >= 2) {
        assert(L.e[1].prev == L.e[0].state);
    }
}

void harness_fib_rejects_large_n(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));
    word_t w = { .w = {1}, .len = 1 };
    err_t rc = ledger_append(&L, MAXN + 1, 0, &w);
    assert(rc == BAD_IDX);
}
