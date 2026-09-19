# Repository Audit — devflow-finance-twin
*Generated 2026-09-19*

**Scale:** 1,237 files · ~50 top-level directories  
**Primary languages:** Python, Go, Rust, Haskell, Lean, Swift, Algol 68, Metal, CUDA, COBOL, RPGLE, VHDL, Agda, Dafny, F*, Isabelle, Pascal, Modula-2, Occam, Zig, TypeScript, C/C++, Julia, APL, BQN, K, Uiua, Circom, Q#, SystemVerilog

---

## 1. Root & Config

### Files that belong at root (kept)
`.gitignore`, `README.md`, `CHANGELOG.md`, `SECURITY.md`, `Makefile`, `build.zig`, `requirements.txt`, all three license files.

### Missing root-level files

| File | Why it matters |
|------|---------------|
| `pyproject.toml` | No root Python package descriptor; sub-packages each have their own but nothing unifies them |
| `.editorconfig` | No shared editor config for a polyglot repo |
| `conftest.py` | pytest PYTHONPATH not auto-configured; Makefile exports `PYTHONPATH=src` manually |
| `.pre-commit-config.yaml` | No pre-commit hooks for linting/formatting |
| `CONTRIBUTING.md` | No contributor guidelines |
| `.dockerignore` | `docker/Dockerfile` exists but no `.dockerignore` |

### Broken Makefile targets
- `make wasm` calls `node compile_wasm.js` but that file lives at `scripts/compile_wasm.js`
- `make asm` references `x86_64/treasury_serialization.o` but the source is at `languages/x86_64/treasury_serialization.nasm`

---

## 2. Structure

| Directory | Purpose |
|-----------|---------|
| `src/` | Core Python engine (worm, twin, audit, quantum, cli) + Go glue + polyglot sub-dirs (agol86, pascal, a68, cuda, ada, bqn) |
| `finance/` | COBOL ACH/treasury, RPGLE ledger, PL/I, C#, Scala ZIO pipeline |
| `dream_rsi/` | Python recursive self-improvement engine |
| `sovereign/ledger/` | Go append-only ledger |
| `semiconductor/` | 13-file SoC design suite (specs + VHDL + Python + MATLAB) |
| `metal/` | Swift/Metal GPU transformer + SwiftTinyLLM |
| `apple-metal-inference/` | 18 Metal kernel files (attention, KV-cache, LoRA, int4 transformer) |
| `formal/` | Multi-prover formal verification (Lean, Coq, Isabelle, Agda, F*, Dafny, Frama-C) |
| `haskell/` | Kraus operator extraction + LiquidHaskell quantum specs |
| `rust/fsl/` | FSL Formal Solver Language Kernel |
| `constraint-harness/` | Deterministic MXML/Datalog/Python constraint engine |
| `quantum_computer/` | Pure-Python quantum simulator |
| `isa-jvm/` | JVM ISA emulator with invokedynamic stub |
| `asp/` | Answer Set Programming solver (Go) |
| `cobalt-compiler/` | Haskell compiler with LiquidHaskell extensions |
| `qflow/` | Haskell quantum dataflow DSL |
| `vsm2500/` | VSM2500 ISA spec + SystemVerilog + CUDA H100 SASS bridge |
| `retro-gpu/` | GPU architecture model in Occam/Modula-2/OCaml |
| `he-binary-functor/` | Polyglot: APL, BQN, K, Uiua, Circom, CUDA-Q, Q#, SystemVerilog, Why3, Rust, Haskell, Lean4 |
| `assembly-120-strict-model/` | x86_64 assembly model with neural accelerator, Dylan runtime |
| `apple6502x86/` | 6502/x86 cross-platform assembly (boot, ROM, monitor) |
| `wasm/` | Pre-compiled WASM binaries + WAT sources (6 modules) |

### Structural concerns
- `spiral-detection/` is an **empty directory** — placeholder or abandoned
- `src/` is triple-duty: Python core, Go acceptance tests, polyglot sub-dirs — Go files in `src/*.go` have no `go.mod`
- `metal/` and `apple-metal-inference/` serve overlapping purposes; relationship undocumented
- `.inbox/conflicts/` contains 11 conflict variants of a 113KB assembly file — unresolved staging conflicts

---

## 3. Code Quality

### Missing `__init__.py`

