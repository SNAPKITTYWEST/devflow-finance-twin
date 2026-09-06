;; Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; SOVEREIGN DEED: DEVFLOW_FINANCE_WORM_FRAME-087
;; WORM Frame Serialization, Merkle Accumulator, and Log Clearing

(module
  (memory (import "env" "memory") 64)

  (global $BORROWCHAIN_LOG_OFFSET i32 (i32.const 0x6000))
  (global $SCRATCH_OFFSET i32 (i32.const 0x8000))
  (global $ENTRY_SIZE i32 (i32.const 64))

  ;; PHASE 17: WORM FRAME SERIALIZATION
  ;; Packs borrowchain log into contiguous binary WORM frame
  ;; Frame format: [Magic: 4B][Log Len: 4B][Prev Hash: 32B][Entries: Len * 64B]
  ;; Returns: Total frame size in bytes
  (func (export "serialize_worm_frame") (param $prev_hash_ptr i32) (result i32)
    (local $log_len i32)
    (local $write_ptr i32)
    (local $read_ptr i32)
    (local $total_size i32)
    (local $i i32)

    (local.set $log_len (i32.load (global.get $BORROWCHAIN_LOG_OFFSET)))
    (local.set $write_ptr (global.get $SCRATCH_OFFSET))

    ;; 1. Write Magic Header ("WORM")
    (i32.store (local.get $write_ptr) (i32.const 0x4D524F57))
    (local.set $write_ptr (i32.add (local.get $write_ptr) (i32.const 4)))

    ;; 2. Write Log Length
    (i32.store (local.get $write_ptr) (local.get $log_len))
    (local.set $write_ptr (i32.add (local.get $write_ptr) (i32.const 4)))

    ;; 3. Copy 32-Byte Previous WORM Hash
    (local.set $i (i32.const 0))
    (block $copy_hash_break
      (loop $copy_hash
        (br_if $copy_hash_break (i32.ge_u (local.get $i) (i32.const 32)))
        (i32.store8
          (i32.add (local.get $write_ptr) (local.get $i))
          (i32.load8_u (i32.add (local.get $prev_hash_ptr) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_hash)
      )
    )
    (local.set $write_ptr (i32.add (local.get $write_ptr) (i32.const 32)))

    ;; 4. Block Copy Borrowchain Entries
    (local.set $read_ptr (i32.add (global.get $BORROWCHAIN_LOG_OFFSET) (i32.const 4)))
    (local.set $total_size (i32.mul (local.get $log_len) (global.get $ENTRY_SIZE)))

    (local.set $i (i32.const 0))
    (block $copy_entries_break
      (loop $copy_entries
        (br_if $copy_entries_break (i32.ge_u (local.get $i) (local.get $total_size)))
        (i32.store8
          (i32.add (local.get $write_ptr) (local.get $i))
          (i32.load8_u (i32.add (local.get $read_ptr) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_entries)
      )
    )

    ;; Return total byte length (4 + 4 + 32 + (len * 64))
    (i32.add (i32.const 40) (local.get $total_size))
  )

  ;; PHASE 7: IN-MEMORY MERKLE ACCUMULATOR
  ;; Folds 64-bit block XOR hashes into lightweight Merkle root
  ;; Returns: 64-bit accumulated state hash
  (func (export "compute_fast_merkle_root") (result i64)
    (local $log_len i32)
    (local $i i32)
    (local $entry_ptr i32)
    (local $root i64)
    (local $entry_hash i64)

    (local.set $log_len (i32.load (global.get $BORROWCHAIN_LOG_OFFSET)))
    (local.set $root (i64.const 0x534F56524549474E)) ;; "SOVEREIGN" seed
    (local.set $i (i32.const 0))

    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $log_len)))

        (local.set $entry_ptr
          (i32.add
            (i32.add (global.get $BORROWCHAIN_LOG_OFFSET) (i32.const 4))
            (i32.add (i32.mul (local.get $i) (global.get $ENTRY_SIZE)) (i32.const 36))
          )
        )

        (local.set $entry_hash (i64.load (local.get $entry_ptr)))

        ;; Non-commutative fold: root = (root rotl 13) ^ entry_hash
        (local.set $root
          (i64.xor
            (i64.or
              (i64.shl (local.get $root) (i64.const 13))
              (i64.shr_u (local.get $root) (i64.const 51))
            )
            (local.get $entry_hash)
          )
        )

        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )

    (local.get $root)
  )

  ;; BUFFER CLEARING
  ;; Resets borrowchain log length to zero post-flush
  (func (export "clear_borrowchain_log")
    (i32.store (global.get $BORROWCHAIN_LOG_OFFSET) (i32.const 0))
  )
)
