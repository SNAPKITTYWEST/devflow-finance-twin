//! Random tensor generation.

use ndarray::{Array, Dimension};
use ndarray_rand::RandomExt;
use ndarray_rand::rand_distr::{Normal, Uniform};

/// Random tensor generation utilities.
pub struct Random;

impl Random {
    /// Generate a random array with uniform distribution.
    pub fn uniform<D: Dimension>(shape: D, low: f64, high: f64) -> Array<f64, D> {
        let dist = Uniform::new(low, high).expect("Invalid uniform bounds");
        Array::random(shape, dist)
    }

    /// Generate a random array with normal distribution.
    pub fn normal<D: Dimension>(shape: D, mean: f64, std_dev: f64) -> Array<f64, D> {
        let dist = Normal::new(mean, std_dev).expect("Invalid normal distribution parameters");
        Array::random(shape, dist)
    }

    /// Generate a random array with standard normal distribution (mean=0, std=1).
    pub fn standard_normal<D: Dimension>(shape: D) -> Array<f64, D> {
        let dist = Normal::new(0.0, 1.0).expect("Standard normal creation failed");
        Array::random(shape, dist)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ndarray::Ix2;

    #[test]
    fn test_uniform_shape() {
        let a = Random::uniform(Ix2(3, 4), 0.0, 1.0);
        assert_eq!(a.shape(), &[3, 4]);
    }

    #[test]
    fn test_uniform_range() {
        let a = Random::uniform(Ix2(10, 10), 0.0, 1.0);
        let min = a.iter().copied().fold(f64::INFINITY, f64::min);
        let max = a.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        assert!(min >= 0.0);
        assert!(max <= 1.0);
    }

    #[test]
    fn test_normal_shape() {
        let a = Random::standard_normal(Ix2(5, 5));
        assert_eq!(a.shape(), &[5, 5]);
    }
}
