# Tensor Core: Project Structure

## Directory Layout

```
tensor-core/
├── Cargo.toml                       # Edition 2024, dependencies
├── README.md                        # User-facing documentation
├── FORMAL_SPEC.md                   # Mathematical specification
├── IMPLEMENTATION_NOTES.md          # Design decisions & architecture
├── STRUCTURE.md                     # This file
│
├── src/
│   ├── lib.rs                       # 617 bytes: public API & prelude
│   ├── tensor.rs                    # 7.5 KB: Tensor wrapper & creation
│   ├── ops.rs                       # 8.5 KB: Element-wise, reductions, linalg
│   ├── error.rs                     # 1.8 KB: Error types & Result
│   └── random.rs                    # 1.7 KB: Random tensor generation
│
├── examples/
│   ├── creation_and_views.rs        # Creation, bounds checking, reshape
│   ├── elementwise_and_broadcast.rs # Operations, Zip, broadcasting
│   ├── reductions.rs                # Sum, mean, max, min, variance
│   ├── matmul.rs                    # Matrix multiply, transpose, identity
│   ├── batch_contraction.rs         # Batch ops with error handling
│   └── parallel_operations.rs       # Rayon parallelism showcase
│
└── target/
    ├── debug/                       # Debug builds (dev, tests)
    ├── release/                     # Optimized build (--release)
    └── doc/                         # Generated documentation (cargo doc)
```

## File Descriptions

### Core Implementation

#### `src/lib.rs` (617 bytes)
**Purpose**: Public API entry point and prelude module
```rust
pub mod error;
pub mod ops;
pub mod random;
pub mod tensor;

pub use error::{Result, TensorError};
pub use tensor::Tensor;

pub mod prelude { ... }
```
**Key export**: `Tensor<A, D>` wrapper type and `Result` type alias.

#### `src/error.rs` (1.8 KB)
**Purpose**: Unified error handling
```rust
pub enum TensorError {
    ShapeMismatch { expected, actual },
    DimOutOfBounds { axis, rank },
    RankMismatch { expected, actual },
    EmptyArray,
    IncompatibleShapes(String),
    IndexOutOfBounds(String),
    ReshapeFailed { from, to },
    DivisionByZero,
}

pub type Result<T> = std::result::Result<T, TensorError>;
```
**Design**: Custom error enum with thiserror derives for automatic Display/Error impl.

#### `src/tensor.rs` (7.5 KB)
**Purpose**: Tensor wrapper and construction
```rust
pub struct Tensor<A, D: Dimension> {
    data: Array<A, D>,
}

impl<A, D> Tensor<A, D> {
    // Introspection: shape(), rank(), len(), strides()
    // Validation: verify_bounds()
    // Transformation: reshape(), permute()
}

impl Tensor<f64, Ix2> {
    // 2D-specific: zeros(), ones(), eye(), from_vec()
}

impl Tensor<f64, Ix1> {
    // 1D-specific: linspace(), arange()
}
```
**Key invariant**: Shape only changes via explicit `reshape()`.

#### `src/ops.rs` (8.5 KB)
**Purpose**: Tensor operations via traits
```rust
pub trait ElementWise<T> { add_scalar, mul_scalar, mapv, abs, ... }
pub trait Reduce<T> { sum, mean, max, min, variance }
pub trait LinearAlgebra<T> { dot, transpose }

// Specialized implementations for f64
impl ElementWise<f64> for Array<f64, D> { ... }
impl Reduce<f64> for Array<f64, Ix1/Ix2/Ix3> { ... }
impl LinearAlgebra<f64> for Array2<f64> { ... }

// Batch operations
pub fn batch_matvec(a: &Array3<f64>, v: &Array2<f64>) -> Result<Array2<f64>>
pub fn batch_matmul(a: &Array3<f64>, b: &Array3<f64>) -> Result<Array3<f64>>
```
**Design**: Traits enable composability; separate dimension impls ensure type safety.

#### `src/random.rs` (1.7 KB)
**Purpose**: Random tensor generation
```rust
pub struct Random;

impl Random {
    pub fn uniform<D: Dimension>(shape: D, low: f64, high: f64) -> Array<f64, D>
    pub fn normal<D: Dimension>(shape: D, mean: f64, std_dev: f64) -> Array<f64, D>
    pub fn standard_normal<D: Dimension>(shape: D) -> Array<f64, D>
}
```
**Design**: Stateless API; thread-local RNG handled by ndarray_rand.

### Examples

Each example demonstrates a feature area and can be run with:
```bash
cargo run --example <name>
```

#### `creation_and_views.rs`
- Creating tensors (array literals, zeros, ones, eye)
- Shape and bounds verification
- Slicing and views (zero-copy)
- Reshape operations with error handling
- Ranges (linspace, arange)

#### `elementwise_and_broadcast.rs`
- Scalar operations (add, mul, div)
- Element-wise arithmetic
- Broadcasting semantics
- Fused operations with Zip
- Column-wise operations

#### `reductions.rs`
- Global reductions (sum, mean, max, min, variance)
- Axis-wise reductions
- Error handling (empty array)
- Cumulative operations
- Argmax/Argmin patterns

#### `matmul.rs`
- Matrix-matrix multiplication
- Transpose (and transpose involution)
- Identity matrices
- A·I = A property verification
- Self multiplication
- Vector operations

#### `batch_contraction.rs`
- Batch matrix-vector multiplication
- Batch matrix-matrix multiplication
- Shape validation
- Real-world example: batched linear transformation

