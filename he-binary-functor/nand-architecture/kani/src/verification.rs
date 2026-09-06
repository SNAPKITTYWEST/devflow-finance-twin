#[cfg(kani)]
mod verification {
    use super::*;

    #[kani::proof]
    fn verify_instruction_roundtrip() {
        let op_val: u8 = kani::any();
        kani::assume(op_val <= 3 || op_val == 7);
        let dst: u8 = kani::any();
        kani::assume(dst < 16);
        let src_a: u8 = kani::any();
        kani::assume(src_a < 16);
        let src_b: u8 = kani::any();
        kani::assume(src_b < 32);

        let op = match op_val {
            0 => Opcode::Nand,
            1 => Opcode::Load,
            2 => Opcode::Store,
            3 => Opcode::JmpZ,
            7 => Opcode::Halt,
            _ => unreachable!(),
        };

        let inst = Instruction { op, dst, src_a, src_b };
        let encoded = inst.encode();
        let decoded = Instruction::decode(encoded).unwrap();

        assert!(decoded.op == inst.op);
        assert!(decoded.dst == inst.dst);
        assert!(decoded.src_a == inst.src_a);
        assert!(decoded.src_b == inst.src_b);
    }

    #[kani::proof]
    fn verify_nand_truth_table() {
        let a: bool = kani::any();
        let b: bool = kani::any();

        let mut vm = VirtualMachine::new();
        vm.regs[1] = a;
        vm.regs[2] = b;

        let inst = Instruction {
            op: Opcode::Nand,
            dst: 3,
            src_a: 1,
            src_b: 2,
        };

        let rom = [inst.encode()];
        vm.step(&rom).unwrap();

        assert_eq!(vm.regs[3], !(a && b));
    }
}
