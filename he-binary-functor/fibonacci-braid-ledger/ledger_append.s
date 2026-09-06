; ledger_append pseudo-asm sketch
; r0 = ledger*, r1 = n, r2 = op, r3 = word*
; returns err in r0
ledger_append:
        lw t0, nent(r0)
        li t1, NENT
        bgeu t0, t1, full

        li t1, MAXN
        bgtu r1, t1, bad_idx

        slli t2, t0, 6          ; rough size
        add t2, r0, t2
        addi t2, t2, 4          ; skip header

        sb r1, 0(t2)            ; n
        sb r2, 1(t2)            ; op

        beqz t0, prev0
        ; load previous state ...
prev0:  sw zero, 4(t2)

        ; copy/reduce word (loop MAXW)
        ; apply transition (mix loop)
        ; seal = mix(head, fields)
        ; store seal, bump nent, update head

        li r0, OK
        ret
full:   li r0, FULL
        ret
bad_idx:
        li r0, BAD_IDX
        ret
