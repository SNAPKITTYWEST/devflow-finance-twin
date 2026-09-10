// BQN-shaped mathematical specification for the Recursive Jitter Machine.
// This module documents the formal semantics in Rust-idiomatic form.
//
// The BQN spec defines:
//   LCG     ← { (1664525×𝕩) + 1013904223 }
//   Fuse    ← ∧´
//   AssertEq← { 𝕨=𝕩 }
//   FuseAsserts← { ∧´ 𝕨 AssertEq¨ 𝕩 }

pub fn lcg_bqn(seed: u32) -> u32 {
    seed.wrapping_mul(1664525).wrapping_add(1013904223)
}

pub fn fuse_asserts(left: &[u32], right: &[u32]) -> bool {
    left.iter().zip(right.iter()).all(|(a, b)| a == b)
}

pub fn jitter_cell(seed: u32, value: u32) -> (u32, u32) {
    let s2 = lcg_bqn(seed);
    let new_val = value ^ (s2 >> 16);
    (s2, new_val)
}

pub fn rec_jitter(seed: u32, vec: &[u32]) -> (u32, Vec<u32>) {
    let s2 = lcg_bqn(seed);
    let len = vec.len() as u32;
    if len == 0 {
        return (s2, vec.to_vec());
    }
    let i = (s2 % len) as usize;
    let mut out = vec.to_vec();
    out[i] = s2 ^ out[i];
    (s2, out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lcg_matches_kernel() {
        use super::super::ops::lcg;
        let s = 42u32;
        assert_eq!(lcg_bqn(s), lcg(s));
    }

    #[test]
    fn test_fuse_asserts_true() {
        assert!(fuse_asserts(&[1, 2, 3], &[1, 2, 3]));
    }

    #[test]
    fn test_fuse_asserts_false() {
        assert!(!fuse_asserts(&[1, 2, 3], &[1, 2, 0]));
    }

    #[test]
    fn test_fuse_asserts_empty() {
        assert!(fuse_asserts(&[], &[]));
    }

    #[test]
    fn test_jitter_cell() {
        let (s2, v) = jitter_cell(1, 0);
        assert_ne!(v, 0);
        assert_ne!(s2, 1);
    }

    #[test]
    fn test_rec_jitter_empty() {
        let (s, out) = rec_jitter(1, &[]);
        assert!(out.is_empty());
        assert_ne!(s, 1);
    }

    #[test]
    fn test_rec_jitter_deterministic() {
        let vec = vec![10, 20, 30];
        let (s1, v1) = rec_jitter(42, &vec);
        let (s2, v2) = rec_jitter(42, &vec);
        assert_eq!(s1, s2);
        assert_eq!(v1, v2);
    }
}