#### `parallel_operations.rs`
- Parallel element-wise fill
- Parallel reductions
- Parallel row iteration
- Parallel axis reductions
- Performance notes and considerations

### Documentation

#### `README.md`
**Audience**: Library users
- Quick start guide
- Feature list
- API examples
- Performance characteristics
- Comparison with alternatives
- Building and testing

#### `FORMAL_SPEC.md`
**Audience**: Mathematicians, verification enthusiasts
- Formal definitions (ℕ, ℝ^n, tensors)
- Component-wise operations
- Reduction and linear algebra formalisms
- Batch contraction semantics
- Temporal verification skeleton
- Error invariants
- Complexity analysis table

#### `IMPLEMENTATION_NOTES.md`
**Audience**: Contributors, maintainers
- Architecture overview
- Design philosophy (zero-cost, ergonomic)
- Key components and their rationale
- Design decisions (trait dispatch, Result-based errors, dimension specialization)
- Testing strategy
- Performance optimization paths
- Formal correctness proofs
- Future enhancements

#### `STRUCTURE.md` (this file)
**Audience**: Contributors getting oriented
- Directory layout
- File descriptions
- Line counts and purposes
- Integration with build system

### Build Artifacts

#### `Cargo.toml`
```toml
[package]
name = "tensor-core"
edition = "2024"
rust-version = "1.85"

[dependencies]
ndarray = { version = "0.17", features = ["rayon", "approx"] }
ndarray-rand = "0.16"
thiserror = "2"
rand = "0.9"

[features]
linalg = ["dep:ndarray-linalg"]  # Optional BLAS backend
full = ["linalg"]
```

**Key choices**:
- Minimal core dependencies (ndarray, error handling, random)
- Rayon enabled by default (for `.par_iter()`, etc.)
- BLAS feature-gated (heavier dependency)

## Dependency Graph

```
tensor-core
├── ndarray 0.17          (linear algebra, broadcasting)
│   ├── num-traits        (trait definitions)
│   ├── matrixmultiply    (GEMM kernel)
│   └── rayon             (parallelism)
├── thiserror 2           (error macros)
├── ndarray-rand 0.16     (random generation)
│   └── rand_distr        (distributions)
└── rand 0.9              (RNG)

Optional:
└── ndarray-linalg 0.18   (SVD, QR, Cholesky)
    └── openblas-static   (BLAS library)
```

## Build Targets

```bash
# Library
cargo build --release                    # Release build
cargo check                             # Check only

# Tests
cargo test --lib                        # Unit tests
cargo test --example batch_contraction  # Single example
cargo test                              # All (lib + examples)

# Examples
cargo run --example creation_and_views
cargo run --example matmul
cargo run --example parallel_operations

# Documentation
cargo doc --open                        # Generate & open docs
```

## Code Statistics

```
Source files:          5
- tensor.rs:           7.5 KB    (wrapper, creation)
- ops.rs:              8.5 KB    (operations)
- error.rs:            1.8 KB    (error types)
- random.rs:           1.7 KB    (random generation)
- lib.rs:              0.6 KB    (public API)
                      --------
Total core:           20.1 KB

Examples:             6 files   (~15 KB)
Documentation:       3 files   (~30 KB)

Tests:               17 passing (inline in modules)
```

## Test Coverage

Each module has `#[cfg(test)]` section:

| Module | Tests | Coverage |
|--------|-------|----------|
| error | 2 | Error creation & equality |
| tensor | 6 | Creation, bounds, reshape |
| ops | 6 | Element-wise, reductions, batch |
| random | 3 | Shape, range, distribution |

**Total**: 17 tests, all passing ✓

## Integration Points

### With ndarray
- `Tensor<A, D>` wraps `Array<A, D>`
- Traits compose with ndarray traits (`Dot`, `RandomExt`)
- Views via `as_array()` expose ndarray slicing API

### With User Code
```rust
use tensor_core::prelude::*;

// Create tensor
let t = Tensor::new(array![[1.0, 2.0], [3.0, 4.0]]);

// Use ndarray features directly
let view = t.as_array().slice(s![0, ..]);

// Use tensor operations
let reshaped = t.reshape(&[4])?;
```

### With Optional BLAS
```bash
cargo build --features linalg
```
Automatically used by ndarray for matmul, decompositions.

## Future Structure

Planned additions:
```
├── src/
│   ├── sparse/          # Sparse tensor support
│   ├── autodiff/        # Automatic differentiation
│   ├── einsum/          # Einstein summation path finder
│   └── gpu/             # CUDA/Vulkan backends

├── benches/             # Micro-benchmarks
├── perf/                # Performance analysis scripts
└── formal/              # Coq/Isabelle formalization (future)
```

## Getting Started for Contributors

1. **Read documentation** in order:
   - README.md (user perspective)
   - IMPLEMENTATION_NOTES.md (architecture)
   - FORMAL_SPEC.md (math foundation)

2. **Explore source** (~20 KB total):
   - Start with `lib.rs` (entry point)
   - Then `tensor.rs` (wrapper)
   - Then `ops.rs` (operations)

3. **Run examples**:
   ```bash
   cargo run --example creation_and_views
   cargo run --example batch_contraction
   ```

4. **Run tests**:
   ```bash
   cargo test
   ```

5. **Make changes**, add tests, verify:
   ```bash
   cargo check
   cargo test
   ```
