/*
 * TLM JXCL ISA — Memory subsystem
 * Frama-C / ACSL formal specification  (Frama-C 26+ / E-ACSL)
 *
 * All predicates and function contracts are written in ACSL.
 * Arithmetic inside ACSL logic uses mathematical integers (unbounded),
 * so additions / subtractions in predicate bodies do NOT wrap.
 */

#ifndef MEMORY_H
#define MEMORY_H

#include <stdint.h>
#include <stddef.h>

/* -------------------------------------------------------------------------
 * Core types
 * --------------------------------------------------------------------- */

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

/* -------------------------------------------------------------------------
 * Global ACSL predicates
 * --------------------------------------------------------------------- */

/*@ predicate ValidMemory(Memory *m) =
  @   \valid(m) &&
  @   \valid(m->data + (0 .. m->size - 1)) &&
  @   m->code_start <= m->code_end &&
  @   m->code_end   <= m->size;
  @*/

/*@ predicate InBounds(Memory *m, uint64_t addr, uint64_t len) =
  @   len <= m->size - addr &&
  @   addr <= m->size - len;
  @*/

/*@ predicate NoCodeOverlap(Memory *m, uint64_t addr, uint64_t len) =
  @   (addr + len <= m->code_start) ||
  @   (addr >= m->code_end);
  @*/

/* -------------------------------------------------------------------------
 * Scalar reads  (little-endian)
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 1);
  @ assigns  \nothing;
  @ ensures  \result == (uint8_t)m->data[addr];
  @*/
uint8_t memory_read8(Memory *m, uint64_t addr);

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 2);
  @ requires addr % 2 == 0;
  @ requires NoCodeOverlap(m, addr, 2);
  @ assigns  \nothing;
  @ ensures  \result ==
  @   (uint16_t)((uint16_t)m->data[addr] |
  @              ((uint16_t)m->data[addr + 1] << 8));
  @*/
uint16_t memory_read16(Memory *m, uint64_t addr);

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 4);
  @ requires addr % 4 == 0;
  @ requires NoCodeOverlap(m, addr, 4);
  @ assigns  \nothing;
  @ ensures  \result ==
  @   (uint32_t)((uint32_t)m->data[addr]       |
  @              ((uint32_t)m->data[addr + 1] << 8)  |
  @              ((uint32_t)m->data[addr + 2] << 16) |
  @              ((uint32_t)m->data[addr + 3] << 24));
  @*/
uint32_t memory_read32(Memory *m, uint64_t addr);

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 8);
  @ requires addr % 8 == 0;
  @ requires NoCodeOverlap(m, addr, 8);
  @ assigns  \nothing;
  @ ensures  \result ==
  @   (uint64_t)((uint64_t)m->data[addr]       |
  @              ((uint64_t)m->data[addr + 1] << 8)  |
  @              ((uint64_t)m->data[addr + 2] << 16) |
  @              ((uint64_t)m->data[addr + 3] << 24) |
  @              ((uint64_t)m->data[addr + 4] << 32) |
  @              ((uint64_t)m->data[addr + 5] << 40) |
  @              ((uint64_t)m->data[addr + 6] << 48) |
  @              ((uint64_t)m->data[addr + 7] << 56));
  @*/
uint64_t memory_read64(Memory *m, uint64_t addr);

/* -------------------------------------------------------------------------
 * Scalar writes  (little-endian)
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 1);
  @ requires NoCodeOverlap(m, addr, 1);
  @ assigns  m->data[addr];
  @ ensures  m->data[addr] == (uint8_t)value;
  @ ensures  ValidMemory(m);
  @*/
void memory_write8(Memory *m, uint64_t addr, uint8_t value);

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 2);
  @ requires addr % 2 == 0;
  @ requires NoCodeOverlap(m, addr, 2);
  @ assigns  m->data[addr .. addr + 1];
  @ ensures  m->data[addr]     == (uint8_t)(value);
  @ ensures  m->data[addr + 1] == (uint8_t)(value >> 8);
  @ ensures  ValidMemory(m);
  @*/
