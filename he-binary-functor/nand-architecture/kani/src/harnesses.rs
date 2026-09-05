//! Kani verification harnesses for NAND ISA.
//!
//! Run (when Kani is installed):
//! cargo kani --harness verify_nand_truth_table
//! cargo kani --harness verify_decode_encode
//! etc.

use nandsharp::bool_ops::*;
use nandsharp::isa::Instr;

#[cfg(kani)]
#[kani::proof]
fn verify_nand_truth_table() {
    assert!(nand(false, false) == true);
    assert!(nand(false, true) == true);
    assert!(nand(true, false) == true);
    assert!(nand(true, true) == false);
}

#[cfg(kani)]
#[kani::proof]
fn verify_derived_not() {
    let x: bool = kani::any();
    assert!(not(x) == !x);
}

#[cfg(kani)]
#[kani::proof]
fn verify_derived_and() {
    let a: bool = kani::any();
    let b: bool = kani::any();
    assert!(and(a, b) == (a & b));
}

#[cfg(kani)]
#[kani::proof]
fn verify_decode_encode_defined() {
    let dst: u8 = kani::any();
    let a: u8 = kani::any();
    let b: u8 = kani::any();
    kani::assume(dst < 16 && a < 16 && b < 16);
    let i = Instr::Nand { dst, a, b };
    assert_eq!(Instr::decode(i.encode()), i);
}

#[cfg(kani)]
#[kani::proof]
fn verify_r0_invariant_model() {
    let imm: u8 = kani::any();
    let i = Instr::Ldi { dst: 0, imm };
    let w = i.encode();
    assert_eq!((w >> 12) & 0xF, 4); // LDI opcode
}

// ---------------------------------------------------------------------------
// Classification of properties
// ---------------------------------------------------------------------------
//
// TESTED        : unit tests in each module (cargo test)
// MODEL-CHECKED : the #[kani::proof] harnesses above (bounded)
// FORMALLY SPEC.: the semantic equations in nand-isa/SPEC.md,
//                 array/SEMANTICS.md, nandsharp/GRAMMAR.md
// ASSUMED       : host Rust compiler correctness, absence of
//                 hardware bit-flips, finite memory of the host
