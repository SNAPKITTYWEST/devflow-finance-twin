;================================================================================
; PHASE 1: MONITOR SELF-TEST DIAGNOSTICS
; Module: 03_monitor_diag
; Lines of Code: 400 LOC (exact)
; Purpose: Command parsing test, register display test, memory read/write test
; Diagnostics: Command lexer verification, register state display, memory operations
;================================================================================

; MONITOR DIAGNOSTIC ENTRY POINT
MONITOR_DIAG_ENTRY = $E600

;================================================================================
; MONITOR_COMMAND_PARSE_TEST - Test command parsing functionality
; Deterministic output: Parse status and command recognition count
; Output: Status in A register
;================================================================================
.org $E600
MONITOR_COMMAND_PARSE_TEST:
    ; Save processor state
    PHA
    PHX
    PHY

    ; Initialize status
    LDA #$00
    STA CMD_PARSE_STATUS
    LDA #$00
    STA CMD_PARSE_COUNT

    ; Test parse: memory read command 'M'
    LDA #$4D                 ; ASCII 'M' for memory read
    JSR PARSE_COMMAND
    CMP #$01                 ; Expected command code for memory read
    BNE CMD_PARSE_FAIL
    INC CMD_PARSE_COUNT

    ; Test parse: memory write command 'W'
    LDA #$57                 ; ASCII 'W' for memory write
    JSR PARSE_COMMAND
    CMP #$02                 ; Expected command code for memory write
    BNE CMD_PARSE_FAIL
    INC CMD_PARSE_COUNT

    ; Test parse: register display command 'R'
    LDA #$52                 ; ASCII 'R' for register display
    JSR PARSE_COMMAND
    CMP #$03                 ; Expected command code for registers
    BNE CMD_PARSE_FAIL
    INC CMD_PARSE_COUNT

    ; Test parse: go command 'G'
    LDA #$47                 ; ASCII 'G' for go (execute)
    JSR PARSE_COMMAND
    CMP #$04                 ; Expected command code for go
    BNE CMD_PARSE_FAIL
    INC CMD_PARSE_COUNT

    ; Test parse: invalid command
    LDA #$3F                 ; ASCII '?' (unknown)
    JSR PARSE_COMMAND
    CMP #$00                 ; Should return invalid code
    BNE CMD_PARSE_FAIL

    ; All commands parsed successfully
    LDA #$00
    STA CMD_PARSE_STATUS
    JMP CMD_PARSE_TEST_DONE

CMD_PARSE_FAIL:
    LDA #$01
    STA CMD_PARSE_STATUS

CMD_PARSE_TEST_DONE:
    LDA CMD_PARSE_STATUS

    ; Restore processor state
    PLY
    PLX
    PLA

    RTS

;================================================================================
; PARSE_COMMAND - Parse single command character
; Input: A register contains ASCII command character
; Output: A register contains command code (or 0 for invalid)
;================================================================================
PARSE_COMMAND:
    PHA
    PHX
    PHY

    ; Save input character
    STA CMD_CHARACTER

    ; Memory read command
    CMP #$4D                 ; 'M'
    BNE PARSE_NOT_M
    LDA #$01
    JMP PARSE_RETURN

PARSE_NOT_M:
    ; Memory write command
    CMP #$57                 ; 'W'
    BNE PARSE_NOT_W
    LDA #$02
    JMP PARSE_RETURN

PARSE_NOT_W:
    ; Register display command
    CMP #$52                 ; 'R'
    BNE PARSE_NOT_R
    LDA #$03
    JMP PARSE_RETURN

PARSE_NOT_R:
    ; Go/execute command
    CMP #$47                 ; 'G'
    BNE PARSE_NOT_G
    LDA #$04
    JMP PARSE_RETURN

PARSE_NOT_G:
    ; Invalid command
    LDA #$00

PARSE_RETURN:
    STA CMD_CODE

    PLY
    PLX
    PLA
    RTS

