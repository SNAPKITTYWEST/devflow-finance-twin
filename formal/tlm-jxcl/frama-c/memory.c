/*
 * TLM JXCL ISA — Memory subsystem stub implementations
 * Frama-C / ACSL formal verification target  (Frama-C 26+)
 *
 * Bodies are minimal stubs sufficient to satisfy syntactic checks and to
 * give WP something to analyse.  The contracts in memory.h drive verification.
 */

#include "memory.h"
#include <stdint.h>
#include <stddef.h>

/* -------------------------------------------------------------------------
 * Scalar reads
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 1);
  @ assigns  \nothing;
  @ ensures  \result == (uint8_t)m->data[addr];
  @*/
uint8_t memory_read8(Memory *m, uint64_t addr)
{
    return m->data[addr];
}

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 2);
  @ requires addr % 2 == 0;
  @ requires NoCodeOverlap(m, addr, 2);
  @ assigns  \nothing;
  @ ensures  \result ==
  @   (uint16_t)((uint16_t)m->data[addr] |
  @              ((uint16_t)m->data[addr + 1] << 8));
  @*/
uint16_t memory_read16(Memory *m, uint64_t addr)
{
    return (uint16_t)((uint16_t)m->data[addr] |
                      ((uint16_t)m->data[addr + 1] << 8));
}

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
uint32_t memory_read32(Memory *m, uint64_t addr)
{
    return (uint32_t)((uint32_t)m->data[addr]        |
                      ((uint32_t)m->data[addr + 1] << 8)  |
                      ((uint32_t)m->data[addr + 2] << 16) |
                      ((uint32_t)m->data[addr + 3] << 24));
}

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
uint64_t memory_read64(Memory *m, uint64_t addr)
{
    return (uint64_t)((uint64_t)m->data[addr]        |
                      ((uint64_t)m->data[addr + 1] << 8)  |
                      ((uint64_t)m->data[addr + 2] << 16) |
                      ((uint64_t)m->data[addr + 3] << 24) |
                      ((uint64_t)m->data[addr + 4] << 32) |
                      ((uint64_t)m->data[addr + 5] << 40) |
                      ((uint64_t)m->data[addr + 6] << 48) |
                      ((uint64_t)m->data[addr + 7] << 56));
}

/* -------------------------------------------------------------------------
 * Scalar writes
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 1);
  @ requires NoCodeOverlap(m, addr, 1);
  @ assigns  m->data[addr];
  @ ensures  m->data[addr] == (uint8_t)value;
  @ ensures  ValidMemory(m);
  @*/
void memory_write8(Memory *m, uint64_t addr, uint8_t value)
{
    m->data[addr] = value;
}

/*@ requires ValidMemory(m);
  @ requires InBounds(m, addr, 2);
  @ requires addr % 2 == 0;
  @ requires NoCodeOverlap(m, addr, 2);
  @ assigns  m->data[addr .. addr + 1];
  @ ensures  m->data[addr]     == (uint8_t)(value);
  @ ensures  m->data[addr + 1] == (uint8_t)(value >> 8);
  @ ensures  ValidMemory(m);
  @*/
void memory_write16(Memory *m, uint64_t addr, uint16_t value)
{
    m->data[addr]     = (uint8_t)(value);
    m->data[addr + 1] = (uint8_t)(value >> 8);
}

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
void memory_write32(Memory *m, uint64_t addr, uint32_t value)
{
    m->data[addr]     = (uint8_t)(value);
    m->data[addr + 1] = (uint8_t)(value >> 8);
    m->data[addr + 2] = (uint8_t)(value >> 16);
    m->data[addr + 3] = (uint8_t)(value >> 24);
}

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
void memory_write64(Memory *m, uint64_t addr, uint64_t value)
{
    m->data[addr]     = (uint8_t)(value);
    m->data[addr + 1] = (uint8_t)(value >> 8);
    m->data[addr + 2] = (uint8_t)(value >> 16);
    m->data[addr + 3] = (uint8_t)(value >> 24);
    m->data[addr + 4] = (uint8_t)(value >> 32);
    m->data[addr + 5] = (uint8_t)(value >> 40);
    m->data[addr + 6] = (uint8_t)(value >> 48);
    m->data[addr + 7] = (uint8_t)(value >> 56);
}

/* -------------------------------------------------------------------------
 * Instruction fetch
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
MemResult memory_fetch(Memory *m, uint64_t addr, uint64_t len, uint8_t *out)
{
    uint64_t i;
    /*@ loop invariant 0 <= i <= len;
      @ loop invariant \forall int j; 0 <= j < (int)i ==> out[j] == m->data[addr + (uint64_t)j];
      @ loop assigns i, out[0 .. len - 1];
      @ loop variant len - i;
      @*/
    for (i = 0; i < len; i++) {
        out[i] = m->data[addr + i];
    }
    return MEM_OK;
}

/* -------------------------------------------------------------------------
 * Loader write  (bypasses code-section guard)
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(m);
  @ requires addr + len <= m->size;
  @ requires \valid(src + (0 .. len - 1));
  @ requires \separated(m->data + (0 .. m->size - 1), src + (0 .. len - 1));
  @ assigns  m->data[addr .. addr + len - 1];
  @ ensures  \forall int i; 0 <= i < (int)len ==> m->data[addr + (uint64_t)i] == src[i];
  @ ensures  ValidMemory(m);
  @*/
void memory_loader_write(Memory *m, uint64_t addr, uint64_t len, const uint8_t *src)
{
    uint64_t i;
    /*@ loop invariant 0 <= i <= len;
      @ loop invariant \forall int j; 0 <= j < (int)i ==>
      @                    m->data[addr + (uint64_t)j] == src[j];
      @ loop assigns i, m->data[addr .. addr + len - 1];
      @ loop variant len - i;
      @*/
    for (i = 0; i < len; i++) {
        m->data[addr + i] = src[i];
    }
}

/* -------------------------------------------------------------------------
 * Overflow-safe overlap check
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
int overlaps(uint64_t addr, uint64_t len, uint64_t start, uint64_t end)
{
    if (len == 0) {
        return 0;
    }
    /* addr + len cannot overflow: guaranteed by requires */
    return (addr < end && start < addr + len) ? 1 : 0;
}
