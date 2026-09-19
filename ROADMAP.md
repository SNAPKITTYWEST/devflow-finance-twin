# Devflow Finance Twin — Technical Roadmap

## Current State Summary (v2.0.0, 2026-09-05)

Devflow Finance Twin is a research-grade polyglot monorepo organized around the
**Inverted Monorepo** principle: the NAND# binary specification is the ground truth
from which all higher-level representations (Rust, Haskell, Lean 4, Verilog-A,
COBOL, Swift/Metal, and ~40 other languages) are derived. Four production tags
shipped in one calendar week (v1.0.0 → v2.0.0), indicating rapid foundational
build-out.

**Working and tested today:**
- WASM runtime (6 compiled modules: runtime, ISA, worm_frame, ledger_replay, account_registry, sha256)
- Lean 4 formal core (ZeroSorryCore, 31 sorries closed, DEED-071–079 unified)
- Rust/Kani bounded proofs (31 harnesses in gfnand/)
- SPARK Ada (SHA-256, CRC-64, HMAC-SHA-256 fully verified)
- Sovereign ledger in Go (2,170+ LOC, hash-chained, Merkle-backed, thread-safe)
- Finance polyglot layer (COBOL ACH, RPGLE EOD, PL/I treasury, Scala ZIO pipeline)
- Constraint-harness phases 1–8 (MXML → Constitution → State machine → DAG)
- Dream-RSI reconstruction (RSIOrchestrator, layered modules, 122/122 pytest)
- Bottom-up MOSFET-to-CPU simulator (7 levels, Python, semiconductor/)
- Metal INT4 transformer inference (MetalTransformer + SwiftTinyLLM + apple-metal-inference)
- VSM-2500 specification and H100 SASS bridge (CUDA, SystemVerilog, C++)
- he-binary-functor deliverables: 30+ subdirectories, Fibonacci Braid Ledger, GFLOP→NAND extractor

**Known stubs and gaps:**
- constraint-harness model adapters are stubs (no live model provider wired)
- dream_rsi CLI `--revisions` flag is ignored; `SimulationBudget.max_worlds` unused
- `.continuity` decisions are all auto-drafted ("needs-review")
- Stage 2 self-compilation fixpoint (binary₁ == binary₂) not yet demonstrated
- quantum_computer Python module is mostly stub/primitive layer
- No GPU benchmark numbers published for Metal inference kernels

---

## Short-Term Milestones (0–3 months)

### M1 — Decision Hygiene and Continuity Completion
- Replace all auto-draft `.continuity/decisions.json` entries with reviewed rationale
- Mark status as "accepted" and wire drift-snapshot.json to CI so stale decisions block merge

### M2 — Dream-RSI CLI Correctness
- Wire `--revisions` through `dream_rsi.cli` to `RSIOrchestrator.run()`
- Activate `SimulationBudget.max_worlds` enforcement
- Add held-out world generalization metric to evaluation report

### M3 — Constraint-Harness Model Adapters
- Replace stub `ModelAdapter` with at least one live provider (local Ollama or HTTP endpoint)
- Add integration test covering full MXML → model → seal path

### M4 — Self-Hosting Bootstrap Stage 1 Audit
- Document and test that compiler₀ (Rust reference) produces binary₁ from NAND# source of compiler₁
- Add CI step recording hash of binary₁ and enforcing reproducibility

### M5 — VSM-2500 Execution Test Harness
- Unit test suite for vsm2500_core.sv (iverilog or Verilator)
- Wire vsm2500_h100_sass_bridge.cu into a CUDA unit test with stub SM90 device

### M6 — Quantum Computer Module Expansion
- Promote quantum_computer/core stubs to concrete gate, noise, and error-correction implementations
- pytest coverage for all promoted modules

---

## Medium-Term Milestones (3–12 months)

### M7 — Inverted Monorepo Stage 2 Bootstrap
- Demonstrate binary₁ == binary₂ (hash equality) for bounded programs via NAND# self-compiling pipeline
- Extend Kani coverage from 31 to 60+ harnesses

