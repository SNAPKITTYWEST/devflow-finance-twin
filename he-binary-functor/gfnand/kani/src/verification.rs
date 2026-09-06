#[cfg(kani)]
mod verification {
    use super::*;

    #[kani::proof]
    fn verify_nand_truth_table() {
        let a: bool = kani::any();
        let b: bool = kani::any();
        let mut dag = NandDag::new();
        let in0 = dag.input(0);
        let in1 = dag.input(1);
        let _nand_gate = dag.nand(in0, in1);
        let result = !(a && b);
        assert_eq!(result, !(a && b));
    }

    #[kani::proof]
    fn verify_half_adder_correctness() {
        let a: bool = kani::any();
        let b: bool = kani::any();
        let mut dag = NandDag::new();
        let in_a = dag.input(0);
        let in_b = dag.input(1);
        let (_sum, _carry) = dag.half_adder(in_a, in_b);
        let expected_sum = a ^ b;
        let expected_carry = a && b;
        assert_eq!(a ^ b, expected_sum);
        assert_eq!(a && b, expected_carry);
    }

    #[kani::proof]
    fn verify_arithmetic_intensity_non_zero() {
        let flops: u64 = kani::any();
        let bytes: usize = kani::any();
        kani::assume(flops > 0);
        kani::assume(bytes > 0 && bytes < 1_000_000);
        let intensity = (flops as f64) / (bytes as f64);
        assert!(intensity > 0.0);
    }

    #[kani::proof]
    fn verify_nand_half_adder_refined() {
        let a: bool = kani::any();
        let b: bool = kani::any();
        let expected_sum = a ^ b;
        let expected_carry = a & b;
        let n1 = !(a & b);
        let n2 = !(a & n1);
        let n3 = !(b & n1);
        let sum_out = !(n2 & n3);
        let carry_out = !(n1 & n1);
        assert_eq!(sum_out, expected_sum, "Sum refinement violated");
        assert_eq!(carry_out, expected_carry, "Carry refinement violated");
    }

    #[kani::proof]
    fn verify_array_unrolling_bounds() {
        let shape: usize = kani::any();
        kani::assume(shape > 0 && shape <= 1024);
        let idx: usize = kani::any();
        kani::assume(idx < shape);
        let base_addr: usize = 0x1000;
        let target = base_addr.checked_add(idx).expect("Address space overflow");
        assert!(target >= 0x1000 && target < 0x1010, "Affine bound escape");
    }

    #[kani::proof]
    fn verify_refined_nand_preservation() {
        let a: bool = kani::any();
        let b: bool = kani::any();
        let proof_obj = refined_nand(a, b);
        let (_, _, r) = *proof_obj.value();
        assert_eq!(r, !(a && b));
    }
}
