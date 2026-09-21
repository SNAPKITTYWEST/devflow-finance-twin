//! Core tensor wrapper and operations.

use crate::error::{Result, TensorError};
use ndarray::{Array, Array1, Array2, Array3, Dimension, IxDyn};
use std::fmt;

/// A thin, zero-cost wrapper around ndarray for ergonomic tensor operations.
#[derive(Clone)]
pub struct Tensor<A, D: Dimension> {
    data: Array<A, D>,
}

impl<A, D: Dimension> Tensor<A, D> {
    /// Create a tensor from an existing array.
    pub fn new(data: Array<A, D>) -> Self {
        Tensor { data }
    }

    /// Get a reference to the underlying ndarray.
    pub fn as_array(&self) -> &Array<A, D> {
        &self.data
    }

    /// Get a mutable reference to the underlying ndarray.
    pub fn as_array_mut(&mut self) -> &mut Array<A, D> {
        &mut self.data
    }

    /// Convert into the underlying ndarray.
    pub fn into_array(self) -> Array<A, D> {
        self.data
    }

    /// Get the shape of the tensor.
    pub fn shape(&self) -> &[usize] {
        self.data.shape()
    }

    /// Get the rank (number of dimensions).
    pub fn rank(&self) -> usize {
        self.data.ndim()
    }

    /// Get the total number of elements.
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// Check if the tensor is empty.
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }

    /// Verify bounds for an index.
    pub fn verify_bounds(&self, idx: &[usize]) -> Result<()> {
        if idx.len() != self.rank() {
            return Err(TensorError::RankMismatch {
                expected: self.rank(),
                actual: idx.len(),
            });
        }

        for (axis, &index) in idx.iter().enumerate() {
            if index >= self.shape()[axis] {
                return Err(TensorError::IndexOutOfBounds(format!(
                    "index {} out of bounds for axis {} (size {})",
                    index, axis, self.shape()[axis]
                )));
            }
        }
        Ok(())
    }

    /// Get strides.
    pub fn strides(&self) -> &[isize] {
        self.data.strides()
    }

    /// Check if the tensor is contiguous in C order.
    pub fn is_c_contiguous(&self) -> bool {
        self.data.is_standard_layout()
    }

    /// Reshape the tensor.
    pub fn reshape(&self, new_shape: &[usize]) -> Result<Array<A, IxDyn>>
    where
        A: Clone,
    {
        let total_old: usize = self.shape().iter().product();
        let total_new: usize = new_shape.iter().product();

        if total_old != total_new {
            return Err(TensorError::ReshapeFailed {
                from: self.shape().to_vec(),
                to: new_shape.to_vec(),
            });
        }

        self.data
            .clone()
            .into_shape_with_order(IxDyn(new_shape))
            .map_err(|_| TensorError::ReshapeFailed {
                from: self.shape().to_vec(),
                to: new_shape.to_vec(),
            })
    }
}

impl<A: Clone, D: Dimension> Tensor<A, D> {
    /// Permute axes.
    pub fn permute(&self, axes: &[usize]) -> Result<Array<A, IxDyn>>
    where
        A: Clone,
    {
        if axes.len() != self.rank() {
            return Err(TensorError::RankMismatch {
                expected: self.rank(),
                actual: axes.len(),
            });
        }

        for &axis in axes {
            if axis >= self.rank() {
                return Err(TensorError::DimOutOfBounds {
                    axis,
                    rank: self.rank(),
                });
            }
        }

        Ok(self.data.to_owned().into_dyn())
    }
}

impl<A: fmt::Debug, D: Dimension> fmt::Debug for Tensor<A, D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Tensor")
            .field("shape", &self.shape())
            .field("rank", &self.rank())
            .field("data", &self.data)
            .finish()
    }
}

impl<A: fmt::Display, D: Dimension> fmt::Display for Tensor<A, D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.data)
    }
}

impl<A, D: Dimension> From<Array<A, D>> for Tensor<A, D> {
    fn from(data: Array<A, D>) -> Self {
        Tensor::new(data)
    }
}

