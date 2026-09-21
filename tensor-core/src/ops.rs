//! Tensor operations: element-wise, reductions, linear algebra, broadcasting.

use crate::error::{Result, TensorError};
use ndarray::{Array, Array2, Array3, Axis, Dimension};

/// Element-wise operations.
pub trait ElementWise<T> {
    /// Add a scalar to all elements.
    fn add_scalar(&self, val: T) -> Self;

    /// Multiply all elements by a scalar.
    fn mul_scalar(&self, val: T) -> Self;

    /// Subtract a scalar from all elements.
    fn sub_scalar(&self, val: T) -> Self;

    /// Divide all elements by a scalar (returns error on division by zero for integer types).
    fn div_scalar(&self, val: T) -> Result<Self>
    where
        Self: Sized;

    /// Element-wise map using a closure.
    fn mapv<F>(&self, f: F) -> Self
    where
        F: Fn(T) -> T;

    /// Element-wise absolute value.
    fn abs(&self) -> Self;
}

impl<D: Dimension> ElementWise<f64> for Array<f64, D> {
    fn add_scalar(&self, val: f64) -> Self {
        self + val
    }

    fn mul_scalar(&self, val: f64) -> Self {
        self * val
    }

    fn sub_scalar(&self, val: f64) -> Self {
        self - val
    }

    fn div_scalar(&self, val: f64) -> Result<Self> {
        if val == 0.0 {
            return Err(TensorError::DivisionByZero);
        }
        Ok(self / val)
    }

    fn mapv<F>(&self, f: F) -> Self
    where
        F: Fn(f64) -> f64,
    {
        let mut result = self.clone();
        for elem in result.iter_mut() {
            *elem = f(*elem);
        }
        result
    }

    fn abs(&self) -> Self {
        let mut result = self.clone();
        for elem in result.iter_mut() {
            *elem = elem.abs();
        }
        result
    }
}

/// Reduction operations.
pub trait Reduce<T> {
    /// Sum all elements.
    fn sum(&self) -> T;

    /// Compute mean of all elements (returns error on empty array).
    fn mean(&self) -> Result<T>;

    /// Find maximum element.
    fn max(&self) -> Result<T>;

    /// Find minimum element.
    fn min(&self) -> Result<T>;

    /// Compute variance.
    fn variance(&self) -> Result<T>;
}

impl Reduce<f64> for Array<f64, ndarray::Ix1> {
    fn sum(&self) -> f64 {
        self.iter().sum()
    }

    fn mean(&self) -> Result<f64> {
        if self.is_empty() {
            return Err(TensorError::EmptyArray);
        }
        Ok(self.sum() / self.len() as f64)
    }

    fn max(&self) -> Result<f64> {
        self.iter()
            .copied()
            .fold(None::<f64>, |a, b| {
                Some(match a {
                    None => b,
                    Some(c) => c.max(b),
                })
            })
            .ok_or(TensorError::EmptyArray)
    }

    fn min(&self) -> Result<f64> {
        self.iter()
            .copied()
            .fold(None::<f64>, |a, b| {
                Some(match a {
                    None => b,
                    Some(c) => c.min(b),
                })
            })
            .ok_or(TensorError::EmptyArray)
    }

    fn variance(&self) -> Result<f64> {
        if self.is_empty() {
            return Err(TensorError::EmptyArray);
        }
        let mean = self.mean()?;
        let sum_sq_diff: f64 = self.iter().map(|&x| (x - mean).powi(2)).sum();
        Ok(sum_sq_diff / self.len() as f64)
    }
}

impl Reduce<f64> for Array<f64, ndarray::Ix2> {
    fn sum(&self) -> f64 {
        self.iter().sum()
    }

    fn mean(&self) -> Result<f64> {
        if self.is_empty() {
            return Err(TensorError::EmptyArray);
        }
        Ok(self.sum() / self.len() as f64)
    }

    fn max(&self) -> Result<f64> {
        self.iter()
            .copied()
            .fold(None::<f64>, |a, b| {
                Some(match a {
                    None => b,
                    Some(c) => c.max(b),
                })
            })
            .ok_or(TensorError::EmptyArray)
    }

    fn min(&self) -> Result<f64> {
        self.iter()
            .copied()
            .fold(None::<f64>, |a, b| {
                Some(match a {
                    None => b,
                    Some(c) => c.min(b),
                })
            })
            .ok_or(TensorError::EmptyArray)
    }

    fn variance(&self) -> Result<f64> {
        if self.is_empty() {
            return Err(TensorError::EmptyArray);
        }
        let mean = self.mean()?;
        let sum_sq_diff: f64 = self.iter().map(|&x| (x - mean).powi(2)).sum();
        Ok(sum_sq_diff / self.len() as f64)
    }
}

impl Reduce<f64> for Array<f64, ndarray::Ix3> {
    fn sum(&self) -> f64 {
        self.iter().sum()
    }

