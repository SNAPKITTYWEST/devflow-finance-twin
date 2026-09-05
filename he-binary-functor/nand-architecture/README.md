# NAND# — Recursive NAND Array Programming Language

```
BOOLEAN NAND
     ↓
BINARY MACHINE (16-bit ISA)
     ↓
ARRAY PROCESSOR (element-wise, reshape, transpose, reduce)
     ↓
NAND# (surface language)
     ↓
VERIFIED RUST (interpreter + compiler + VM)
     ↓
RECURSIVE SELF-HOSTING (bootstrap chain)
```

**Fundamental rule:** everything above NAND eventually reduces to NAND.

## Directory map

| Path | Content |
|------|---------|
| `nand-isa/` | ISA specification, instruction encoding, derived Boolean operators |
| `nand-binary/` | Canonical binary format, assembler grammar, golden encoding |
| `nandsharp/` | Surface language grammar, type system, semantic rules |
| `array/` | Array values, broadcasting, reshape, transpose, reduction |
| `rust/` | Reference implementation (zero runtime deps) |
| `kani/` | Model-checking harnesses + property classification |
| `omega/` | Bounded mathematical model (addresses, shapes, termination) |
| `bootstrap/` | Explicit compiler₀ → compiler₁ chain and subset boundary |
| `tests/` | Test driver |

## Quick start

```bash
cd rust
cargo test
```

## Semantic equivalence claim (bounded subset)

For every closed Boolean expression `e` built from the operators
`nand`, `not`, `and`, `or`, `xor`, `mux` and the constants `0`/`1`:

```
EXECUTE(LOWER(e)) = EVAL(e)
```

The equality is witnessed by:

1. unit tests that execute both paths,
2. Kani proofs of the Boolean identities and of encode/decode injectivity
   for the defined instruction set,
3. the explicit lowering rules in `rust/src/lower.rs`.

## What is *not* claimed

- NAND alone does not give performance, safety, or fault tolerance.
- Kani has not proven unbounded properties; only the listed harnesses
  have been written for bounded model-checking.
- The self-hosting fixed-point has not yet been mechanically reached;
  the bootstrap boundary and the seed program are defined so that the
  remaining work is concrete.
