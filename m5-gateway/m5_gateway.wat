(module
  ;; Allocate 1 page (64KB) of linear memory to comfortably house the 4096-byte M5 buffer.
  ;; Exported directly so the host environment can act as the frame buffer without UI bridging.
  (memory (export "m5_memory") 1)

  ;; ----------------------------------------------------------------
  ;; Deterministic State Registers (Stripped of Swift overhead)
  ;; ----------------------------------------------------------------
  (global $r0 (export "r0") (mut i64) (i64.const 0))
  (global $r1 (export "r1") (mut i64) (i64.const 0))
  (global $r2 (export "r2") (mut i64) (i64.const 0))
  (global $r3 (export "r3") (mut i64) (i64.const 0))
  (global $pc (export "pc") (mut i64) (i64.const 0))
  (global $sp (export "sp") (mut i64) (i64.const 0))
  (global $status (export "status") (mut i64) (i64.const 0))

  ;; Hardware Lock State (Invisible to outside, controlled via functions)
  (global $locked (mut i32) (i32.const 0))

  ;; ----------------------------------------------------------------
  ;; Core Execution Logic ("Flops")
  ;; ----------------------------------------------------------------

  (func (export "lock")
    (global.set $locked (i32.const 1))
  )

  (func (export "unlock")
    (global.set $locked (i32.const 0))
  )

  ;; Writes a byte. Returns 0 on success, -1 if locked, -2 if out of bounds.
  (func (export "write_byte") (param $addr i32) (param $val i32) (result i32)
    (if (global.get $locked)
      (then (return (i32.const -1)))
    )
    (if (i32.ge_u (local.get $addr) (i32.const 4096))
      (then (return (i32.const -2)))
    )
    ;; Bare-metal linear memory write
    (i32.store8 (local.get $addr) (local.get $val))
    (i32.const 0)
  )

  ;; Reads a byte. Returns byte value, or -1 if out of bounds.
  (func (export "read_byte") (param $addr i32) (result i32)
    (if (i32.ge_u (local.get $addr) (i32.const 4096))
      (then (return (i32.const -1)))
    )
    (i32.load8_u (local.get $addr))
  )

  ;; Deterministic Checksum Pipeline
  ;; Replaces the Swift array map/reduce with a direct memory loop
  (func (export "checksum") (result i64)
    (local $i i32)
    (local $sum i64)
    (local.set $i (i32.const 0))
    (local.set $sum (i64.const 0))

    (loop $accumulate
      (if (i32.lt_u (local.get $i) (i32.const 4096))
        (then
          (local.set $sum
            (i64.add
              (local.get $sum)
              (i64.extend_i32_u (i32.load8_u (local.get $i)))
            )
          )
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $accumulate)
        )
      )
    )
    (local.get $sum)
  )

  ;; Hardware Reset
  (func (export "reset")
    (if (global.get $locked) (then (return)))

    ;; Bulk memory clear (dest=0, val=0, size=4096)
    (memory.fill (i32.const 0) (i32.const 0) (i32.const 4096))

    (global.set $r0 (i64.const 0))
    (global.set $r1 (i64.const 0))
    (global.set $r2 (i64.const 0))
    (global.set $r3 (i64.const 0))
    (global.set $pc (i64.const 0))
    (global.set $sp (i64.const 0))
    (global.set $status (i64.const 0))
  )
)
