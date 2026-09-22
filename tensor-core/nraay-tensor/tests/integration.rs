use nraay_tensor::prelude::*;
use std::sync::Arc;

#[test]
fn test_1_identity_layout() {
    let t = NraayTensor::new(vec![2, 3]).unwrap();
    assert_eq!(t.is_contiguous(), true);
    assert_eq!(t.owns_storage(), true);
    assert_eq!(t.refcount(), 1);
}

#[test]
fn test_2_logical_shift() {
    let mut t = NraayTensor::new(vec![2, 3]).unwrap();
    t.transpose(&[1, 0]).unwrap();

    assert_eq!(t.shape(), &[3, 2]);
    assert_eq!(t.is_contiguous(), false); // B_layout → 0
    assert_eq!(t.buffer_size(), 6); // Physical size unchanged
}

#[test]
fn test_3_bound_restoration() {
    let mut t = NraayTensor::new(vec![2, 3]).unwrap();
    t.transpose(&[1, 0]).unwrap();

    t.materialize().unwrap();

    assert_eq!(t.is_contiguous(), true); // B_layout → 1
    assert_eq!(t.strides(), &[2, 1]); // Canonical for [3, 2]
}

#[test]
fn test_4_adversarial_shift() {
    let mut t = NraayTensor::new(vec![3, 4, 5]).unwrap();

    // Apply multiple permutations
    t.transpose(&[2, 0, 1]).unwrap();
    assert_eq!(t.is_contiguous(), false);

    t.transpose(&[1, 0, 2]).unwrap();
    assert_eq!(t.is_contiguous(), false);

    // Only materialize restores B_layout
    t.materialize().unwrap();
    assert_eq!(t.is_contiguous(), true);
}

#[test]
fn test_5_zero_copy_slice() {
    let t = NraayTensor::new(vec![4, 4]).unwrap();
    let s = t.slice(&[(1, 3, 1), (0, 4, 1)]).unwrap();

    assert_eq!(Arc::ptr_eq(&t.data(), &s.data()), true); // Same Arc
    assert_eq!(s.offset(), 4); // Offset = 1 * stride[0]
    assert_eq!(s.shape(), &[2, 4]);
    assert_eq!(s.is_contiguous(), true); // Unit steps preserve canonical
}

#[test]
fn test_6_non_contiguous_slice() {
    let t = NraayTensor::new(vec![4, 4]).unwrap();
    let s = t.slice(&[(0, 4, 1), (0, 4, 2)]).unwrap();

    assert_eq!(Arc::ptr_eq(&t.data(), &s.data()), true); // Shared
    assert_eq!(s.is_contiguous(), false); // Step=2 breaks canonical
}

#[test]
fn test_7_cow_isolation() {
    let t = NraayTensor::new(vec![4, 4]).unwrap();
    let mut s = t.slice(&[(0, 2, 1), (0, 4, 1)]).unwrap();

    let t_data_before = Arc::clone(&t.data());

    s.materialize().unwrap();

    // S gets new buffer
    assert_ne!(Arc::ptr_eq(&t.data(), &s.data()), true);
    // T's buffer unchanged
    assert!(Arc::ptr_eq(&t.data(), &t_data_before));
}

#[test]
fn test_8_slice_of_slice() {
    let t = NraayTensor::new(vec![8, 8]).unwrap();
    let s1 = t.slice(&[(1, 6, 1), (1, 6, 1)]).unwrap();
    let s2 = s1.slice(&[(0, 3, 1), (0, 3, 1)]).unwrap();

    // Verify compositional slicing
    assert_eq!(s2.shape(), &[3, 3]);
    // t[1:6, 1:6][0:3, 0:3] == t[1:4, 1:4]
    assert_eq!(s2.offset(), 9); // 1*8 + 1 = 9
}

#[test]
fn test_9_refcount_release() {
    let t = NraayTensor::new(vec![4, 4]).unwrap();
    let s1 = t.slice(&[(0, 2, 1), (0, 4, 1)]).unwrap();
    let s2 = t.slice(&[(2, 4, 1), (0, 4, 1)]).unwrap();

    assert_eq!(t.refcount(), 3); // t, s1, s2

    drop(s1);
    assert_eq!(t.refcount(), 2);

    drop(s2);
    assert_eq!(t.refcount(), 1); // Only t
}

