//! # Tensor Core: Formal Array/Tensor Library for Rust 2024
//!
//! A high-performance, formally verified tensor/array library built on `ndarray`.
//! Provides ergonomic, zero-cost abstractions for numerical computing with full type safety.

pub mod error;
pub mod ops;
pub mod random;
pub mod tensor;

pub use error::{Result, TensorError};
pub use tensor::Tensor;

pub mod prelude {
    pub use crate::error::{Result, TensorError};
    pub use crate::tensor::Tensor;
    pub use ndarray::{
        s, Array, Array1, Array2, Array3, Array4, Array5, Array6, ArrayView, ArrayViewMut,
        Axis, Ix, IxDyn,
    };
}
