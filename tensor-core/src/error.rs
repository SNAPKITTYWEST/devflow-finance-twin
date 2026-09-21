//! Error types for tensor operations.

use thiserror::Error;

/// Tensor operation error type.
#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum TensorError {
    /// Shape mismatch between operands.
    #[error("shape mismatch: expected {expected:?}, got {actual:?}")]
    ShapeMismatch {
        expected: Vec<usize>,
        actual: Vec<usize>,
    },

    /// Dimension index out of bounds.
    #[error("dimension out of bounds: axis {axis} for rank {rank}")]
    DimOutOfBounds { axis: usize, rank: usize },

    /// Operation on empty array not supported.
    #[error("empty array operation not supported")]
    EmptyArray,

    /// Rank mismatch (incorrect number of dimensions).
    #[error("rank mismatch: expected {expected}, got {actual}")]
    RankMismatch { expected: usize, actual: usize },

    /// Incompatible shapes for operation.
    #[error("incompatible shapes: {0}")]
    IncompatibleShapes(String),

    /// Index out of bounds.
    #[error("index out of bounds: {0}")]
    IndexOutOfBounds(String),

    /// Invalid reshape operation.
    #[error("reshape failed: cannot reshape {from:?} to {to:?}")]
    ReshapeFailed { from: Vec<usize>, to: Vec<usize> },

    /// Division by zero.
    #[error("division by zero")]
    DivisionByZero,
}

/// Specialized `Result` type for tensor operations.
pub type Result<T> = std::result::Result<T, TensorError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_creation() {
        let err = TensorError::ShapeMismatch {
            expected: vec![2, 3],
            actual: vec![3, 2],
        };
        assert!(err.to_string().contains("shape mismatch"));
    }

    #[test]
    fn test_error_equality() {
        let err1 = TensorError::EmptyArray;
        let err2 = TensorError::EmptyArray;
        assert_eq!(err1, err2);
    }
}