| Directory | Status |
|-----------|--------|
| `quantum_computer/circuit/` | 5 `.py` files, has `__pycache__` but not importable as package |
| `src/agol86/` | 19 files, no `__init__.py` |
| `semiconductor/` | `mosfet_to_cpu.py` present, no package init |
| `astre-vault/` | Python files, no init |
| `scripts/` | Python files, no init |

### Notable stubs/placeholders
- `isa-jvm/compiler/bytecode.py:166,204,218,231` — multiple placeholder comments in JVM bytecode emitter
- `src/pcode_vm_full_stack.py:1188` — `# placeholder, patch later`
- `constraint-harness/commands/model_command.py:24,28,30` — entire `ModelCommand` is a deliberate stub (`"stub execution"`) — undocumented as such

### Empty files
- `constraint-harness/tests/__init__.py` — empty
- `isa-jvm/tools/__init__.py` — empty

---

## 4. Security

**No hardcoded credentials found.** Grep for `password/secret/api_key/token = "..."` returned no hits.

### Gitignore gaps
The `.gitignore` covers `.env`, `__pycache__/`, `target/`, `dist/` but is **missing**:
- `*.key`, `*.pem`, `*.cert`, `*.p12`, `*.pfx`, `*.jks`
- `secrets/`, `credentials/`
- `*.asc` (GPG keys)

This matters given: COBOL ACH treasury code, `he-binary-functor/crypto/`, Circom ZK circuits, `formal/keyring.dfy`.

### License situation
Three simultaneous licenses: AGPL-3.0, FSL-1.1, 645-line custom SNAPKITTY OPAQUE SOURCE LICENSE. File headers use FSL-1.1 SPDX or AGPL-3.0 markers inconsistently. No precedence matrix documented.

---

## 5. Dependency Gaps

### Python
Root `requirements.txt` lists only `pytest>=8.0.0`. **30+ Python files** import `jax`, `torch`, `tensorflow`, `numpy`, `scipy` — all absent. Sub-packages handle it independently:
- `constraint-harness/pyproject.toml` — declares `torch>=2.0` as optional
- `dream_rsi/pyproject.toml` — lists no dependencies

### Go
Three `go.mod` files (`asp/`, `classifier/`, `sovereign/ledger/`) — all missing `go.sum`. Standard library only so `go mod tidy` would create trivially empty sums, but reproducible builds fail without them.

Go files in `src/*.go` have **no `go.mod`** — orphaned or implicit module.

### Haskell
`haskell/` has 10 `.hs` files but **no `.cabal` file**. CI references `test_runner.sh` which is missing. `qflow/` has a proper `.cabal`.

### Scala
`finance/scala/build.sbt` exists with ZIO deps but **no `project/` directory** and no sbt launcher. Build will fail.

### WASM
Six `.wasm` binaries committed alongside `.wat` sources. No WAT→WASM build step. `make wasm` target is broken (see above).

---

## 6. Test Coverage

### Has test suites
Core stack (`tests/test_stack.py`), dream_rsi (5 test files), sovereign/ledger (Go), quantum_computer (3 test files), constraint-harness (4 test files), isa-jvm (2 files), metal/MetalTransformerTests, Swift/ObjC physics tests, asp/solver.

### No test suites
`finance/`, `semiconductor/`, `formal/`, `metal/Sources/SwiftTinyLLM/`, `apple-metal-inference/`, `haskell/`, `rust/fsl/`, `cobalt-compiler/`, `datalog-engine/`, `physics/`, `astre-vault/`, `gpu/`, `wasm/`, `vsm2500/`, `retro-gpu/`, `he-binary-functor/`, `apple6502x86/`, `assembly-120-strict-model/`, `languages/`, `polyglot/`, `qflow/`, `src/agol86/`, `src/cuda/`.

**`make test` runs only `tests/test_stack.py` — less than 10% of available test files.**

---

## 7. Documentation Gaps

### Has READMEs
`apple-design-parser/`, `asp/parser/`, `asp/semantics/`, `benchmarks/rsi_lua/`, `classifier/`, `constraint-harness/`, `docs/`, `dream_rsi/`, `formal/linear-algebra/`, `formal/token-verification/`, `he-binary-functor/`, `isa-jvm/`, `kernel-language/`, `lua/`, `metal/`, `occam-b-bscl/`, `sovereign/ledger/`.

