//! Error types for NraayTensor operations.

use thiserror::Error;

/// Error type for NraayTensor operations.
#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum NraayError {
    /// Shape mismatch in operation.
    #[error("shape mismatch: expected {expected:?}, got {actual:?}")]
    ShapeMismatch {
        expected: Vec<usize>,
        actual: Vec<usize>,
    },

    /// Index out of bounds.
    #[error("index out of bounds at dimension {dim}: {index} >= {size}")]
    IndexOutOfBounds { dim: usize, index: usize, size: usize },

    /// Invalid slice range.
    #[error("invalid slice range: start={start} >= end={end} (dim size={size})")]
    InvalidSliceRange { start: usize, end: usize, size: usize },

    /// Dimension mismatch.
    #[error("dimension mismatch: expected {expected}, got {actual}")]
    DimensionMismatch { expected: usize, actual: usize },

    /// Cannot transpose with invalid permutation.
    #[error("invalid transpose permutation: expected length {expected}, got {actual}")]
    InvalidPermutation { expected: usize, actual: usize },

    /// Empty tensor operation not supported.
    #[error("operation on empty tensor not supported")]
    EmptyTensor,

    /// Cannot materialize already contiguous tensor.
    #[error("tensor is already contiguous")]
    AlreadyContiguous,
}

/// Specialized `Result` type for NraayTensor operations.
pub type Result<T> = std::result::Result<T, NraayError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_creation() {
        let err = NraayError::ShapeMismatch {
            expected: vec![2, 3],
            actual: vec![3, 2],
        };
        assert!(err.to_string().contains("shape mismatch"));
    }

    #[test]
    fn test_error_equality() {
        let err1 = NraayError::EmptyTensor;
        let err2 = NraayError::EmptyTensor;
        assert_eq!(err1, err2);
    }
}
