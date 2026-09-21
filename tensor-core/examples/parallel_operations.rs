//! Example: Parallel tensor operations
//!
//! Demonstrates:
//! - Parallel element-wise operations
//! - Parallel reductions
//! - Performance benefits

use ndarray::Array2;
use ndarray::parallel::prelude::*;

fn main() {
    println!("=== Parallel Tensor Operations ===\n");

    let n = 2000;
    println!("Creating {}x{} matrix\n", n, n);

    let mut a = Array2::<f64>::zeros((n, n));

    // Parallel element-wise fill
    println!("=== Parallel Element-wise Fill ===");
    a.par_mapv_inplace(|_| 1.5);
    println!("✓ Parallel fill complete\n");

    // Parallel sum
    println!("=== Parallel Reduction ===");
    let sum: f64 = a.par_iter().sum();
    println!("Parallel sum: {} (expected: {})\n", sum, (n * n) as f64 * 1.5);

    // Parallel axis reduction
    println!("=== Axis Reduction ===");
    let sum_rows: Vec<f64> = a
        .outer_iter()
        .map(|row| row.iter().sum::<f64>())
        .collect();
    println!("Sum of first few rows:");
    for (i, &s) in sum_rows.iter().take(3).enumerate() {
        println!("  Row {}: {}", i, s);
    }
    println!();

    // Complex parallel operation: parallel inplace modification
    println!("=== Parallel In-place Modification ===");
    let mut d = Array2::from_shape_vec((n, n), (0..n * n).map(|i| i as f64).collect()).unwrap();
    d.par_mapv_inplace(|x| x * 2.0);
    let sum_all: f64 = d.par_iter().sum();
    println!("Parallel in-place modify complete, sum: {}\n", sum_all);

    // Element-wise operation then reduction
    println!("=== Sequential Element-wise with Parallel Reduction ===");
    let e = Array2::from_shape_vec((n, n), (0..n * n).map(|i| i as f64).collect()).unwrap();

    let doubled = e.mapv(|x| x * 2.0 + 1.0);
    let parallel_sum: f64 = doubled.par_iter().sum();
    println!("Element-wise then parallel sum: {}\n", parallel_sum);

    // Performance note
    println!("=== Performance Notes ===");
    println!("For tensor operations:");
    println!("  - Small tensors (< 10k elements): overhead may dominate");
    println!("  - Medium tensors (10k - 1M): parallelism helpful");
    println!("  - Large tensors (> 1M): significant speedup expected");
    println!("\nActual speedup depends on:");
    println!("  - Number of CPU cores");
    println!("  - Cache locality and memory bandwidth");
    println!("  - Operation complexity");
}
