# Changelog

All notable changes to Devflow Finance Twin are documented here.

## [v2.0.0] — 2026-09-05

### Added
- **Inverted Monorepo** topology — binary-first compilation architecture
- GFLOP→NAND Extractor pipeline (parser, IR, nand_lowering, metrics, refinement)
- Kani verification harnesses (6 proofs: NAND truth table, half-adder, arithmetic intensity, refined NAND, array bounds, refinement preservation)
- Block-Lace topology: C++ ledger node, Rust re-invocation, Liquid Haskell refinements
- CRC-64 structural seal (SPARK Ada)
- HMAC-SHA-256 structural seal (SPARK Ada)
- SHA-256 full FIPS-180-4 implementation (SPARK Ada)
- SHA-256 reverse hash (bounded pre-image search, SPARK Ada)
- Verilog-A trigonometric processing: braid_trig_processor, trig_processor
- SPARK-to-Verilog-A cross-domain specification mapping
- Cryptographic Invertibility analysis
- FSL XML annotations for NAND# VM
- Refinement types for NAND and pointer arithmetic
- Self-Refining Bootstrap compiler design
- Math/Arithmetic dictionary
- SECURITY.md
- CHANGELOG.md
- Interactive badges (25+ language/tool badges)
- Flow chart diagrams (ASCII architecture)

### Changed
- README.md: complete rewrite with badges, about section, user guides, flow charts

## [v1.2.0] — 2026-09-05

### Added
- Ahmad Ali Parr Binary Functor Architecture deliverables
- XSLT→WASM compiler (`he-binary-functor/xslt-wasm/`)
- SGL Spherical Geometry Language (`he-binary-functor/sgl/`)
- BEAM assembly (`he-binary-functor/beam/`)
- C call fibre supervisor (`he-binary-functor/c-core/`)
- Rate Limiter Kernel (RISC-V + Liquid Haskell)
- State Machine Kernels (3 Haskell specs + 3 RISC-V assemblies + C worker)
- Fibonacci Braid Ledger v1 and v2
- SPARK Ada zero-copy tensor parser (DBTC, MLTR, BTEN formats)
- NAND# architecture spec suite (ISA, binary format, grammar, array semantics, omega model, bootstrap chain)
- FBL Research Paper (~8500 words)
- Tensor parser test fixtures (9 .bten files)
- FBL binary test fixtures (6 .bten files)
- `Sovereign_Harmony.pdf` — formal spec
- `assets/sovharmony.gif` — animated banner

## [v1.1.0] — 2026-09-05

### Added
- Cold Boot Protocol (`src/cold_boot.py`) — 3-phase: ROM Anchor → Bridge Init → Treasury Driver
- ICP Anchor Bridge (`src/icp_anchor.py`) — canister state, anchor chain, proof export, WORM sync
- 31 cold boot + ICP integration tests
- Dockerfile, Makefile, GitHub Actions CI
- PRODUCTION.md deployment guide

## [v1.0.0] — 2026-09-05

### Added
- Initial release
- WASM runtime (6 modules: runtime, ISA, worm_frame, ledger_replay, account_registry, sha256)
- WORM storage engine with Merkle chain
- Sovereign Treasury Engine (PL/I, COBOL, C, NASM, Chisel, Scala)
- Lean 4 formal verification (12 deeds, 0 sorries)
- Native loader (Ada + Zig)
- CUDA/PTX kernels
- x86-64 assembly
- Python legacy reference implementation
- 91 core tests passing
