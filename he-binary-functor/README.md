# he-binary-functor

**Ahmad Ali Parr's Binary Functor Architecture** — Complete deliverables repository.

This directory contains the full Binary Functor Architecture implementation spanning 30+ subdirectories, 20+ programming languages, and covering the complete pipeline from formal specification to hardware implementation.

---

## Directory Index

| Directory | Language(s) | Description |
|-----------|-------------|-------------|
| [apl/](apl/) | APL | Braid interpreter, opcodes, evidence gates, LEDGER_STATE |
| [beam/](beam/) | Erlang/BEAM | Call functor assembly |
| [block-lace/](block-lace/) | C++, Rust, Haskell | Topological block-lace ledger |
| [bqn/](bqn/) | BQN | Sovereign homogeneous array algebra |
| [c-core/](c-core/) | C | Call fibre supervisor |
| [circom/](circom/) | Circom | Zero-knowledge circuit |
| [crypto/](crypto/) | Rust, Markdown | IAMAC, malleability, RSL primitives, QTM |
| [cuda-q/](cuda-q/) | CUDA-Q | Quantum manifold greedy optimizer |
| [fibonacci-braid-ledger/](fibonacci-braid-ledger/) | Multi-lang | Core FBL research (see subdirs) |
| [gfnand/](gfnand/) | Rust, BQN, Kani | GFLOP→NAND extractor |
| [haskell/](haskell/) | Haskell | Workerman calculus, ISA, SGL |
| [k/](k/) | K | Sovereign tensor operations |
| [kernel/](kernel/) | Rust, Haskell, C | State machine kernels |
| [lean4/](lean4/) | Lean 4 | Formal proofs |
| [nand-architecture/](nand-architecture/) | Multi-lang | NAND# ISA spec (see subdirs) |
| [qrisp/](qrisp/) | Qrisp | Quantum circuits |
| [qsharp/](qsharp/) | Q# | Quantum programs |
| [rate-limiter/](rate-limiter/) | RISC-V, Haskell | Rate limiter kernel |
| [rust/](rust/) | Rust | PWC verified crate |
| [sgl/](sgl/) | Haskell | Spherical Geometry Language |
| [src/](src/) | Rust | SMT parser, BQN, K entry points |
| [systemverilog/](systemverilog/) | SystemVerilog | Hardware verification |
| [tensor-parser/](tensor-parser/) | SPARK Ada | Zero-copy tensor parser |
| [uiua/](uiua/) | Uiua | Array programming |
| [verilog-a/](verilog-a/) | Verilog-A | Analog/mixed-signal circuits |
| [why3/](why3/) | Why3 | Formal verification |
| [xslt-wasm/](xslt-wasm/) | Rust, JS, TS | XSLT→WASM compiler |

---

## Core Research Lines

### 1. Fibonacci Braid Ledger (FBL)
**Location:** `fibonacci-braid-ledger/`
- Array algebra (BQN), lock-free C++ ledger, x86-64 ASM, RV64I, research paper
- Liquid Haskell refinements, formal proofs

### 2. NAND# Architecture
**Location:** `nand-architecture/`
- ISA spec, binary format, NAND# grammar, array semantics, omega model
- Bootstrap chain, refinement types, FSL annotations, Kani verification

### 3. GFLOP→NAND Extractor
**Location:** `gfnand/`
- Parser, IR, NAND lowering, metrics, refinement types
- Kani bounded proofs (31), BQN workload analysis

### 4. Tensor Parser
**Location:** `tensor-parser/`
- SPARK Ada zero-copy parser for BTEN format
- SHA-256, CRC-64, HMAC-SHA-256, SHA-256 reverse

### 5. Crypto Primitives
**Location:** `crypto/`
- IAMAC (homomorphic MAC), Malleability Engine (Riemann ζ zeros)
- RSL Architecture (10 candidate primitives)
- Trigonometric QTM, Yang-Baxter vault

### 6. Verilog-A Analog
**Location:** `verilog-a/`
- Trigonometric braid processors
- Riemann ζ zero unfolding, Chua's circuit injection
- Lyapunov verification

### 7. APL Braid Interpreter
**Location:** `apl/`
- Recursive blob interpreter, opcodes 0-9
- Evidence gates (OS, Vacuum, Gap, Corr, Confinement)
- LEDGER_STATE LOCKED/UNLOCKED

---

## Quick Navigation

