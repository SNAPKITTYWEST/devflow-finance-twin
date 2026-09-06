/* pseudo-stack kernel state machine */
/* r1 = current state, r2 = message, r3 = scratch, r4 = target */

KERNEL_STEP:
    LOAD r1, [0x00]       ; Load current state
    LOAD r2, [0x04]       ; Load incoming message

    ; Validate message bounds (r2 == 0x01 or r2 == 0xFF)
    CMP r2, 0x01
    JE MSG_OK
    CMP r2, 0xFF
    JE MSG_OK
    JMP HANDLE_FAULT

MSG_OK:
    CMP r1, 0x00          ; RUN
    JNE CHECK_RECOVER
    CMP r2, 0x01          ; RUN + Valid Tick -> RUN
    JNE HANDLE_FAULT
    MOV r4, 0x00
    JMP STORE_STATE

CHECK_RECOVER:
    CMP r1, 0x02          ; RECOVER
    JNE HANDLE_FAULT
    CMP r2, 0x01          ; RECOVER + Valid Tick -> RUN
    JNE HANDLE_FAULT
    MOV r4, 0x00
    JMP STORE_STATE

HANDLE_FAULT:
    MOV r4, 0x01          ; FAULT(0x01)
    LOAD r3, [0x08]       ; Increment fault counter
    ADD r3, 0x01
    STORE [0x08], r3

STORE_STATE:
    STORE [0x00], r4      ; Commit new state
    RET