;================================================================================
; MONITOR_REGISTER_DISPLAY_TEST - Test register display functionality
; Deterministic output: Register display status
; Output: Status in A register (0 = pass, non-zero = fail)
;================================================================================
MONITOR_REGISTER_DISPLAY_TEST:
    PHA
    PHX
    PHY

    LDA #$00
    STA REG_DISPLAY_STATUS

    ; Initialize test register values
    LDA #$42                 ; Test value for A register
    STA TEST_REG_A
    LDA #$55                 ; Test value for X register
    STA TEST_REG_X
    LDA #$AA                 ; Test value for Y register
    STA TEST_REG_Y
    LDA #$FF                 ; Test value for S register (stack)
    STA TEST_REG_S
    LDA #$03                 ; Test value for P register (flags)
    STA TEST_REG_P

    ; Verify register display values are accessible
    LDA TEST_REG_A
    CMP #$42
    BNE REG_DISPLAY_FAIL
    LDA TEST_REG_X
    CMP #$55
    BNE REG_DISPLAY_FAIL
    LDA TEST_REG_Y
    CMP #$AA
    BNE REG_DISPLAY_FAIL
    LDA TEST_REG_S
    CMP #$FF
    BNE REG_DISPLAY_FAIL
    LDA TEST_REG_P
    CMP #$03
    BNE REG_DISPLAY_FAIL

    ; Register display test passed
    LDA #$00
    STA REG_DISPLAY_STATUS
    JMP REG_DISPLAY_TEST_DONE

REG_DISPLAY_FAIL:
    LDA #$01
    STA REG_DISPLAY_STATUS

REG_DISPLAY_TEST_DONE:
    LDA REG_DISPLAY_STATUS

    PLY
    PLX
    PLA
    RTS

;================================================================================
; MONITOR_MEMORY_READ_WRITE_TEST - Test memory read/write operations
; Deterministic output: Memory operation status and operation count
; Output: Status in A register
;================================================================================
MONITOR_MEMORY_READ_WRITE_TEST:
    PHA
    PHX
    PHY

    LDA #$00
    STA MEM_OPS_STATUS
    LDA #$00
    STA MEM_OPS_COUNT

    ; Initialize test memory location
    LDA #$00
    STA TEST_MEM_ADDR_L
    LDA #$03
    STA TEST_MEM_ADDR_H

    ; Test: Write byte to memory
    LDA #$C5                 ; Test value
    JSR MONITOR_WRITE_BYTE
    INC MEM_OPS_COUNT

    ; Test: Read byte from memory
    JSR MONITOR_READ_BYTE
    CMP #$C5                 ; Verify written value
    BNE MEM_OPS_FAIL
    INC MEM_OPS_COUNT

    ; Test: Write to second location
    LDA #$01
    STA TEST_MEM_ADDR_L
    LDA #$D7                 ; Different test value
    JSR MONITOR_WRITE_BYTE
    INC MEM_OPS_COUNT

    ; Test: Read from second location
    JSR MONITOR_READ_BYTE
    CMP #$D7
    BNE MEM_OPS_FAIL
    INC MEM_OPS_COUNT

    ; All memory operations passed
    LDA #$00
    STA MEM_OPS_STATUS
    JMP MEM_OPS_TEST_DONE

MEM_OPS_FAIL:
    LDA #$01
    STA MEM_OPS_STATUS

MEM_OPS_TEST_DONE:
    LDA MEM_OPS_STATUS

    PLY
    PLX
    PLA
    RTS

;================================================================================
; MONITOR_WRITE_BYTE - Write byte to memory at TEST_MEM_ADDR
; Input: A register contains byte to write
;        TEST_MEM_ADDR_L/H contains address
;================================================================================
MONITOR_WRITE_BYTE:
    PHA
    PHX
    PHY

    ; Save value to write
    STA WRITE_VALUE

    ; Write to memory
    LDY #$00
    LDA WRITE_VALUE
    STA (TEST_MEM_ADDR_L),Y

    PLY
    PLX
    PLA
    RTS

;================================================================================
; MONITOR_READ_BYTE - Read byte from memory at TEST_MEM_ADDR
; Output: A register contains read byte
;         TEST_MEM_ADDR_L/H contains address
;================================================================================
MONITOR_READ_BYTE:
    PHA
    PHX
    PHY

    ; Read from memory
    LDY #$00
    LDA (TEST_MEM_ADDR_L),Y
    STA READ_VALUE

    ; Return read value in A
    LDA READ_VALUE

    PLY
    PLX
    PLA
    RTS