```
he-binary-functor/
├── README.md                           # This file
├── HE-BINARY-FUNCTOR-SPEC-001.md       # Formal spec (if present)
├── apl/                                # APL braid interpreter
├── beam/                               # BEAM assembly
├── block-lace/                         # Block-lace topology
├── bqn/                                # BQN array algebra
├── c-core/                             # C call fibre
├── circom/                             # ZK circuits
├── crypto/                             # Crypto primitives
├── cuda-q/                             # Quantum CUDA
├── fibonacci-braid-ledger/             # FBL core research
│   ├── asm_x86/                        # x86-64 assembly
│   ├── bqn/                            # BQN array code
│   ├── cpp/                            # C++ lock-free ledger
│   ├── test_fixtures/                  # Binary test vectors
│   ├── FBL_RESEARCH_PAPER.md           # ~8500 word paper
│   ├── LiquidHaskell.hs                # Refinement types
│   └── LiquidHaskell_full.hs           # Full specs
├── gfnand/                             # GFLOP→NAND
│   ├── src/                            # Parser, IR, lowering
│   ├── kani/                           # Bounded proofs
│   └── bqn/                            # Workload analysis
├── haskell/                            # Workerman, ISA, SGL
├── k/                                  # Sovereign tensor K
├── kernel/                             # State machines
├── lean4/                              # Lean 4 proofs
├── nand-architecture/                  # NAND# spec
│   ├── nand-isa/                       # ISA spec
│   ├── nand-binary/                    # Binary format
│   ├── nandsharp/                      # NAND# grammar
│   ├── array/                          # Array semantics
│   ├── omega/                          # Omega model
│   ├── bootstrap/                      # Self-refining compiler
│   ├── refinement/                     # Refinement types
│   ├── fsl/                            # FSL XML annotations
│   ├── kani/                           # Kani harnesses
│   └── rust/                           # Rust NAND VM
├── qrisp/                              # Qrisp quantum
├── qsharp/                             # Q# quantum
├── rate-limiter/                       # Rate limiter
├── rust/                               # PWC verified
├── sgl/                                # Spherical Geometry
├── src/                                # SMT parser, BQN, K
├── systemverilog/                      # SV verification
├── tensor-parser/                      # SPARK Ada parser
│   ├── test_fixtures/                  # BTEN test vectors
│   ├── sha256.ads/.adb                 # FIPS-180-4
│   ├── crc64.ads/.adb                  # CRC-64
│   ├── hmac_sha256.ads/.adb            # HMAC
│   └── sha256_reverse.ads/.adb         # Reverse hash
├── uiua/                               # Uiua array lang
├── verilog-a/                          # Analog circuits
│   ├── trig_braid_processor.va         # Braid trig
│   ├── CHUAS_CIRCUIT.md                # Chua's circuit
│   ├── RIEMANN_ZETA_VERILOG_A.md       # ζ unfolding
│   ├── ZETA_UNFOLD_REVERSE_ENGINEERING.md
│   ├── CHUA_INJECTION.md               # Chua into zeta
│   ├── LYAPUNOV_VERIFICATION.md        # Lyapunov analysis
│   └── SPARK_TO_VERILOG_A.md           # Cross-domain map
├── why3/                               # Why3 proofs
└── xslt-wasm/                          # XSLT→WASM compiler
    ├── src/                            # Rust compiler
    ├── js/                             # JS bindings
    └── ts/                             # TS bindings
```

---

## Key Files at Root

| File | Description |
|------|-------------|
| `HE-BINARY-FUNCTOR-SPEC-001.md` | Formal specification document |
| `sovereign_homogeneous.bqn` | BQN sovereign homogeneous array |
| `sovereign_tensor.k` | K tensor operations |
| `smt_parser.rs` | SMT parser entry point |

---

## Build & Test

```bash
# GFLOP→NAND (Rust + Kani)
cd gfnand/kani && cargo kani

# Tensor Parser (SPARK Ada)
cd tensor-parser && gnatprove -P project.gpr

# NAND Architecture (Rust + Kani)
cd nand-architecture/rust && cargo kani

# APL Braid Interpreter
# Run in Dyalog APL or GNU APL

# Lean 4 Proofs
cd lean4 && lake build
```

---

## License

Dual-licensed: AGPL-3.0 (WASM/PL-I/COBOL/C/NASM/Chisel/Scala) and FSL-1.1 (all others).

```
Copyright (c) 2026 SnapKittyWest.
Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
EIN 42-697643
```