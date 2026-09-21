# Tensor Core: Quick Start Guide

## What is Tensor Core?

A high-performance, formally verified tensor library for Rust 2024. Think NumPy but in Rust with full type safety and zero runtime overhead.

## Installation

```bash
cd tensor-core
cargo build --release
```

## 5-Minute Tutorial

### 1. Create a Tensor

```rust
use tensor_core::prelude::*;

// From array literal
let a = array![[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]];
let t = Tensor::new(a);

// Or use convenience constructors
let zeros = Tensor::<f64, _>::new(ndarray::Array::zeros((3, 4)));
let ones = Tensor::<f64, _>::new(ndarray::Array::ones((2, 3)));
let eye = Tensor::eye(4);
```

### 2. Inspect & Validate

```rust
println!("Shape: {:?}", t.shape());      // [2, 3]
println!("Rank: {}", t.rank());           // 2
println!("Elements: {}", t.len());        // 6

// Validate index
assert!(t.verify_bounds(&[0, 0]).is_ok());
assert!(t.verify_bounds(&[2, 0]).is_err());  // Out of bounds
```

### 3. Transform

```rust
// Reshape
let flat = t.reshape(&[6])?;

// Transpose (2D only)
use tensor_core::ops::LinearAlgebra;
let transposed = t.as_array().t().to_owned();
```

### 4. Element-wise Operations

```rust
use tensor_core::ops::ElementWise;

let x = ndarray::Array::from(vec![1.0, 2.0, 3.0]);
let y = x.add_scalar(5.0);      // [6, 7, 8]
let z = x.mul_scalar(2.0);      // [2, 4, 6]
let w = x.mapv(|a| a * a);      // [1, 4, 9]
```

### 5. Reductions

```rust
use tensor_core::ops::Reduce;

let v = ndarray::Array::from(vec![1.0, 2.0, 3.0, 4.0, 5.0]);
let sum = v.sum();              // 15.0
let mean = v.mean()?;           // 3.0
let max = v.max()?;             // 5.0
let variance = v.variance()?;   // 2.0
```

### 6. Linear Algebra

```rust
use tensor_core::ops::LinearAlgebra;

let a = ndarray::Array2::eye(3);
let b = a.transpose();
let c = a.dot(&b);
```

### 7. Batch Operations

```rust
use tensor_core::ops::batch_matvec;

let a = ndarray::Array3::zeros((2, 3, 4));  // 2 batches, 3×4 matrices
let v = ndarray::Array2::zeros((2, 4));    // 2 batches, 4-vectors
let result = batch_matvec(&a, &v)?;        // 2 batches, 3-vectors
```

## Running Examples

```bash
# Create & inspect tensors
cargo run --example creation_and_views

# Element-wise operations
cargo run --example elementwise_and_broadcast

# Reductions
cargo run --example reductions

# Matrix multiply
cargo run --example matmul

# Batch operations
cargo run --example batch_contraction

# Parallelism
cargo run --example parallel_operations
```

## Error Handling

All operations that can fail return `Result<T>`:

```rust
use tensor_core::Result;

let t: Result<_> = try {
    let x = Tensor::zeros((3, 4));
    x.reshape(&[12])?     // Success
};

// vs

let x = Tensor::zeros((3, 4));
if let Err(e) = x.reshape(&[4, 4]) {
    println!("Error: {}", e);  // "reshape failed: cannot reshape [3, 4] to [4, 4]"
}
```

## Common Patterns

### Verify bounds before indexing
```rust
t.verify_bounds(&idx)?;
// Now safe to access
```

### Clone for independent copies
```rust
let original = Tensor::zeros((3, 4));
let copy = original.clone();  // Deep copy
```

### Use views for zero-copy slicing
```rust
let view = t.as_array().slice(s![.., 1..]);  // View columns 1..end
```

### Chain operations
```rust
use tensor_core::ops::Reduce;

let vec = ndarray::Array::from(vec![1.0, 2.0, 3.0, 4.0, 5.0]);
let result = (vec.sum() + 10.0) / 2.0;  // (15.0 + 10.0) / 2.0 = 12.5
```

## API Overview

### Tensor Creation
- `Tensor::new(array)` - Wrap ndarray Array
- `Tensor::zeros(shape)` - All zeros
- `Tensor::ones(shape)` - All ones
- `Tensor::eye(n)` - Identity matrix (2D)
- `Tensor::linspace(start, end, num)` - Evenly spaced (1D)
- `Tensor::arange(start, end, step)` - Range (1D)

