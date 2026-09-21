/* SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0 */
/*
 * crc32_dylan.S -- ARM64 (AAPCS64) CRC32 implementation
 *
 * IEEE polynomial 0xEDB88320 (reflected / LSB-first).
 * Init XOR 0xFFFFFFFF, final XOR 0xFFFFFFFF.
 * Byte-at-a-time reflected loop.
 *
 * Calling convention (AAPCS64):
 *   x0 = pointer to buffer
 *   x1 = length in bytes
 *   Returns CRC32 in w0
 *
 * This is the hot path for task_done checksum -- must match :erlang.crc32
 */

        .text
        .align  4
        .globl  _crc32_asm

_crc32_asm:
        /* w2 = crc = 0xFFFFFFFF */
        mov     w2, #0xFFFFFFFF

        /* If length is zero, skip straight to finalize */
        cbz     x1, .Lfinalize

.Lbyte_loop:
        /* Load one byte from [x0], post-increment */
        ldrb    w3, [x0], #1

        /* crc ^= byte */
        eor     w2, w2, w3

        /* 8 iterations: reflected bit loop */
        mov     w4, #8

.Lbit_loop:
        /* test LSB of crc */
        tst     w2, #1

        /* tmp = crc >> 1 */
        lsr     w5, w2, #1

        /* Load the polynomial 0xEDB88320 into w6.
         * ARM64 immediate encoding cannot represent this value directly,
         * so we build it from two halves with movz + movk.
         *   low  16 bits: 0x8320
         *   next 16 bits: 0xEDB8
         */
        movz    w6, #0x8320
        movk    w6, #0xEDB8, lsl #16

        /* poly_xor = (crc >> 1) ^ 0xEDB88320 */
        eor     w6, w5, w6

        /* crc = (crc & 1) ? poly_xor : (crc >> 1) */
        csel    w2, w6, w5, ne

        /* decrement bit counter */
        subs    w4, w4, #1
        b.ne    .Lbit_loop

        /* decrement byte counter */
        subs    x1, x1, #1
        b.ne    .Lbyte_loop

.Lfinalize:
        /* return crc ^ 0xFFFFFFFF (bitwise NOT) */
        mvn     w0, w2
        ret
