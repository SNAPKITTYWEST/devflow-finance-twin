use nraay_tensor::prelude::*;
use std::sync::Arc;

fn main() -> Result<()> {
    println!("=== NraayTensor: Materialization & COW ===\n");

    let mut t = NraayTensor::new(vec![3, 4])?;
    println!("Original tensor: shape {:?}, contiguous: {}\n", t.shape(), t.is_contiguous());

    // Apply transpose (logical shift)
    println!("=== Step 1: Transpose ===");
    t.transpose(&[1, 0])?;
    println!("After transpose:");
    println!("  Shape: {:?}", t.shape());
    println!("  Is Contiguous: {}", t.is_contiguous());
    println!("  Strides: {:?}\n", t.strides());

    // Create slices (shared ownership)
    println!("=== Step 2: Create Slices ===");
    let s1 = t.slice(&[(0, 2, 1), (0, 3, 1)])?;
    let s2 = t.slice(&[(2, 4, 1), (0, 3, 1)])?;

    println!("Created s1 and s2:");
    println!("  t.refcount() = {} (t + s1 + s2)", t.refcount());
    println!("  s1.is_contiguous() = {}", s1.is_contiguous());
    println!("  s2.is_contiguous() = {}\n", s2.is_contiguous());

    // Materialize main tensor
    println!("=== Step 3: Materialize main tensor ===");
    let t_buf_ptr_before = Arc::as_ptr(&t.data());
    t.materialize()?;
    let t_buf_ptr_after = Arc::as_ptr(&t.data());

    println!("After t.materialize():");
    println!("  t.is_contiguous() = {}", t.is_contiguous());
    println!("  t.owns_storage() = {}", t.owns_storage());
    println!("  Buffer changed: {}", t_buf_ptr_before != t_buf_ptr_after);
    println!("  t.refcount() = {} (only t, slices still share old buffer)\n", t.refcount());

    // Slices still valid (share original buffer)
    println!("=== Step 4: Slices Still Valid ===");
    println!("s1 still valid:");
    println!("  s1.shape() = {:?}", s1.shape());
    println!("  s1.is_contiguous() = {}", s1.is_contiguous());
    println!("  s1.refcount() = {} (s1 + s2, both still share original buffer)\n", s1.refcount());

    // Materialize a slice (COW)
    println!("=== Step 5: Materialize Slice (COW) ===");
    let mut s1_mut = s1;
    let s1_buf_ptr_before = Arc::as_ptr(&s1_mut.data());
    s1_mut.materialize()?;
    let s1_buf_ptr_after = Arc::as_ptr(&s1_mut.data());

    println!("After s1_mut.materialize():");
    println!("  s1_mut.is_contiguous() = {}", s1_mut.is_contiguous());
    println!("  s1_mut.owns_storage() = {}", s1_mut.owns_storage());
    println!("  Buffer changed (COW): {}", s1_buf_ptr_before != s1_buf_ptr_after);
    println!("  s1_mut.refcount() = {} (exclusive)", s1_mut.refcount());
    println!("  s2.refcount() = {} (s2 still on original buffer)\n", s2.refcount());

    // Show isolation
    println!("=== Step 6: Buffer Isolation ===");
    println!("After COW materialization:");
    println!("  t, s1_mut have DIFFERENT buffers:");
    println!("    t.data() ptr: {:?}", Arc::as_ptr(&t.data()));
    println!("    s1_mut.data() ptr: {:?}", Arc::as_ptr(&s1_mut.data()));
    println!("  s2 still shares original buffer with nothing");

    Ok(())
}
