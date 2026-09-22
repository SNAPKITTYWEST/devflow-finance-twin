//! NraayTensor: Binary Semantic Governance with Virtual Slicing and Temporal Safety

use crate::error::{NraayError, Result};
use std::sync::Arc;

/// NraayTensor: Binary Semantic Governance Model
///
/// Mathematical Definition:
/// - Physical Storage (𝒫): Strictly contiguous 1D array of length N = ∏ s_i
/// - Semantic View (𝒮): Tuple (S, O, Σ) where:
///   * S (Shape): Dimensions (s_0, ..., s_{d-1})
///   * O (Offset): Starting pointer in 𝒫
///   * Σ (Strides): Step sizes to move along each axis
/// - Binary Governance: Flags (B_layout, B_own)
///   * B_layout = 1 ⟺ σ_i = ∏_{j>i} s_j for all i (canonical strides)
///   * B_own = 1 ⟺ this view exclusively owns the buffer (refcount=1)
///
/// Index Mapping: f(x_0, ..., x_{d-1}) = O + Σ x_i σ_i
#[derive(Clone)]
pub struct NraayTensor {
    /// Ownership Token: Shared buffer via Arc (temporal safety)
    data: Arc<Vec<f32>>,

    /// Semantic Shape
    shape: Vec<usize>,

    /// Semantic Strides
    strides: Vec<usize>,

    /// Memory Offset (for slicing)
    offset: usize,

    /// B_layout: Is canonical stride pattern (for this view's shape)?
    is_contiguous: bool,

    /// B_own: Does this view exclusively own the buffer (for COW)?
    owns_storage: bool,
}

impl NraayTensor {
    /// Create new tensor with given shape. Initializes with zeros.
    ///
    /// **Governance State**: B_layout=1, B_own=1 (contiguous, exclusive)
    pub fn new(shape: Vec<usize>) -> Result<Self> {
        if shape.is_empty() {
            return Err(NraayError::EmptyTensor);
        }

        let size: usize = shape.iter().product();
        if size == 0 {
            return Err(NraayError::EmptyTensor);
        }

        let strides = Self::canonical_strides(&shape);

        Ok(NraayTensor {
            data: Arc::new(vec![0.0; size]),
            shape,
            strides,
            offset: 0,
            is_contiguous: true,
            owns_storage: true,
        })
    }

    /// Get reference to data
    pub fn data(&self) -> Arc<Vec<f32>> {
        Arc::clone(&self.data)
    }

    /// Get shape
    pub fn shape(&self) -> &[usize] {
        &self.shape
    }

    /// Get strides
    pub fn strides(&self) -> &[usize] {
        &self.strides
    }

    /// Get offset
    pub fn offset(&self) -> usize {
        self.offset
    }

    /// Get B_layout flag (is canonical contiguous?)
    pub fn is_contiguous(&self) -> bool {
        self.is_contiguous
    }

    /// Get B_own flag (exclusive ownership?)
    pub fn owns_storage(&self) -> bool {
        self.owns_storage
    }

    /// Total number of elements
    pub fn len(&self) -> usize {
        self.shape.iter().product()
    }

    /// Physical buffer size
    pub fn buffer_size(&self) -> usize {
        self.data.len()
    }

    /// Calculate canonical strides for a given shape
    fn canonical_strides(shape: &[usize]) -> Vec<usize> {
        let mut strides = vec![0; shape.len()];
        let mut stride = 1;
        for i in (0..shape.len()).rev() {
            strides[i] = stride;
            stride *= shape[i];
        }
        strides
    }

    /// Recompute B_layout flag (check if strides are canonical)
    fn recompute_contiguity(&mut self) {
        if self.shape.is_empty() {
            self.is_contiguous = false;
            return;
        }

        let canonical = Self::canonical_strides(&self.shape);
        self.is_contiguous = self.strides == canonical;
    }

