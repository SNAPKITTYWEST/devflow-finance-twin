; a0=prev_state a1=&word a2=len -> a0=new_state
transit:
        mv t0,a0
        beqz a2,.tdone
.tloop: lb t1,0(a1)
        bgez t1,1f
        neg t1,t1
1:      li t2,3
        mul t0,t0,t2
        add t0,t0,t1
        addi a1,a1,1
        addi a2,a2,-1
        bnez a2,.tloop
.tdone: mv a0,t0
        ret

; a0=prev_seal a1=&Entry -> a0=new_seal
seal:
        lh t0,0(a1)           ; n
        slli t0,t0,16
        xor a0,a0,t0
        lhu t0,2(a1)          ; prev
        xor a0,a0,t0
        lhu t0,4(a1)          ; state
        xor a0,a0,t0
        lbu t1,7(a1)          ; len
        addi a1,a1,8          ; &word
        beqz t1,.sdone
.sloop: lb t0,0(a1)
        slli a0,a0,5
        xor a0,a0,t0
        addi a1,a1,1
        addi t1,t1,-1
        bnez t1,.sloop
.sdone: ret
