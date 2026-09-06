# Recursive NAND# Bootstrap Chain

```
Boolean NAND
    ↓
NAND ISA (16-bit fixed encoding)
    ↓
NAND assembler (text → binary)
    ↓
NAND# compiler₀ (Rust reference, this repository)
    ↓
NAND# source of a subset compiler
    ↓
compiler₁ (emitted as NAND binary)
    ↓
compiler₂ … (future stages)
```

## Self-hosting subset (explicit boundary)

The subset that is intended to be expressible in NAND# itself:

- lexer for the grammar in `nandsharp/GRAMMAR.md`
- recursive-descent parser producing the IR of `ir.rs`
- scalar NAND lowering (`lower_scalar_nand`)
- binary emitter (`Program::from_instrs` + `to_bytes`)

**Outside the bootstrap boundary (remain in Rust host):**

- host file I/O
- Kani verification driver
- unbounded array allocation
- the first compiler₀ that produces compiler₁

## Recursion is explicit

```
compiler₀ : NAND# → NAND binary  (implemented in Rust)
compiler₁ : NAND# → NAND binary  (the binary produced by compiler₀
                                    from a NAND# source that implements
                                    the same subset)
```

Running compiler₁ on its own source must produce a binary that is
functionally equivalent to compiler₁ (observable by identical output on
the golden test suite). That fixed-point check is the definition of
successful self-hosting for the subset.

## Current status

- compiler₀ exists and is the Rust code under `rust/`.
- A minimal NAND# source that can emit a NAND program for the identity
  function on a single bit is provided in `bootstrap/identity.n#`.
- Full self-hosting of the lexer/parser is future work; the chain and
  the boundary are defined so that progress is measurable.
