# lean4

**Lean 4 Formal Proofs** — Formal verification of NAND# architecture components.

## Files

| File | Description |
|------|-------------|
| `*.lean` | Lean 4 proof files |

## Purpose

Formal verification of:
- NAND# ISA correctness
- Refinement type soundness
- Bootstrap compiler properties

## Build

```bash
lake build
lake test
```