    fn mean(&self) -> Result<f64> {
        if self.is_empty() {
            return Err(TensorError::EmptyArray);
        }
        Ok(self.sum() / self.len() as f64)
    }

    fn max(&self) -> Result<f64> {
        self.iter()
            .copied()
            .fold(None::<f64>, |a, b| {
                Some(match a {
                    None => b,
                    Some(c) => c.max(b),
                })
            })
            .ok_or(TensorError::EmptyArray)
    }

    fn min(&self) -> Result<f64> {
        self.iter()
            .copied()
            .fold(None::<f64>, |a, b| {
                Some(match a {
                    None => b,
                    Some(c) => c.min(b),
                })
            })
            .ok_or(TensorError::EmptyArray)
    }

    fn variance(&self) -> Result<f64> {
        if self.is_empty() {
            return Err(TensorError::EmptyArray);
        }
        let mean = self.mean()?;
        let sum_sq_diff: f64 = self.iter().map(|&x| (x - mean).powi(2)).sum();
        Ok(sum_sq_diff / self.len() as f64)
    }
}

/// Linear algebra operations.
pub trait LinearAlgebra<T> {
    /// Matrix multiply (dot product).
    fn dot(&self, other: &Self) -> Self;

    /// Transpose (2D only for simplicity here).
    fn transpose(&self) -> Self;
}

impl LinearAlgebra<f64> for Array2<f64> {
    fn dot(&self, other: &Self) -> Self {
        use ndarray::linalg::Dot;
        <Array2<f64> as Dot<Array2<f64>>>::dot(self, other)
    }

    fn transpose(&self) -> Self {
        self.t().to_owned()
    }
}

/// Batch matrix-vector contraction.
/// Given A: (batch, m, n) and v: (batch, n), returns out: (batch, m)
pub fn batch_matvec(a: &Array3<f64>, v: &Array2<f64>) -> Result<Array2<f64>> {
    let (b, m, n) = a.dim();
    if v.dim() != (b, n) {
        return Err(TensorError::ShapeMismatch {
            expected: vec![b, n],
            actual: vec![v.dim().0, v.dim().1],
        });
    }

    let mut out = Array2::zeros((b, m));
    for i in 0..b {
        let mat = a.index_axis(Axis(0), i);
        let vec = v.index_axis(Axis(0), i);
        out.index_axis_mut(Axis(0), i).assign(&mat.dot(&vec));
    }
    Ok(out)
}

/// Batch matrix multiplication.
/// Given A: (batch, m, k) and B: (batch, k, n), returns out: (batch, m, n)
pub fn batch_matmul(a: &Array3<f64>, b: &Array3<f64>) -> Result<Array3<f64>> {
    let (batch_a, m, k) = a.dim();
    let (batch_b, k2, n) = b.dim();

    if batch_a != batch_b || k != k2 {
        return Err(TensorError::ShapeMismatch {
            expected: vec![batch_a, m, k, n],
            actual: vec![batch_b, k2],
        });
    }

    let mut out = Array3::zeros((batch_a, m, n));
    for i in 0..batch_a {
        let a_mat = a.index_axis(Axis(0), i);
        let b_mat = b.index_axis(Axis(0), i);
        out.index_axis_mut(Axis(0), i).assign(&a_mat.dot(&b_mat));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ndarray::{Array as NdArray, Ix1, Ix2, Ix3};

    #[test]
    fn test_elementwise_scalar() {
        let a = NdArray::<f64, Ix1>::from(vec![1.0, 2.0, 3.0]);
        let b = a.add_scalar(5.0);
        assert_eq!(b[0], 6.0);
        assert_eq!(b[1], 7.0);
    }

    #[test]
    fn test_reduce_sum() {
        let a = NdArray::<f64, Ix1>::from(vec![1.0, 2.0, 3.0]);
        assert_eq!(a.sum(), 6.0);
    }

    #[test]
    fn test_reduce_mean() {
        let a = NdArray::<f64, Ix1>::from(vec![1.0, 2.0, 3.0]);
        assert_eq!(a.mean().unwrap(), 2.0);
    }

    #[test]
    fn test_reduce_max() {
        let a = NdArray::<f64, Ix1>::from(vec![1.0, 5.0, 3.0]);
        assert_eq!(a.max().unwrap(), 5.0);
    }

    #[test]
    fn test_batch_matvec() {
        let a = ndarray::Array3::zeros((2, 3, 4));
        let v = ndarray::Array2::zeros((2, 4));
        let out = batch_matvec(&a, &v).unwrap();
        assert_eq!(out.dim(), (2, 3));
    }

    #[test]
    fn test_batch_matvec_shape_mismatch() {
        let a = ndarray::Array3::zeros((2, 3, 4));
        let v = ndarray::Array2::zeros((2, 5));
        assert!(batch_matvec(&a, &v).is_err());
    }
}
