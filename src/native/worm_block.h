// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: AGPL-3.0-or-later
// DEED-089: Sovereign Treasury Engine — C Header for WORM Block
// Shared WormBlock definition for C, NASM, and FFI interop.

#ifndef WORM_BLOCK_H
#define WORM_BLOCK_H

#include <stdint.h>

#define WORM_MAGIC_SIZE     4
#define WORM_HASH_SIZE      64
#define WORM_PAYLOAD_SIZE   4096
#define WORM_BLOCK_SIZE     (WORM_MAGIC_SIZE + WORM_HASH_SIZE + WORM_HASH_SIZE + sizeof(uint32_t) + WORM_PAYLOAD_SIZE)

typedef struct {
    char magic[WORM_MAGIC_SIZE];        // "WORM"
    char prev_hash[WORM_HASH_SIZE];     // 64 hex chars
    char current_hash[WORM_HASH_SIZE];  // 64 hex chars
    uint32_t record_count;              // monotonic counter
    unsigned char payload[WORM_PAYLOAD_SIZE];
} WormBlock;

// Entry offsets (matches PL/I morphism table)
#define OFFSET_TX_ID        0
#define OFFSET_TX_TS        36
#define OFFSET_TX_SEQ       44
#define OFFSET_SRC_ACCT     48
#define OFFSET_DST_ACCT     64
#define OFFSET_AMOUNT       80
#define OFFSET_CCY          88
#define OFFSET_FLAGS        91
#define ENTRY_SIZE          128

// Return codes
#define WORM_OK             0
#define WORM_ERR_SEEK       -1
#define WORM_ERR_WRITE      -2
#define WORM_ERR_FSYNC      -3

#endif
