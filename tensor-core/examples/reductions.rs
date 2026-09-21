//! Example: Reduction operations
//!
//! Demonstrates:
//! - Sum, mean, max, min reductions
//! - Reductions along axes
//! - Variance calculation

use ndarray::Array;
use tensor_core::ops::Reduce;

fn main() {
    println!("=== Reduction Operations ===\n");

    let t = Array::from_shape_vec((2, 3, 4), (0..24).map(|i| i as f64).collect()).unwrap();
    println!("3D tensor shape: {:?}\nValues:\n{}\n", t.shape(), t);

    // Global reductions
    println!("=== Global Reductions ===");
    println!("Sum: {}", t.sum());
    println!("Mean: {}", t.mean().unwrap());
    println!("Max: {}", t.max().unwrap());
    println!("Min: {}", t.min().unwrap());
    println!("Variance: {}\n", t.variance().unwrap());

    // Axis reductions (2D example)
    let mat = Array::from_shape_vec((3, 4), (0..12).map(|i| i as f64).collect()).unwrap();
    println!("=== 2D Matrix ===");
    println!("{}\n", mat);

    let sum_axis0 = mat.sum_axis(ndarray::Axis(0));
    println!("Sum along axis 0 (rows):\n{}\n", sum_axis0);

    let sum_axis1 = mat.sum_axis(ndarray::Axis(1));
    println!("Sum along axis 1 (columns):\n{}\n", sum_axis1);

    // 1D vector reductions
    let vec = Array::from_vec(vec![1.0, 2.0, 3.0, 4.0, 5.0]);
    println!("=== 1D Vector ===");
    println!("Values: {:?}", vec.to_vec());
    println!("Sum: {}", vec.sum());
    println!("Mean: {}", vec.mean().unwrap());
    println!("Variance: {}\n", vec.variance().unwrap());

    // Empty array handling
    println!("=== Error Handling ===");
    let empty = Array::from_vec(vec![]) as ndarray::Array1<f64>;
    match empty.mean() {
        Ok(_) => println!("✗ Unexpectedly succeeded on empty array"),
        Err(e) => println!("✓ Expected error on empty array: {}\n", e),
    }

    // Cumulative sum and other derived operations
    println!("=== Derived Operations ===");
    let cumsum: Vec<f64> = vec
        .iter()
        .scan(0.0, |acc, &x| {
            *acc += x;
            Some(*acc)
        })
        .collect();
    println!("Cumulative sum: {:?}\n", cumsum);

    // Standard deviation
    let var = vec.variance().unwrap();
    let std = var.sqrt();
    println!("Standard deviation: {}\n", std);

    // Argmax / Argmin (manual implementation)
    if !vec.is_empty() {
        let max_idx = vec
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .map(|(i, _)| i);
        if let Some(idx) = max_idx {
            println!("Argmax: {} (value: {})", idx, vec[idx]);
        }
    }
}
