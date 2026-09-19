/*
 * TLM JXCL ISA — Execution stack and machine state
 * Frama-C / ACSL formal specification  (Frama-C 26+ / E-ACSL)
 *
 * Covers: ValidStack, exec_push, exec_pop, exec_call, addr_of,
 *         and the CycleCountMonotone axiomatic.
 */

#ifndef EXECUTION_STACK_H
#define EXECUTION_STACK_H

#include <stdint.h>
#include "memory.h"

/* -------------------------------------------------------------------------
 * Machine register file
 * --------------------------------------------------------------------- */

#define JXCL_NUM_REGS 16

typedef struct {
    uint64_t r[JXCL_NUM_REGS]; /* general-purpose r0 … r15 */
    uint64_t sp;                /* stack pointer             */
    uint64_t pc;                /* program counter           */
    uint64_t flags;             /* packed flag register      */
} Registers;

/* -------------------------------------------------------------------------
 * Full machine state
 * --------------------------------------------------------------------- */

typedef struct {
    Registers regs;
    Memory    memory;
    int       halted;
    uint64_t  cycle_count;
} MachineState;

/* -------------------------------------------------------------------------
 * Stack predicate
 *   The stack grows downward; sp is always 8-byte aligned and within the
 *   address space described by the embedded Memory.
 * --------------------------------------------------------------------- */

/*@ predicate ValidStack(MachineState *s) =
  @   \valid(s) &&
  @   s->regs.sp % 8 == 0 &&
  @   s->regs.sp <= s->memory.size;
  @*/

/* -------------------------------------------------------------------------
 * Cycle-count monotonicity axiom
 *   Each non-halted step increments cycle_count by exactly 1.
 *   Captured as an axiomatic so WP can use it as a lemma during proofs.
 * --------------------------------------------------------------------- */

/*@ axiomatic CycleCountMonotone {
  @   predicate StepOf(MachineState *before, MachineState *after) =
  @     \valid(before) && \valid(after) &&
  @     !before->halted &&
  @     after->cycle_count == before->cycle_count + 1;
  @
  @   axiom step_increments_count:
  @     \forall MachineState *s1, *s2;
  @       StepOf(s1, s2) ==> s2->cycle_count > s1->cycle_count;
  @ }
  @*/

/* -------------------------------------------------------------------------
 * exec_push  —  PUSH value onto stack
 *   Decrements sp by 8, then writes value in little-endian at new sp.
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(&state->memory);
  @ requires ValidStack(state);
  @ requires state->regs.sp >= 8;
  @ requires NoCodeOverlap(&state->memory, state->regs.sp - 8, 8);
  @ requires InBounds(&state->memory, state->regs.sp - 8, 8);
  @ assigns  state->regs.sp,
  @          state->memory.data[state->regs.sp - 8 .. state->regs.sp - 1];
  @ ensures  state->regs.sp == \old(state->regs.sp) - 8;
  @ ensures  ValidStack(state);
  @ ensures  ValidMemory(&state->memory);
  @ ensures  state->memory.data[state->regs.sp]     == (uint8_t)(value);
  @ ensures  state->memory.data[state->regs.sp + 1] == (uint8_t)(value >> 8);
  @ ensures  state->memory.data[state->regs.sp + 2] == (uint8_t)(value >> 16);
  @ ensures  state->memory.data[state->regs.sp + 3] == (uint8_t)(value >> 24);
  @ ensures  state->memory.data[state->regs.sp + 4] == (uint8_t)(value >> 32);
  @ ensures  state->memory.data[state->regs.sp + 5] == (uint8_t)(value >> 40);
  @ ensures  state->memory.data[state->regs.sp + 6] == (uint8_t)(value >> 48);
  @ ensures  state->memory.data[state->regs.sp + 7] == (uint8_t)(value >> 56);
  @*/
void exec_push(MachineState *state, uint64_t value);

