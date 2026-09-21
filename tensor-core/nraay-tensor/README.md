# NraayTensor: Binary Semantic Governance with Temporal Safety

A formally verified tensor library implementing Ahmad's specification for decoupling logical tensor views from physical memory management.

## Overview

**NraayTensor** provides:

- **Binary Semantic Governance**: Two-flag system (B_layout, B_own) tracking:
  - B_layout: Is canonical stride pattern? (contiguity)
  - B_own: Exclusive ownership of buffer? (refcount=1)

- **Virtual Slicing**: Zero-copy views sharing physical memory via Arc<Vec<f32>>

- **Temporal Safety**: Use-after-free prevention through Rust ownership system

- **Materialization**: Copy-on-write to restore contiguity when needed

## Mathematical Foundation

### Physical Storage (𝒫)
Strictly contiguous 1D array of elements, length N = ∏ s_i

### Semantic View (𝒮)
Tuple (S, O, Σ) where:
- **S** (Shape): Dimensions (s_0, s_1, ..., s_{d-1})
- **O** (Offset): Starting pointer in 𝒫
- **Σ** (Strides): Step sizes σ_i to move along axis i

### Index Mapping
For logical coordinate (x_0, ..., x_{d-1}):
```
physical_index = O + Σ x_i σ_i
```

### Binary Governance
- **B_layout = 1 ⟺** σ_i = ∏_{j>i} s_j for all i (canonical strides)
- **B_own = 1 ⟺** refcount(buffer) = 1 (exclusive ownership)

## Quick Start

```rust
use nraay_tensor::prelude::*;

// Create tensor
let mut t = NraayTensor::new(vec![3, 4])?;

// Get/set values
t.set(&[0, 1], 42.0)?;
println!("{}", t.get(&[0, 1])?); // 42.0

// Check governance state
assert!(t.is_contiguous());      // B_layout = 1
assert!(t.owns_storage());       // B_own = 1

// Virtual slicing (zero-copy)
let s = t.slice(&[(0, 2, 1), (0, 4, 1)])?;
assert!(!s.owns_storage());      // B_own = 0 (shared)

// Transpose (logical shift, no copy)
t.transpose(&[1, 0])?;
assert!(!t.is_contiguous());     // B_layout = 0

// Materialize (restore contiguity)
t.materialize()?;
assert!(t.is_contiguous());      // B_layout = 1
```

## Core Operations

### Creation
```rust
let t = NraayTensor::new(vec![2, 3])?;
// Shape: [2, 3]
// Strides: [3, 1] (canonical)
// B_layout = 1, B_own = 1
```

### Slicing (Virtual)
```rust
let s = t.slice(&[(start, end, step), ...])?;
// Zero-copy view into t
// New offset: O' = O + Σ start_i σ_i
// New strides: σ'_i = σ_i * step_i
// Shared ownership (Arc clone)
```

### Transpose (Logical Shift)
```rust
t.transpose(&[1, 0])?;
// Permutes shape and strides
// Physical memory untouched
// May set B_layout = 0
```

### Materialization (Restore Contiguity)
```rust
t.materialize()?;
// If B_layout = 0:
//   - Allocate new buffer
//   - Copy viewed elements in row-major order
//   - Reset strides to canonical
//   - Set B_layout = 1
// If B_layout = 1: no-op
```

## Governance State Machine

```
        Creation
            |
            v
    [Contiguous & Exclusive]
    B_layout=1, B_own=1
            |
    +-------+-------+
    |               |
    v               v
slice()         transpose()
    |               |
    v               v
[Shared]        [Non-canonical]
B_own=0         B_layout=0
    |               |
    +-------+-------+
            |
            v
       materialize()
            |
            v
    [Exclusive & Canonical]
    B_layout=1, B_own=1
```

## Proof Obligations

### PO-1: Contiguity Preservation
Physical buffer size remains constant during view operations.

### PO-2: Mapping Uniqueness
For valid (S, Σ, O), the mapping f(x) = O + Σ x_i σ_i is injective.

### PO-3: Governance Correctness
- B_layout = 1 ⟺ strides match canonical pattern
- B_own = 1 ⟺ refcount = 1

### PO-4: Slice Soundness
∀x ∈ dom(s'): f(x, s') = f(x + start, s)

### PO-5: COW Isolation
If refcount > 1, materializing one view doesn't affect others' buffers.

### PO-6: Temporal Safety
Buffer deallocation occurs only when refcount = 0 (no live views).

## Examples

### Basic Usage
```bash
cargo run --example basic_usage
```
Demonstrates creation, setting/getting values, transpose, and materialization.

### Virtual Slicing
```bash
cargo run --example slicing
```
Shows zero-copy views, reference counting, and slice composition.

### Materialization & COW
```bash
cargo run --example materialization
```
Illustrates Copy-on-Write semantics and buffer isolation.

## Testing

```bash
# Run all tests (17 comprehensive tests)
cargo test

# Run integration tests
cargo test --test integration

# Run with output
cargo test -- --nocapture
```

### Test Coverage

- **Test 1**: Identity layout (B=1 initially)
- **Test 2**: Logical shift sets B_layout=0
- **Test 3**: Materialize restores B_layout=1
- **Test 4**: Multiple permutations maintain B_layout=0 until materialize
- **Test 5**: Zero-copy slice preservation
- **Test 6**: Non-contiguous slice detection
- **Test 7**: COW isolation (materialized views separate)
- **Test 8**: Compositional slicing (slice-of-slice)
- **Test 9**: Reference count release
- **Test 10**: Adversarial view graph (multiple views with materialization)

## Implementation Details

### Arc-Based Shared Ownership
```rust
struct NraayTensor {
    data: Arc<Vec<f32>>,  // Temporal safety via Arc
    shape: Vec<usize>,
    strides: Vec<usize>,
    offset: usize,
    is_contiguous: bool,   // B_layout
    owns_storage: bool,    // B_own
}
```

### Reference Counting
- Creation: refcount = 1
- Slice: refcount += 1
- Materialize (COW): new Arc, old refcount unchanged
- Drop: refcount -= 1 (buffer freed when 0)

### Memory Safety
- All buffer accesses bounds-checked
- Unsafe only in exclusive ownership set operations
- Arc prevents use-after-free automatically

## Complexity Analysis

| Operation | Time | Space | Notes |
|-----------|------|-------|-------|
| Creation | O(n) | O(n) | allocate + zero |
| Slice | O(1) | O(1) | only metadata |
| Transpose | O(d) | O(d) | d=rank |
| Materialize | O(n) | O(n) | copy viewed elements |
| Get/Set | O(1) | O(1) | stride arithmetic |

## Known-Method Collision Analysis

NraayTensor is **mechanistically equivalent** to:
- NumPy's ndarray (stride-based views)
- PyTorch's Tensor (Arc storage, is_contiguous check)
- TensorFlow's Tensor (storage sharing, COW)

**Novelty**: The explicit **binary governance contract** where materialization is triggered solely by B_layout, making ownership/contiguity transitions first-class state machine operations (not passive properties).

## License

Triple License: MIT OR Apache-2.0 OR GPL-3.0-or-later

## References

- Formal specification: FORMAL_SPEC.md
- Implementation notes: IMPLEMENTATION_NOTES.md
- Usage guide: QUICKSTART.md