    /// Virtual Slicing: Zero-copy view with shared ownership
    ///
    /// Creates new view sharing the same physical buffer. Updates:
    /// - Shape: s'_i = end_i - start_i
    /// - Offset: O' = O + Σ start_i σ_i
    /// - Strides: σ'_i = σ_i * step_i
    /// - B_own: → 0 (shared ownership)
    /// - B_layout: Recomputed for new shape
    ///
    /// **Governance Invariant**: Physical buffer 𝒫 immutable during view creation
    pub fn slice(&self, ranges: &[(usize, usize, usize)]) -> Result<Self> {
        if ranges.len() != self.shape.len() {
            return Err(NraayError::DimensionMismatch {
                expected: self.shape.len(),
                actual: ranges.len(),
            });
        }

        let mut new_shape = Vec::with_capacity(self.shape.len());
        let mut new_strides = Vec::with_capacity(self.strides.len());
        let mut new_offset = self.offset;

        for (dim, &(start, end, step)) in ranges.iter().enumerate() {
            if start >= self.shape[dim] || end > self.shape[dim] || start >= end || step == 0 {
                return Err(NraayError::InvalidSliceRange {
                    start,
                    end,
                    size: self.shape[dim],
                });
            }

            let dim_size = (end - start + step - 1) / step; // Ceiling division
            new_shape.push(dim_size);

            new_offset += start * self.strides[dim];
            new_strides.push(self.strides[dim] * step);
        }

        let mut view = NraayTensor {
            data: Arc::clone(&self.data),
            shape: new_shape,
            strides: new_strides,
            offset: new_offset,
            is_contiguous: false,
            owns_storage: false,
        };
        view.recompute_contiguity();

        Ok(view)
    }

    /// Logical Shift (Axes Permutation): Transpose via stride rearrangement
    ///
    /// Permutes axes without touching physical memory:
    /// - S_new = S[perm]
    /// - Σ_new = Σ[perm]
    /// - B_own: unchanged
    /// - B_layout: → 0 if permutation changes canonical order
    ///
    /// **Governance Invariant**: Physical buffer 𝒫 untouched (only metadata)
    pub fn transpose(&mut self, perm: &[usize]) -> Result<()> {
        if perm.len() != self.shape.len() {
            return Err(NraayError::InvalidPermutation {
                expected: self.shape.len(),
                actual: perm.len(),
            });
        }

        // Verify permutation is valid
        let mut seen = vec![false; perm.len()];
        for &p in perm {
            if p >= perm.len() || seen[p] {
                return Err(NraayError::InvalidPermutation {
                    expected: self.shape.len(),
                    actual: perm.len(),
                });
            }
            seen[p] = true;
        }

        let mut new_shape = Vec::with_capacity(self.shape.len());
        let mut new_strides = Vec::with_capacity(self.strides.len());

        for &p in perm {
            new_shape.push(self.shape[p]);
            new_strides.push(self.strides[p]);
        }

        self.shape = new_shape;
        self.strides = new_strides;
        self.recompute_contiguity();

        Ok(())
    }

    /// Materialization: Restore Contiguity with Copy-on-Write
    ///
    /// If B_layout=1 and B_own=1: No-op (already canonical and exclusive)
    /// If B_layout=0 or B_own=0:
    ///   - Allocate new contiguous buffer
    ///   - Copy viewed elements in row-major order
    ///   - Update strides to canonical
    ///   - Set B_layout=1, B_own=1
    ///
    /// **COW Semantics**: If refcount > 1, other views unaffected (new Arc)
    /// **Governance Invariant**: "Preserving order, strict and bound"
    pub fn materialize(&mut self) -> Result<()> {
        if self.is_contiguous && self.owns_storage {
            return Ok(());
        }

        // Allocate new buffer for viewed elements
        let viewed_size = self.len();
        let mut new_data = vec![0.0; viewed_size];

        // Copy viewed elements in logical order
        self.copy_viewed_to(&mut new_data, 0)?;

        // Replace shared Arc with exclusive ownership
        self.data = Arc::new(new_data);

        // Reset to canonical strides
        self.strides = Self::canonical_strides(&self.shape);
        self.offset = 0;
        self.is_contiguous = true;
        self.owns_storage = true;

        Ok(())
    }

