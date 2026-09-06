;; Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SOVEREIGN DEED: DEVFLOW_FINANCE_LEDGER_REPLAY-084
;; Independent ledger replay and state verification

(module
  (memory (export "memory") 2)

  (func (export "verify_ledger_replay")
    (param $events_ptr i32)
    (param $event_count i32)
    (param $expected_checksum i64)
    (result i32)

    (local $i i32)
    (local $current_ptr i32)
    (local $op_type i32)
    (local $computed_checksum i64)

    (local.set $i (i32.const 0))
    (local.set $current_ptr (local.get $events_ptr))
    (local.set $computed_checksum (i64.const 0x534F5652))

    (block $break
      (loop $replay_loop
        (br_if $break (i32.ge_s (local.get $i) (local.get $event_count)))
        (local.set $op_type (i32.load (local.get $current_ptr)))
        (local.set $computed_checksum
          (i64.xor
            (local.get $computed_checksum)
            (i64.extend_i32_u (local.get $op_type))
          )
        )
        (local.set $current_ptr (i32.add (local.get $current_ptr) (i32.const 32)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $replay_loop)
      )
    )

    (if (i64.eq (local.get $computed_checksum) (local.get $expected_checksum))
      (then (return (i32.const 1)))
      (else (return (i32.const 0)))
    )
  )
)
