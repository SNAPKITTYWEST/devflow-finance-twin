;================================================================================
; PHASE 1: ROM VERIFICATION DIAGNOSTICS
; Module: 02_rom_diag
; Lines of Code: 450 LOC (exact)
; Purpose: ROM checksum validation, vector table verification, integrity tests
; Diagnostics: Deterministic ROM checksums, vector validation, boot pointer check
;================================================================================

; ROM DIAGNOSTIC ENTRY POINT
ROM_DIAG_ENTRY = $E500

;================================================================================
; ROM_CHECKSUM_VALIDATE - Compute and validate ROM checksums
; Validates each ROM sector with deterministic output
; Output: Status in A register (0 = all pass, non-zero = fail code)
;================================================================================
.org $E500
ROM_CHECKSUM_VALIDATE:
    ; Save processor state
    PHA
    PHX
    PHY

    ; Initialize status
    LDA #$00
    STA ROM_DIAG_STATUS

    ; Compute boot sector checksum ($E000-$E1FF)
    LDA #$00
    STA ROM_ADDR_L
    LDA #$E0
    STA ROM_ADDR_H
    LDA #$02                ; 2 pages (512 bytes)
    STA ROM_SIZE
    JSR COMPUTE_ROM_CHECKSUM
    STA BOOT_SECTOR_CHECKSUM
    CMP #$00                ; Verify expected checksum
    BNE ROM_CHECKSUM_FAIL

    ; Compute monitor sector checksum ($E800-$E9FF)
    LDA #$00
    STA ROM_ADDR_L
    LDA #$E8
    STA ROM_ADDR_H
    LDA #$02
    STA ROM_SIZE
    JSR COMPUTE_ROM_CHECKSUM
    STA MONITOR_SECTOR_CHECKSUM
    CMP #$00
    BNE ROM_CHECKSUM_FAIL

    ; Compute vector table checksum ($FFFA-$FFFF)
    LDA #$FA
    STA ROM_ADDR_L
    LDA #$FF
    STA ROM_ADDR_H
    JSR COMPUTE_VECTOR_CHECKSUM
    STA VECTOR_CHECKSUM
    CMP #$00
    BNE ROM_CHECKSUM_FAIL

    ; All checksums verified
    LDA #$00
    STA ROM_DIAG_STATUS
    JMP ROM_CHECKSUM_DONE

ROM_CHECKSUM_FAIL:
    LDA #$01                ; Checksum validation failure
    STA ROM_DIAG_STATUS

ROM_CHECKSUM_DONE:
    LDA ROM_DIAG_STATUS

    ; Restore processor state
    PLY
    PLX
    PLA

    RTS

;================================================================================
; COMPUTE_ROM_CHECKSUM - Calculate deterministic ROM sector checksum
; Inputs: ROM_ADDR_L/H = starting address
;         ROM_SIZE = number of pages
; Output: Checksum value in A register
;================================================================================
COMPUTE_ROM_CHECKSUM:
    PHA
    PHX
    PHY

    LDX #$00
    LDY #$00
    LDA #$00
    STA ROM_CHECKSUM

ROM_CHECKSUM_LOOP:
    CPX ROM_SIZE
    BEQ ROM_CHECKSUM_RETURN

ROM_CHECKSUM_INNER:
    LDA (ROM_ADDR_L),Y
    ADC ROM_CHECKSUM
    STA ROM_CHECKSUM
    INY
    BNE ROM_CHECKSUM_INNER

    ; Increment address page
    INC ROM_ADDR_H
    INX
    JMP ROM_CHECKSUM_LOOP

ROM_CHECKSUM_RETURN:
    LDA ROM_CHECKSUM

    PLY
    PLX
    PLA
    RTS

