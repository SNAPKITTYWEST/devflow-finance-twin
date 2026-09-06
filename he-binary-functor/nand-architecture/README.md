# nand-architecture

**NAND# Architecture Specification** — Complete formal specification of the NAND# instruction set architecture, binary encoding, grammar, and verification infrastructure.

## Subdirectories

| Directory | Language | Description |
|-----------|----------|-------------|
| [nand-isa/](nand-isa/) | Markdown | ISA specification (SPEC.md) |
| [nand-binary/](nand-binary/) | Markdown | Binary encoding format (FORMAT.md) |
| [nandsharp/](nandsharp/) | Markdown | NAND# high-level grammar (GRAMMAR.md) |
| [array/](array/) | Markdown | Array semantics (SEMANTICS.md) |
| [omega/](omega/) | Markdown | Omega model (MODEL.md) |
| [bootstrap/](bootstrap/) | Markdown | Self-refining compiler design (CHAIN.md, SELF_REFINING.md) |
| [refinement/](refinement/) | Markdown | Refinement type system (NAND_REFINEMENTS.md) |
| [fsl/](fsl/) | FSL XML | Formal Specification Language (nand_vm.fsl) |
| [kani/](kani/) | Rust/Kani | Bounded verification harnesses (verification.rs, harnesses.rs) |
| [rust/](rust/) | Rust | NAND# VM implementation (src/lib.rs) |

## Key Files at Root

| File | Description |
|------|-------------|
| `NAND_SPEC.md` | Master NAND# specification |
| `README.md` | This file |

## NAND# Core

```
NAND(a,b) = NOT(AND(a,b))  — Universal gate
All Boolean functions expressible as NAND compositions
Gate counts: n-bit add = 9n-6, n×n mul = 9n²-15n+6
```

## Verification

```bash
# Kani bounded proofs
cd kani && cargo kani

# Rust VM
cd rust && cargo build
```

## Specifications

| Spec | File | Status |
|------|------|--------|
| ISA | nand-isa/SPEC.md | Defined |
| Binary Format | nand-binary/FORMAT.md | Defined |
| Grammar | nandsharp/GRAMMAR.md | Defined |
| Array Semantics | array/SEMANTICS.md | Defined |
| Omega Model | omega/MODEL.md | Defined |
| Bootstrap Chain | bootstrap/CHAIN.md | Design |
| Refinement Types | refinement/NAND_REFINEMENTS.md | Defined |
| FSL Annotations | fsl/nand_vm.fsl | Defined |
| Kani Harnesses | kani/src/*.rs | 31 proofs |

## Bootstrap Stages

| Stage | Language | Description |
|-------|----------|-------------|
| compiler₀ | Rust | Trusted reference, Kani-verified |
| compiler₁ | NAND# | Self-hosted with refinement types |
| compiler₂ | NAND# | Fixed-point: binary₁ == binary₂ |