#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t  *data;
    uint64_t  size;
    uint64_t  code_start;
    uint64_t  code_end;
} Memory;

typedef enum {
    MEM_OK = 0,
    MEM_INVALID_ADDRESS,
    MEM_ALIGNMENT_FAULT,
    MEM_READ_VIOLATION,
    MEM_WRITE_VIOLATION,
    MEM_EXECUTE_VIOLATION
} MemResult;

uint8_t   memory_read8 (Memory *m, uint64_t addr);
uint16_t  memory_read16(Memory *m, uint64_t addr);
uint32_t  memory_read32(Memory *m, uint64_t addr);
uint64_t  memory_read64(Memory *m, uint64_t addr);
void      memory_write8 (Memory *m, uint64_t addr, uint8_t  value);
void      memory_write16(Memory *m, uint64_t addr, uint16_t value);
void      memory_write32(Memory *m, uint64_t addr, uint32_t value);
void      memory_write64(Memory *m, uint64_t addr, uint64_t value);
MemResult memory_fetch(Memory *m, uint64_t addr, uint64_t len, uint8_t *out);
int       overlaps(uint64_t addr, uint64_t len, uint64_t start, uint64_t end);

#define TEST_SIZE 256

void harness_read_write_roundtrip(void) {
    uint8_t buf[TEST_SIZE];
    memset(buf, 0, TEST_SIZE);
    Memory m = { .data = buf, .size = TEST_SIZE, .code_start = 0, .code_end = 0 };

    memory_write8(&m, 0, 0xAB);
    assert(memory_read8(&m, 0) == 0xAB);

    memory_write16(&m, 2, 0x1234);
    assert(memory_read16(&m, 2) == 0x1234);

    memory_write32(&m, 4, 0xDEADBEEF);
    assert(memory_read32(&m, 4) == 0xDEADBEEF);

    memory_write64(&m, 8, 0xCAFEBABE12345678ULL);
    assert(memory_read64(&m, 8) == 0xCAFEBABE12345678ULL);
}

void harness_fetch_in_code_region(void) {
    uint8_t buf[TEST_SIZE];
    memset(buf, 0x90, TEST_SIZE);
    Memory m = { .data = buf, .size = TEST_SIZE, .code_start = 0, .code_end = 64 };

    uint8_t out[8];
    MemResult rc = memory_fetch(&m, 0, 8, out);
    assert(rc == MEM_OK);
    assert(out[0] == 0x90);
}

void harness_overlaps_logic(void) {
    assert(overlaps(0, 10, 5, 15) == 1);
    assert(overlaps(0, 5, 5, 15) == 0);
    assert(overlaps(10, 5, 0, 10) == 0);
    assert(overlaps(0, 20, 5, 10) == 1);
    assert(overlaps(6, 2, 5, 10) == 1);
    assert(overlaps(20, 5, 0, 10) == 0);
}

void harness_no_code_overlap_write(void) {
    uint8_t buf[TEST_SIZE];
    memset(buf, 0, TEST_SIZE);
    Memory m = { .data = buf, .size = TEST_SIZE, .code_start = 32, .code_end = 64 };

    memory_write8(&m, 0, 0xFF);
    assert(buf[0] == 0xFF);

    memory_write8(&m, 100, 0xCC);
    assert(buf[100] == 0xCC);
}

void harness_alignment(void) {
    uint8_t buf[TEST_SIZE];
    memset(buf, 0, TEST_SIZE);
    Memory m = { .data = buf, .size = TEST_SIZE, .code_start = 0, .code_end = 0 };

    memory_write16(&m, 0, 0x1111);
    assert(memory_read16(&m, 0) == 0x1111);

    memory_write32(&m, 0, 0x22222222);
    assert(memory_read32(&m, 0) == 0x22222222);

    memory_write64(&m, 0, 0x3333333333333333ULL);
    assert(memory_read64(&m, 0) == 0x3333333333333333ULL);
}