impl<A, D: Dimension> Into<Array<A, D>> for Tensor<A, D> {
    fn into(self) -> Array<A, D> {
        self.data
    }
}

// Specialized tensor creation functions for common element types
impl Tensor<f64, ndarray::Ix2> {
    /// Create a 2D tensor of zeros.
    pub fn zeros(shape: (usize, usize)) -> Self {
        Tensor::new(Array2::zeros(shape))
    }

    /// Create a 2D tensor of ones.
    pub fn ones(shape: (usize, usize)) -> Self {
        Tensor::new(Array2::ones(shape))
    }

    /// Create a 2D identity tensor.
    pub fn eye(n: usize) -> Self {
        Tensor::new(Array2::eye(n))
    }

    /// Create a 2D tensor from values.
    pub fn from_vec(shape: (usize, usize), data: Vec<f64>) -> Result<Self> {
        let len = data.len();
        Array2::from_shape_vec(shape, data)
            .map(Tensor::new)
            .map_err(|_| TensorError::ReshapeFailed {
                from: vec![len],
                to: vec![shape.0, shape.1],
            })
    }
}

impl Tensor<f64, ndarray::Ix3> {
    /// Create a 3D tensor of zeros.
    pub fn zeros(shape: (usize, usize, usize)) -> Self {
        Tensor::new(Array3::zeros(shape))
    }

    /// Create a 3D tensor of ones.
    pub fn ones(shape: (usize, usize, usize)) -> Self {
        Tensor::new(Array3::ones(shape))
    }
}

impl Tensor<f64, ndarray::Ix1> {
    /// Create a 1D tensor (vector) of zeros.
    pub fn zeros(len: usize) -> Self {
        Tensor::new(Array1::zeros(len))
    }

    /// Create a 1D tensor (vector) of ones.
    pub fn ones(len: usize) -> Self {
        Tensor::new(Array1::ones(len))
    }

    /// Create a 1D linspace tensor.
    pub fn linspace(start: f64, end: f64, num: usize) -> Self {
        Tensor::new(Array1::linspace(start, end, num))
    }

    /// Create a 1D arange tensor.
    pub fn arange(start: f64, end: f64, step: f64) -> Result<Self> {
        if step == 0.0 {
            return Err(TensorError::IncompatibleShapes(
                "step cannot be zero".to_string(),
            ));
        }
        let n = ((end - start) / step).ceil() as usize;
        let data: Vec<f64> = (0..n)
            .map(|i| start + step * i as f64)
            .filter(|&x| x < end)
            .collect();
        Ok(Tensor::new(Array1::from(data)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tensor_creation() {
        let t: Tensor<f64, _> = Tensor::new(Array2::zeros((2, 3)));
        assert_eq!(t.rank(), 2);
        assert_eq!(t.shape(), &[2, 3]);
        assert_eq!(t.len(), 6);
    }

    #[test]
    fn test_tensor_bounds_check() {
        let t: Tensor<f64, _> = Tensor::new(Array2::zeros((2, 3)));
        assert!(t.verify_bounds(&[0, 0]).is_ok());
        assert!(t.verify_bounds(&[1, 2]).is_ok());
        assert!(t.verify_bounds(&[2, 0]).is_err());
        assert!(t.verify_bounds(&[0, 3]).is_err());
    }

    #[test]
    fn test_reshape() {
        let t: Tensor<f64, _> = Tensor::new(Array2::zeros((2, 3)));
        let reshaped = t.reshape(&[3, 2]).unwrap();
        assert_eq!(reshaped.shape(), &[3, 2]);
    }

    #[test]
    fn test_reshape_invalid() {
        let t: Tensor<f64, _> = Tensor::new(Array2::zeros((2, 3)));
        assert!(t.reshape(&[4, 4]).is_err());
    }

    #[test]
    fn test_eye() {
        let eye = Tensor::eye(3);
        assert_eq!(eye.shape(), &[3, 3]);
    }

    #[test]
    fn test_linspace() {
        let v = Tensor::linspace(0.0, 1.0, 11);
        assert_eq!(v.len(), 11);
    }
}
