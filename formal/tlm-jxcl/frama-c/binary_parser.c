/*
 * TLM JXCL ISA — Binary parser stub implementations
 * Frama-C / ACSL formal verification target  (Frama-C 26+)
 *
 * The stubs are complete enough to satisfy WP's syntactic checks and to
 * supply proof obligations for the contracts in binary_parser.h.
 */

#include "binary_parser.h"
#include <stdint.h>
#include <stddef.h>

/* -------------------------------------------------------------------------
 * Little-endian decoders
 * --------------------------------------------------------------------- */

/*@ requires \valid(p + (0 .. 1));
  @ assigns  \nothing;
  @ ensures  \result == (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
  @*/
uint16_t read_le16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

/*@ requires \valid(p + (0 .. 3));
  @ assigns  \nothing;
  @ ensures  \result ==
  @   (uint32_t)((uint32_t)p[0]       |
  @              ((uint32_t)p[1] << 8)  |
  @              ((uint32_t)p[2] << 16) |
  @              ((uint32_t)p[3] << 24));
  @*/
uint32_t read_le32(const uint8_t *p)
{
    return (uint32_t)((uint32_t)p[0]        |
                      ((uint32_t)p[1] << 8)  |
                      ((uint32_t)p[2] << 16) |
                      ((uint32_t)p[3] << 24));
}

/*@ requires \valid(p + (0 .. 7));
  @ assigns  \nothing;
  @ ensures  \result ==
  @   (uint64_t)((uint64_t)p[0]       |
  @              ((uint64_t)p[1] << 8)  |
  @              ((uint64_t)p[2] << 16) |
  @              ((uint64_t)p[3] << 24) |
  @              ((uint64_t)p[4] << 32) |
  @              ((uint64_t)p[5] << 40) |
  @              ((uint64_t)p[6] << 48) |
  @              ((uint64_t)p[7] << 56));
  @*/
uint64_t read_le64(const uint8_t *p)
{
    return (uint64_t)((uint64_t)p[0]        |
                      ((uint64_t)p[1] << 8)  |
                      ((uint64_t)p[2] << 16) |
                      ((uint64_t)p[3] << 24) |
                      ((uint64_t)p[4] << 32) |
                      ((uint64_t)p[5] << 40) |
                      ((uint64_t)p[6] << 48) |
                      ((uint64_t)p[7] << 56));
}

/* -------------------------------------------------------------------------
 * validate_section_bounds
 * --------------------------------------------------------------------- */

/*@ requires total_len <= (uint64_t)0xFFFFFFFFFFFFFFFFULL;
  @ assigns  \nothing;
  @ behavior fits:
  @   assumes offset <= total_len && size <= total_len - offset;
  @   ensures \result == 1;
  @ behavior overflow_or_oob:
  @   assumes offset > total_len || size > total_len - offset;
  @   ensures \result == 0;
  @ complete behaviors;
  @ disjoint behaviors;
  @*/
int validate_section_bounds(uint64_t offset, uint64_t size, uint64_t total_len)
{
    if (offset > total_len) {
        return 0;
    }
    /* offset <= total_len, so total_len - offset does not underflow */
    if (size > total_len - offset) {
        return 0;
    }
    return 1;
}

/* -------------------------------------------------------------------------
 * parse_header
 *
 * Layout (all fields little-endian):
 *   [0]   uint16_t  version        (must == 1)
 *   [2]   uint16_t  architecture   (must == 0x4A58)
 *   [4]   4 bytes   padding
 *   [8]   uint64_t  entry_point
 *   [16]  uint64_t  code_offset
 *   [24]  uint64_t  code_size
 *   [32]  uint64_t  data_offset
 *   [40]  uint64_t  data_size
 *   [48]  uint32_t  reserved       (must == 0)
 * --------------------------------------------------------------------- */

/*@ requires \valid(bytes + (0 .. len - 1));
  @ requires len >= HEADER_SIZE;
  @ requires \valid(out);
  @ assigns  *out;
  @ behavior valid_header:
  @   assumes bytes[0] == 'J' && bytes[1] == 'X' &&
  @           bytes[2] == 'C' && bytes[3] == 'L';
  @   ensures \result == 0;
  @   ensures BinaryHeaderValid(out, len);
  @ behavior invalid_magic:
  @   assumes bytes[0] != 'J' || bytes[1] != 'X' ||
  @           bytes[2] != 'C' || bytes[3] != 'L';
  @   ensures \result != 0;
  @ complete behaviors;
  @ disjoint behaviors;
  @*/
int parse_header(const uint8_t *bytes, uint64_t len, BinaryHeader *out)
{
    /* Magic check */
    if (bytes[0] != (uint8_t)'J' || bytes[1] != (uint8_t)'X' ||
        bytes[2] != (uint8_t)'C' || bytes[3] != (uint8_t)'L') {
        return -1;
    }

    /* Decode fields from raw bytes (avoids alignment concerns) */
    out->version       = read_le16(bytes + 0);
    out->architecture  = read_le16(bytes + 2);
    /* bytes[4..7]: padding, skip */
    out->entry_point   = read_le64(bytes + 8);
    out->code_offset   = read_le64(bytes + 16);
    out->code_size     = read_le64(bytes + 24);
    out->data_offset   = read_le64(bytes + 32);
    out->data_size     = read_le64(bytes + 40);
    out->reserved      = read_le32(bytes + 48);

    /* Semantic validation */
    if (out->version != 1) {
        return -2;
    }
    if (out->architecture != 0x4A58U) {
        return -3;
    }
    if (out->reserved != 0U) {
        return -4;
    }
    if (!validate_section_bounds(out->code_offset, out->code_size, len)) {
        return -5;
    }
    if (!validate_section_bounds(out->data_offset, out->data_size, len)) {
        return -6;
    }
    /* Entry point must lie within the code section */
    if (out->entry_point < out->code_offset ||
        out->entry_point >= out->code_offset + out->code_size) {
        return -7;
    }

    return 0;
}
