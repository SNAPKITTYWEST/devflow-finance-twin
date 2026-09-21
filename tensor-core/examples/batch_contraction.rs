//! Example: Batch tensor contractions
//!
//! Demonstrates:
//! - Batch matrix-vector multiplication
//! - Batch matrix-matrix multiplication
//! - Higher-order tensor operations

use ndarray::{Array2, Array3};
use tensor_core::ops::{batch_matvec, batch_matmul};

fn main() {
    println!("=== Batch Tensor Contractions ===\n");

    // Batch matrix-vector multiplication
    println!("=== Batch Matrix-Vector ===");
    let batch_size = 3;
    let m = 4;
    let n = 5;

    let a = Array3::from_shape_vec(
        (batch_size, m, n),
        (0..batch_size * m * n)
            .map(|i| (i as f64 + 1.0))
            .collect(),
    )
    .unwrap();

    let v = Array2::from_shape_vec(
        (batch_size, n),
        (0..batch_size * n).map(|i| (i as f64 + 1.0)).collect(),
    )
    .unwrap();

    println!("A shape: {:?} (batch_size={}, m={}, n={})", a.shape(), batch_size, m, n);
    println!("v shape: {:?} (batch_size={}, n={})\n", v.shape(), batch_size, n);

    match batch_matvec(&a, &v) {
        Ok(result) => {
            println!("A @ v shape: {:?}", result.shape());
            println!("Result:\n{}\n", result);
        }
        Err(e) => println!("Error: {}\n", e),
    }

    // Batch matrix-matrix multiplication
    println!("=== Batch Matrix-Matrix ===");
    let k = 6;
    let b = Array3::from_shape_vec(
        (batch_size, n, k),
        (0..batch_size * n * k)
            .map(|i| (i as f64 + 1.0))
            .collect(),
    )
    .unwrap();

    println!("A shape: {:?} (batch_size={}, m={}, n={})", a.shape(), batch_size, m, n);
    println!("B shape: {:?} (batch_size={}, n={}, k={})\n", b.shape(), batch_size, n, k);

    match batch_matmul(&a, &b) {
        Ok(result) => {
            println!("A @ B shape: {:?}", result.shape());
            println!("First batch result:\n{}\n", result.index_axis(ndarray::Axis(0), 0));
        }
        Err(e) => println!("Error: {}\n", e),
    }

    // Error case: shape mismatch
    println!("=== Shape Mismatch Handling ===");
    let v_wrong = Array2::from_shape_vec((batch_size, n + 1), vec![0.0; batch_size * (n + 1)])
        .unwrap();

    match batch_matvec(&a, &v_wrong) {
        Ok(_) => println!("✗ Unexpectedly succeeded"),
        Err(e) => println!("✓ Expected error: {}\n", e),
    }

    // Real-world example: batched linear transformation
    println!("=== Real-world Example: Batched Linear Transformation ===");
    let batch = 2;
    let inputs_dim = 10;
    let outputs_dim = 5;

    let weights = Array3::from_shape_vec(
        (batch, outputs_dim, inputs_dim),
        (0..batch * outputs_dim * inputs_dim)
            .map(|i| ((i as f64) / 1000.0))
            .collect(),
    )
    .unwrap();

    let inputs =
        Array2::from_shape_vec(
            (batch, inputs_dim),
            (0..batch * inputs_dim).map(|i| (i as f64)).collect(),
        )
        .unwrap();

    match batch_matvec(&weights, &inputs) {
        Ok(outputs) => {
            println!("Weights shape: {:?}", weights.shape());
            println!("Inputs shape: {:?}", inputs.shape());
            println!("Outputs shape: {:?}", outputs.shape());
            println!("Sample output (first batch):\n{}\n", outputs.row(0));
        }
        Err(e) => println!("Error: {}", e),
    }
}