    /// Copy viewed elements to destination buffer in row-major order
    fn copy_viewed_to(&self, dst: &mut [f32], mut dst_idx: usize) -> Result<()> {
        self.copy_recursive(dst, &mut dst_idx, 0, self.offset)?;
        Ok(())
    }

    /// Recursive helper for copying elements
    fn copy_recursive(
        &self,
        dst: &mut [f32],
        dst_idx: &mut usize,
        dim: usize,
        offset: usize,
    ) -> Result<()> {
        if dim == self.shape.len() {
            if offset < self.data.len() {
                dst[*dst_idx] = self.data[offset];
                *dst_idx += 1;
                Ok(())
            } else {
                Err(NraayError::IndexOutOfBounds {
                    dim: 0,
                    index: offset,
                    size: self.data.len(),
                })
            }
        } else {
            for i in 0..self.shape[dim] {
                self.copy_recursive(dst, dst_idx, dim + 1, offset + i * self.strides[dim])?;
            }
            Ok(())
        }
    }

    /// Get element at logical coordinate
    pub fn get(&self, coord: &[usize]) -> Result<f32> {
        if coord.len() != self.shape.len() {
            return Err(NraayError::DimensionMismatch {
                expected: self.shape.len(),
                actual: coord.len(),
            });
        }

        // Check bounds
        for (i, &c) in coord.iter().enumerate() {
            if c >= self.shape[i] {
                return Err(NraayError::IndexOutOfBounds {
                    dim: i,
                    index: c,
                    size: self.shape[i],
                });
            }
        }

        // Compute physical index
        let mut idx = self.offset;
        for (i, &c) in coord.iter().enumerate() {
            idx += c * self.strides[i];
        }

        if idx < self.data.len() {
            Ok(self.data[idx])
        } else {
            Err(NraayError::IndexOutOfBounds {
                dim: 0,
                index: idx,
                size: self.data.len(),
            })
        }
    }

    /// Set element at logical coordinate
    pub fn set(&mut self, coord: &[usize], value: f32) -> Result<()> {
        if coord.len() != self.shape.len() {
            return Err(NraayError::DimensionMismatch {
                expected: self.shape.len(),
                actual: coord.len(),
            });
        }

        // Check bounds
        for (i, &c) in coord.iter().enumerate() {
            if c >= self.shape[i] {
                return Err(NraayError::IndexOutOfBounds {
                    dim: i,
                    index: c,
                    size: self.shape[i],
                });
            }
        }

        // Compute physical index
        let mut idx = self.offset;
        for (i, &c) in coord.iter().enumerate() {
            idx += c * self.strides[i];
        }

        if idx < self.data.len() {
            // Ensure we have exclusive ownership before mutating
            if Arc::strong_count(&self.data) > 1 {
                // Shared; create exclusive copy
                let mut new_data = (*self.data).clone();
                new_data[idx] = value;
                self.data = Arc::new(new_data);
                self.owns_storage = true;
            } else {
                // Exclusive; safe to mutate via Arc::get_mut (refcount==1 checked above).
                if let Some(ptr) = Arc::get_mut(&mut self.data) {
                    ptr[idx] = value;
                }
            }
            Ok(())
        } else {
            Err(NraayError::IndexOutOfBounds {
                dim: 0,
                index: idx,
                size: self.data.len(),
            })
        }
    }

    /// Get Arc strong count (for testing reference counting)
    pub fn refcount(&self) -> usize {
        Arc::strong_count(&self.data)
    }