### Missing READMEs (substantial directories)
`apple-metal-inference/`, `apple6502x86/`, `assembly-120-strict-model/`, `astre-vault/`, `cobalt-compiler/`, `datalog-engine/`, `finance/`, `formal/` (parent), `gpu/`, `haskell/`, `languages/`, `physics/`, `polyglot/`, `qflow/`, `quantum_computer/`, `retro-gpu/`, `rust/`, `schema/`, `scripts/`, `semiconductor/`, `sovereign/` (parent), `src/`, `tests/`, `vsm2500/`, `wasm/`.

---

## 8. Semiconductor Directory

13 files covering architecture → logic design → RTL → EDA → fabrication → packaging. Pipeline is structurally complete as documentation. Implementation layer covers gate-level cells, attention compute, and behavioral CPU but:
- No RTL ALU/multiplier in VHDL to match spec docs
- No simulation testbench for `sk_transformer.vhd` or `sk_attention_matvec.vhd`
- No synthesis constraint files (SDC, TCL)
- No README
- `architecture.md` (3nm, 10 TOPS) and `soc-pipeline-spec.md` (5nm, 32–64 TOPS) describe overlapping targets without reconciliation

---

## 9. Metal/Swift

### Critical gap in Package.swift
`SwiftTinyLLM` (11 source files under `Sources/SwiftTinyLLM/`) is **not declared in Package.swift**. `swift build` will not compile any SwiftTinyLLM files. Fix: add executable target to Package.swift.

### Other gaps
- `frontend/` (HTML + TypeScript) and `m5-gateway/` (Swift + WAT) have no build integration
- `m5_gateway.wat` has no WAT→WASM build step
- `MetalTransformerTests.swift` requires macOS 13+ Metal — no CI guard for non-Apple environments

---

## 10. Novelty Highlights

1. **MOSFET-to-CPU simulator** — 7-level bottom-up simulation in pure Python stdlib: switch-level physics → CMOS cells → adder → ALU → CPU. Inline verification suite.
2. **Multi-prover adversarial verification** (`formal/token-verification/`) — same theorem in Lean 4, Coq, Isabelle, Agda, F* simultaneously, with counterproof in all five and `self_critique.md`.
3. **Algol 68 transformer** (`src/a68/`, 22 files) — complete transformer in a 1968 language; almost certainly the only finance-adjacent Algol 68 transformer in existence.
4. **VHDL Weyl quantum structure** — `WEYL_N = 2 * QQ_W` and `fx_mat_wq` embed Weyl algebra structure into fixed-point VHDL hardware types.
5. **H100 SASS bridge** (`vsm2500/`) — custom ISA with both SystemVerilog hardware and H100 SASS GPU execution paths.
6. **Occam GPU model** (`retro-gpu/`) — GPU warp/shared-memory/synchronization model in Occam (1983 transputer language) with OCaml and Modula-2 reference implementations.
7. **LiquidHaskell Kraus operator CI** — CI runs `liquid haskell/KrausLH.hs` to type-check quantum channel completeness conditions.
8. **Fibonacci braid ledger in x86 assembly** — ledger using braid group structures in x86_64 ASM.
9. **Qflow quantum dataflow DSL** — complete Haskell compiler (Lexer, Parser, AST) for a custom quantum dataflow language.
10. **`.continuity/` AI continuity system** — live MCP server cache tracking architectural decisions, drift snapshots, and code-link mappings.

---

## Priority Action Items

| Priority | Item |
|----------|------|
| 🔴 Critical | Fix `Package.swift` — add SwiftTinyLLM target |
| 🔴 Critical | Fix broken Makefile targets (`wasm`, `asm`) |
| 🔴 High | Add missing `.gitignore` patterns for key/pem/cert/secrets |
| 🟡 Medium | Add `go.sum` files to `asp/`, `classifier/`, `sovereign/ledger/` |
| 🟡 Medium | Add `haskell/` `.cabal` file |
| 🟡 Medium | Add `__init__.py` to `quantum_computer/circuit/`, `src/agol86/` |
| 🟡 Medium | Add READMEs to 25+ undocumented directories |
| 🟢 Low | Add `.editorconfig` |
| 🟢 Low | Add `CONTRIBUTING.md` |
| 🟢 Low | Add `conftest.py` at repo root |
| 🟢 Low | Document `model_command.py` stub status |
| 🟢 Low | Remove or populate `spiral-detection/` |
