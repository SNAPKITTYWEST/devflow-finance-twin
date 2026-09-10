#[cfg(test)]
mod tests {
    use crate::jitter_machine::kernel::{Kernel, KernelConfig};
    use crate::jitter_machine::ops::{pack, Opcodes, Flags, lcg};
    use crate::jitter_machine::kernel::Kernel as K;

    /// Demo: LOADK two cells to 5, ASSERT they match, FUSE → HALT with FUSED_OK.
    fn demo_program() -> K {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 5),   // STATE[0] = 5
            pack(Opcodes::LOADK, 1, 0, 5),   // STATE[1] = 5
            pack(Opcodes::ASSERT, 0, 1, 0),  // assert STATE[0] == STATE[1]
            pack(Opcodes::FUSE, 0, 0, 0),    // fuse all asserts
            pack(Opcodes::HALT, 0, 0, 0),    // halt
        ];
        K::with_code(KernelConfig { n: 4, ..Default::default() }, code)
    }

    #[test]
    fn test_demo_fuse_ok() {
        let mut k = demo_program();
        k.run(10_000);
        assert!(k.flags & Flags::HALT != 0);
        assert!(k.flags & Flags::FUSED != 0);
        assert!(k.flags & Flags::FAIL == 0);
    }

    #[test]
    fn test_assert_fail() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 1),
            pack(Opcodes::LOADK, 1, 0, 2),
            pack(Opcodes::ASSERT, 0, 1, 0),
            pack(Opcodes::FUSE, 0, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = K::with_code(KernelConfig { n: 4, ..Default::default() }, code);
        k.run(100);
        assert!(k.flags & Flags::FAIL != 0);
        assert!(k.flags & Flags::FUSED == 0);
    }

    /// Recursive demo: count down from 3 using RECUR/RET, assert a trivial truth, fuse.
    ///
    /// Layout:
    ///   [0] LOADK 0, 0, 3          — counter = 3
    ///   [1] LOADK 1, 0, 0          — scratch = 0
    ///   [2] LOADK 2, 0, 1          — STATE[2] = 1 (subtractend)
    ///   [3] SUB    0, 0, 2         — counter--
    ///   [4] JZ     0, 0, 2         — if counter==0 skip 2 → jump to [7]
    ///   [5] RECUR  2, 0, 0         — recurse to STATE[2] (=1, which is addr 1 → loops)
    ///   [6] HALT                   — unreachable if recursing
    ///   [7] LOADK  3, 0, 1         — STATE[3] = 1
    ///   [8] ASSERT 3, 3, 0         — assert STATE[3]==STATE[3] (trivial true)
    ///   [9] FUSE                   — fuse
    ///  [10] HALT                   — done
    fn recursive_demo() -> K {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 3),   // [0] counter = 3
            pack(Opcodes::LOADK, 1, 0, 0),   // [1] scratch = 0 (target for recurs to loop)
            pack(Opcodes::LOADK, 2, 0, 1),   // [2] STATE[2] = 1 (subtractend)
            pack(Opcodes::SUB, 0, 0, 2),     // [3] counter--
            pack(Opcodes::JZ, 0, 0, 2),      // [4] if counter==0, skip 2 → [7]
            pack(Opcodes::RECUR, 2, 0, 0),   // [5] RECUR to STATE[2] (=1) → addr 1
            pack(Opcodes::HALT, 0, 0, 0),    // [6] unreachable
            pack(Opcodes::LOADK, 3, 0, 1),   // [7] STATE[3] = 1
            pack(Opcodes::ASSERT, 3, 3, 0),  // [8] assert STATE[3]==STATE[3]
            pack(Opcodes::FUSE, 0, 0, 0),    // [9] fuse
            pack(Opcodes::HALT, 0, 0, 0),    // [10] halt
        ];
        K::with_code(KernelConfig { n: 8, maxdepth: 16, ..Default::default() }, code)
    }

    #[test]
    fn test_recursive_demo() {
        let mut k = recursive_demo();
        k.run(10_000);
        assert!(k.flags & Flags::HALT != 0);
        assert!(k.flags & Flags::FUSED != 0);
        assert_eq!(k.state[0], 0); // counter reached 0
    }

    #[test]
    fn test_kernel_words_roundtrip() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 42),
            pack(Opcodes::ADD, 1, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = K::with_code(KernelConfig { n: 4, seed: 7, ..Default::default() }, code);
        k.run(100);
        let words = k.to_words();
        let k2 = K::from_words(&words).unwrap();
        assert_eq!(k2.state[0], 42);
        assert_eq!(k2.state[1], 84);
        assert!(k2.flags & Flags::HALT != 0);
    }

    #[test]
    fn test_mul_op() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 6),
            pack(Opcodes::LOADK, 1, 0, 7),
            pack(Opcodes::MUL, 2, 0, 1),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = K::with_code(KernelConfig { n: 4, ..Default::default() }, code);
        k.run(100);
        assert_eq!(k.state[2], 42);
    }

    #[test]
    fn test_jitter_deterministic() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 0),
            pack(Opcodes::JITTER, 0, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = K::with_code(KernelConfig { n: 2, seed: 99, ..Default::default() }, code.clone());
        k.run(100);
        let mut k2 = K::with_code(KernelConfig { n: 2, seed: 99, ..Default::default() }, code);
        k2.run(100);
        assert_eq!(k.state[0], k2.state[0]);
    }

    #[test]
    fn test_lcg_deterministic() {
        let s = 1u32;
        assert_eq!(lcg(s), lcg(s));
    }
}
