(module
  (memory (export "memory") 2)

  (global $ACCOUNT_BASE_ADDR i32 (i32.const 1024))
  (global $ACCOUNT_ENTRY_SIZE i32 (i32.const 16))
  (global $account_count (mut i32) (i32.const 0))

  (func (export "execute_binary_isa") (param $inst_ptr i32) (param $inst_len i32) (result i32)
    (local $opcode i32)
    (local $pc i32)
    (local $id_hash i64)
    (local $balance i64)
    (local $idx i32)
    (local $addr i32)

    (if (i32.le_s (local.get $inst_len) (i32.const 0))
      (then (return (i32.const 0)))
    )
    (local.set $pc (local.get $inst_ptr))
    (local.set $opcode (i32.load8_u (local.get $pc)))
    (local.set $pc (i32.add (local.get $pc) (i32.const 1)))

    (if (i32.eq (local.get $opcode) (i32.const 0x10))
      (then
        (local.set $id_hash (i64.load (local.get $pc)))
        (local.set $balance (i64.load offset=8 (local.get $pc)))
        (local.set $idx (global.get $account_count))
        (local.set $addr (i32.add (global.get $ACCOUNT_BASE_ADDR) (i32.mul (local.get $idx) (global.get $ACCOUNT_ENTRY_SIZE))))
        (i64.store (local.get $addr) (local.get $id_hash))
        (i64.store offset=8 (local.get $addr) (local.get $balance))
        (global.set $account_count (i32.add (local.get $idx) (i32.const 1)))
        (return (i32.const 1))
      )
    )

    (if (i32.eq (local.get $opcode) (i32.const 0x20))
      (then (return (i32.const 1)))
    )

    (i32.const 0)
  )
)
