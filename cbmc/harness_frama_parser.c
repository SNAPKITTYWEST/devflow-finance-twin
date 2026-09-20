#include <assert.h>
#include <stdint.h>
#include <string.h>

#define HEADER_SIZE 56

typedef struct {
    uint16_t version;
    uint16_t architecture;
    uint64_t entry_point;
    uint64_t code_offset;
    uint64_t code_size;
    uint64_t data_offset;
    uint64_t data_size;
    uint32_t reserved;
} BinaryHeader;

uint16_t read_le16(const uint8_t *p);
uint32_t read_le32(const uint8_t *p);
uint64_t read_le64(const uint8_t *p);
int      validate_section_bounds(uint64_t offset, uint64_t size, uint64_t total_len);
int      parse_header(const uint8_t *bytes, uint64_t len, BinaryHeader *out);

static void build_valid_header(uint8_t *buf, uint64_t total_len) {
    memset(buf, 0, HEADER_SIZE);
    buf[0] = 'J'; buf[1] = 'X'; buf[2] = 'C'; buf[3] = 'L';
    buf[4] = 1; buf[5] = 0;
    buf[6] = 0x58; buf[7] = 0x4A;

    uint64_t code_off = HEADER_SIZE;
    uint64_t code_sz  = 64;
    uint64_t data_off = code_off + code_sz;
    uint64_t data_sz  = total_len - data_off;
    uint64_t entry    = code_off;

    memcpy(buf + 16, &entry, 8);
    memcpy(buf + 24, &code_off, 8);
    memcpy(buf + 32, &code_sz, 8);
    memcpy(buf + 40, &data_off, 8);
    memcpy(buf + 48, &data_sz, 8);
}

void harness_valid_header_parses(void) {
    uint8_t buf[256];
    memset(buf, 0, 256);
    build_valid_header(buf, 256);

    BinaryHeader hdr;
    int rc = parse_header(buf, 256, &hdr);
    assert(rc == 0);
    assert(hdr.version == 1);
    assert(hdr.architecture == 0x4A58);
    assert(hdr.entry_point >= hdr.code_offset);
    assert(hdr.entry_point < hdr.code_offset + hdr.code_size);
}

void harness_bad_magic_rejected(void) {
    uint8_t buf[256];
    memset(buf, 0, 256);
    build_valid_header(buf, 256);
    buf[0] = 'X';

    BinaryHeader hdr;
    int rc = parse_header(buf, 256, &hdr);
    assert(rc != 0);
}

void harness_bad_version_rejected(void) {
    uint8_t buf[256];
    memset(buf, 0, 256);
    build_valid_header(buf, 256);
    buf[4] = 99;

    BinaryHeader hdr;
    int rc = parse_header(buf, 256, &hdr);
    assert(rc != 0);
}

void harness_too_short_rejected(void) {
    uint8_t buf[32];
    memset(buf, 0, 32);

    BinaryHeader hdr;
    int rc = parse_header(buf, 32, &hdr);
    assert(rc != 0);
}

void harness_section_bounds_valid(void) {
    assert(validate_section_bounds(0, 10, 100) == 0);
    assert(validate_section_bounds(90, 10, 100) == 0);
    assert(validate_section_bounds(91, 10, 100) != 0);
    assert(validate_section_bounds(0, 101, 100) != 0);
}

void harness_entry_in_code(void) {
    uint8_t buf[256];
    memset(buf, 0, 256);
    build_valid_header(buf, 256);

    BinaryHeader hdr;
    int rc = parse_header(buf, 256, &hdr);
    if (rc == 0) {
        assert(hdr.entry_point >= hdr.code_offset);
        assert(hdr.entry_point < hdr.code_offset + hdr.code_size);
    }
}
