use pwc_verified::pwc_pipeline::{run_timed_pipeline, build_test_word};

fn main() {
    println!("=== PWC VERIFIED PIPELINE ===");
    let word = build_test_word();
    println!("INPUT: {:?}", word);
    run_timed_pipeline(&word);
    println!("=== PIPELINE COMPLETE ===");
}
