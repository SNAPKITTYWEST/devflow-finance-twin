; fib_braid.asm — Dense x86-64 implementation
; BQN ↔ Liquid Haskell ↔ Assembly correspondence
; ABI: System V AMD64

section .data
    MAX_FIB equ 90
    MAX_GEN equ 4
    MAX_WORD equ 64
    SEAL_MOD equ 0x100000000

align 8
fib_table:
    dq 0,1,1,2,3,5,8,13,21,34
    dq 55,89,144,233,377,610,987,1597,2584,4181
    dq 6765,10946,17711,28657,46368,75025,121393,196418,317811,514229
    dq 832040,1346269,2178309,3524578,5702887,9227465,14930352,24157817,39088169,63245986
    dq 102334155,165580141,267914296,433494437,701408733,1134903170,1836311903,2971215073
    dq 4807526976,7778742049,12586269025,20365011074,32951280099,53316291173,86267571272
    dq 139583862445,225851433717,365435296162,591286729879,956722026041,1548008755920
    dq 2504730781961,4052739537881,6557470319842,10610209857723,17167680177565
    dq 27777890035288,44945570212853,72723460248141,117669030460994,190392490709135
    dq 308061521170129,498454011879264,806515533049393,1304969544928657
    dq 2111485077978050,3416454622906707,5527939700884757,8944394323791464
    dq 14472334024676221,23416728348467685,37889062373143906,61305790721611591
    dq 99194853094755497,160500643816367088,259695496911122585,420196140727489673
    dq 679891637638612258,1100087778366101931,1779979416004714189,2880067194370816120

section .text
global fib, braid_from_fib, reduce_word, transition, valid_word

; int64_t fib(uint32_t n)
fib:
    cmp edi, MAX_FIB
    ja .overflow
    mov rax, [fib_table + rdi*8]
    ret
.overflow:
    xor eax, eax
    ret

; size_t braid_from_fib(uint32_t n, int32_t *out)
braid_from_fib:
    push rbx
    push r12
    mov r12, rsi
    call fib
    mov rcx, rax
    cmp rcx, MAX_WORD
    jbe .len_ok
    mov rcx, MAX_WORD
.len_ok:
    test rcx, rcx
    jz .empty
    xor ebx, ebx
.loop:
    mov eax, ebx
    and eax, 3
    inc eax
    test ebx, 1
    jz .pos
    neg eax
.pos:
    mov [r12 + rbx*4], eax
    inc ebx
    cmp ebx, ecx
    jb .loop
.empty:
    mov rax, rcx
    pop r12
    pop rbx
    ret

; size_t reduce_word(const int32_t *w, size_t len, int32_t *out)
reduce_word:
    xor ecx, ecx
    xor r8, r8
    test rsi, rsi
    jz .done
.loop:
    mov eax, [rdi + r8*4]
    test ecx, ecx
    jz .push
    mov r9d, [rdx + rcx*4 - 4]
    neg r9d
    cmp r9d, eax
    jne .push
    dec ecx
    jmp .next
.push:
    mov [rdx + rcx*4], eax
    inc ecx
.next:
    inc r8
    cmp r8, rsi
    jb .loop
.done:
    mov rax, rcx
    ret

; int valid_word(const int32_t *w, size_t len)
valid_word:
    cmp rsi, MAX_WORD
    ja .bad
    xor ecx, ecx
.vloop:
    cmp rcx, rsi
    jae .good
    mov eax, [rdi + rcx*4]
    mov r8d, eax
    neg r8d
    cmovs r8d, eax
    cmp r8d, 1
    jl .bad
    cmp r8d, MAX_GEN
    jg .bad
    inc ecx
    jmp .vloop
.good:
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

; void transition(State *s, const int32_t *w, size_t len)
transition:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx

    mov rdi, r13
    mov rsi, rbx
    call valid_word
    test eax, eax
    jz .fail

    mov eax, [r12]
    inc eax
    cmp eax, MAX_FIB
    ja .fail
    mov [r12], eax

    mov [r12+4], ebx

    sub rsp, MAX_WORD*4
    mov rdi, r13
    mov rsi, rbx
    mov rdx, rsp
    call reduce_word
    mov [r12+8], eax

    mov edi, [r12]
    dec edi
    call fib
    mov r8, rax

    xor ecx, ecx
    xor r9, r9
.sumloop:
    cmp rcx, rbx
    jae .sumdone
    mov eax, [r13 + rcx*4]
    cdqe
    mov r10, rax
    neg r10
    cmovs r10, rax
    add r9, r10
    inc rcx
    jmp .sumloop
.sumdone:
    imul r9, r8
    mov rax, [r12+16]
    add rax, r9
    mov rcx, SEAL_MOD
    xor rdx, rdx
    div rcx
    mov [r12+16], rdx

    xor r9, r9
    mov ecx, [r12+8]
    xor r8, r8
.chkloop:
    cmp r8, rcx
    jae .chkdone
    movsx rax, dword [rsp + r8*4]
    add r9, rax
    inc r8
    jmp .chkloop
.chkdone:
    xor [r12+24], r9

    add rsp, MAX_WORD*4
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    pop r13
    pop r12
    pop rbx
    ret
