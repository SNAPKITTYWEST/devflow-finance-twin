use nraay_tensor::prelude::*;

fn main() -> Result<()> {
    println!("=== NraayTensor: Basic Usage ===\n");

    // Create a 3x4 tensor (zeros)
    let mut t = NraayTensor::new(vec![3, 4])?;
    println!("Created tensor:");
    println!("  Shape: {:?}", t.shape());
    println!("  Strides: {:?}", t.strides());
    println!("  Is Contiguous: {}", t.is_contiguous());
    println!("  Owns Storage: {}\n", t.owns_storage());

    // Set some values
    t.set(&[0, 0], 1.0)?;
    t.set(&[1, 1], 5.0)?;
    t.set(&[2, 2], 9.0)?;

    // Read values
    println!("Values:");
    println!("  t[0,0] = {}", t.get(&[0, 0])?);
    println!("  t[1,1] = {}", t.get(&[1, 1])?);
    println!("  t[2,2] = {}", t.get(&[2, 2])?);
    println!("  t[0,1] = {} (uninitialized)\n", t.get(&[0, 1])?);

    // Check reference counting
    println!("Reference Count: {}\n", t.refcount());

    // Transpose (logical shift, no physical copy)
    println!("=== Transpose (Logical Shift) ===");
    t.transpose(&[1, 0])?;
    println!("After transpose:");
    println!("  Shape: {:?}", t.shape());
    println!("  Strides: {:?}", t.strides());
    println!("  Is Contiguous: {}", t.is_contiguous());
    println!("  Buffer Size: {} (unchanged)\n", t.buffer_size());

    // Materialize (restore contiguity)
    println!("=== Materialize (Restore Contiguity) ===");
    t.materialize()?;
    println!("After materialize:");
    println!("  Shape: {:?}", t.shape());
    println!("  Strides: {:?}", t.strides());
    println!("  Is Contiguous: {}", t.is_contiguous());
    println!("  Owns Storage: {}\n", t.owns_storage());

    Ok(())
}
