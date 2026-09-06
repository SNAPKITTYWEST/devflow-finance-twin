// =====================================================================
// PWC_PIPELINE - Full Verified Pipeline
// =====================================================================

use crate::pwc_core::BraidWord;
use crate::pwc_hardware::{hw_execute_transform_timed, worm_seal_timed};
use crate::pwc_core::GeneratorIndex;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn run_timed_pipeline(raw_braid: &[GeneratorIndex]) {
    let result = hw_execute_transform_timed(raw_braid);

    let timestamp_ns = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos() as u64;

    worm_seal_timed(result.cycles, result.matrix_hash, timestamp_ns);

    println!("COMPRESSED: {:?}", result.compressed);
    println!("CYCLES: {}", result.cycles);
    println!("HASH: 0x{:08X}", result.matrix_hash);
}

pub fn build_test_word() -> Vec<GeneratorIndex> {
    vec![1, 2, 1, 2, 1]
}