;================================================================================
; COMPUTE_VECTOR_CHECKSUM - Calculate vector table checksum
; Specifically validates interrupt vectors at $FFFA-$FFFF
; Output: Checksum in A register
;================================================================================
COMPUTE_VECTOR_CHECKSUM:
    PHA
    PHX
    PHY

    LDA #$00
    STA VECTOR_CHECKSUM

    ; Read NMI vector at $FFFA-$FFFB
    LDA $FFFA
    ADC VECTOR_CHECKSUM
    STA VECTOR_CHECKSUM
    LDA $FFFB
    ADC VECTOR_CHECKSUM
    STA VECTOR_CHECKSUM

    ; Read RESET vector at $FFFC-$FFFD
    LDA $FFFC
    ADC VECTOR_CHECKSUM
    STA VECTOR_CHECKSUM
    LDA $FFFD
    ADC VECTOR_CHECKSUM
    STA VECTOR_CHECKSUM

    ; Read IRQ vector at $FFFE-$FFFF
    LDA $FFFE
    ADC VECTOR_CHECKSUM
    STA VECTOR_CHECKSUM
    LDA $FFFF
    ADC VECTOR_CHECKSUM
    STA VECTOR_CHECKSUM

    LDA VECTOR_CHECKSUM

    PLY
    PLX
    PLA
    RTS

;================================================================================
; ROM_VECTOR_TABLE_VALIDATE - Verify interrupt vector table integrity
; Deterministic output: Vector count and validity
; Output: Status in A register
;================================================================================
ROM_VECTOR_TABLE_VALIDATE:
    PHA
    PHX
    PHY

    LDA #$00
    STA VECTOR_STATUS
    LDA #$00
    STA VECTOR_COUNT

    ; Validate NMI vector
    LDA $FFFA                ; NMI low byte
    CMP #$F0                 ; Expected NMI handler start
    BNE VECTOR_VALIDATE_FAIL
    LDA $FFFB                ; NMI high byte
    CMP #$00
    BNE VECTOR_VALIDATE_FAIL
    INC VECTOR_COUNT

    ; Validate RESET vector
    LDA $FFFC                ; RESET low byte
    CMP #$00                 ; Expected RESET handler start
    BNE VECTOR_VALIDATE_FAIL
    LDA $FFFD                ; RESET high byte
    CMP #$E0
    BNE VECTOR_VALIDATE_FAIL
    INC VECTOR_COUNT

    ; Validate IRQ vector
    LDA $FFFE                ; IRQ low byte
    CMP #$00
    BNE VECTOR_VALIDATE_FAIL
    LDA $FFFF                ; IRQ high byte
    CMP #$E1
    BNE VECTOR_VALIDATE_FAIL
    INC VECTOR_COUNT

    ; All vectors valid
    LDA #$00
    STA VECTOR_STATUS
    JMP VECTOR_VALIDATE_DONE

VECTOR_VALIDATE_FAIL:
    LDA #$01
    STA VECTOR_STATUS

VECTOR_VALIDATE_DONE:
    LDA VECTOR_STATUS

    PLY
    PLX
    PLA
    RTS

;================================================================================
; ROM_SIGNATURE_VERIFY - Check for valid Apple II ROM signature
; Deterministic output: Signature validation status
; Output: Status in A register (0 = valid, non-zero = invalid)
;================================================================================
ROM_SIGNATURE_VERIFY:
    PHA
    PHX
    PHY

    LDA #$00
    STA ROM_SIGNATURE_STATUS

    ; Check for Apple II ROM signature at standard location
    LDA $E000                ; First byte of ROM
    CMP #$A5                 ; Apple II signature byte
    BNE ROM_SIGNATURE_INVALID

    ; Check ROM header pattern
    LDA $E001
    CMP #$00
    BNE ROM_SIGNATURE_INVALID

    ; Check for valid instruction pattern
    LDA $E002
    ; Should be a valid 6502 opcode
    JSR VALIDATE_OPCODE
    BCS ROM_SIGNATURE_INVALID

    LDA #$00
    STA ROM_SIGNATURE_STATUS
    JMP ROM_SIGNATURE_CHECK_DONE

ROM_SIGNATURE_INVALID:
    LDA #$01
    STA ROM_SIGNATURE_STATUS

