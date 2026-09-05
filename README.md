<p align="center">
  <img src="./docs/assets/hero-02.jpg" width="600">
</p>

<h1 align="center">Fibonacci Braid Ledger</h1>

<p align="center">
  <strong>Recursive Cryptographic Primitives from Logic, State, and Braid Algebra</strong>
</p>

<p align="center">
  <a href="LICENSE-FSL-1.1"><img src="https://img.shields.io/badge/License-FSL--1.1-blue.svg"></a>
  <a href="LICENSE-AGPL-3.0"><img src="https://img.shields.io/badge/License-AGPL--3.0-green.svg"></a>
  <a href="lean/"><img src="https://img.shields.io/badge/Lean_4-12__deeds__0__sorry-orange.svg"></a>
  <a href="wasm/"><img src="https://img.shields.io/badge/WASM-6__modules-black.svg"></a>
  <a href="tests/"><img src="https://img.shields.io/badge/Tests-122__passing-brightgreen.svg"></a>
  <a href="frontend/quantum_shadow_ledger.html"><img src="https://img.shields.io/badge/Frontend-Live__UI-brightgreen.svg"></a>
  <a href="https://www.meta.ai/share/a/870285d6-ca54-4ce2-a963-498cd5b9697b"><img src="https://img.shields.io/badge/Meta__AI-Artifact-blue.svg"></a>
</p>

---

## Table of Contents

