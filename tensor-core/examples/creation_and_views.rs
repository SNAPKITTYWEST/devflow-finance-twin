//! Example: Tensor creation and views
//!
//! Demonstrates:
//! - Creating tensors with different shapes
//! - Zero-copy views and slicing
//! - Shape and bounds verification

use ndarray::{array, s, Array, Ix3};
use tensor_core::Tensor;

fn main() {
    println!("=== Tensor Creation and Views ===\n");

    // Create a 2D tensor from an array literal
    let a = array![[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]];
    let t = Tensor::new(a);
    println!("2D tensor:\n{}\nShape: {:?}, Rank: {}\n", t, t.shape(), t.rank());

    // Create zero and one tensors
    let zeros: Tensor<f64, Ix3> = Tensor::new(Array::zeros((3, 4, 5)));
    println!("Zeros tensor shape: {:?} (rank={})\n", zeros.shape(), zeros.rank());

    let ones: Tensor<f64, ndarray::Ix2> = Tensor::new(Array::ones((2, 3)));
    println!("Ones tensor shape: {:?}\n", ones.shape());

    // Create identity matrix
    let eye = Tensor::eye(4);
    println!("Identity matrix (4x4):\n{}\n", eye);

    // Create from vec
    let from_vec = Tensor::from_vec((2, 3), vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
    println!("From vec:\n{}\n", from_vec);

    // Bounds checking
    println!("=== Bounds Checking ===");
    match from_vec.verify_bounds(&[0, 0]) {
        Ok(_) => println!("✓ Index [0, 0] is valid"),
        Err(e) => println!("✗ Error: {}", e),
    }

    match from_vec.verify_bounds(&[1, 2]) {
        Ok(_) => println!("✓ Index [1, 2] is valid"),
        Err(e) => println!("✗ Error: {}", e),
    }

    match from_vec.verify_bounds(&[2, 0]) {
        Ok(_) => println!("✓ Index [2, 0] is valid"),
        Err(e) => println!("✗ Error: {}", e),
    }
    println!();

    // Slicing through underlying array
    let arr: ndarray::Array2<f64> = array![[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]];
    let t2 = Tensor::new(arr);
    let view = t2.as_array().slice(s![.., 1..]);
    println!("Sliced view (columns 1..end):\n{}\n", view);

    // Reshape operation
    println!("=== Reshape Operations ===");
    let shape_orig = t2.shape();
    println!("Original shape: {:?}", shape_orig);

    match t2.reshape(&[9]) {
        Ok(reshaped) => println!("Reshaped to {:?}\n", reshaped.shape()),
        Err(e) => println!("Error: {}", e),
    }

    // Invalid reshape
    match t2.reshape(&[4, 4]) {
        Ok(reshaped) => println!("Reshaped to {:?}", reshaped.shape()),
        Err(e) => println!("✓ Expected error: {}\n", e),
    }

    // Linspace and arange
    println!("=== Ranges ===");
    let linspace = Tensor::linspace(0.0, 1.0, 11);
    println!("Linspace [0,1] with 11 points: {:?}\n", linspace.shape());

    match Tensor::arange(0.0, 10.0, 2.0) {
        Ok(arange) => {
            println!(
                "Arange [0,10) step 2: {:?} elements\n",
                arange.as_array()
            );
        }
        Err(e) => println!("Error: {}", e),
    }

    // Strides
    println!("=== Memory Layout ===");
    println!("Strides: {:?}", t2.strides());
    println!("Is C-contiguous: {}", t2.is_c_contiguous());
}
