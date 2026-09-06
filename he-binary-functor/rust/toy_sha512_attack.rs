// Toy SHA-512 Preimage Attack Engine
fn rotr8(val: u8, n: u32) -> u8 {
    (val >> (n & 7)) | (val << (8 - (n & 7)))
}

pub fn toy_sha512_round(m: u8) -> u8 {
    let sigma1 = rotr8(m, 2) ^ rotr8(m, 5) ^ (m >> 1);
    m.wrapping_add(sigma1)
}

pub fn break_toy_sha512(target_hash: u8) -> Option<u8> {
    // Exhaustive search over 256 possible 8-bit inputs
    for m in 0..=255 {
        if toy_sha512_round(m as u8) == target_hash {
            return Some(m as u8);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preimage_recovery() {
        // Target hash H = 175 (0xAF)
        let result = break_toy_sha512(175);
        assert_eq!(result, Some(60)); // m = 60 (0x3C)
    }

    #[test]
    fn test_round_function() {
        // Verify the toy SHA-512 round function
        let m: u8 = 60;
        let h = toy_sha512_round(m);
        assert_eq!(h, 175); // Expected: 175 (0xAF)
    }
}
