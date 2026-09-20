#include <assert.h>
#include <stdint.h>
#include <string.h>

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed char s8;

enum {
    FB_MAX_ENTRIES = 64,
    FB_MAX_FIB    = 63,
    FB_MAX_STRANDS = 8,
    FB_MAX_WORD   = 16,
    FB_STATE_MASK = 0x0000FFFFFFFFFFFFULL,
    FB_APPLY      = 0,
    FB_UNDO       = 1
};

enum {
    FB_OK=0, FB_BAD_INDEX, FB_BAD_GENERATOR, FB_WORD_OVERFLOW,
    FB_STATE_INVALID, FB_SEAL_INVALID, FB_CHAIN_INVALID, FB_FULL,
    FB_SCHEDULE_INVALID
};

typedef struct __attribute__((packed)) {
    u64 n; u64 fib; u64 prev_state; u64 state;
    u64 prev_seal; u64 seal;
    u8 op; u8 strands; u8 len;
    s8 word[FB_MAX_WORD];
} FBEntry;

typedef struct __attribute__((packed)) {
    u64 n; u64 expected_prev_state; u64 expected_prev_seal;
    u8 op; u8 strands; u8 len;
    s8 word[FB_MAX_WORD];
} FBRequest;

typedef struct __attribute__((packed)) {
    u64 count; u64 head_state; u64 head_seal;
    FBEntry entries[FB_MAX_ENTRIES];
} FBLedger;

int fb_fib(u64 n, u64 *out);
int fb_reduce(const s8 *in, u8 len, u8 strands, s8 out[FB_MAX_WORD], u8 *olen);
u64 fb_seal(const FBEntry *e);
int fb_verify_head(const FBLedger *l);
int fb_append(FBLedger *l, const FBRequest *r, FBEntry *audit);

void harness_count_bounded(void) {
    FBLedger l;
    memset(&l, 0, sizeof(l));
    u64 count;
    __CPROVER_assume(count <= FB_MAX_ENTRIES);
    l.count = count;
    assert(l.count <= FB_MAX_ENTRIES);
}

void harness_append_rejects_full(void) {
    FBLedger l;
    memset(&l, 0, sizeof(l));
    l.count = FB_MAX_ENTRIES;

    FBRequest r;
    memset(&r, 0, sizeof(r));
    r.n = 5;
    r.op = FB_APPLY;
    r.strands = 3;
    r.len = 1;
    r.word[0] = 1;
    r.expected_prev_state = l.head_state;
    r.expected_prev_seal = l.head_seal;

    FBEntry audit;
    int rc = fb_append(&l, &r, &audit);
    assert(rc == FB_FULL);
}

void harness_fib_rejects_overflow(void) {
    u64 out;
    int rc = fb_fib(FB_MAX_FIB + 1, &out);
    assert(rc == FB_BAD_INDEX);
}

void harness_word_len_bounded(void) {
    FBLedger l;
    memset(&l, 0, sizeof(l));

    FBRequest r;
    memset(&r, 0, sizeof(r));
    r.n = 0;
    r.op = FB_APPLY;
    r.strands = 3;
    r.len = FB_MAX_WORD + 1;
    r.word[0] = 1;
    r.expected_prev_state = l.head_state;
    r.expected_prev_seal = l.head_seal;

    FBEntry audit;
    int rc = fb_append(&l, &r, &audit);
    assert(rc != FB_OK);
}

void harness_strands_bounded(void) {
    s8 in[FB_MAX_WORD] = {1};
    s8 out[FB_MAX_WORD];
    u8 olen;

    int rc = fb_reduce(in, 1, 0, out, &olen);
    assert(rc != FB_OK);

    rc = fb_reduce(in, 1, FB_MAX_STRANDS + 1, out, &olen);
    assert(rc != FB_OK);
}
