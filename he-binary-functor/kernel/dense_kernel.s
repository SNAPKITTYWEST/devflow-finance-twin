.equ MAX, 15
.equ RMAX, 3
.equ MODE_MASK, 3
.equ PAY_SHIFT, 2

# entry: a0 = &state, a1 = msg
step:
    lw t0, 0(a0)            # t0 = state_word
    andi t1, t0, MODE_MASK  # t1 = mode
    srli t2, t0, PAY_SHIFT  # t2 = payload

    beqz a0, .L_inv         # null state -> FAULT(0)
    li t3, 2
    bgtu t1, t3, .L_inv     # mode > 2 -> FAULT(0)

    beqz t1, .L_run
    li t3, 1
    beq t1, t3, .L_fault
.L_rec:
    li t3, 2                # RESET
    beq a1, t3, .L_to_run0
    li t3, 0                # TICK
    bne a1, t3, .L_to_fault2
    li t3, RMAX
    bgeu t2, t3, .L_to_run0
    addi t2, t2, 1
    slli t0, t2, PAY_SHIFT
    ori t0, t0, 2           # RECOVER
    j .L_store
.L_to_run0:
    li t0, 0                # RUN(0)
    j .L_store
.L_to_fault2:
    li t0, (2<<PAY_SHIFT)|1
    j .L_store

.L_fault:
    li t3, 2                # RESET
    beq a1, t3, .L_to_rec0
    j .L_store              # sticky
.L_to_rec0:
    li t0, 2                # RECOVER(0)
    j .L_store

.L_run:
    li t3, 0                # TICK
    beq a1, t3, .L_tick
    li t3, 1                # FAIL
    beq a1, t3, .L_to_fault1
    li t3, 2                # RESET
    beq a1, t3, .L_to_run0
    li t0, (3<<PAY_SHIFT)|1
    j .L_store
.L_tick:
    li t3, MAX
    bgeu t2, t3, .L_store
    addi t2, t2, 1
    slli t0, t2, PAY_SHIFT
    j .L_store
.L_to_fault1:
    li t0, (1<<PAY_SHIFT)|1
    j .L_store

.L_inv:
    li t0, 1                # FAULT(0)
    li a2, 2                # invalid-input status
    j .L_store_status

.L_store:
    li a2, 0
    andi t3, t0, MODE_MASK
    li t1, 1
    beq t3, t1, .L_set_fault_status
    j .L_do_store
.L_set_fault_status:
    li a2, 1
.L_do_store:
.L_store_status:
    sw t0, 0(a0)
    ret
