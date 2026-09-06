pub fn re_invoke_block_lace(
    ledger_entry: &mut LedgerEntry,
    block_word: &[i8],
    prev_seal: u64
) -> Result<u64, LedgerStatus> {
    if block_word.len() > 16 {
        return Err(LedgerStatus::ERR_WORD_OVERFLOW);
    }

    let mut acc = ledger_entry.state_in;
    for &g in block_word {
        acc = (acc.wrapping_mul(31)) ^ ((g as u64).wrapping_mul(g as u64).wrapping_add(g as u64));
    }
    ledger_entry.state_out = acc;
    ledger_entry.prev_seal = prev_seal;

    let hash_len = std::mem::offset_of!(LedgerEntry, self_seal);
    let computed_seal = fnv1a_hash(ledger_entry as *const _ as *const _, hash_len);
    ledger_entry.self_seal = computed_seal;

    Ok(computed_seal)
}

pub fn emit_reinvoke_nand_binary(block_word: &[i8]) -> Vec<u16> {
    let mut binary_stream = Vec::new();
    binary_stream.push(0x2000);
    for &gen in block_word {
        let opcode_word = 0x0000 | ((gen.unsigned_abs() as u16) & 0x1F);
        binary_stream.push(opcode_word);
    }
    binary_stream.push(0xE000);
    binary_stream
}
