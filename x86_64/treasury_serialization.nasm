; Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
; SPDX-License-Identifier: AGPL-3.0-or-later
; DEED-089: Sovereign Treasury Engine — NASM WORM Serialization Bridge
; Low-level serialization, fixed-offset byte shifting, hardware FFI dispatch.

bits 64
default rel

section .data
    WORM_MAGIC db 'WORM'
    ALIGN_PADDING times 12 db 0

section .bss
    resb 4220 ; WormBlock buffer space (header + 4096 payload)

section .text
    global serialize_treasury_record
    global invoke_chisel_worm_accelerator
    extern chisel_hardware_seal_ffi

; ---------------------------------------------------------------------
; 1. Serialize Treasury Record (replaces PL/I SERIALIZE_ENTRY)
; Inputs: RDI = pointer to treasury entry, RSI = pointer to destination buffer
; ---------------------------------------------------------------------
serialize_treasury_record:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi ; rbx = source treasury entry base
    mov r12, rsi ; r12 = destination payload pointer

    ; Copy TX_ID (36 bytes at offset 0)
    mov rcx, 36
    rep movsb

    ; Copy TX_TS (8 bytes at offset 36)
    mov rcx, 8
    rep movsb

    ; Copy TX_SEQ (4 bytes at offset 44)
    mov rcx, 4
    rep movsb

    ; Copy SRC_ACCT (16 bytes at offset 48)
    mov rcx, 16
    rep movsb

    ; Copy DST_ACCT (16 bytes at offset 64)
    mov rcx, 16
    rep movsb

    ; Copy AMOUNT (8 bytes at offset 80)
    mov rcx, 8
    rep movsb

    ; Copy CCY (3 bytes at offset 88)
    mov rcx, 3
    rep movsb

    ; Copy FLAGS (1 byte at offset 91)
    mov al, byte [rbx + 91]
    mov byte [r12], al

    pop r12
    pop rbx
    pop rbp
    ret

; ---------------------------------------------------------------------
; 2. FFI Dispatcher to Chisel Hardware Core
; Inputs: RDI = block buffer pointer, RSI = block size
; ---------------------------------------------------------------------
invoke_chisel_worm_accelerator:
    push rbp
    mov rbp, rsp

    sub rsp, 8
    call chisel_hardware_seal_ffi
    add rsp, 8

    pop rbp
    ret
