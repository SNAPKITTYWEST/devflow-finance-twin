# Array Processor Semantics

## Values

An array value is a pair `(shape, data)`:

- `shape : [usize; RANK]` with `RANK ≤ 4` in the reference implementation
- `data : Vec<bool>` of length `∏ shape[i]`, row-major

Scalar = rank-0 array (shape `[]`, single element).

## Element-wise NAND

```
(A nand B)[i] = NAND(A[i], B[i])
```

Requires `shape(A) == shape(B)` or one of them rank-0 (broadcast).

Broadcast rule (only rank-0):

```
scalar nand array → map (λx. NAND(scalar, x)) array
```

No other broadcasting is supported in the verified subset (keeps index arithmetic simple).

## Reshape

```
reshape(A, new_shape) requires ∏new_shape = ∏shape(A)
```

Data layout unchanged; only the shape descriptor is replaced.

## Transpose

For rank-2:

```
transpose(A)[i,j] = A[j,i]
```

For higher rank the axes are fully reversed.

## Reduction

```
reduce_nand(A) = foldl NAND true (data of A)
```

(Identity of NAND-reduction is 1; the fold is left-associative and deterministic.)

## Indexing

```
A[i₀, i₁, …]  0 ≤ iₖ < shape[k]
```

Out-of-range indices are a static error in the type checker or a dynamic trap in the VM.

## Lowering to scalar NAND

```
for each linear index i in 0 .. len-1:
    load a ← A_base + i
    load b ← B_base + i
    nand c, a, b
    store c → C_base + i
```

The compiler emits a counted loop (using LDI / JZ / arithmetic built from NAND) or fully unrolls when the bound is a small constant known at compile time.
