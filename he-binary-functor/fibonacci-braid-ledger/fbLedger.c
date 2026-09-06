/* fbLedger.c — Fibonacci Braid Ledger implementation */
#include "fbLedger.h"

int fb_fib(u64 n, u64 *out) {
    u64 a = 0, b = 1, t;
    if (n > FB_MAX_FIB) return 1;
    while (n) { t = a + b; a = b; b = t; --n; }
    *out = a;
    return 0;
}

int fb_reduce(const s8 *in, u8 len, u8 strands, s8 out[FB_MAX_WORD], u8 *olen) {
    u8 i, top = 0;
    s8 g;
    if (strands < 2 || strands > FB_MAX_STRANDS) return 2;
    if (len > FB_MAX_WORD) return 3;
    for (i = 0; i < len; ++i) {
        g = in[i];
        if (g == 0) return 2;
        if (g >= (s8)strands || g <= -(s8)strands) return 2;
        if (top && out[top - 1] == (s8)-g) --top;
        else { if (top == FB_MAX_WORD) return 3; out[top++] = g; }
    }
    *olen = top;
    return 0;
}

u64 fb_word_delta(const s8 *w, u8 len) {
    u64 h = 0;
    u8 i;
    for (i = 0; i < len; ++i) h = (h + (u64)(long long)w[i]) & FB_STATE_MASK;
    return h;
}

static u64 fb_fnv1a64(u64 h, const u8 *p, u64 n) {
    const u64 P = 0x00000100000001B3ULL;
    while (n--) { h ^= *p++; h *= P; }
    return h;
}

u64 fb_seal(const FBEntry *e) {
    const u64 B = 0xCBF29CE484222325ULL;
    u64 h = fb_fnv1a64(B, (const u8 *)&e->prev_seal, 8);
    return fb_fnv1a64(h, (const u8 *)e, 48);
}

int fb_verify_head(const FBLedger *l) {
    const FBEntry *e;
    u64 f;
    if (l->count > FB_MAX_ENTRIES) return 6;
    if (!l->count) return (l->head_state || l->head_seal) ? 6 : 0;
    e = &l->entries[l->count - 1];
    if (e->n != l->count - 1) return 6;
    if (fb_fib(e->n, &f)) return 1;
    if (e->fib != f) return 6;
    if (e->state != l->head_state || e->seal != l->head_seal) return 6;
    if (fb_seal(e) != e->seal) return 5;
    return 0;
}

int fb_append(FBLedger *l, const FBRequest *r, FBEntry *audit) {
    FBEntry e;
    u64 fib, d;
    int rc;
    if (l->count >= FB_MAX_ENTRIES) return 7;
    if ((rc = fb_verify_head(l))) return rc;
    if (r->n != l->count || r->n > FB_MAX_FIB) return 1;
    if (r->op != FB_APPLY && r->op != FB_UNDO) return 4;
    if ((rc = fb_fib(r->n, &fib))) return 1;
    if (r->expected_prev_state != l->head_state) return 4;
    if (r->expected_prev_seal != l->head_seal) return 6;

    e.n = r->n;
    e.fib = fib;
    e.prev_state = l->head_state;
    e.prev_seal = l->head_seal;
    e.op = r->op;
    e.strands = r->strands;

    if ((rc = fb_reduce(r->word, r->len, e.strands, e.word, &e.len))) return rc;

    d = fb_word_delta(e.word, e.len);
    e.state = (e.op == FB_APPLY)
            ? (e.prev_state + d) & FB_STATE_MASK
            : (e.prev_state - d) & FB_STATE_MASK;

    e.seal = fb_seal(&e);

    l->entries[l->count] = e;
    l->count++;
    l->head_state = e.state;
    l->head_seal = e.seal;
    if (audit) *audit = e;
    return 0;
}