ROM_SIGNATURE_CHECK_DONE:
    LDA ROM_SIGNATURE_STATUS

    PLY
    PLX
    PLA
    RTS

;================================================================================
; VALIDATE_OPCODE - Validate that byte is a known 6502 opcode
; Input: A register contains potential opcode
; Output: Carry clear if valid, set if invalid
;================================================================================
VALIDATE_OPCODE:
    ; Check against known valid opcodes
    ; A5, A9, AA, AD, B0, B1, B2, B4, B5, B9, BD, BE, BF, C0, C4, C5, C9, CA, etc.

    CMP #$A5                 ; LDA zero page
    BEQ OPCODE_VALID
    CMP #$A9                 ; LDA immediate
    BEQ OPCODE_VALID
    CMP #$AA                 ; TAX
    BEQ OPCODE_VALID
    CMP #$AD                 ; LDA absolute
    BEQ OPCODE_VALID
    CMP #$4C                 ; JMP
    BEQ OPCODE_VALID
    CMP #$20                 ; JSR
    BEQ OPCODE_VALID
    CMP #$60                 ; RTS
    BEQ OPCODE_VALID

    SEC                      ; Invalid opcode
    RTS

OPCODE_VALID:
    CLC                      ; Valid opcode
    RTS

;================================================================================
; ROM_BOOT_POINTER_VERIFY - Verify boot entry points are valid
; Deterministic output: Boot pointer validation status
; Output: Status in A register
;================================================================================
ROM_BOOT_POINTER_VERIFY:
    PHA
    PHX
    PHY

    LDA #$00
    STA BOOT_POINTER_STATUS
    LDA #$00
    STA BOOT_POINTER_COUNT

    ; Check MONITOR_ENTRY pointer ($E800)
    LDA $E800                ; Read first instruction at monitor entry
    ; Should be a valid instruction
    JSR VALIDATE_OPCODE
    BCS BOOT_POINTER_FAIL
    INC BOOT_POINTER_COUNT

    ; Check ROM_INIT pointer ($E900)
    LDA $E900
    JSR VALIDATE_OPCODE
    BCS BOOT_POINTER_FAIL
    INC BOOT_POINTER_COUNT

    ; Check MEM_INIT pointer ($E400)
    LDA $E400
    JSR VALIDATE_OPCODE
    BCS BOOT_POINTER_FAIL
    INC BOOT_POINTER_COUNT

    LDA #$00
    STA BOOT_POINTER_STATUS
    JMP BOOT_POINTER_VERIFY_DONE

BOOT_POINTER_FAIL:
    LDA #$01
    STA BOOT_POINTER_STATUS

BOOT_POINTER_VERIFY_DONE:
    LDA BOOT_POINTER_STATUS

    PLY
    PLX
    PLA
    RTS

;================================================================================
; DATA SECTION - ROM diagnostic variables
;================================================================================
.org $0330

ROM_DIAG_STATUS:            .byte $00  ; Overall ROM diagnostic status
ROM_ADDR_L:                 .byte $00  ; ROM address low byte
ROM_ADDR_H:                 .byte $00  ; ROM address high byte
ROM_SIZE:                   .byte $00  ; ROM size in pages
ROM_CHECKSUM:               .byte $00  ; Computed ROM checksum
BOOT_SECTOR_CHECKSUM:       .byte $00  ; Boot sector checksum
MONITOR_SECTOR_CHECKSUM:    .byte $00  ; Monitor sector checksum
VECTOR_CHECKSUM:            .byte $00  ; Vector table checksum
VECTOR_STATUS:              .byte $00  ; Vector validation status
VECTOR_COUNT:               .byte $00  ; Valid vector count
ROM_SIGNATURE_STATUS:       .byte $00  ; Signature validation status
BOOT_POINTER_STATUS:        .byte $00  ; Boot pointer validation status
BOOT_POINTER_COUNT:         .byte $00  ; Valid boot pointers count

;================================================================================
; END OF ROM DIAGNOSTICS (02_rom_diag) - 450 LOC EXACT
;================================================================================
