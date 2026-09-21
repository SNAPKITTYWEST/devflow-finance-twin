# Tensor Core: Formal Mathematical Specification

## Overview

This document provides the formal mathematical foundation for the `tensor-core` library, a high-performance tensor/array library built on `ndarray` for Rust 2024.

## Formal Array/Tensor Core

### Basic Definitions

```
ℕ = {0, 1, 2, ...}
ℕ^k = ℕ × ℕ × ... × ℕ (k times)

For k ∈ ℕ:
  A_k : ℕ^k → ℝ (tensor of rank k)
  A_n ∈ ℝ^n (n-dimensional array)
```

### Equality and Component-wise Operations

```
For x, y ∈ ℝ^n:
  x = y iff ∧_{i=0}^{n-1} x_i = y_i

Component-wise operations:
  (A ⊕ B)_i = A_i + B_i           (addition)
  (A ⊗ B)_i = A_i · B_i            (multiplication)
  (A ⊖ B)_i = max(A_i - B_i, 0)   (saturating subtraction)
```

### Shape, Rank, and Indexing

```
Shape(A_n) = n                      (rank/dimensionality)
Rank(A_n) = n
Index(A_n) = {i ∈ ℕ | i < n}
Bounds(A_n) ≡ ∀i (i < n ⟹ 0 ≤ i < n)
```

### Reduction Operations

```
Map_n : ℝ^n → ℝ^n
  Map_n(x)_i = f_i(x_i)

Fold_0([]) = 0
Fold_{n+1}(x_0, ..., x_n) = x_0 ⊕ Fold_n(x_1, ..., x_n)

Reduce(x) = ∑_{i=0}^{n-1} x_i
```

### Linear Algebra

```
Matrix product (A ∈ ℝ^{m×ℓ}, B ∈ ℝ^{ℓ×n}):
  (AB)_{ij} = ∑_{k=0}^{ℓ-1} A_{ik}B_{kj}

Identity matrix:
  (I_n)_{ij} = δ_{ij} (Kronecker delta)

Transpose (involution):
  (A^T)_{ij} = A_{ji}
  (A^T)^T = A
```

### Batch Contraction

For batch size b, matrix dimensions m, k, n:

```
Given:
  A ∈ ℝ^{b×m×k}
  B ∈ ℝ^{b×k×n}

Batch matrix multiplication:
  C = BatchMatMul(A, B)
  C_i = A_i · B_i  for i ∈ {0, 1, ..., b-1}
  C ∈ ℝ^{b×m×n}
```

### Temporal Verification Skeleton

```
Discrete time: t_0 = 0, t_{r+1} = t_r + 1
Valid(0) ∧ (∀r Valid(r) ⟹ Valid(r+1)) ⟹ ∀r Valid(r)

Lock mechanism:
  LOCK = 1 ⟹ EXECUTE
  LOCK = 0 ⟹ HALT

Hash-chain monotonicity (for audit trail):
  h_{i+1} = H(h_i || action_i)
```

## Error Types and Validation

### Shape Compatibility

```
For element-wise operations:
  shape(A) = shape(B) or broadcasting applies

For matmul(A, B):
  A: (m, k), B: (k, n) ⟹ Result: (m, n)

For batch operations:
  batch_size(A) = batch_size(B)
```

### Index Bounds

```
Valid index i for tensor of size n:
  0 ≤ i < n

Multi-dimensional index (i_1, ..., i_r):
  ∀j: 0 ≤ i_j < shape_j
```

## Performance Guarantees

### Algorithm Complexity

| Operation | Time | Space | Notes |
|-----------|------|-------|-------|
| Elementwise | O(n) | O(n) | unit stride |
| Reduction | O(n) | O(1) | parallel-friendly |
| Matmul (m×k)·(k×n) | O(mkn) | O(mn) | BLAS-backed |
| Batch matmul | O(b·mkn) | O(b·mn) | per-batch parallelized |
| Reshape | O(n) | O(n) | view when possible |
| Transpose | O(n) | O(1) | lazy if supported |

### Memory Hierarchy

```
Cache-aware operations: GETT (GEMM-like Tensor-Tensor)
- Pack sub-tensors into cache-resident blocks
- Invoke micro-kernel with unit-stride access
- Result: unit-stride, full vectorization, cache awareness
```

## Safety Properties

### Invariants

1. **Shape Invariant**: shape never mutates except during explicit reshape
2. **Bounds Invariant**: all indexing verified before access
3. **Zero-cost Abstraction**: Tensor wrapper incurs no runtime overhead
4. **Memory Safety**: all allocations managed by ndarray/Rust ownership

### Verified Properties

```
∀ tensor t:
  len(t) = ∏ shape(t)           (product formula)
  strides(t) compatible          (ndarray guarantees)
  no aliasing during mutation    (Rust borrow checker)
```

## Implementation Stack

```
     Application Code
            ↓
   tensor-core (ergonomic API)
            ↓
    ndarray 0.17+ (linear algebra)
            ↓
  BLAS/LAPACK (optional backend)
            ↓
   Rayon (parallelism)
            ↓
   Hardware (CPU, SIMD)
```

## Formal Properties

### Associativity

```
(A · B) · C = A · (B · C)  (matrix multiplication)
(A ⊕ B) ⊕ C = A ⊕ (B ⊕ C)  (addition is associative)
```

### Identity Elements

```
A · I = A
I · A = A
A ⊕ 0 = A
A ⊗ 1 = A
```

### Transpose Properties

```
(A · B)^T = B^T · A^T
(A^T)^T = A
(A + B)^T = A^T + B^T
```

### Reduction Properties

```
Reduce(Map(f, x)) = ∑ f(x_i)
Reduce(x ⊕ y) = Reduce(x) + Reduce(y)  (linearity)
```

## License

Triple license: MIT OR Apache-2.0 OR GPL-3.0-or-later

This ensures:
- Commercial use (MIT/Apache-2.0)
- Open source compliance (GPL-3.0)
- AI company restrictions (GPL-3.0 clause 5)
