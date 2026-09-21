# Tensor Core: Implementation Notes

## Architecture Overview

This document describes the implementation strategy, design decisions, and key components of tensor-core.

## Design Philosophy

### Zero-Cost Abstractions

The `Tensor<A, D>` wrapper is entirely transparent to the compiler:

```rust
pub struct Tensor<A, D: Dimension> {
    data: Array<A, D>,
}
```

- **No vtables**: Monomorphized at compile time
- **No heap indirection**: Inline with ndarray's Array
- **No bounds checks**: Validated once, not repeatedly
- **Inline-eligible**: Compiler can optimize aggressively

### Ergonomic API

The wrapper provides:

```rust
// Natural construction
let t = Tensor::new(array);

// Type-safe shape access
let shape = t.shape();  // &[usize]
let rank = t.rank();    // usize

// Unified error handling
t.verify_bounds(&idx)?;
```

### Memory Safety

Leverages Rust's ownership system:

```rust
// Views are zero-copy (never copy the data)
let view = t.as_array().slice(s![..]);

// Mutations prevent aliasing
let mut t = tensor;
t.as_array_mut()[0] = 1.0;  // Can't use old reference
```

## Core Components

### 1. Error Module (`src/error.rs`)

**Key design**:
- Custom `TensorError` enum for precise error reporting
- Unified `Result<T> = std::result::Result<T, TensorError>`
- All shape/bounds errors report expected vs actual

**Variants**:
```rust
ShapeMismatch { expected, actual }    // Array operations
DimOutOfBounds { axis, rank }         // Indexing
RankMismatch { expected, actual }     // Dimension count
EmptyArray                             // Reduction on empty
DivisionByZero                         // Scalar operations
IncompatibleShapes(String)            // Generic mismatch
```

**Rationale**: Precise errors enable better debugging; `thiserror` derives Display automatically.

### 2. Tensor Module (`src/tensor.rs`)

**Generic wrapper** over any ndarray `Array<A, D>`:

```rust
pub struct Tensor<A, D: Dimension> {
    data: Array<A, D>,
}
```

**Methods**:
- Creation: `new()`, `from_vec()`, `zeros()`, `ones()`, `eye()`, `linspace()`, `arange()`
- Introspection: `shape()`, `rank()`, `len()`, `strides()`, `is_c_contiguous()`
- Validation: `verify_bounds()`
- Transformation: `reshape()`, `permute()`

**Key invariant**: Shape only changes via explicit `reshape()`.

### 3. Operations Module (`src/ops.rs`)

**Trait-based design** for composability:

#### ElementWise Trait
```rust
pub trait ElementWise<T> {
    fn add_scalar(&self, val: T) -> Self;
    fn mul_scalar(&self, val: T) -> Self;
    fn mapv<F>(&self, f: F) -> Self where F: Fn(T) -> T;
    // ...
}
```

**Implementation for `Array<f64, D>`**:
- Uses Rust's operator overloading where possible
- Falls back to explicit loops for complex operations
- Checks for division by zero

#### Reduce Trait
```rust
pub trait Reduce<T> {
    fn sum(&self) -> T;
    fn mean(&self) -> Result<T>;
    fn max(&self) -> Result<T>;
    fn variance(&self) -> Result<T>;
}
```

**Key detail**: Each dimension (Ix1, Ix2, Ix3) implements Reduce separately to maintain type safety.

#### LinearAlgebra Trait
```rust
pub trait LinearAlgebra<T> {
    fn dot(&self, other: &Self) -> Self;
    fn transpose(&self) -> Self;
}
```

**Implementation**: Delegates to ndarray's `Dot` trait via:
```rust
<Array2<f64> as Dot<Array2<f64>>>::dot(self, other)
```

#### Batch Operations

**`batch_matvec`**: (batch, m, n) × (batch, n) → (batch, m)
```rust
pub fn batch_matvec(a: &Array3<f64>, v: &Array2<f64>) -> Result<Array2<f64>> {
    // Shape validation
    // Loop over batch dimension
    // Use dot for each slice
}
```

**`batch_matmul`**: (batch, m, k) × (batch, k, n) → (batch, m, n)
```rust
pub fn batch_matmul(a: &Array3<f64>, b: &Array3<f64>) -> Result<Array3<f64>> {
    // Similar pattern with nested matrix multiply
}
```

**Rationale**: Explicit loops enable index-based parallelization (each batch is independent).

### 4. Random Module (`src/random.rs`)

**Stateless random generation**:

```rust
pub struct Random;

impl Random {
    pub fn uniform<D: Dimension>(shape: D, low: f64, high: f64) -> Array<f64, D> {
        Array::random(shape, Uniform::new(low, high)?)
    }
}
```

**Why stateless?**
- No RNG state to manage
- Each call generates fresh random data
- Uses thread-local RNG (ndarray_rand handles this)

## Key Design Decisions

### 1. No Generic Element Type for All Ops

We specialize implementations for `f64`:

```rust
impl ElementWise<f64> for Array<f64, D> { ... }
impl Reduce<f64> for Array<f64, Ix1> { ... }
```

**Rationale**:
- Most operations are numeric (sum, mean, max, etc.)
- Generics over abstract rings/fields are complex
- Users can easily convert (f64 ↔ f32 via `mapv()`)

