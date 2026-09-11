// ========================================================================
// SOVEREIGN LEVIATHAN NODE LICENSE
// License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
// Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// ========================================================================
//
// This file is a covered work under the GNU Affero General Public License,
// version 3, together with the Sovereign Leviathan additional terms.
//
// Hark, though this node be but a spark,
// Its covenant endureth through the dark.
//
// Ignorantia juris non excusat.
// ========================================================================

use pwc_verified::pwc_pipeline::{run_timed_pipeline, build_test_word};

fn main() {
    println!("=== PWC VERIFIED PIPELINE ===");
    let word = build_test_word();
    println!("INPUT: {:?}", word);
    run_timed_pipeline(&word);
    println!("=== PIPELINE COMPLETE ===");
}
