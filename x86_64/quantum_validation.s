.global validate_quantum_output
.global mix_quantum_entropy
.text

validate_quantum_output:
    movl (%rdi), %eax
    movl $9500, %ecx
    cmpl %ecx, %eax
    jl .L_reject
    movl $10000, %ecx
    cmpl %ecx, %eax
    jg .L_reject
    movl $1, %eax
    ret
.L_reject:
    xorl %eax, %eax
    ret

mix_quantum_entropy:
    movl $0x534F5652, %eax
    xorq %rcx, %rcx
.L_entropy_loop:
    cmpq %rsi, %rcx
    jge .L_entropy_done
    movzbl (%rdi,%rcx), %edx
    xorl %edx, %eax
    incq %rcx
    jmp .L_entropy_loop
.L_entropy_done:
    ret
