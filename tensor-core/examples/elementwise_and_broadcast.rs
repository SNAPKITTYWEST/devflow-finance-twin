//! Example: Element-wise operations and broadcasting
//!
//! Demonstrates:
//! - Scalar operations
//! - Element-wise arithmetic
//! - Broadcasting semantics
//! - Fused operations with Zip

use ndarray::{s, Array, Zip};
use tensor_core::ops::ElementWise;

fn main() {
    println!("=== Element-wise and Broadcasting Operations ===\n");

    let a = Array::from_shape_vec((2, 3), vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
    let b = Array::from_elem((2, 3), 10.0);

    println!("Matrix A:\n{}\n", a);
    println!("Matrix B (all 10s):\n{}\n", b);

    // Addition
    let c = &a + &b;
    println!("A + B:\n{}\n", c);

    // Subtraction
    let d = &b - &a;
    println!("B - A:\n{}\n", d);

    // Element-wise multiplication
    let e = &a * 2.0;
    println!("A * 2:\n{}\n", e);

    // Element-wise division
    let f = &b / 5.0;
    println!("B / 5:\n{}\n", f);

    // Scalar operations via trait
    let g = a.add_scalar(100.0);
    println!("A + 100 (scalar):\n{}\n", g);

    let h = a.mul_scalar(3.0);
    println!("A * 3 (scalar):\n{}\n", h);

    // Map with closure
    let squared = a.mapv(|x| x * x);
    println!("A squared (map):\n{}\n", squared);

    // Absolute value
    let neg = a.sub_scalar(3.0);
    println!("A - 3:\n{}\n", neg);
    let abs_val = neg.abs();
    println!("abs(A - 3):\n{}\n", abs_val);

    // Broadcasting with Zip (fused operations)
    println!("=== Fused Operations ===");
    let mut result = Array::zeros(a.raw_dim());
    Zip::from(&mut result)
        .and(&a)
        .and(&b)
        .for_each(|r, &x, &y| *r = x * y + 1.0);
    println!("Fused: (A * B + 1):\n{}\n", result);

    // Complex fused operation
    let mut complex = Array::zeros(a.raw_dim());
    Zip::from(&mut complex)
        .and(&a)
        .and(&b)
        .for_each(|r, &x, &y| {
            if y > 0.0 {
                *r = x / y;
            } else {
                *r = 0.0;
            }
        });
    println!("Fused: (A / B with check):\n{}\n", complex);

    // Slicing and broadcasting
    let row = a.slice(s![0, ..]);
    println!("First row: {:?}\n", row);

    let col = a.slice(s![.., 1]);
    println!("Second column: {:?}\n", col);

    // Column-wise operations
    let mut col_normalized = Array::zeros(a.raw_dim());
    for i in 0..a.ncols() {
        let col_sum = a.column(i).iter().sum::<f64>();
        Zip::from(col_normalized.column_mut(i))
            .and(a.column(i))
            .for_each(|r, &x| *r = x / col_sum);
    }
    println!("Column-normalized:\n{}\n", col_normalized);
}
