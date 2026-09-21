use nraay_tensor::prelude::*;

fn main() -> Result<()> {
    println!("=== NraayTensor: Virtual Slicing ===\n");

    let t = NraayTensor::new(vec![4, 4])?;
    println!("Original tensor: shape {:?}, refcount {}\n", t.shape(), t.refcount());

    // Slice 1: Rows [1:3], all columns
    println!("=== Slice 1: [1:3, :] (unit steps) ===");
    let s1 = t.slice(&[(1, 3, 1), (0, 4, 1)])?;
    println!("  Shape: {:?}", s1.shape());
    println!("  Offset: {}", s1.offset());
    println!("  Strides: {:?}", s1.strides());
    println!("  Is Contiguous: {}", s1.is_contiguous());
    println!("  Shared Buffer: {}", std::ptr::eq(
        std::sync::Arc::as_ptr(&t.data()),
        std::sync::Arc::as_ptr(&s1.data())
    ));
    println!("  Refcount: {}\n", t.refcount());

    // Slice 2: All rows, columns [::2] (step=2)
    println!("=== Slice 2: [:, ::2] (step=2) ===");
    let s2 = t.slice(&[(0, 4, 1), (0, 4, 2)])?;
    println!("  Shape: {:?}", s2.shape());
    println!("  Strides: {:?}", s2.strides());
    println!("  Is Contiguous: {} (step breaks canonical)\n", s2.is_contiguous());

    // Slice 3: Sub-slice of Slice 1
    println!("=== Slice 3: Slice-of-Slice ===");
    let s3 = s1.slice(&[(0, 2, 1), (0, 4, 1)])?;
    println!("  Shape: {:?}", s3.shape());
    println!("  Offset: {} (composed offsets)", s3.offset());
    println!("  Strides: {:?}", s3.strides());
    println!("  Refcount: {}\n", t.refcount());

    // Show sharing
    println!("=== Shared Buffer Analysis ===");
    println!("t, s1, s2 all share the same buffer:");
    println!("  t.refcount() = {}", t.refcount());
    println!("  s1.refcount() = {}", s1.refcount());
    println!("  s2.refcount() = {}\n", s2.refcount());

    // Dropping slices decrements refcount
    println!("=== Reference Counting ===");
    drop(s1);
    println!("After dropping s1: t.refcount() = {}", t.refcount());

    drop(s2);
    println!("After dropping s2: t.refcount() = {}", t.refcount());

    drop(s3);
    println!("After dropping s3: t.refcount() = {}\n", t.refcount());

    Ok(())
}
