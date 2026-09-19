/*
 * TLM JXCL ISA — Execution stack stub implementations
 * Frama-C / ACSL formal verification target  (Frama-C 26+)
 */

#include "execution_stack.h"
#include <stdint.h>

/* -------------------------------------------------------------------------
 * exec_push
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
void exec_push(MachineState *state, uint64_t value)
{
    state->regs.sp -= 8;

    state->memory.data[state->regs.sp]     = (uint8_t)(value);
    state->memory.data[state->regs.sp + 1] = (uint8_t)(value >> 8);
    state->memory.data[state->regs.sp + 2] = (uint8_t)(value >> 16);
    state->memory.data[state->regs.sp + 3] = (uint8_t)(value >> 24);
    state->memory.data[state->regs.sp + 4] = (uint8_t)(value >> 32);
    state->memory.data[state->regs.sp + 5] = (uint8_t)(value >> 40);
    state->memory.data[state->regs.sp + 6] = (uint8_t)(value >> 48);
    state->memory.data[state->regs.sp + 7] = (uint8_t)(value >> 56);
}

/* -------------------------------------------------------------------------
 * exec_pop
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
void exec_pop(MachineState *state, uint64_t *out)
{
    uint64_t sp = state->regs.sp;

    *out = (uint64_t)((uint64_t)state->memory.data[sp]       |
                      ((uint64_t)state->memory.data[sp + 1] << 8)  |
                      ((uint64_t)state->memory.data[sp + 2] << 16) |
                      ((uint64_t)state->memory.data[sp + 3] << 24) |
                      ((uint64_t)state->memory.data[sp + 4] << 32) |
                      ((uint64_t)state->memory.data[sp + 5] << 40) |
                      ((uint64_t)state->memory.data[sp + 6] << 48) |
                      ((uint64_t)state->memory.data[sp + 7] << 56));

    state->regs.sp += 8;
}

/* -------------------------------------------------------------------------
 * exec_call
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
  @ ensures  state->memory.data[state->regs.sp]     == (uint8_t)(return_addr);
  @ ensures  state->memory.data[state->regs.sp + 1] == (uint8_t)(return_addr >> 8);
  @ ensures  state->memory.data[state->regs.sp + 2] == (uint8_t)(return_addr >> 16);
  @ ensures  state->memory.data[state->regs.sp + 3] == (uint8_t)(return_addr >> 24);
  @ ensures  state->memory.data[state->regs.sp + 4] == (uint8_t)(return_addr >> 32);
  @ ensures  state->memory.data[state->regs.sp + 5] == (uint8_t)(return_addr >> 40);
  @ ensures  state->memory.data[state->regs.sp + 6] == (uint8_t)(return_addr >> 48);
  @ ensures  state->memory.data[state->regs.sp + 7] == (uint8_t)(return_addr >> 56);
  @*/
void exec_call(MachineState *state, uint64_t target, uint64_t return_addr)
{
    /* Push return address */
    state->regs.sp -= 8;

    state->memory.data[state->regs.sp]     = (uint8_t)(return_addr);
    state->memory.data[state->regs.sp + 1] = (uint8_t)(return_addr >> 8);
    state->memory.data[state->regs.sp + 2] = (uint8_t)(return_addr >> 16);
    state->memory.data[state->regs.sp + 3] = (uint8_t)(return_addr >> 24);
    state->memory.data[state->regs.sp + 4] = (uint8_t)(return_addr >> 32);
    state->memory.data[state->regs.sp + 5] = (uint8_t)(return_addr >> 40);
    state->memory.data[state->regs.sp + 6] = (uint8_t)(return_addr >> 48);
    state->memory.data[state->regs.sp + 7] = (uint8_t)(return_addr >> 56);

    /* Jump */
    state->regs.pc = target;
}

/* -------------------------------------------------------------------------
 * addr_of
 * --------------------------------------------------------------------- */

/*@ assigns  \nothing;
  @ ensures  \result == (uint64_t)((int64_t)base + disp);
  @*/
uint64_t addr_of(uint64_t base, int64_t disp)
{
    return (uint64_t)((int64_t)base + disp);
}