### 2. Result-Based Error Handling

We use `Result<T>` instead of panicking:

```rust
pub fn mean(&self) -> Result<f64> {
    if self.is_empty() {
        return Err(TensorError::EmptyArray);
    }
    Ok(self.sum() / self.len() as f64)
}
```

**Rationale**:
- Library code shouldn't panic
- Callers decide error handling strategy
- Matches Rust idioms

### 3. Separate Dimension Implementations

```rust
impl Reduce<f64> for Array<f64, Ix1> { /* 1D */ }
impl Reduce<f64> for Array<f64, Ix2> { /* 2D */ }
impl Reduce<f64> for Array<f64, Ix3> { /* 3D */ }
```

**Instead of**: Single generic `impl<D: Dimension> Reduce<f64> for Array<f64, D>`

**Rationale**:
- Type safety: can't accidentally apply 2D-only operations to 1D
- Clarity: method signatures are explicit
- Performance: no runtime dimension checking

### 4. Zero-Copy Views

We expose ndarray's view capabilities:

```rust
pub fn as_array(&self) -> &Array<A, D> {
    &self.data
}

// Users can then do:
let view = tensor.as_array().slice(s![..]);  // No copy
```

**Rationale**:
- Slicing is O(1), not O(n)
- Maintains zero-cost abstraction
- Integrates naturally with ndarray ecosystem

### 5. Trait Bounds Validation

Shape validation happens early:

```rust
pub fn batch_matvec(a: &Array3<f64>, v: &Array2<f64>) -> Result<Array2<f64>> {
    let (b, m, n) = a.dim();
    if v.dim() != (b, n) {
        return Err(TensorError::ShapeMismatch { ... });
    }
    // Now we know dimensions match; safe to proceed
}
```

**Rationale**:
- Fast path: if shapes valid, no runtime checks in loop
- Error locality: report early before partial computation

## Testing Strategy

### Unit Tests

Each module has inline `#[cfg(test)]` blocks:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_elementwise_scalar() {
        let a = Array::from(vec![1.0, 2.0, 3.0]);
        let b = a.add_scalar(5.0);
        assert_eq!(b[0], 6.0);
    }
}
```

### Example-based Testing

Running examples verifies integration:

```bash
cargo run --example creation_and_views
cargo run --example batch_contraction
```

Each example includes:
- Primary use case
- Error handling (fallible operations)
- Edge cases (empty tensors, shape mismatches)

### Property-Based Tests (Future)

Could add quickcheck-style tests:

```rust
#[test]
fn prop_reshape_preserves_elements() {
    for (old_shape, new_shape) in valid_reshape_pairs() {
        let original = Array::random(old_shape);
        let reshaped = original.reshape(new_shape).unwrap();
        assert_eq!(original.len(), reshaped.len());
    }
}
```

## Performance Optimization Paths

### 1. BLAS Backend (Feature-gated)

```toml
[features]
linalg = ["dep:ndarray-linalg"]
```

Automatically used by ndarray when available:
- Matrix multiply: 10-100× faster
- Decompositions: SVD, QR, Cholesky
- Solve: linear systems

### 2. Rayon Parallelism

Already integrated via ndarray:

```rust
let sum: f64 = matrix.par_iter().sum();
matrix.par_mapv_inplace(|x| x * 2.0);
```

**Cost**: Minimal overhead; pays off for n > ~1000 elements.

### 3. SIMD Vectorization

Automatic via:
- ndarray's BLAS backend
- Rust compiler's autovectorization
- Explicit with `packed_simd` (if needed)

### 4. Cache Locality

Ndarray layout optimizes for:
- Row-major (C) or column-major (F) order
- `is_c_contiguous()` check enables specialization
- Loop fusion with `Zip` combinator

## Formal Correctness

### Invariants Maintained

1. **Shape Invariant**: `len(tensor) = ∏ shape(tensor)`
   - Enforced by ndarray's construction
   - Verified in bounds checks

2. **Index Safety**: `∀ i: i < shape ⟹ access valid`
   - Checked in `verify_bounds()`
   - Runtime assertion in reshape

3. **Memory Safety**: No data races, no use-after-free
   - Rust ownership system
   - No unsafe code in core

### Mathematical Properties

**Transpose involution**:
```rust
#[test]
fn test_transpose_involution() {
    let a = Array2::eye(3);
    assert_eq!(a.transpose().transpose(), a);
}
```

**Reduction linearity**:
```rust
let sum_ab = (a + b).sum();
let sum_a_plus_b = a.sum() + b.sum();
assert_eq!(sum_ab, sum_a_plus_b);  // Proven mathematically
```

## Future Enhancements

1. **Sparse tensors**: COO, CSR formats for low-density data
2. **GPU support**: CUDA backend via candle integration
3. **Einsum optimization**: Path finder + contraction scheduler
4. **Automatic differentiation**: Reverse-mode autodiff
5. **Distributed computing**: Multi-machine tensor operations

## References

- Ndarray: <https://docs.rs/ndarray/>
- BLAS: <https://netlib.org/blas/>
- Rayon: <https://docs.rs/rayon/>
- Rust 2024 Edition: <https://doc.rust-lang.org/edition-guide/rust-2024/>
