<p align="center">
  <img src="./docs/assets/hero-02.jpg" width="540">
</p>

<p align="center">
  <strong>Recursive Cryptographic Primitives from Logic, State, and Braid Algebra</strong>
</p>

<p align="center">
  EXPERIMENTAL RESEARCH
</p>

---

[![License: FSL-1.1](https://img.shields.io/badge/License-FSL--1.1-blue.svg)](LICENSE-FSL-1.1)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-green.svg)](LICENSE-AGPL-3.0)
[![Lean 4](https://img.shields.io/badge/Lean_4-12__deeds__0__sorry-orange.svg)](lean/)
[![WebAssembly](https://img.shields.io/badge/WASM-6__modules-black.svg)](wasm/)
[![Tests](https://img.shields.io/badge/Tests-122__passing-brightgreen.svg)](tests/)
[![NAND](https://img.shields.io/badge/NAND__Sharp-Spec-purple.svg)](he-binary-functor/nand-architecture/)
[![FBL](https://img.shields.io/badge/FBL-Braid__Ledger-red.svg)](he-binary-functor/fibonacci-braid-ledger/)
[![Frontend](https://img.shields.io/badge/Frontend-Interactive__UI-brightgreen.svg)](frontend/quantum_shadow_ledger.html)
[![Meta_Artifact](https://img.shields.io/badge/Meta__AI-Artifact-blue.svg)](https://www.meta.ai/share/a/870285d6-ca54-4ce2-a963-498cd5b9697b)
[![Production](https://img.shields.io/badge/Production-Hardened-green.svg)](PRODUCTION.md)
[![Security](https://img.shields.io/badge/Security-Policy-red.svg)](SECURITY.md)

---

## What This Repo Contains

**279 files** across **20+ programming languages** implementing a complete cryptographic ledger system:

```
Fibonacci Number -> Braid Word -> Array State -> NAND DAG -> FNV-1a Seal -> Ledger
```

### By Language

| Count | Language | What It Does |
|-------|----------|-------------|
| 30 | **Rust** | GFLOP-to-NAND extractor, Kani verification, braid kernel, IAMAC, malleability engine |
| 29 | **SPARK Ada** | Zero-copy tensor parser (BTEN format), SHA-256, CRC-64, HMAC-SHA-256 |
| 16 | **Ada** | Parser bodies, SHA-256 reverse, loader, firmware |
| 14 | **Haskell** | Liquid Haskell refinements, SGL geometry, BEAM assembly, ISA spec |
| 12 | **Lean 4** | 12 formal proof deeds with 0 sorry policy (Enochian, Malbolge, Bifrost, WORM) |
| 12 | **Python** | WORM engine, twin, audit, quantum, cold boot, ICP anchor, CLI |
| 10 | **Verilog-A** | Trigonometric braid processors, analog computing |
| 9 | **C** | WORM commit, call fibre, kernel workers |
| 7 | **BQN** | Array algebra workload analysis, fibonacci/braid/ledger |
| 6 | **WASM** | 6 modules: runtime, ISA, worm_frame, ledger_replay, account_registry, sha256 |
| 3 | **PL/I** | Treasury ledger, functor, records |
| 3 | **Scala** | Sovereign Treasury pipeline + ZIO |
| 3 | **CUDA/PTX** | Malbolge step kernel, host launcher |
| 3 | **x86-64 ASM** | Treasury serialization, quantum validation |
| 3 | **TypeScript** | Legacy loader, ISA |
| 2 | **Zig** | WASM native loader |
| 2 | **Chisel** | Hardware accelerator |

### By Directory

| Directory | Files | Description |
|-----------|-------|-------------|
| `he-binary-functor/` | 140+ | Ahmad's complete Binary Functor Architecture |
| `lean/` | 12 | Formal verification proofs |
| `wasm/` | 12 | WebAssembly runtime modules |
| `ada/` | 9 | Firmware, loader, CLI ISA |
| `src/` | 10 | Python legacy, cold boot, ICP anchor |
| `docs/` | 5 + 12 media | Documentation, videos, images |
| `frontend/` | 1 | Interactive Quantum Shadow Ledger UI |

---

## System Flowchart

```
                            +-------------------------+
                            |     FIBONACCI F(n)      |
                            |  Closed-form + BigInt   |
                            +-----------+-------------+
                                        |
                                        v
                            +-------------------------+
                            |   MATRIX ENCODING       |
                            |  2x4 [FIB(n) -> binary] |
                            +-----------+-------------+
                                        |
                                        v
                            +-------------------------+
                            |     BRAID WORD          |
                            |  W = [sigma_1, ...]     |
                            |  Generators 1..4        |
                            +-----------+-------------+
                                        |
                       +----------------+----------------+
                       |                |                |
                       v                v                v
              +----------------+ +-----------+ +----------------+
              |  BIFURCATION   | | ADVERSARY | | CRYSTALLIZATION|
              |  split state   | |  mutate   | |  normalize     |
              +-------+--------+ +-----+-----+ +-------+--------+
                      |                |                |
                      +----------------+----------------+
                                       |
                                       v
                            +-------------------------+
                            |    ARRAY STATE S_n       |
                            |  8-element Z vector      |
                            +-----------+-------------+
                                        |
                                        v
                            +-------------------------+
                            |    NAND DAG VERIFY       |
                            |  Full adder from 5 gates |
                            +-----------+-------------+
                                        |
                                        v
                            +-------------------------+
                            |    FNV-1a-64 HASH        |
                            |  Seal = H(prev || C(S))  |
                            +-----------+-------------+
                                        |
                                        v
                            +-------------------------+
                            |    LEDGER SEAL           |
                            |  Append-only integrity   |
                            +-------------------------+
```

---

## Core Model

```
RELATION -> CONSTRAINT -> STATE -> RECURSIVE STEP -> INVARIANT -> SEAL
```

---

## Research Lineage

```
Prolog -> Logic Reduction -> Datalog -> Mercury -> MUMPS Mini-Syntax
  -> Constraint Systems -> Recursive-Step Programming -> Cryptographic State Machines
```

---

## What Each Component Does

### Fibonacci Braid Ledger (`he-binary-functor/fibonacci-braid-ledger/`)
The core research: maps Fibonacci numbers to braid group words, evaluates them as permutations, and seals the result. Contains Liquid Haskell specs, BQN array algebra, RV64I assembly, C++ lock-free ledger, x86-64 ASM, and a research paper.

### NAND Architecture (`he-binary-functor/nand-architecture/`)
Formal specification of NAND# -- an ISA built from NAND gates. Includes the spec, binary format, grammar, array semantics, omega model, bootstrap chain, and Kani verification harnesses.

### GFLOP-to-NAND Extractor (`he-binary-functor/gfnand/`)
Parses tensor operations, builds an IR, and lowers them to NAND gate DAGs. Measures FLOPs, gate count, depth, and arithmetic intensity. Includes BQN workload analysis and 6 Kani proofs.

### Tensor Parser (`he-binary-functor/tensor-parser/`)
SPARK Ada zero-copy parser for BTEN binary tensor format. Includes SHA-256, CRC-64, HMAC-SHA-256, and SHA-256 reverse hash. 29 files, 10 test fixtures.

### Block-Lace (`he-binary-functor/block-lace/`)
C++ ledger node, Rust re-invocation, Liquid Haskell refinements for topological weaving of block sequences.

### Crypto Primitives (`he-binary-functor/crypto/`)
IAMAC (homomorphic MAC), malleability engine (Riemann zeta zeros), RSL architecture (10 candidate primitives), braid kernel, WORM seal chain, evolutionary convergence matrix.

### Verilog-A (`he-binary-functor/verilog-a/`)
Analog/mixed-signal trigonometric processors for braid matrix evaluation. Translinear circuits, SPARK-to-Verilog-A mapping.

### WASM Runtime (`wasm/`)
6 WebAssembly modules: runtime dispatch, ISA, WORM frame serialization, ledger replay, account registry, SHA-256.

### Lean 4 Proofs (`lean/`)
12 formal verification deeds with 0 sorry policy. Enochian engine, Malbolge processor, Bifrost capability exchange, WORM frame serialization, treasury engine.

### Python Legacy (`src/`)
Reference implementation: WORM storage, twin, audit, quantum adapter, cold boot protocol (3-phase), ICP anchor bridge.

### Frontend (`frontend/`)
Interactive Quantum Shadow Ledger with 6-stage pipeline, CTF challenges, tamper simulation, NAND visualization.

---

## Quick Start

```bash
# Open the frontend
open frontend/quantum_shadow_ledger.html

# Full build
make full

# Run tests
make test
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Fibonacci Braid Ledger](./docs/FIBONACCI_BRAID_LEDGER.md) | Core specification |
| [Formal Algebra](./docs/FORMAL_ALGEBRA.md) | Braid state transitions |
| [User Guide](./docs/USER.md) | Installation, usage |
| [About](./docs/ABOUT.md) | Ahmad Ali Parr |
| [Ledger](./docs/LEDGER.md) | WORM storage spec |
| [Inverted Monorepo](./INVERTED_MONOREPO.md) | Binary-first architecture |
| [Math Dictionary](./MATH_DICTIONARY.md) | All math operations |
| [Security](./SECURITY.md) | Threat model |
| [Changelog](./CHANGELOG.md) | Version history |

---

## Visual Research Archive

<p align="center">
  <img src="./docs/assets/hero-03.jpg" width="280">
  <img src="./docs/assets/hero-04.png" width="280">
  <img src="./docs/assets/hero-05.gif" width="280">
</p>

---

## Demonstration (8 Parts)

| Part | Video | Description |
|------|-------|-------------|
| 1 | [demo-part1](./docs/assets/demo-part1.mp4) | Core braid state transitions and seal generation |
| 2 | [demo-part2](./docs/assets/demo-part2.mp4) | Adversarial transform and crystallization |
| 3 | [demo-part3](./docs/assets/demo-part3.mp4) | NAND recursive primitive |
| 4 | [demo-part4](./docs/assets/demo-part4.mp4) | Full ledger verification |
| 5 | [demo-part5](./docs/assets/demo-part5.mp4) | Braid algebra deep dive |
| 7 | [demo-part7](./docs/assets/demo-part7.mp4) | Cryptographic seal chain |
| 8 | [demo-part8](./docs/assets/demo-part8.mp4) | Complete system integration |

---

## License

Dual-licensed: AGPL-3.0 (WASM/PL-I/COBOL/C/NASM/Chisel/Scala) and FSL-1.1 (all others).

```
Copyright (c) 2026 SnapKittyWest.
Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
EIN 42-697643
```