- [What Is This](#what-is-this)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Braid Algebra](#braid-algebra)
- [Research Lineage](#research-lineage)
- [Languages](#languages)
- [Repository Structure](#repository-structure)
- [Verification](#verification)
- [Interactive Frontend](#interactive-frontend)
- [Demo Videos](#demo-videos)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [License](#license)

---

## What Is This

A cryptographic ledger system built on **braid group algebra**. Fibonacci numbers generate braid words, braid words produce state transitions, state transitions get sealed with FNV-1a-64 hashes, and the whole chain is append-only and tamper-evident.

**279 files. 20+ languages. 122 tests passing. 12 Lean 4 proofs with 0 sorry.**

---

## How It Works

```mermaid
flowchart TD
    A["Fibonacci F(n)"] --> B["Braid Word W"]
    B --> C{"Generator Valid?"}
    C -->|Yes| D["State Transition T(σ, S)"]
    C -->|No| E["REJECT"]
    D --> F{"Invariant Holds?"}
    F -->|No| G["Discard Transient"]
    F -->|Yes| H["Crystallize C(S)"]
    H --> I["Seal = H(Seal_prev ‖ C(S))"]
    I --> J["Append to Ledger"]
    J --> K["Next Recursive State"]
    K --> A
```

---

## Architecture

```mermaid
flowchart LR
    subgraph Core["Core Pipeline"]
        F["FIB<br/>Fibonacci"] --> B["BRAID<br/>Word Gen"]
        B --> S["ARRAY<br/>State Vec"]
        S --> N["NAND<br/>Gate DAG"]
        N --> C["CRYPTO<br/>FNV-1a"]
        C --> L["LEDGER<br/>Seal Chain"]
    end

    subgraph Input["Input Layer"]
        FI["Fib Index n"]
        SD["Seed"]
    end

    subgraph Verify["Verification"]
        INV["Invariant Check"]
        CHR["Chain Validation"]
    end

    FI --> F
    SD --> F
    L --> CHR
    D -.-> INV
```

---

## Braid Algebra

```mermaid
stateDiagram-v2
    [*] --> B0: Init {s | Valid(s)}
    B0 --> B1: σ₁
    B1 --> B2: σ₂⁻¹
    B2 --> B3: σ₁
    B3 --> B4: σ₃

    state B0 {
        [*] --> zero: [0,0,0,0,0,0,0,0]
    }
    state B1 {
        [*] --> one: [1,0,0,0,0,0,0,0]
    }
    state B2 {
        [*] --> two: [1,-1,0,0,0,0,0,0]
    }
    state B3 {
        [*] --> three: [2,-1,0,0,0,0,0,0]
    }
    state B4 {
        [*] --> four: [2,-1,1,0,0,0,0,0]
    }
```

**Transition function:** `T(σᵢ, Bₙ) = Bₙ + contrib(σᵢ)`

**Refinement type:** `braid_step : (g:Generator) × (s:{s|Valid(s)}) → {s'|s' = s + contrib(g) ∧ Valid(s')}`

---

## Research Lineage

```mermaid
flowchart TD
    P["Prolog<br/>Unification + DFS"] --> LR["Logic Reduction<br/>Directed Evaluation"]
    LR --> D["Datalog<br/>Stratified Fixpoint"]
    D --> M["Mercury<br/>Mode-Directed Compile"]
    M --> MU["MUMPS Mini-Syntax<br/>Global Arrays"]
    MU --> CS["Constraint Systems<br/>ASP Stable Models"]
    CS --> RS["Recursive-Step Programming<br/>Deterministic Transitions"]
    RS --> CSM["Cryptographic State Machines<br/>Braid + WORM Seals"]

    style P fill:#1a1c25,stroke:#8a8d98
    style D fill:#1a1c25,stroke:#8a8d98
    style M fill:#1a1c25,stroke:#8a8d98
    style RS fill:#1a1c25,stroke:#d6ff6a
    style CSM fill:#1a1c25,stroke:#d6ff6a
```

---

## Languages

| Language | Files | What It Does |
|----------|-------|-------------|
| **Rust** | 30 | GFLOP→NAND extractor, Kani proofs, braid kernel, IAMAC, malleability engine |
| **SPARK Ada** | 29 | Zero-copy tensor parser, SHA-256, CRC-64, HMAC-SHA-256 |
| **Ada** | 16 | Parser bodies, SHA-256 reverse, loader, firmware |
| **Haskell** | 14 | Liquid Haskell refinements, SGL geometry, ISA spec |
| **Lean 4** | 12 | Formal verification proofs (0 sorry policy) |
| **Python** | 12 | WORM engine, cold boot, ICP anchor, CLI |
| **Verilog-A** | 10 | Analog trigonometric braid processors |
| **C** | 9 | WORM commit, call fibre, kernel workers |
| **BQN** | 7 | Array algebra, fibonacci/braid/ledger |
| **WASM** | 6 | Runtime, ISA, worm_frame, ledger, acct, sha256 |
| **PL/I** | 3 | Treasury ledger, functor, records |
| **Scala** | 3 | Sovereign Treasury pipeline + ZIO |
| **CUDA/PTX** | 3 | Malbolge step kernel, host launcher |
| **ASM** | 6 | x86-64, NASM, RISC-V |

---

## Repository Structure

```mermaid
flowchart TD
    Repo["devflow-finance-twin/"] --> Docs["docs/<br/>Documentation + Media"]
    Repo --> Frontend["frontend/<br/>Quantum Shadow Ledger UI"]
    Repo --> Lean["lean/<br/>12 Formal Proofs"]
    Repo --> Wasm["wasm/<br/>6 WASM Modules"]
    Repo --> Ada["ada/<br/>Firmware + Loader"]
    Repo --> Haskell["haskell/<br/>ISA Spec"]
    Repo --> Ptx["ptx/<br/>CUDA Kernels"]
    Repo --> Asm["x86_64/<br/>Assembly"]
    Repo --> Pli["pli/<br/>Treasury Engine"]
    Repo --> Cobol["cobol/<br/>WORM Bridge"]
    Repo --> Chisel["chisel/<br/>Hardware Accel"]
    Repo --> Scala["scala/<br/>Pipeline"]
    Repo --> Src["src/<br/>Python Legacy"]
    Repo --> Tests["tests/<br/>122 Tests"]
    Repo --> FBL["he-binary-functor/<br/>Binary Functor Architecture"]

    FBL --> NandArch["nand-architecture/<br/>NAND# ISA Spec"]
    FBL --> Gfnand["gfnand/<br/>GFLOP→NAND Extractor"]
    FBL --> Tensor["tensor-parser/<br/>SPARK Ada Parser"]
    FBL --> BlockLace["block-lace/<br/>Topology"]
    FBL --> Verilog["verilog-a/<br/>Analog Circuits"]
    FBL --> Crypto["crypto/<br/>IAMAC, Malleability, RSL"]
    FBL --> FblCore["fibonacci-braid-ledger/<br/>Core Research"]
    FBL --> Kernel["kernel/<br/>State Machines"]
    FBL --> RateLimiter["rate-limiter/<br/>RISC-V + Haskell"]
    FBL --> Xslt["xslt-wasm/<br/>XSLT Compiler"]
    FBL --> Sgl["sgl/<br/>Geometry Language"]
```

---

## Verification

```mermaid
flowchart LR
    subgraph Formal["Formal Proofs"]
        L4["Lean 4<br/>12 deeds, 0 sorry"]
        SPARK["SPARK Ada<br/>SHA-256, CRC-64, HMAC"]
        KANI["Kani<br/>31 bounded proofs"]
    end

    subgraph Runtime["Runtime Checks"]
        INV["Invariant Guard<br/>|sᵢ| < 8"]
        CHAIN["Chain Validation<br/>prev_hash = H(record)"]
        SEAL["Seal Integrity<br/>FNV-1a-64"]
    end

    L4 --> INV
    SPARK --> CHAIN
    KANI --> SEAL
```

---

## Interactive Frontend

<p align="center">
  <a href="./frontend/quantum_shadow_ledger.html">
    <img src="./docs/assets/hero-05.gif" width="500">
  </a>
</p>

**[Open Quantum Shadow Ledger →](./frontend/quantum_shadow_ledger.html)**

6-stage pipeline with interactive controls:
- **FIB INDEX** slider (1-20)
- **TAMPER** simulation
- **NAND** gate DAG visualization
- **QUANTUM** shadow display
- **ADVERSARIAL** attack surface
- **CTF MODE** with 6 challenges

---

## Demo Videos

| Part | Link | What It Shows |
|------|------|---------------|
| 1 | [demo-part1](./docs/assets/demo-part1.mp4) | Braid state transitions + seal generation |
| 2 | [demo-part2](./docs/assets/demo-part2.mp4) | Adversarial transform + crystallization |
| 3 | [demo-part3](./docs/assets/demo-part3.mp4) | NAND recursive primitive |
| 4 | [demo-part4](./docs/assets/demo-part4.mp4) | Full ledger verification |
| 5 | [demo-part5](./docs/assets/demo-part5.mp4) | Braid algebra deep dive |
| 7 | [demo-part7](./docs/assets/demo-part7.mp4) | Cryptographic seal chain |
| 8 | [demo-part8](./docs/assets/demo-part8.mp4) | Complete system integration |

---

## Quick Start

```bash
# Frontend
open frontend/quantum_shadow_ledger.html

# Build
make full

# Test
make test
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Fibonacci Braid Ledger](./docs/FIBONACCI_BRAID_LEDGER.md) | Core specification |
| [Formal Algebra](./docs/FORMAL_ALGEBRA.md) | Braid state transitions |
| [User Guide](./docs/USER.md) | Installation + usage |
| [About](./docs/ABOUT.md) | Ahmad Ali Parr |
| [Ledger](./docs/LEDGER.md) | WORM storage spec |
| [Inverted Monorepo](./INVERTED_MONOREPO.md) | Binary-first architecture |
| [Math Dictionary](./MATH_DICTIONARY.md) | All math operations |
| [Security](./SECURITY.md) | Threat model |
| [Changelog](./CHANGELOG.md) | Version history |

---

## License

Dual-licensed: **AGPL-3.0** (WASM/PL-I/COBOL/C/NASM/Chisel/Scala) and **FSL-1.1** (all others).

```
Copyright (c) 2026 SnapKittyWest.
Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
EIN 42-697643
```
