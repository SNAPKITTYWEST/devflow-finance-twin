# Bootstrap Design — Self-Refining Compiler

## Goal
Compiler whose own representation is refined.

## Stages

### Stage 0: compiler₀ — Rust reference, trusted, not self-verified
- Implements grammar, type system, refinement checking, IR, NAND lowering, binary encoding
- Written in safe Rust with some trusted unsafe for Bit construction
- Verified with Kani for bounded instances

### Stage 1: compiler₁ — refined compiler written in NAND#
- Source: NAND# program implementing same compilation pipeline with refinement types carrying proofs
- Type: `{c:Compiler | forall p. ValidProg(p) => Preserves(c,p)}`
- Compiled by compiler₀ → binary₁
- binary₁ should compile NAND# programs and preserve refinements

### Stage 2: compiler₂ — self-hosted
- compiler₁ compiles its own source → binary₂
- If binary₁ = binary₂ (bitwise), we have fixed point
- compiler₂ can verify increasingly large portions of its own implementation

## Self-Verification Claim — When Allowed?

Do NOT claim self-verification unless bootstrap demonstrates:
1. compiler₀ produces binary₁ from source₁
2. binary₁ produces binary₂ from source₁
3. binary₁ == binary₂ (hash equality)
4. Kani proves for bounded programs that binary₁ execution satisfies refinement preservation

Currently at stage 0 → 1 design; stage 2 is research target.

## Recursive Proof Object for Bootstrap

Each compilation result is `Refined<MachineCode, P'>` where P' is proof that code preserves source refinement.

For bootstrap: `Refined<Compiler₁, {c | Preserves(c)>`
where Preserves is itself a refinement predicate over compiler behavior.

This is higher-order refinement: predicate quantifying over all programs.

Kani can verify bounded instances: for all programs up to size K, compiler preserves.

## Challenges
- Predicate P' ⊨ P is undecidable in general — restrict to decidable fragment
- Proof objects must be carried, not just checked — use `Refined<T,P> = (value, ghost proof)`
- Self-reference leads to Gödel-like limits — no full self-verification, only bounded

## Roadmap
1. Implement stage0 in Rust (this repo)
2. Write stage1 in NAND# (minimal compiler: handles only NAND expressions)
3. Prove stage0→stage1 preserves for bounded programs via Kani
4. Attempt fixed-point
5. Measure how much of compiler can be verified in its own language