#[test]
fn test_10_adversarial_view_graph() {
    let t = NraayTensor::new(vec![4, 4]).unwrap();

    // Create multiple view permutations
    let mut views = vec![];

    for _ in 0..3 {
        let s = t.slice(&[(0, 2, 1), (0, 4, 1)]).unwrap();
        views.push(s);
    }

    assert_eq!(t.refcount(), 4); // t + 3 views

    // Materialize each
    for v in &mut views {
        v.materialize().ok();
    }

    // After materialization, views have their own buffers
    for v in &views {
        assert!(v.is_contiguous());
        assert!(v.owns_storage());
    }
}

#[test]
fn test_buffer_lifetime_safety() {
    // Test that buffer is not freed while views exist
    let t = NraayTensor::new(vec![4, 4]).unwrap();
    let s = t.slice(&[(0, 2, 1), (0, 4, 1)]).unwrap();

    // Both hold Arc strong count
    assert_eq!(t.refcount(), 2);

    // Drop t but s still valid
    drop(t);
    assert_eq!(s.refcount(), 1); // s alone

    // Buffer freed when s drops (end of scope)
}

#[test]
fn test_materialization_non_interference() {
    let t = NraayTensor::new(vec![4, 4]).unwrap();
    let s1 = t.slice(&[(0, 2, 1), (0, 4, 1)]).unwrap();
    let mut s2 = t.slice(&[(2, 4, 1), (0, 4, 1)]).unwrap();

    let t_ptr_before = Arc::as_ptr(&t.data());

    // Materialize s2
    s2.materialize().unwrap();

    // t's buffer unchanged
    assert_eq!(Arc::as_ptr(&t.data()), t_ptr_before);
    // s1 still shares with t
    assert_eq!(Arc::ptr_eq(&t.data(), &s1.data()), true);
}

#[test]
fn test_exclusive_ownership_post_materialize() {
    let t = NraayTensor::new(vec![2, 3]).unwrap();
    let mut s = t.slice(&[(0, 2, 1), (0, 3, 1)]).unwrap();

    // Before: shared
    assert_eq!(s.refcount(), 2);
    assert!(!s.owns_storage());

    // Materialize
    s.materialize().unwrap();

    // After: s exclusive, t unchanged
    assert_eq!(s.refcount(), 1);
    assert!(s.owns_storage());
    assert_eq!(t.refcount(), 1);
}

#[test]
fn test_get_set_operations() {
    let mut t = NraayTensor::new(vec![3, 3]).unwrap();

    // Set values
    t.set(&[0, 0], 1.0).unwrap();
    t.set(&[1, 1], 5.0).unwrap();
    t.set(&[2, 2], 9.0).unwrap();

    // Get values
    assert_eq!(t.get(&[0, 0]).unwrap(), 1.0);
    assert_eq!(t.get(&[1, 1]).unwrap(), 5.0);
    assert_eq!(t.get(&[2, 2]).unwrap(), 9.0);

    // Get unset (should be 0.0)
    assert_eq!(t.get(&[0, 1]).unwrap(), 0.0);
}

#[test]
fn test_get_set_on_slice() {
    let mut t = NraayTensor::new(vec![4, 4]).unwrap();
    t.set(&[0, 0], 10.0).unwrap();

    let s = t.slice(&[(0, 2, 1), (0, 4, 1)]).unwrap();

    // Read through slice
    assert_eq!(s.get(&[0, 0]).unwrap(), 10.0);
}

#[test]
fn test_contiguity_check() {
    let mut t = NraayTensor::new(vec![2, 3, 4]).unwrap();

    // Identity is contiguous
    assert!(t.is_contiguous());

    // After transpose, non-contiguous
    t.transpose(&[2, 0, 1]).unwrap();
    assert!(!t.is_contiguous());

    // After materialize, canonical
    t.materialize().unwrap();
    assert!(t.is_contiguous());
}

#[test]
fn test_stride_calculation() {
    let mut t = NraayTensor::new(vec![2, 3, 4]).unwrap();
    assert_eq!(t.strides(), &[12, 4, 1]);

    // After transpose [2, 0, 1]: shape [4, 2, 3], strides [1, 12, 4]
    t.transpose(&[2, 0, 1]).unwrap();
    assert_eq!(t.strides(), &[1, 12, 4]);
}
