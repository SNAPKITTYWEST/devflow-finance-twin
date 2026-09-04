// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: FSL-1.1

const ACCOUNT_BASE_ADDR: i32 = 1024;
const ACCOUNT_ENTRY_SIZE: i32 = 16;
var account_count: i32 = 0;

export function execute_binary_isa(inst_ptr: i32, inst_len: i32): i32 {
  if (inst_len <= 0) {
    return 0;
  }

  let opcode = load<u8>(inst_ptr);
  let pc = inst_ptr + 1;

  if (opcode == 0x10) {
    let id_hash = load<u64>(pc);
    let balance = load<u64>(pc + 8);

    let idx = account_count;
    let addr = ACCOUNT_BASE_ADDR + (idx * ACCOUNT_ENTRY_SIZE);

    store<u64>(addr, id_hash);
    store<u64>(addr + 8, balance);
    account_count = idx + 1;

    return 1;
  }

  if (opcode == 0x20) {
    return 1;
  }

  return 0;
}
