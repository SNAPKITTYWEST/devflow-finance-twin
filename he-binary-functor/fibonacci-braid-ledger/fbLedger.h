/* fbLedger.h — Fibonacci Braid Ledger (RV64I target)
 * 64-byte entries, FNV-1a-64 seal, 48-bit state
 */
#ifndef FB_LEDGER_H
#define FB_LEDGER_H

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed char s8;

enum {
    FB_MAX_ENTRIES = 64,
    FB_MAX_FIB     = 63,
    FB_MAX_STRANDS = 8,
    FB_MAX_WORD    = 16,
    FB_STATE_MASK  = 0x0000FFFFFFFFFFFFULL,
    FB_APPLY       = 0,
    FB_UNDO        = 1
};

enum {
    FB_OK = 0,
    FB_BAD_INDEX,
    FB_BAD_GENERATOR,
    FB_WORD_OVERFLOW,
    FB_STATE_INVALID,
    FB_SEAL_INVALID,
    FB_CHAIN_INVALID,
    FB_FULL,
    FB_SCHEDULE_INVALID
} __attribute__((packed));

typedef struct __attribute__((packed)) {
    u64 n;
    u64 fib;
    u64 prev_state;
    u64 state;
    u64 prev_seal;
    u64 seal;
    u8  op;
    u8  strands;
    u8  len;
    s8  word[FB_MAX_WORD];
} FBEntry; /* 64 bytes */

typedef struct __attribute__((packed)) {
    u64 n;
    u64 expected_prev_state;
    u64 expected_prev_seal;
    u8  op;
    u8  strands;
    u8  len;
    s8  word[FB_MAX_WORD];
} FBRequest; /* 43 bytes */

typedef struct __attribute__((packed)) {
    u64 count;
    u64 head_state;
    u64 head_seal;
    FBEntry entries[FB_MAX_ENTRIES];
} FBLedger;

/* core functions */
int  fb_fib(u64 n, u64 *out);
int  fb_reduce(const s8 *in, u8 len, u8 strands, s8 out[FB_MAX_WORD], u8 *olen);
u64  fb_word_delta(const s8 *w, u8 len);
u64  fb_seal(const FBEntry *e);
int  fb_append(FBLedger *l, const FBRequest *r, FBEntry *audit);
int  fb_verify_head(const FBLedger *l);

#endif
