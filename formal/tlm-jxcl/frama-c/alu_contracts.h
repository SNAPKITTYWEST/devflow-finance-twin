/*
 * TLM JXCL ISA — ALU function contracts
 * Frama-C / ACSL formal specification  (Frama-C 26+ / E-ACSL)
 *
 * This is a contract-only header.  No implementation is provided here;
 * the contracts serve as checked specifications for the ALU implementation.
 *
 * Flag register layout (packed into Flags struct):
 *   z  — zero:             result == 0
 *   n  — negative:         MSB of result is 1 (i.e. >= 0x8000000000000000)
 *   c  — carry / borrow:   unsigned overflow for add; borrow for sub
 *   v  — signed overflow:  the signed result does not fit in int64_t
 *
 * ACSL integer arithmetic in ensures clauses uses mathematical integers
 * (unbounded), so expressions like  a + b > 0xFFFFFFFFFFFFFFFF  are well
 * formed and detect 64-bit unsigned overflow without wrapping.
 */

#ifndef ALU_CONTRACTS_H
#define ALU_CONTRACTS_H

#include <stdint.h>
#include <stdbool.h>

/* -------------------------------------------------------------------------
 * Flag register
 * --------------------------------------------------------------------- */

typedef struct {
    int z;   /* zero flag           */
    int n;   /* negative flag       */
    int c;   /* carry / borrow flag */
    int v;   /* signed overflow flag */
} Flags;

/* -------------------------------------------------------------------------
 * alu_add  —  64-bit unsigned addition
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a + b);
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == (a + b > (uint64_t)0xFFFFFFFFFFFFFFFFULL);
  @ ensures  out_flags->v ==
  @   (((int64_t)a >= 0 && (int64_t)b >= 0 && (int64_t)\result <  0) ||
  @    ((int64_t)a <  0 && (int64_t)b <  0 && (int64_t)\result >= 0));
  @*/
uint64_t alu_add(uint64_t a, uint64_t b, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_sub  —  64-bit subtraction  (a - b)
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a - b);
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == (a < b);
  @ ensures  out_flags->v ==
  @   (((int64_t)a >= 0 && (int64_t)b <  0 && (int64_t)\result <  0) ||
  @    ((int64_t)a <  0 && (int64_t)b >= 0 && (int64_t)\result >= 0));
  @*/
uint64_t alu_sub(uint64_t a, uint64_t b, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_mul  —  64-bit unsigned multiplication  (low 64 bits of product)
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a * b);
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == (a * b > (uint64_t)0xFFFFFFFFFFFFFFFFULL);
  @ ensures  out_flags->v == out_flags->c;
  @*/
uint64_t alu_mul(uint64_t a, uint64_t b, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_div  —  64-bit unsigned division  (a / b)
 *   Caller must ensure b != 0 (architectural invariant — divide-by-zero is
 *   trapped by the fetch-decode stage before reaching the ALU).
 * --------------------------------------------------------------------- */

/*@ requires b != 0;
  @ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == a / b;
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_div(uint64_t a, uint64_t b, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_shl  —  logical shift left   (6-bit count mask, so count & 63)
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a << (count & 63u));
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_shl(uint64_t a, uint64_t count, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_shr  —  logical shift right  (6-bit count mask)
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a >> (count & 63u));
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_shr(uint64_t a, uint64_t count, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_rol  —  rotate left  (6-bit count mask)
 *   When (count & 63) == 0 the value is unchanged.
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ behavior zero_count:
  @   assumes (count & 63u) == 0;
  @   ensures \result == a;
  @ behavior nonzero_count:
  @   assumes (count & 63u) != 0;
  @   ensures \result ==
  @     (uint64_t)((a << (count & 63u)) | (a >> (64u - (count & 63u))));
  @ complete behaviors;
  @ disjoint behaviors;
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_rol(uint64_t a, uint64_t count, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_ror  —  rotate right  (6-bit count mask)
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ behavior zero_count:
  @   assumes (count & 63u) == 0;
  @   ensures \result == a;
  @ behavior nonzero_count:
  @   assumes (count & 63u) != 0;
  @   ensures \result ==
  @     (uint64_t)((a >> (count & 63u)) | (a << (64u - (count & 63u))));
  @ complete behaviors;
  @ disjoint behaviors;
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_ror(uint64_t a, uint64_t count, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_and  —  bitwise AND
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a & b);
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_and(uint64_t a, uint64_t b, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_or   —  bitwise OR
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a | b);
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_or(uint64_t a, uint64_t b, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_xor  —  bitwise XOR
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(a ^ b);
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_xor(uint64_t a, uint64_t b, Flags *out_flags);

/* -------------------------------------------------------------------------
 * alu_not  —  bitwise NOT  (unary, single operand)
 *   Carry and overflow are architecturally undefined for NOT; both cleared.
 * --------------------------------------------------------------------- */

/*@ requires \valid(out_flags);
  @ assigns  *out_flags;
  @ ensures  \result == (uint64_t)(~a);
  @ ensures  out_flags->z == (\result == 0);
  @ ensures  out_flags->n == (\result >= (uint64_t)0x8000000000000000ULL);
  @ ensures  out_flags->c == 0;
  @ ensures  out_flags->v == 0;
  @*/
uint64_t alu_not(uint64_t a, Flags *out_flags);

#endif /* ALU_CONTRACTS_H */
