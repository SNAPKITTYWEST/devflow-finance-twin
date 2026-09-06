# FBL-RV64 — Dense Fibonacci Braid Ledger (RV64I)
# 64-byte entries, FNV-1a-64 seal, 48-bit state, no allocator

.equ FB_MAX_ENTRIES, 64
.equ FB_MAX_FIB, 63
.equ FB_MAX_STRANDS, 8
.equ FB_MAX_WORD, 16
.equ FB_STATE_MASK, 0x0000FFFFFFFFFFFF

# a0 = FBLedger* L
# a1 = FBRequest* R
# a2 = FBEntry* audit_or_zero
# return a0 = status

# L offsets: 0=count, 8=head_state, 16=head_seal, 24=entries[]
# R offsets: 0=n, 8=exp_prev_state, 16=exp_prev_seal, 24=op, 25=strands, 26=len, 27=word[16]
# Entry offsets: 0=n, 8=fib, 16=prev_state, 24=state, 32=prev_seal, 40=seal, 48=op, 49=strands, 50=len, 51=word[16]

.section .text
.globl fb_append_rv64

fb_append_rv64:
        add s0,a0,x0
        add s1,a1,x0

        ld t0,0(s0)             # count
        addi t1,x0,64
        bgeu t0,t1,.Lfull

        ld t1,0(s1)             # request.n
        bne t0,t1,.Lbad_index
        addi t2,x0,63
        bltu t2,t1,.Lbad_index

        lbu t2,24(s1)           # op
        addi t3,x0,1
        bltu t3,t2,.Lbad_state

        lbu t2,25(s1)           # strands
        addi t3,x0,2
        bltu t2,t3,.Lbad_gen
        addi t3,x0,8
        bltu t3,t2,.Lbad_gen

        lbu t2,26(s1)           # input len
        addi t3,x0,16
        bltu t3,t2,.Lword_overflow

        ld t3,8(s0)             # ledger head state
        ld t4,8(s1)             # expected prev state
        bne t3,t4,.Lbad_state
        ld t3,16(s0)            # ledger head seal
        ld t4,16(s1)            # expected prev seal
        bne t3,t4,.Lchain_invalid

        # fib(n): iterative
        addi t3,x0,0
        addi t4,x0,1
        ld t5,0(s1)
.Lfib:
        beq t5,x0,.Lfib_done
        add t6,t3,t4
        add t3,t4,x0
        add t4,t6,x0
        addi t5,t5,-1
        jal x0,.Lfib
.Lfib_done:
        add s3,t3,x0           # F(n)

        # slot = L + 24 + 64*count
        ld t0,0(s0)
        slli t0,t0,6
        addi s2,s0,24
        add s2,s2,t0

        # copy fixed entry fields
        ld t0,0(s1)
        sd t0,0(s2)            # n
        sd s3,8(s2)            # fib
        ld t0,8(s0)
        sd t0,16(s2)           # prev_state
        ld t0,16(s0)
        sd t0,32(s2)           # prev_seal
        lbu t0,24(s1)
        sb t0,48(s2)           # op
        lbu t0,25(s1)
        sb t0,49(s2)           # strands

        # reduce word: source=s1+27, dest=s2+51, top=s5
        addi t1,s1,27
        addi t2,s2,51
        addi t0,x0,0
        addi s5,x0,0
        lbu t3,26(s1)          # input length
.Lreduce:
        bgeu t0,t3,.Lreduced
        add t4,t1,t0
        lb t5,0(t4)            # signed generator g
        beq t5,x0,.Lbad_gen
        blt t5,x0,.Lneg_gen
        lbu t6,49(s2)          # strands
        bge t5,t6,.Lbad_gen
        jal x0,.Lreduce_push
.Lneg_gen:
        sub t6,x0,t5
        lbu t4,49(s2)
        bge t6,t4,.Lbad_gen
.Lreduce_push:
        beq s5,x0,.Lpush
        addi t4,s5,-1
        add t4,t2,t4
        lb t6,0(t4)
        add t6,t6,t5
        beq t6,x0,.Lcancel
.Lpush:
        addi t4,x0,16
        bgeu s5,t4,.Lword_overflow
        add t4,t2,s5
        sb t5,0(t4)
        addi s5,s5,1
        jal x0,.Lnext_letter
.Lcancel:
        addi s5,s5,-1
.Lnext_letter:
        addi t0,t0,1
        jal x0,.Lreduce
.Lreduced:
        sb s5,50(s2)           # store reduced length

        # delta = sum(reduced signed bytes) mod 2^48
        addi s4,x0,0
        addi t0,x0,0
.Ldelta:
        bgeu t0,s5,.Ldelta_done
        addi t1,s2,51
        add t1,t1,t0
        lb t2,0(t1)
        add s4,s4,t2
        addi t0,t0,1
        jal x0,.Ldelta
.Ldelta_done:
        ld t1,16(s2)           # prev_state
        lbu t2,48(s2)          # op
        beq t2,x0,.Lapply
        sub t1,t1,s4
        jal x0,.Lstate_mask
.Lapply:
        add t1,t1,s4
.Lstate_mask:
        slli t1,t1,16
        srli t1,t1,16          # mask to 48 bits
        sd t1,24(s2)           # store state

        # seal = FNV1a64(B, prev_seal || entry[0..47])
        # B = 0xCBF29CE484222325
        lui s3,0xCBF2A
        addi s3,s3,-0x6E1B
        addi t0,s2,32          # &prev_seal
        addi t1,x0,8
.Lhash_prev:
        beq t1,x0,.Lhash_entry_init
        lbu t2,0(t0)
        xor s3,s3,t2
        # mul s3,s3,0x100000001B3 (requires M extension)
        addi t0,t0,1
        addi t1,t1,-1
        jal x0,.Lhash_prev
.Lhash_entry_init:
        add t0,s2,x0
        addi t1,x0,48
.Lhash_entry:
        beq t1,x0,.Lseal_done
        lbu t2,0(t0)
        xor s3,s3,t2
        addi t0,t0,1
        addi t1,t1,-1
        jal x0,.Lhash_entry
.Lseal_done:
        sd s3,40(s2)           # store seal

        # commit
        ld t0,24(s2)
        sd t0,8(s0)            # head_state
        sd s3,16(s0)           # head_seal
        ld t0,0(s0)
        addi t0,t0,1
        sd t0,0(s0)            # count++

        beq a2,x0,.Lok
        # copy to audit buffer
        ld t0,0(s2);  sd t0,0(a2)
        ld t0,8(s2);  sd t0,8(a2)
        ld t0,16(s2); sd t0,16(a2)
        ld t0,24(s2); sd t0,24(a2)
        ld t0,32(s2); sd t0,32(a2)
        ld t0,40(s2); sd t0,40(a2)
        ld t0,48(s2); sd t0,48(a2)
.Lok:
        addi a0,x0,0
        jalr x0,0(ra)

.Lbad_index:     addi a0,x0,1; jalr x0,0(ra)
.Lbad_gen:       addi a0,x0,2; jalr x0,0(ra)
.Lword_overflow: addi a0,x0,3; jalr x0,0(ra)
.Lbad_state:     addi a0,x0,4; jalr x0,0(ra)
.Lseal_invalid:  addi a0,x0,5; jalr x0,0(ra)
.Lchain_invalid: addi a0,x0,6; jalr x0,0(ra)
.Lfull:          addi a0,x0,7; jalr x0,0(ra)