void memory_write16(Memory *m, uint64_t addr, uint16_t value);

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 4);
  @ requires addr % 4 == 0;
  @ requires NoCodeOverlap(m, addr, 4);
  @ assigns  m->data[addr .. addr + 3];
  @ ensures  m->data[addr]     == (uint8_t)(value);
  @ ensures  m->data[addr + 1] == (uint8_t)(value >> 8);
  @ ensures  m->data[addr + 2] == (uint8_t)(value >> 16);
  @ ensures  m->data[addr + 3] == (uint8_t)(value >> 24);
  @ ensures  ValidMemory(m);
  @*/
void memory_write32(Memory *m, uint64_t addr, uint32_t value);

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 8);
  @ requires addr % 8 == 0;
  @ requires NoCodeOverlap(m, addr, 8);
  @ assigns  m->data[addr .. addr + 7];
  @ ensures  m->data[addr]     == (uint8_t)(value);
  @ ensures  m->data[addr + 1] == (uint8_t)(value >> 8);
  @ ensures  m->data[addr + 2] == (uint8_t)(value >> 16);
  @ ensures  m->data[addr + 3] == (uint8_t)(value >> 24);
  @ ensures  m->data[addr + 4] == (uint8_t)(value >> 32);
  @ ensures  m->data[addr + 5] == (uint8_t)(value >> 40);
  @ ensures  m->data[addr + 6] == (uint8_t)(value >> 48);
  @ ensures  m->data[addr + 7] == (uint8_t)(value >> 56);
  @ ensures  ValidMemory(m);
  @*/
void memory_write64(Memory *m, uint64_t addr, uint64_t value);

/* -------------------------------------------------------------------------
 * Instruction fetch  (code region only)
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(m);
  @ requires m->code_start <= addr;
  @ requires addr + len <= m->code_end;
  @ requires InBounds(m, addr, len);
  @ requires \valid(out + (0 .. len - 1));
  @ requires \separated(m->data + (0 .. m->size - 1), out + (0 .. len - 1));
  @ assigns  out[0 .. len - 1];
  @ ensures  \forall int i; 0 <= i < (int)len ==> out[i] == m->data[addr + (uint64_t)i];
  @*/
MemResult memory_fetch(Memory *m, uint64_t addr, uint64_t len, uint8_t *out);

/* -------------------------------------------------------------------------
 * Loader write  (bypasses code-section guard — called before execution)
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(m);
  @ requires addr + len <= m->size;
  @ requires \valid(src + (0 .. len - 1));
  @ requires \separated(m->data + (0 .. m->size - 1), src + (0 .. len - 1));
  @ assigns  m->data[addr .. addr + len - 1];
  @ ensures  \forall int i; 0 <= i < (int)len ==> m->data[addr + (uint64_t)i] == src[i];
  @ ensures  ValidMemory(m);
  @*/
void memory_loader_write(Memory *m, uint64_t addr, uint64_t len, const uint8_t *src);

/* -------------------------------------------------------------------------
 * Overflow-safe overlap check
 *   Returns 1 if [addr, addr+len) overlaps [start, end), 0 otherwise.
 *   When len == 0 the range is empty and the result is always 0.
 * --------------------------------------------------------------------- */

/*@ requires addr <= (uint64_t)0xFFFFFFFFFFFFFFFFULL - len || len == 0;
  @ assigns  \nothing;
  @ behavior empty_range:
  @   assumes len == 0;
  @   ensures \result == 0;
  @ behavior non_empty_range:
  @   assumes len != 0;
  @   ensures \result == 1 <==>
  @     (addr < end && start < addr + len);
  @ complete behaviors;
  @ disjoint behaviors;
  @*/
int overlaps(uint64_t addr, uint64_t len, uint64_t start, uint64_t end);

#endif /* MEMORY_H */