### Introspection
- `.shape()` → `&[usize]`
- `.rank()` → `usize`
- `.len()` → `usize`
- `.strides()` → `&[isize]`
- `.is_c_contiguous()` → `bool`

### Validation
- `.verify_bounds(idx)` → `Result<()>`

### Transformation
- `.reshape(shape)` → `Result<Array<_, IxDyn>>`
- `.permute(axes)` → `Result<Array<_, IxDyn>>`
- `.as_array()` → `&Array<A, D>`
- `.as_array_mut()` → `&mut Array<A, D>`
- `.into_array()` → `Array<A, D>`

### Operations
**ElementWise**: `add_scalar`, `mul_scalar`, `sub_scalar`, `div_scalar`, `mapv`, `abs`

**Reduce**: `sum`, `mean`, `max`, `min`, `variance`

**LinearAlgebra**: `dot`, `transpose`

**Batch**: `batch_matvec`, `batch_matmul`

## Type Signatures

```rust
// Tensor wrapper
Tensor<A: element_type, D: Dimension>
  // A = f64, f32, i32, u64, etc.
  // D = Ix1, Ix2, Ix3, ..., IxDyn

// Common types
Tensor<f64, Ix1>  // 1D float vector
Tensor<f64, Ix2>  // 2D float matrix
Tensor<f64, Ix3>  // 3D float tensor
Tensor<f64, IxDyn> // Dynamic-rank float tensor

// Underlying ndarray types
Array<f64, Ix2>  // 2D array (owned)
ArrayView<'a, f64, Ix2>  // 2D view (borrowed)
ArrayViewMut<'a, f64, Ix2>  // 2D mutable view
```

## Performance Tips

1. **Use views for slicing**: `t.as_array().slice(s![..])` is O(1)
2. **Enable parallelism**: Operations automatically parallelize via Rayon
3. **Batch operations**: Process multiple tensors together
4. **Column-major for iteration**: Prefer column operations (memory layout)
5. **Feature gate BLAS**: `cargo build --features linalg` for matrix ops

## Testing Your Setup

```bash
cargo test
# Should see: test result: ok. 17 passed; 0 failed

cargo check
# Should see: Finished `check` profile

cargo doc --open
# Generates and opens documentation
```

## Troubleshooting

### "Cannot infer type"
```rust
// ❌ Wrong: Compiler can't infer dimension
let t = Tensor::new(Array::zeros((3, 4)));

// ✅ Right: Explicit type
let t: Tensor<f64, Ix2> = Tensor::new(Array::zeros((3, 4)));
```

### "Shape mismatch"
```rust
let a = ndarray::Array::zeros((2, 3));
let b = ndarray::Array::zeros((3, 2));
// a + &b fails; need compatible shapes
```

### "Empty array"
```rust
let empty = ndarray::Array::from(vec![]) as ndarray::Array1<f64>;
// empty.mean() returns Err(EmptyArray)
```

## Next Steps

1. **Read README.md** - User documentation
2. **Read FORMAL_SPEC.md** - Mathematical specification
3. **Read IMPLEMENTATION_NOTES.md** - Architecture details
4. **Run examples** - See features in action
5. **Integrate** - Use tensor-core in your projects

## Key Concepts

| Concept | Meaning | Example |
|---------|---------|---------|
| **Tensor** | N-dimensional array | Matrix is 2D tensor |
| **Rank** | Number of dimensions | Matrix has rank 2 |
| **Shape** | Size in each dimension | (3, 4) is 3 rows, 4 cols |
| **Contraction** | Multiply & sum along axes | Matrix multiply |
| **Broadcasting** | Align shapes for operations | Add scalar to matrix |
| **Slice** | View subset without copy | Get one row |
| **Stride** | Memory jump per dimension | Row-major vs column-major |

## Resources

- `README.md` - Full user guide
- `FORMAL_SPEC.md` - Mathematical foundation
- `IMPLEMENTATION_NOTES.md` - Architecture & design decisions
- `STRUCTURE.md` - Project layout & contributing
- `COMPLETION_SUMMARY.md` - Project status & deliverables

## License

Triple License: MIT OR Apache-2.0 OR GPL-3.0-or-later

Choose what fits your needs:
- **MIT**: Simple, permissive
- **Apache-2.0**: Patent protection
- **GPL-3.0+**: Copyleft (with AI company restrictions in clause 5)

---

**Questions?** Start with the README or run an example!
