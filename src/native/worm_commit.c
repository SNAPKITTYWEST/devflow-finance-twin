// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: AGPL-3.0-or-later
// DEED-089: Sovereign Treasury Engine — C WORM Commit + FFI Shim
// SHA-256 hashing, append-only disk write, fsync, DPI-C bridge to Chisel.

#include <stdint.h>
#include <string.h>

// ── WormBlock C struct (matches PL/I WORM_BLOCK_HEADER) ──────────────────────

typedef struct {
    char magic[4];          // "WORM"
    char prev_hash[64];     // 64 hex chars
    char current_hash[64];  // 64 hex chars
    uint32_t record_count;  // monotonic counter
    unsigned char payload[4096];
} WormBlock;

// ── WORM commit (production uses OpenSSL SHA-256) ────────────────────────────

#ifdef USE_OPENSSL
#include <openssl/sha.h>

int commit_to_worm_storage(int fd, WormBlock *block) {
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, block->prev_hash, 64);
    SHA256_Update(&sha256, block->payload, sizeof(block->payload));
    SHA256_Final((unsigned char *)block->current_hash, &sha256);

    off_t offset = lseek(fd, 0, SEEK_END);
    if (offset == (off_t)-1) return -1;

    ssize_t written = write(fd, block, sizeof(WormBlock));
    if (written != sizeof(WormBlock)) return -2;

    if (fsync(fd) < 0) return -3;

    return 0;
}
#else

// Deterministic hash placeholder (replace with OpenSSL in production)
static void deterministic_hash(const char *prev, const unsigned char *payload,
                                uint32_t payload_len, char *out_hash) {
    uint32_t acc = 0;
    for (uint32_t i = 0; i < 64; i++) {
        acc = acc * 31 + (unsigned char)prev[i];
        acc = acc * 17 + i;
    }
    for (uint32_t i = 0; i < payload_len; i++) {
        acc = acc * 33 + payload[i];
        acc = acc + (i + 1) * 17;
    }
    const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 64; i++) {
        out_hash[i] = hex[(acc >> (i % 8 * 4)) & 0xf];
    }
}

int commit_to_worm_storage(int fd, WormBlock *block) {
    deterministic_hash(block->prev_hash, block->payload,
                       sizeof(block->payload), block->current_hash);

    off_t offset = lseek(fd, 0, SEEK_END);
    if (offset == (off_t)-1) return -1;

    ssize_t written = write(fd, block, sizeof(WormBlock));
    if (written != sizeof(WormBlock)) return -2;

    if (fsync(fd) < 0) return -3;

    return 0;
}
#endif

// ── FFI Shim: C-ABI bridge to Chisel hardware accelerator ────────────────────

extern void chisel_hardware_seal_ffi(void* block_ptr, uint32_t len);

void chisel_hardware_seal_ffi(void* block_ptr, uint32_t len) {
    volatile uint8_t* mmio_control = (volatile uint8_t*)0x40000000;

    __asm__ __volatile__("mfence" ::: "memory");

    *(mmio_control) = 0x01;
}
