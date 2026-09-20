#include <assert.h>
#include <stdint.h>
#include <string.h>

#define WORM_MAGIC_SIZE   4
#define WORM_HASH_SIZE    64
#define WORM_PAYLOAD_SIZE 4096

typedef struct {
    char magic[WORM_MAGIC_SIZE];
    char prev_hash[WORM_HASH_SIZE];
    char current_hash[WORM_HASH_SIZE];
    uint32_t record_count;
    unsigned char payload[WORM_PAYLOAD_SIZE];
} WormBlock;

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

void harness_hash_output_is_hex(void) {
    WormBlock block;
    memcpy(block.magic, "WORM", 4);
    memset(block.prev_hash, '0', 64);
    memset(block.payload, 0, WORM_PAYLOAD_SIZE);

    deterministic_hash(block.prev_hash, block.payload,
                       WORM_PAYLOAD_SIZE, block.current_hash);

    for (int i = 0; i < 64; i++) {
        char c = block.current_hash[i];
        assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'));
    }
}

void harness_magic_preserved(void) {
    WormBlock block;
    memcpy(block.magic, "WORM", 4);
    memset(block.prev_hash, '0', 64);
    block.record_count = 0;
    memset(block.payload, 0, WORM_PAYLOAD_SIZE);

    deterministic_hash(block.prev_hash, block.payload,
                       WORM_PAYLOAD_SIZE, block.current_hash);

    assert(block.magic[0] == 'W');
    assert(block.magic[1] == 'O');
    assert(block.magic[2] == 'R');
    assert(block.magic[3] == 'M');
}

void harness_record_count_fits(void) {
    WormBlock block;
    block.record_count = 0;
    uint32_t prev = block.record_count;
    block.record_count++;
    assert(block.record_count == prev + 1);
    assert(block.record_count > 0);
}

void harness_hash_deterministic(void) {
    WormBlock b1, b2;
    memcpy(b1.magic, "WORM", 4);
    memcpy(b2.magic, "WORM", 4);
    memset(b1.prev_hash, 'a', 64);
    memset(b2.prev_hash, 'a', 64);
    memset(b1.payload, 0x42, WORM_PAYLOAD_SIZE);
    memset(b2.payload, 0x42, WORM_PAYLOAD_SIZE);

    deterministic_hash(b1.prev_hash, b1.payload, WORM_PAYLOAD_SIZE, b1.current_hash);
    deterministic_hash(b2.prev_hash, b2.payload, WORM_PAYLOAD_SIZE, b2.current_hash);

    assert(memcmp(b1.current_hash, b2.current_hash, 64) == 0);
}

void harness_different_input_different_hash(void) {
    WormBlock b1, b2;
    memset(b1.prev_hash, '0', 64);
    memset(b2.prev_hash, '0', 64);
    memset(b1.payload, 0x00, WORM_PAYLOAD_SIZE);
    memset(b2.payload, 0xFF, WORM_PAYLOAD_SIZE);

    deterministic_hash(b1.prev_hash, b1.payload, WORM_PAYLOAD_SIZE, b1.current_hash);
    deterministic_hash(b2.prev_hash, b2.payload, WORM_PAYLOAD_SIZE, b2.current_hash);

    assert(memcmp(b1.current_hash, b2.current_hash, 64) != 0);
}
