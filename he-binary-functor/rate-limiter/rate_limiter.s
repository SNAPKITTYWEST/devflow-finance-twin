; rate_limiter_step: (state*, time:u32, request:bool) -> (state*, grant:bool)
; a0=state, a1=time, a2=request
; Returns: a0=state (unchanged), a1=grant (0 or 1)

rate_limiter_step:
  ; Load state
  lb t0, 0(a0)          ; state_tag
  lbu t1, 1(a0)         ; tokens [0,16]
  lbu t2, 2(a0)         ; fail_count [0,8]
  lw t3, 4(a0)          ; last_permit_time
  lw t4, 8(a0)          ; fault_entry_time
  sw a1, 12(a0)         ; snapshot current_time

  ; Compute elapsed times
  sub t5, a1, t3        ; elapsed = time - last_permit_time
  sub t6, a1, t4        ; fault_age = time - fault_entry_time

  ; Refill tokens every REFILL_INTERVAL ms
  li t7, 1000           ; REFILL_INTERVAL
  blt t5, t7, .no_refill
  addi t1, t1, 1        ; tokens++
  li t8, 16             ; MAX_TOKENS
  bge t1, t8, .cap_tokens
  sw a1, 4(a0)          ; last_permit_time = time
  j .no_refill
.cap_tokens:
  li t1, 16             ; tokens = MAX_TOKENS
  sw a1, 4(a0)          ; last_permit_time = time

.no_refill:
  sb t1, 1(a0)          ; store tokens back

  ; State machine dispatch
  beqz t0, .state_run
  li t8, 1
  beq t0, t8, .state_fault
  li t8, 2
  beq t0, t8, .state_recover
  j .invalid_state      ; unreachable

  ; --- STATE: RUN ---
.state_run:
  beqz a2, .run_deny    ; if no request, deny
  beqz t1, .run_deny    ; if tokens==0, deny

  ; GRANT
  sub t1, t1, 1         ; tokens--
  sb t1, 1(a0)
  sw a1, 4(a0)          ; last_permit_time = time
  li t2, 0              ; fail_count = 0
  sb t2, 2(a0)
  li a1, 1              ; grant = 1
  ret

.run_deny:
  addi t2, t2, 1        ; fail_count++
  li t8, 8              ; MAX_FAIL
  ble t2, t8, .run_store_fail
  li t2, 8              ; saturate at MAX_FAIL
.run_store_fail:
  sb t2, 2(a0)

  li t8, 4              ; FAIL_THRESHOLD
  blt t2, t8, .run_return_deny

  li t0, 1              ; state_tag = FAULT
  sb t0, 0(a0)
  sw a1, 8(a0)          ; fault_entry_time = time
  li a1, 0              ; grant = 0
  ret

.run_return_deny:
  li a1, 0              ; grant = 0
  ret

  ; --- STATE: FAULT ---
.state_fault:
  li t8, 5000           ; FAULT_TIMEOUT
  blt t6, t8, .fault_wait

  li t0, 2              ; state_tag = RECOVER
  sb t0, 0(a0)
  sw a1, 8(a0)          ; reuse fault_entry_time for recovery start
  li a1, 0              ; grant = 0
  ret

.fault_wait:
  li a1, 0              ; grant = 0
  ret

  ; --- STATE: RECOVER ---
.state_recover:
  li t8, 2000           ; RECOVER_TIMEOUT
  blt t6, t8, .recover_wait

  li t0, 0              ; state_tag = RUN
  sb t0, 0(a0)
  li t1, 8              ; tokens = 8 (reset to half capacity)
  sb t1, 1(a0)
  li t2, 0              ; fail_count = 0
  sb t2, 2(a0)
  sw a1, 4(a0)          ; last_permit_time = time
  sw x0, 8(a0)          ; fault_entry_time = 0
  li a1, 0              ; grant = 0 (deny during recover)
  ret

.recover_wait:
  li a1, 0              ; grant = 0
  ret

  ; --- ERROR ---
.invalid_state:
  li a1, -1             ; error flag
  ret