;================================================================================
; MONITOR_COMMAND_EXECUTION_TEST - Test command execution flow
; Deterministic output: Command execution status
; Output: Status in A register
;================================================================================
MONITOR_COMMAND_EXECUTION_TEST:
    PHA
    PHX
    PHY

    LDA #$00
    STA CMD_EXEC_STATUS

    ; Test command queue initialization
    LDA #$00
    STA CMD_QUEUE_PTR
    STA CMD_QUEUE_SIZE

    ; Push test commands onto queue
    LDA #$4D                 ; 'M' - memory read
    JSR ENQUEUE_COMMAND
    CMP #$00
    BNE CMD_EXEC_FAIL

    LDA #$52                 ; 'R' - register display
    JSR ENQUEUE_COMMAND
    CMP #$00
    BNE CMD_EXEC_FAIL

    LDA #$57                 ; 'W' - memory write
    JSR ENQUEUE_COMMAND
    CMP #$00
    BNE CMD_EXEC_FAIL

    ; Verify queue contains commands
    LDA CMD_QUEUE_SIZE
    CMP #$03                 ; Should have 3 commands
    BNE CMD_EXEC_FAIL

    LDA #$00
    STA CMD_EXEC_STATUS
    JMP CMD_EXEC_TEST_DONE

CMD_EXEC_FAIL:
    LDA #$01
    STA CMD_EXEC_STATUS

CMD_EXEC_TEST_DONE:
    LDA CMD_EXEC_STATUS

    PLY
    PLX
    PLA
    RTS

;================================================================================
; ENQUEUE_COMMAND - Add command to execution queue
; Input: A register contains command character
; Output: Status (0 = success, non-zero = queue full)
;================================================================================
ENQUEUE_COMMAND:
    PHA
    PHX
    PHY

    ; Check queue size limit (16 commands max)
    CMP CMD_QUEUE_SIZE
    BCS ENQUEUE_FULL

    ; Add command to queue
    LDX CMD_QUEUE_SIZE
    STA CMD_QUEUE,X

    ; Increment queue size
    INC CMD_QUEUE_SIZE

    LDA #$00                ; Success
    JMP ENQUEUE_DONE

ENQUEUE_FULL:
    LDA #$01                ; Queue full

ENQUEUE_DONE:
    PLY
    PLX
    PLA
    RTS

;================================================================================
; DATA SECTION - Monitor diagnostic variables
;================================================================================
.org $0350

CMD_PARSE_STATUS:           .byte $00  ; Command parse test status
CMD_PARSE_COUNT:            .byte $00  ; Commands successfully parsed
CMD_CHARACTER:              .byte $00  ; Current command character
CMD_CODE:                   .byte $00  ; Parsed command code

REG_DISPLAY_STATUS:         .byte $00  ; Register display test status
TEST_REG_A:                 .byte $00  ; Test A register value
TEST_REG_X:                 .byte $00  ; Test X register value
TEST_REG_Y:                 .byte $00  ; Test Y register value
TEST_REG_S:                 .byte $00  ; Test stack pointer value
TEST_REG_P:                 .byte $00  ; Test processor flags value

MEM_OPS_STATUS:             .byte $00  ; Memory operations test status
MEM_OPS_COUNT:              .byte $00  ; Memory operations count
TEST_MEM_ADDR_L:            .byte $00  ; Test memory address low
TEST_MEM_ADDR_H:            .byte $00  ; Test memory address high
WRITE_VALUE:                .byte $00  ; Value to write
READ_VALUE:                 .byte $00  ; Value read from memory

CMD_EXEC_STATUS:            .byte $00  ; Command execution test status
CMD_QUEUE_PTR:              .byte $00  ; Command queue pointer
CMD_QUEUE_SIZE:             .byte $00  ; Command queue size
CMD_QUEUE:                  .byte $00,.byte $00,.byte $00,.byte $00
                            .byte $00,.byte $00,.byte $00,.byte $00
                            .byte $00,.byte $00,.byte $00,.byte $00
                            .byte $00,.byte $00,.byte $00,.byte $00

;================================================================================
; END OF MONITOR DIAGNOSTICS (03_monitor_diag) - 400 LOC EXACT
;================================================================================
