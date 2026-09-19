/*
 * TLM JXCL ISA — Binary parser
 * Frama-C / ACSL formal specification  (Frama-C 26+ / E-ACSL)
 *
 * Magic bytes: 'J' 'X' 'C' 'L'  (0x4A 0x58 0x43 0x4C)
 * Architecture code: 0x4A58
 */

#ifndef BINARY_PARSER_H
#define BINARY_PARSER_H

#include <stdint.h>
#include <stddef.h>

/* On-disk header is exactly 56 bytes (two uint16s + padding + five uint64s + uint32).
 * With natural alignment, sizeof(BinaryHeader) == 56 == HEADER_SIZE.            */
#define HEADER_SIZE 56

typedef struct {
    uint16_t version;        /*  0: must be 1                         */
    uint16_t architecture;   /*  2: must be 0x4A58                    */
                             /*  4: 4 bytes implicit padding           */
    uint64_t entry_point;    /*  8                                    */
    uint64_t code_offset;    /* 16                                    */
    uint64_t code_size;      /* 24                                    */
    uint64_t data_offset;    /* 32                                    */
    uint64_t data_size;      /* 40                                    */
    uint32_t reserved;       /* 48: must be 0                         */
                             /* 52: 4 bytes implicit trailing padding  */
} BinaryHeader;

/* -------------------------------------------------------------------------
 * Predicates
 * --------------------------------------------------------------------- */

/*@ predicate BinaryHeaderValid(BinaryHeader *h, uint64_t total_len) =
  @   \valid(h) &&
  @   h->version      == 1       &&
  @   h->architecture == 0x4A58  &&
  @   h->reserved     == 0       &&
  @   // code section: no overflow, fully within file
  @   h->code_offset  <= total_len                              &&
  @   h->code_size    <= total_len - h->code_offset            &&
  @   // data section: no overflow, fully within file
  @   h->data_offset  <= total_len                              &&
  @   h->data_size    <= total_len - h->data_offset            &&
  @   // entry point is within the code section
  @   h->entry_point  >= h->code_offset                        &&
  @   h->entry_point  <  h->code_offset + h->code_size;
  @*/

/* -------------------------------------------------------------------------
 * parse_header
 *   Deserialises the first HEADER_SIZE bytes of `bytes` into `*out`.
 *   Returns 0 on success, non-zero on any validation failure.
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
int parse_header(const uint8_t *bytes, uint64_t len, BinaryHeader *out);

/* -------------------------------------------------------------------------
 * validate_section_bounds
 *   Returns 1 if the section [offset, offset+size) is wholly within
 *   a file of `total_len` bytes and the arithmetic does not overflow.
 *   Returns 0 otherwise.
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
int validate_section_bounds(uint64_t offset, uint64_t size, uint64_t total_len);

/* -------------------------------------------------------------------------
 * read_le16 / read_le32 / read_le64
 *   Helper decoders used by parse_header.  Separated so WP can verify them
 *   independently.
 * --------------------------------------------------------------------- */

/*@ requires \valid(p + (0 .. 1));
  @ assigns  \nothing;
  @ ensures  \result == (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
  @*/
uint16_t read_le16(const uint8_t *p);

/*@ requires \valid(p + (0 .. 3));
  @ assigns  \nothing;
  @ ensures  \result ==
  @   (uint32_t)((uint32_t)p[0]       |
  @              ((uint32_t)p[1] << 8)  |
  @              ((uint32_t)p[2] << 16) |
  @              ((uint32_t)p[3] << 24));
  @*/
uint32_t read_le32(const uint8_t *p);

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
uint64_t read_le64(const uint8_t *p);

#endif /* BINARY_PARSER_H */
