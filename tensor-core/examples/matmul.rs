//! Example: Matrix multiplication and linear algebra
//!
//! Demonstrates:
//! - Matrix-matrix multiplication
//! - Matrix transpose
//! - Identity and diagonal operations

use ndarray::Array2;
use tensor_core::ops::LinearAlgebra;

fn main() {
    println!("=== Matrix Multiplication and Linear Algebra ===\n");

    // Create matrices
    let a = Array2::from_shape_vec((2, 3), vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
    let b = Array2::from_shape_vec((3, 2), vec![7.0, 8.0, 9.0, 10.0, 11.0, 12.0]).unwrap();

    println!("Matrix A (2x3):\n{}\n", a);
    println!("Matrix B (3x2):\n{}\n", b);

    // Matrix multiplication
    let c = a.dot(&b);
    println!("A @ B (2x2):\n{}\n", c);

    // Reverse order
    let d = b.dot(&a);
    println!("B @ A (3x3):\n{}\n", d);

    // Transpose
    let a_t = a.transpose();
    println!("A^T (3x2):\n{}\n", a_t);

    // Verify transpose properties
    let a_tt = a_t.transpose();
    println!("(A^T)^T == A: {}\n", a_tt == a);

    // Identity matrices
    let eye3 = Array2::<f64>::eye(3);
    let eye2 = Array2::<f64>::eye(2);
    println!("I_3 (identity):\n{}\n", eye3);
    println!("I_2 (identity):\n{}\n", eye2);

    // A @ I = A
    let a_eye = a.dot(&eye3);
    println!("A @ I_3 == A: {}\n", a_eye == a);

    // Square matrix operations
    let square = Array2::from_shape_vec((3, 3), (0..9).map(|i| i as f64 + 1.0).collect())
        .unwrap();
    println!("Square matrix (3x3):\n{}\n", square);

    let square_t = square.transpose();
    println!("Transpose:\n{}\n", square_t);

    // Self multiplication
    let square2 = square.dot(&square);
    println!("A @ A:\n{}\n", square2);

    // Vector-matrix multiplication (treat as 2x1)
    let v = Array2::from_shape_vec((3, 1), vec![1.0, 2.0, 3.0]).unwrap();
    println!("Vector v (3x1):\n{}\n", v);

    let av = a.dot(&v);
    println!("A @ v:\n{}\n", av);

    // Row vector
    let row = Array2::from_shape_vec((1, 2), vec![1.0, 2.0]).unwrap();
    let row_result = row.dot(&c);
    println!("row @ (A @ B):\n{}\n", row_result);
}