    /// Copy element values from `src` (same shape) into this tensor's logical view.
    /// Materializes self first so writes land on an exclusive contiguous buffer.
    /// Used by the ML layer to store gradient buffers.
    pub fn set_raw_from(&mut self, src: &NraayTensor) -> Result<()> {
        if self.shape != src.shape {
            return Err(NraayError::ShapeMismatch {
                expected: self.shape.clone(),
                actual: src.shape.clone(),
            });
        }
        self.materialize()?;
        let mut coord = vec![0usize; self.shape.len()];
        loop {
            let v = src.get(&coord)?;
            self.set(&coord, v)?;
            // Increment multi-index (row-major odometer).
            let mut d = self.shape.len();
            loop {
                if d == 0 {
                    return Ok(());
                }
                d -= 1;
                coord[d] += 1;
                if coord[d] < self.shape[d] {
                    break;
                }
                coord[d] = 0;
            }
        }
    }

    /// Weak observer (𝒲): non-owning handle that never prevents deallocation.
    pub fn downgrade(&self) -> std::sync::Weak<Vec<f32>> {
        Arc::downgrade(&self.data)
    }
}

impl std::fmt::Debug for NraayTensor {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NraayTensor")
            .field("shape", &self.shape)
            .field("strides", &self.strides)
            .field("offset", &self.offset)
            .field("is_contiguous", &self.is_contiguous)
            .field("owns_storage", &self.owns_storage)
            .field("refcount", &Arc::strong_count(&self.data))
            .field("buffer_size", &self.data.len())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_creation() {
        let t = NraayTensor::new(vec![2, 3]).unwrap();
        assert_eq!(t.shape(), &[2, 3]);
        assert_eq!(t.len(), 6);
        assert!(t.is_contiguous());
        assert!(t.owns_storage());
    }

    #[test]
    fn test_canonical_strides() {
        let strides = NraayTensor::canonical_strides(&[2, 3, 4]);
        assert_eq!(strides, vec![12, 4, 1]);
    }

    #[test]
    fn test_slice_shared_ownership() {
        let t = NraayTensor::new(vec![4, 4]).unwrap();
        let s1 = t.slice(&[(0, 2, 1), (0, 4, 1)]).unwrap();
        assert!(!s1.owns_storage());
        assert_eq!(t.refcount(), 2); // t + s1
        assert_eq!(s1.len(), 8);
    }

    #[test]
    fn test_slice_non_contiguous() {
        let t = NraayTensor::new(vec![4, 4]).unwrap();
        let s = t.slice(&[(0, 4, 1), (0, 4, 2)]).unwrap();
        assert!(!s.is_contiguous()); // Step > 1 makes non-canonical
        assert_eq!(s.shape(), &[4, 2]);
    }

    #[test]
    fn test_transpose() {
        let mut t = NraayTensor::new(vec![2, 3]).unwrap();
        t.transpose(&[1, 0]).unwrap();
        assert_eq!(t.shape(), &[3, 2]);
        assert!(!t.is_contiguous());
    }

    #[test]
    fn test_materialize() {
        let mut t = NraayTensor::new(vec![2, 3]).unwrap();
        t.transpose(&[1, 0]).unwrap();
        assert!(!t.is_contiguous());

        let _refcount_before = t.refcount();
        t.materialize().unwrap();
        assert!(t.is_contiguous());
        assert_eq!(t.strides(), &[2, 1]);
        assert_eq!(t.refcount(), 1); // New exclusive buffer
    }

    #[test]
    fn test_get_set() {
        let mut t = NraayTensor::new(vec![2, 3]).unwrap();
        t.set(&[0, 1], 42.0).unwrap();
        assert_eq!(t.get(&[0, 1]).unwrap(), 42.0);
    }

    #[test]
    fn test_temporal_safety() {
        let t = NraayTensor::new(vec![2, 3]).unwrap();
        let s1 = t.slice(&[(0, 1, 1), (0, 3, 1)]).unwrap();
        let s2 = t.slice(&[(1, 2, 1), (0, 3, 1)]).unwrap();

        assert_eq!(t.refcount(), 3); // t, s1, s2

        drop(s1);
        assert_eq!(t.refcount(), 2);

        drop(s2);
        assert_eq!(t.refcount(), 1); // Only t remains
    }
}