/* -------------------------------------------------------------------------
 * exec_pop  —  POP 8 bytes from stack into *out
 *   Reads little-endian 64-bit word at current sp, then increments sp by 8.
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(&state->memory);
  @ requires ValidStack(state);
  @ requires state->regs.sp + 8 <= state->memory.size;
  @ requires NoCodeOverlap(&state->memory, state->regs.sp, 8);
  @ requires InBounds(&state->memory, state->regs.sp, 8);
  @ requires \valid(out);
  @ assigns  state->regs.sp, *out;
  @ ensures  state->regs.sp == \old(state->regs.sp) + 8;
  @ ensures  ValidStack(state);
  @ ensures  *out ==
  @   (uint64_t)(
  @     (uint64_t)\old(state->memory.data[\old(state->regs.sp)])       |
  @     ((uint64_t)\old(state->memory.data[\old(state->regs.sp) + 1]) << 8)  |
  @     ((uint64_t)\old(state->memory.data[\old(state->regs.sp) + 2]) << 16) |
  @     ((uint64_t)\old(state->memory.data[\old(state->regs.sp) + 3]) << 24) |
  @     ((uint64_t)\old(state->memory.data[\old(state->regs.sp) + 4]) << 32) |
  @     ((uint64_t)\old(state->memory.data[\old(state->regs.sp) + 5]) << 40) |
  @     ((uint64_t)\old(state->memory.data[\old(state->regs.sp) + 6]) << 48) |
  @     ((uint64_t)\old(state->memory.data[\old(state->regs.sp) + 7]) << 56));
  @*/
void exec_pop(MachineState *state, uint64_t *out);

/* -------------------------------------------------------------------------
 * exec_call  —  CALL target
 *   Pushes the return address (the instruction after the CALL site), then
 *   sets pc = target.
 *   The caller computes return_addr = pc_after_fetch before calling.
 * --------------------------------------------------------------------- */

/*@ requires ValidMemory(&state->memory);
  @ requires ValidStack(state);
  @ requires state->regs.sp >= 8;
  @ requires NoCodeOverlap(&state->memory, state->regs.sp - 8, 8);
  @ requires InBounds(&state->memory, state->regs.sp - 8, 8);
  @ assigns  state->regs.sp,
  @          state->regs.pc,
  @          state->memory.data[state->regs.sp - 8 .. state->regs.sp - 1];
  @ ensures  state->regs.sp == \old(state->regs.sp) - 8;
  @ ensures  state->regs.pc == target;
  @ ensures  ValidStack(state);
  @ ensures  ValidMemory(&state->memory);
  @ // Return address stored in little-endian at new sp:
  @ ensures  state->memory.data[state->regs.sp]     == (uint8_t)(return_addr);
  @ ensures  state->memory.data[state->regs.sp + 1] == (uint8_t)(return_addr >> 8);
  @ ensures  state->memory.data[state->regs.sp + 2] == (uint8_t)(return_addr >> 16);
  @ ensures  state->memory.data[state->regs.sp + 3] == (uint8_t)(return_addr >> 24);
  @ ensures  state->memory.data[state->regs.sp + 4] == (uint8_t)(return_addr >> 32);
  @ ensures  state->memory.data[state->regs.sp + 5] == (uint8_t)(return_addr >> 40);
  @ ensures  state->memory.data[state->regs.sp + 6] == (uint8_t)(return_addr >> 48);
  @ ensures  state->memory.data[state->regs.sp + 7] == (uint8_t)(return_addr >> 56);
  @*/
void exec_call(MachineState *state, uint64_t target, uint64_t return_addr);

/* -------------------------------------------------------------------------
 * addr_of  —  signed displacement + unsigned base (wrapping semantics)
 *   Models addressing modes such as  [rN + imm16].
 *   The cast path (int64_t)base + disp uses 64-bit signed arithmetic whose
 *   result is reinterpreted as uint64_t, giving well-defined wrap-around.
 * --------------------------------------------------------------------- */

/*@ assigns  \nothing;
  @ ensures  \result == (uint64_t)((int64_t)base + disp);
  @*/
uint64_t addr_of(uint64_t base, int64_t disp);

#endif /* EXECUTION_STACK_H */
