pub const FIELD_MODULUS: u64 = 0xFFFFFFFFFFFFFFC5; // Mersenne-like prime

#[inline]
pub fn mul_mod(a: u64, b: u64, modulus: u64) -> u64 {
    ((a as u128 * b as u128) % modulus as u128) as u64
}

#[inline]
pub fn add_mod(a: u64, b: u64, modulus: u64) -> u64 {
    (a + b >= modulus).then_some(a + b - modulus).unwrap_or(a + b)
}

pub fn compute_iamac(key: u64, message_vector: &[u64], eval_point: u64) -> u64 {
    let mut poly_eval = 0u64;
    let mut x_pow = 1u64;

    for &m_i in message_vector {
        let term = mul_mod(m_i, x_pow, FIELD_MODULUS);
        poly_eval = add_mod(poly_eval, term, FIELD_MODULUS);
        x_pow = mul_mod(x_pow, eval_point, FIELD_MODULUS);
    }

    mul_mod(poly_eval, key, FIELD_MODULUS)
}

pub fn verify_aggregated_iamac(
    key: u64, 
    tag_a: u64, 
    tag_b: u64, 
    expected_sum_tag: u64
) -> bool {
    let computed_sum = add_mod(tag_a, tag_b, FIELD_MODULUS);
    computed_sum == expected_sum_tag
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn homomorphic_addition() {
        let key = 42u64;
        let eval = 7u64;
        let msg_a = [1u64, 2, 3];
        let msg_b = [4u64, 5, 6];
        let msg_sum = [5u64, 7, 9];

        let tag_a = compute_iamac(key, &msg_a, eval);
        let tag_b = compute_iamac(key, &msg_b, eval);
        let tag_sum = compute_iamac(key, &msg_sum, eval);

        assert!(verify_aggregated_iamac(key, tag_a, tag_b, tag_sum));
    }
}
