.section .text
.globl step_kernel

# a0 = &state_in
# a1 = &message_in
# a2 = &state_out
# a3 = &status_out

step_kernel:
        lw t3,0(a0)         # state word
        lw t4,0(a1)         # message word

        # VALIDATE: message tag == 0xAB
        srli t0,t4,24
        addi t1,x0,0xAB
        bne t0,t1,.Linvalid

        # opcode = (message >> 16) & 0xFF
        srli s0,t4,16
        andi s0,s0,0xFF

        # delta = message & 0xFFFF
        slli t2,t4,16
        srli t2,t2,16

        # state tag = (state >> 16) & 0xFF
        srli t6,t3,16
        andi t6,t6,0xFF

        # Reject nonzero reserved state bits
        srli t0,t3,24
        bne t0,x0,.Linvalid

        # TRANSITION: state dispatch
        beq t6,x0,.Lrun
        addi t0,x0,1
        beq t6,t0,.Lfault
        addi t0,x0,2
        beq t6,t0,.Lrecov
        j .Linvalid

.Lrun:
        beq s0,x0,.Ladd
        addi t0,x0,1
        beq s0,t0,.Lsub
        addi t0,x0,2
        beq s0,t0,.Lreset
        addi t0,x0,3
        beq s0,t0,.Lto_recov
        j .Linvalid

.Ladd:
        slli t5,t3,16
        srli t5,t5,16       # counter = state & 0xFFFF
        add t5,t5,t2        # c + d
        lui t0,0x10         # t0 = 65536
        bgeu t5,t0,.Lfault_invalid
        addi t0,t0,-2       # t0 = 65534
        bgtu t5,t0,.Lfault_invalid
        j .Lrun_store

.Lsub:
        slli t5,t3,16
        srli t5,t5,16
        bltu t5,t2,.Lfault_invalid
        sub t5,t5,t2
        j .Lrun_store

.Lreset:
        addi t5,x0,0
        j .Lrun_store

.Lto_recov:
        slli t5,t3,16
        srli t5,t5,16
        addi t0,x0,2
        slli t0,t0,16
        or t3,t5,t0         # State counter RECOVER
        addi t1,x0,0
        j .Lstore

.Lrun_store:
        addi t3,t5,0        # state tag RUN is zero
        addi t1,x0,0
        j .Lstore

.Lfault:
        addi t0,x0,3
        bne s0,t0,.Lstay_fault
        addi t3,x0,0        # RECOVER: State 0 RUN
        addi t1,x0,1
        j .Lstore

.Lstay_fault:
        addi t3,x0,0x00010000  # State 0 FAULT
        addi t1,x0,1
        j .Lstore

.Lrecov:
        slli t5,t3,16
        srli t5,t5,16       # preserve counter
        addi t3,t5,0        # State counter RUN
        addi t1,x0,0
        j .Lstore

.Linvalid:
        addi t3,x0,0x00010000  # State 0 FAULT
        addi t1,x0,2
        j .Lstore

.Lfault_invalid:
        addi t3,x0,0x00010000  # State 0 FAULT
        addi t1,x0,2

.Lstore:
        sw t3,0(a2)
        sw t1,0(a3)
        jalr x0,0(ra)