### M8 — Semiconductor SoC Integration
- Connect mosfet_to_cpu.py to VHDL sk_transformer.vhd/sk_logic_cells.vhd via co-simulation (GHDL + Python FFI)
- Expand EDA pipeline from specification to runnable synthesis scripts (Yosys or OpenROAD)

### M9 — Apple Metal Performance Benchmarking
- Repeatable Xcode GPU counter benchmarks for all 15 apple-metal-inference kernels
- Publish throughput (tokens/sec) and power figures on M-series chips

### M10 — Finance Layer End-to-End Integration
- Stand up end-to-end ACH → COBOL → treasury_ledger.pli → WORM → sovereign/ledger integration test in CI
- Add Scala ZIO `SovereignTreasuryZIO` property-based tests via ScalaCheck

### M11 — Formal Verification Paper Publication
- Complete `formal/verification-paper/main.tex` and submit to formal methods venue
- Add Isabelle proof objects for Kraus operator extraction

### M12 — Dream-RSI Production Expansion
- Reach 22,000 LOC production budget: real generalization metrics, multi-domain evaluators,
  persistence-backed replay, and distributed SimulatorPool

---

## Long-Term Vision (12+ months)

1. **Closed Binary-First Toolchain** — NAND# bootstrap reaches Stage 2 self-hosting;
   every language in the repo is a provably-equivalent projection of the same binary semantics.
2. **Verified Finance Infrastructure** — COBOL/RPGLE/PL/I layer carries end-to-end SPARK
   and Lean 4 proofs for ACH origination, treasury posting, and WORM commit integrity.
3. **Heterogeneous Inference Stack** — Metal INT4 (apple-metal-inference), CUDA H100 SASS
   (vsm2500), and VSM-2500 converge into a unified inference substrate with constitutional
   constraint-harness guardrails.
4. **Recursive Self-Improvement in Production** — Dream-RSI evolves from reconstruction
   to operational capability: live domain evaluators, world persistence, multi-agent
   policy development, sovereign ledger audit trail.
5. **Silicon Tapeout Preparation** — 10 TOPS @ 3nm FinFET SoC advances from RTL simulation
   to tapeout-ready physical design.

---

## Per-Subsystem Status

| Subsystem | Language(s) | Status | Key Gap |
|-----------|-------------|--------|---------|
| semiconductor | VHDL, MATLAB, Python | Active (spec + sim) | No EDA synthesis integration |
| metal/SwiftTinyLLM | Swift, Metal MSL | Active (kernels done) | No published benchmark |
| formal (multi-prover) | Lean 4, Coq, Isabelle, Dafny, F* | Active (31 sorries closed) | Isabelle .thy stubs not linked to Kraus |
| finance | COBOL, RPGLE, PL/I, C#, Scala | Active (all entry programs) | No CI integration test |
| dream_rsi | Python | Active (122 tests) | CLI --revisions ignored; max_worlds unused |
| sovereign/ledger | Go | Stable (2170+ LOC) | No replication/consensus layer |
| quantum_computer | Python | Stub | Most submodules are primitives only |
| constraint-harness | Python, MXML | Active (phases 1–8) | Model adapters are stubs |
| he-binary-functor | Rust, Haskell, Ada, BQN, K, etc. | Active (30+ dirs) | Bootstrap Stage 2 not demonstrated |
| vsm2500 | CUDA, C++, SystemVerilog | Active (spec + bridge) | No simulation test harness |
| apple-metal-inference | Swift, Metal MSL | Active (15 kernels) | No benchmark numbers |
| haskell (Kraus/Quipper) | Haskell, Liquid Haskell | Active | Isabelle export is stub |
| rust/fsl | Rust | Active | Cobalt self-hosting not tested |
| cobalt-compiler | Haskell | Active (cabal builds) | No end-to-end Prolog→ELF test |
| qflow | Haskell | Active (lexer/parser/AST) | No IR or codegen backend |
| wasm | WAT/WASM | Stable (6 modules) | No incremental update path |
