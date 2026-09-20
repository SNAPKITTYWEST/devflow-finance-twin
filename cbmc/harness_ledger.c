#include <assert.h>
#include <stdint.h>
#include <string.h>

#define MAXN 20
#define MAXS 4
#define MAXW 8
#define NENT 32

typedef enum { OK=0, BAD_INDEX, BAD_GEN, WORD_OVF, STATE_INV, SEAL_INV, CHAIN_INV, FULL } err_t;
typedef int8_t Gen;

typedef struct { Gen w[MAXW]; uint8_t len; } word_t;
typedef struct { uint8_t n; uint32_t prev; uint8_t op; word_t word; uint32_t state; uint32_t seal; } entry_t;
typedef struct { entry_t e[NENT]; uint16_t nent; uint32_t head; } ledger_t;

int append(ledger_t *L, uint8_t n, uint8_t op);
int verify(const ledger_t *L);

void harness_nent_bounded(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    for (int i = 0; i < NENT + 2; i++) {
        int rc = append(&L, (uint8_t)i, 0);
        if (rc != OK) break;
    }
    assert(L.nent <= NENT);
}

void harness_gen_range(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    int rc = append(&L, 0, 0);
    if (rc == OK && L.nent > 0) {
        word_t *w = &L.e[0].word;
        for (uint8_t j = 0; j < w->len; j++) {
            Gen g = w->w[j];
            assert(g != 0);
            int mag = g < 0 ? -g : g;
            assert(mag >= 1 && mag <= MAXS - 1);
        }
    }
}

void harness_verify_empty(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));
    int rc = verify(&L);
    assert(rc == OK);
}

void harness_sequential_n(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    append(&L, 0, 0);
    int rc = append(&L, 5, 0);
    assert(rc == BAD_INDEX);
}

void harness_word_len(void) {
    ledger_t L;
    memset(&L, 0, sizeof(L));

    for (int i = 0; i < 4; i++) {
        append(&L, (uint8_t)i, 0);
    }

    for (uint16_t i = 0; i < L.nent; i++) {
        assert(L.e[i].word.len <= MAXW);
    }
}
