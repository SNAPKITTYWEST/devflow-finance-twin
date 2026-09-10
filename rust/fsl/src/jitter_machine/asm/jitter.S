# Recursive Jitter Machine — abstract / portable assembly sketch
# Not linked against any libc. Register convention is local to this file.
#
# r0 = base of kernel array (pointer)
# r1 = scratch
# r2 = scratch
# r3 = PC index
# r4 = DEPTH
# r5 = SEED
#
# This is a readable kernel-style listing. Host must map load/store
# to the flat u32 array defined in KERNEL_ARRAY.md.

.equ OFF_MAGIC, 0
.equ OFF_VER, 4
.equ OFF_N, 8
.equ OFF_DEPTH, 12
.equ OFF_MAXDEPTH, 16
.equ OFF_SEED, 20
.equ OFF_PC, 24
.equ OFF_FLAGS, 28
.equ OFF_STATE, 32

.equ FLAG_HALT, 1
.equ FLAG_FAIL, 2
.equ FLAG_FUSED, 4

.equ OP_NOP, 0x00
.equ OP_LOADK, 0x01
.equ OP_ADD, 0x02
.equ OP_JITTER, 0x05
.equ OP_RECUR, 0x06
.equ OP_RET, 0x07
.equ OP_ASSERT, 0x08
.equ OP_FUSE, 0x09
.equ OP_HALT, 0x0A

# entry: r0 = kernel base
.global jitter_run
jitter_run:
    # load DEPTH, SEED, PC
    ldr r4, [r0, #OFF_DEPTH]
    ldr r5, [r0, #OFF_SEED]
    ldr r3, [r0, #OFF_PC]

fetch:
    # if FLAGS & HALT -> return
    ldr r1, [r0, #OFF_FLAGS]
    tst r1, #FLAG_HALT
    bne done

    # load instruction word at CODE[PC]
    # decode op, a, b, c
    # dispatch...

    add r3, r3, #1
    str r3, [r0, #OFF_PC]
    str r5, [r0, #OFF_SEED]
    b fetch

done:
    str r4, [r0, #OFF_DEPTH]
    str r5, [r0, #OFF_SEED]
    bx lr
