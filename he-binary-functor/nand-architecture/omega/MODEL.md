# Bounded / Symbolic Model (Ω-style)

This directory contains a *mathematical model*, not an executable prover run.

## Objects

- Addresses are elements of the finite set `{0 … 2¹⁶−1}`.
- Array shapes are tuples of positive integers whose product is ≤ `MAX_ELEMS = 256` in the verified subset.
- Index expressions are affine: `base + Σ cᵢ·iᵢ` with compile-time constant coefficients.

## Statements we reason about

1. **Termination of lowering**
   For every array operation whose element count is a compile-time constant ≤ 16, the generated instruction sequence is finite and contains exactly one `HALT`.

2. **Address bounds**
   Every `Load`/`Store` address computed by the lowering of an in-bounds array index satisfies `0 ≤ addr < MEM_SIZE`.

3. **Shape preservation**
   `reshape` preserves element cardinality; `transpose` of a rank-2 array swaps the two dimensions and preserves cardinality.

4. **Semantic equivalence (scalar fragment)**
   ```
   EXECUTE(LOWER(e)) = EVAL(e)
   ```
   for every closed Boolean expression `e` built from `nand`, `not`, `and`, `or`, `xor`, `mux` and constants.

## Separation

- The model is *descriptive*.
- The Rust implementation is *executable*.
- Kani harnesses *model-check* finite unfoldings of selected functions.
- No claim is made that an external Omega prover has discharged these obligations; the obligations are stated so that a future tool can be applied.
