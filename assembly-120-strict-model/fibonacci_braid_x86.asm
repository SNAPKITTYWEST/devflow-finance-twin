; assembly.asm — Bounded machine representation of Fibonacci Braid Ledger
; Target: x86-64 System V, 64-bit signed, no silent overflow (JO checks)
; Corresponds to BQN ↔ Liquid Haskell

%define MAX_IDX   92
%define MAX_WORD  256
%define STRANDS   8
%define GEN_MAX   7
%define INT_MAX   9223372036854775807
%define INT_MIN   0x8000000000000000

section .data
fib_table: dq 0, 1
init_state: dq 0,0,0,0,0,0,0,0

section .text
global fib_array, braid_from_fib, reduce_word, transition, ledger_seal

; fib_array: rdi=n, rsi=out_ptr → len or error
fib_array:
    cmp rdi, 0
    jl .neg_err
    cmp rdi, MAX_IDX
    jg .max_err
    mov rax, [fib_table]
    mov [rsi], rax
    cmp rdi, 0
    je .done1
    mov rax, [fib_table+8]
    mov [rsi+8], rax
    cmp rdi, 1
    je .done2
    mov rcx, 2
    lea r8, [rsi]
.loop:
    cmp rcx, rdi
    jg .done
    mov r9, [r8+rcx*8-8]
    mov r10,[r8+rcx*8-16]
    mov rax, r9
    add rax, r10
    jo .ovf_err
    mov [r8+rcx*8], rax
    inc rcx
    jmp .loop
.done:
    mov rax, rdi
    inc rax
    ret
.done1: mov rax,1
    ret
.done2: mov rax,2
    ret
.neg_err: mov rax, -1
    ret
.max_err: mov rax, -2
    ret
.ovf_err: mov rax, -3
    ret

; braid_from_fib: rdi=n, rsi=out_word_ptr, rdx=out_len_ptr
braid_from_fib:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rax, [fib_table + r12*8]
    mov r13, rax
    mov rax, r12
    and rax, 7
    inc rax
    mov rbx, rax
    mov [rdx], rbx
    xor rcx, rcx
.jloop:
    cmp rcx, rbx
    jge .jdone
    mov rax, rcx
    imul rax, 13
    add rax, r13
    mov r9, r12
    imul r9, 7
    add rax, r9
    mov r9, 7
    cqo
    idiv r9
    mov rax, rdx
    add rax, 1
    mov r10, rax
    mov rax, r13
    add rax, rcx
    add rax, r12
    and rax, 1
    cmp rax, 0
    je .even
    mov rax, -1
    jmp .sign
.even: mov rax, 1
.sign:
    imul rax, r10
    mov [rsi + rcx*8], rax
    inc rcx
    jmp .jloop
.jdone:
    pop r13
    pop r12
    pop rbx
    ret

; reduce_word: rdi=in_ptr, rsi=len, rdx=out_ptr, rcx=out_len_ptr
reduce_word:
    push rbx
    push r12
    push r13
    xor r12, r12
    xor rbx, rbx
.rloop:
    cmp rbx, rsi
    jge .rdone
    mov r13, [rdi + rbx*8]
    cmp r12, 0
    je .push
    mov rax, [rdx + r12*8 -8]
    neg rax
    cmp rax, r13
    jne .push
    dec r12
    jmp .next
.push:
    mov [rdx + r12*8], r13
    inc r12
.next:
    inc rbx
    jmp .rloop
.rdone:
    mov [rcx], r12
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

; transition: rdi=state_ptr (8 qwords), rsi=word_ptr, rdx=word_len
transition:
    xor rcx, rcx
.tloop:
    cmp rcx, rdx
    jge .tdone
    mov rax, [rsi + rcx*8]
    mov r9, rax
    sar r9, 63
    xor rax, r9
    sub rax, r9
    dec rax
    cmp rax, 7
    jae .skip
    mov r10, [rdi + rax*8]
    mov r11, [rsi + rcx*8]
    cmp r11, 0
    jg .pos
    dec r10
    jmp .store
.pos: inc r10
.store:
    mov [rdi + rax*8], r10
.skip:
    inc rcx
    jmp .tloop
.tdone: ret

; ledger_seal: rdi=n, rsi=val, rdx=word_ptr, rcx=word_len, r8=state_ptr
ledger_seal:
    mov rax, rdi
    imul rax, 1000003
    jo .ovf
    add rax, rsi
    jo .ovf
    xor r9, r9
    xor r10, r10
.whash:
    cmp r9, rcx
    jge .whash_done
    mov r11, [rdx + r9*8]
    imul r11, r9
    add r10, r11
    jo .ovf
    inc r9
    jmp .whash
.whash_done:
    add rax, r10
    jo .ovf
    xor r9, r9
    mov rcx, 8
.shash:
    cmp r9, rcx
    jge .shash_done
    mov r11, [r8 + r9*8]
    mov r10, r9
    inc r10
    imul r11, r10
    add rax, r11
    jo .ovf
    inc r9
    jmp .shash
.shash_done:
    ret
.ovf: mov rax, -3
    ret
