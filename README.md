# devflow-finance-twin

> Sovereign BaaS Ledger Stack — IBM i authoritative core, deterministic event sourcing, formal verification, quantum circuits, and a polyglot proof infrastructure spanning 18+ languages.

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%203.0-blue.svg)](LICENSE-AGPL-3.0)
[![License: FSL-1.1](https://img.shields.io/badge/License-FSL%201.1-green.svg)](LICENSE-FSL-1.1)

---

## What This Is

This repository is a production-grade sovereign banking-as-a-service ledger combined with a large-scale research platform. The two sides are distinct but share a philosophical core: **determinism, provenance, and formal accountability**.

The **production side** is a Python financial twin backed by IBM i (COBOL/RPGLE/DB2). Every financial event is append-only, hash-chained, and sealed with a cryptographic decision stamp. State is never mutated — it is always reconstructed from immutable history. The quantum layer exists as an advisory oracle; it can never write state directly.

The **research side**, built by Ahmad Ali Parr, is a complete tower of novel architectures: a Virtual Semantic Machine with its own ISA stack running down to SM90 CUDA, a NAND-complete language that compiles every operation to a single gate, Prolog-style logic engines embedded inside IBM i COBOL, a refinement type calculus that includes braid groups and Ptolemaic epicycles, and 26 parallel language implementations of a formal homomorphic encryption functor spec.

These are not prototypes. They are complete, coherent systems with formal proofs, hardware RTL, and verified execution.

---

## Table of Contents

- [Production Financial Core](#production-financial-core)
- [IBM i Layer](#ibm-i-layer)
- [VSM-2500 — Virtual Semantic Machine](#vsm-2500--virtual-semantic-machine)
- [NAND# Architecture](#nand-architecture)
- [HE-Binary-Functor](#he-binary-functor)
- [Custom Languages and DSLs](#custom-languages-and-dsls)
- [Workerman Calculus](#workerman-calculus)
- [Formal Verification](#formal-verification)
- [Non-Commutative Torus](#non-commutative-torus)
- [Quantum Layer](#quantum-layer)
- [Technical Stack](#technical-stack)
- [Build and Run](#build-and-run)
- [License](#license)

---

## Production Financial Core

The financial engine is an event-sourced ledger. Operations are `CREATE_ACCOUNT`, `POST_TRANSACTION`, `CREATE_INVOICE`, `RECORD_PAYMENT`, `CREATE_OBLIGATION`, `APPROVE_TRANSACTION`, `REJECT_TRANSACTION`, `REVERSE_TRANSACTION`.

Every operation is validated, appended to a WORM (Write Once Read Many) file as a JSON record, and given a cryptographic decision seal — a SHA-256 digest that chains every event to every prior event. The in-memory financial state is always rebuilt from scratch by replaying the WORM chain forward; it is never persisted separately. `verify_ledger_consistency()` rebuilds the entire chain and confirms the state hash matches.

Monetary arithmetic uses 18-decimal `Decimal` throughout — no floating point anywhere in the financial path. Rate limiting enforces 1000 operations per 60-second window. The quantum layer is called for suggestions but its output is discarded before any state change; the deterministic approval gate is the only path to state mutation.

The CLI is the entry point. The Docker image runs non-root, removes pip after installation, and runs a healthcheck that verifies WORM integrity on startup.

---

## IBM i Layer

The IBM i layer consists of four COBOL programs — the COBILT family — that implement financial logic on IBM i with RPGLE translators and DB2 for i storage.

What makes these unusual is that they are not ordinary COBOL. Each embeds a complete execution model that has no precedent in the COBOL world:

**COBILT-VAULT** is a cryptographic logic vault with a Prolog-style execution engine built entirely inside COBOL's EVALUATE/PERFORM dispatch. It has real predicate evaluation (`PRED-EXISTS`, `PRED-EQUAL`, `PRED-AUTHORIZED`), rule combinators (`RULE-AND`, `RULE-OR`, `RULE-CHAIN`), a unification stack with push/pop binding, choice point control for backtracking, and hash-chained ledger entries. This is a logic programming runtime inside a traditional IBM i COBOL program — no external runtime, no assembler.

**COBILT-DATAWORM** replaces SQL entirely with a Datalog storage engine implemented in COBOL. Facts are asserted, retracted, and queried through Datalog semantics. The persistence layer is a custom fact/rule/binding/stack working-storage system that the program manages itself.

**COBILT-ACH-TREASURY** handles ACH payment routing with the same embedded logic system — `QUERY`, `UNIFY`, `BACKTRACK` are first-class verbs alongside `CREATE-BATCH`, `ROUTE-PAYMENT`, `SETTLE`.

**COBILT-DATAWORM-TREASURY** combines the Datalog engine with the treasury logic in a single program targeting REXX orchestration with zero SQL.

The **Funnel DSL** is a custom business-rules language that compiles to COBOL, Prolog, or Mercury. It is parsed entirely inside RPGLE using YAJL for JSON emission. Declarations are `PROGRAM`, `TYPE` (enum), `RECORD`, `FILE ... USING ... KEY`, `RULE`, `PROC`. Statements include `REQUIRE`, `LOAD ... AS`, `SAVE`, `FAIL`. The RPGLE parser implements a full lexer, recursive-descent parser, typed IR, and three code generation backends.

---

## VSM-2500 — Virtual Semantic Machine

VSM-2500 is Ahmad's complete virtual machine stack. It is a deterministic register-memory-graph machine with binary semantic primitives, a viral springboard propagation mechanism, proof obligations on every state transition, and provenance on every event. It has no probabilistic selection, no floating-point at its core, and no softmax-style generation.

The stack has five layers:

**P2** is the hardware parallel fabric — 32 SIMD lanes, 8-wide issue, 256-register file, crystallization (speculative→committed state promotion), mirror hashing (state integrity verification), clone verification, and a barrier network. It is implemented as C++ with all seven verification suites passing and as SystemVerilog RTL with synthesizable binary ALU, synchronous register file, and springboard controller.

**P3** is the binary ISA — a 64-bit instruction word with explicit field layout, dual encoding layers (the C struct layer and the CUDA kernel layer), full opcode coverage for ALU, logic, shift, compare, memory, binding, compose/split/merge, springboard, commit, rollback, and halt.

**P4** is the virtual microcode layer — control words, datapath select, dependency masks, micro-opcode dispatch. It defines the execution contract from `FETCH → DECODE → DEPENDENCY_CHECK → REGISTER_READ → MICRO_OP_DISPATCH → DATAPATH_EXECUTE → MEMORY_OPERATION → STATUS_UPDATE → REGISTER_WRITE → VALIDATION → COMMIT`.

**The CUDA stack** maps this to SM90 execution across five `.cu` files covering the ISA kernel, semantic execution block, H100 SASS bridge, and the full recursive semantic→binary→embedding→convolution→SM90 reference. None of these fabricate SASS — all SASS is toolchain-generated via `nvcc -arch=sm_90`.

**The Lean 4 layer** formally verifies the binary algebra underlying VSM-2500: 20 Boolean axioms proven (`AND commutative`, `De Morgan's laws`, `XOR self-inverse`, `double negation`, etc.), word-level operators, shift operations, comparison semantics, instruction correctness proofs, and invariant preservation chains — all with zero `sorry`.

The non-commutative torus parameter θ = 89/2462 appears inside VSM-2500's execution kernels as a live phase-space parameter for chaotic transformation steps.

---

## NAND# Architecture

NAND# is a complete language tower with a single compute primitive: the NAND gate. Everything else — AND, OR, NOT, arithmetic, control flow — is derived from it.

The **NAND ISA** is 16-bit fixed instruction width with 16 registers (R0 = 0). One compute opcode (`NAND rd, ra, rb → R[rd] ← ¬(R[ra] ∧ R[rb])`), one halt, and five memory/control opcodes. The binary format has no header, no magic bytes, no relocation — entry at address 0, round-trip guarantee `∀w. encode(decode(w)) = w`.

The **NAND# language** compiles to NAND binary through: `AST → typed SSA IR (explicit shapes) → element-wise expansion → scalar NAND graph → register allocation → NAND ISA binary`. It is self-hosting: `compiler₀` (Rust) compiles a subset; its output `compiler₁` is NAND binary that compiles the full language.

The EBNF carries liquid-type-style refinement predicates inside grammar productions. `FibIndex<N>`, `Ledger<Type, N>`, `Generator<N>`, `Word<N>` are domain types. Braid-group generators `σᵢ` and `σ⁻¹` are grammar terminals. In-bounds array indexing is a syntax-level invariant.

The **FSL** (Formal Specification Language) is an XML dialect (`xmlns="urn:nandsharp:fsl"`) that carries LiquidHaskell-style refinement predicates inline. `RegId = {r : nat | 0 <= r && r < REG_COUNT}`, machine invariants (`r0_zero`, `pc_in_bounds`, `mem_wellformed`), and per-instruction pre/postconditions — all in a single spec file.

The **cobalt compiler** is a Prolog-to-x86 compiler. Prolog Horn clauses are parsed, loaded into a `Library`, expanded through `expandUntilCrystal → crystalize → crystalFold` (depth-bounded term rewriting), optionally transformed by `vaultTransform` (structural inversion: reverses atom names and argument order), then lowered to x86 bytes via a batch assembler with per-unit `trilockHash` integrity seals.

The ISA is encoded as a Haskell GADT making illegal encodings unrepresentable. The macro library is bilingual: every macro has Arabic and English documentation (e.g., `-- نسخ قيمة السجل / copy register`). `macroNot`, `macroAnd`, `macroOr` are all derived from NAND.

---

## HE-Binary-Functor

The HE-Binary-Functor is a formal specification for a recursive homomorphic encryption binary functor system. A `BinaryFunctor` is a 32-byte block: opcode (u16), version (u8), flags (u8), input/output widths (u32 each), parameter length (u32), child count (u16), reserved (u16), integrity hash (u64, Blake3 truncated). Composition is closed. Identity exists. Execution is deterministic. Failures are explicit.

The same formal spec is implemented in parallel across 26 languages: APL, Beam/Erlang, BQN, C, Circom, CUDA-Q, Fibonacci Braid Ledger (C + Haskell + BQN + x86 ASM + RV64I + C++), GF-NAND (Rust + Kani), Haskell (Workerman Calculus), K, Lean 4, NAND# (as above), QRisp, Q#, Rust, SGL, SystemVerilog, tensor-parser (SPARK Ada), Uiua, Verilog-A, Why3, XSLT-WASM. All target the same binary block header and composition invariants.

The **Fibonacci Braid Ledger** within this family uses braid group words with Fibonacci-indexed generators as the ledger data structure. Append operations are braid generator compositions. The seal is a cryptographic proof over the composed braid word.

The **GF-NAND** layer adds GF(2) finite-field refinements to the NAND IR — all operations are proven equivalent to polynomial operations modulo 2. Kani model-check harnesses verify formal refinement properties (31 bounded proofs).

---

## Custom Languages and DSLs

Beyond the systems above, the repository contains:

**ISA-JVM**: A custom ISA extending JVM-style bytecodes with actor primitives (`AGENT_SPAWN`, `AGENT_SEND`, `AGENT_YIELD`, `AGENT_HALT`), CSP-style channel operations (`CHAN_CREATE`, `CHAN_WRITE`, `CHAN_READ`), synchronization (`SYNC`, `CAS`), and tensor operations (`TENSOR_ADD`). No existing ISA combines these families.

**MXML (Machine eXecution Markup Language)**: An XML dialect for constrained multi-agent task graphs. `<runtime>` contains `<limits>` (max_workers, max_revisions, timeout_seconds), `<axioms>` (constitutional hard rules in Datalog style), `<commands>` (typed with isolation level), and `<tasks>` (DAG with dependency declarations). The constraint harness executes MXML documents through a state machine: `RECEIVE → PARSE → CONSTITUTION_CHECK → DECOMPOSE → ROUTE → DISPATCH → SUPERVISE → VALIDATE → CROSS_CHECK → ACCEPT` (or `FAILED_CLOSED` / `REVISE`).

**AGOL-86 / .a86**: ALGOL 68 syntax used as a neural network architecture specification format. Transformer forward passes, attention, matmul, GELU, layer norm, residual connections — all expressed as ALGOL 68 procedures. The Python tooling in `src/agol86/` interprets these files.

**BTEN Binary Format**: A custom binary tensor serialization with SPARK Ada formal layout. Magic `0x4E455442`. 64-byte header with CRC32. Per-tensor descriptors with explicit `Bit_Order => Low_Order_First`. Maximum rank 8, maximum tensors 1024, HMAC-SHA256 seal. Verified with GNAT Prove.

**Meta-Circular Datalog**: A self-hosting Datalog evaluator written in Datalog. The interpreter represents rules as data within the same relation space. Stratified negation via closed-world assumption. This replaces SQL as the persistence layer for the COBILT stack.

**Eclipse ParLog Kernel**: Fuses ECLiPSe constraint logic (finite-domain, interval, linear arithmetic) with Parlog concurrent logic (mode declarations, guarded clauses, committed-choice OR, concurrent streams, process pools) in a single kernel. Includes `alldifferent`, `cumulative`, `bin_packing` global constraints, reified constraints, and branch-and-bound.

**Astre-Vault**: Pure S/K/I combinatory logic implementing Madhava–Leibniz series for π and Qin Jiushao's algorithm (大衍術 — Chinese Remainder Theorem). No λ-abstraction. No interpreter. Pure combinator reduction.

**PL/I Functor Pipeline**: A PL/I sovereign treasury engine with pointer-threaded functor composition and VSAM ESDS WORM termination. `TREASURY_ENTRY` and `FUNCTOR_STATE` are ALIGNED structs. Hash chain verification runs before every append.

---

## Workerman Calculus

The Workerman Calculus extends LiquidHaskell's refinement type system with objects that have no counterpart in existing calculi:

**Ptolemaic terms** — `Epicycle(deferent, epicycle, mean_motion, anomaly)` as a type-level construct. Celestial coordinates (`SphereCoord` with RA/Dec), Hopf fibers over CP¹ (Bloch states), and a `Celestial` S² base manifold are built-in base types.

**Yang-Baxter normalization** runs as a fixed-point rewrite over `BraidWord` terms: cancels `σᵢσᵢ⁻¹`, commutes distant generators (`|i−j| ≥ 2`), applies the braid relation `σᵢσᵢ₊₁σᵢ = σᵢ₊₁σᵢσᵢ₊₁`. This normalization is proven terminating by lexicographic measure.

**WORM-sealed ROM lookups** (`FlopRom`) — reading from a WORM-sealed ROM is a typed operation that carries the seal in the type.

**Trigonometric annotations** — `sin[e]`, `cos[e]`, `period[p](e)` are first-class term constructors in the refinement language.

The **SGL (Spherical Geometry Library)** provides `Angle`, `Length`, `Radius`, `Point2` (lat/lon), `Point3` (unit sphere), `PointOn` (constrained to sphere), `GreatCircle` (sphere + normal), `Arc` as distinct types — preventing coordinate-system category errors at the type level.

---

## Formal Verification

Lean 4 proofs cover: BorrowchainStorageEngine, BifrostCapabilityExchange, EnochianEngine, MalbolgePTXKernel, SHREWDWeightLoader, ZeroSorryCore, VSM-2500 binary algebra (20 Boolean axioms, all complete), array verification templates.

The `formal-token-verification/` directory has multi-prover verification of the token model: Lean 4, Coq, F*, Isabelle/HOL, Agda — five proof assistants on the same specification.

`formal-verification-paper/theorem_ledger.rs` is a Rust program containing 500 formal claims across 10 families (TORUS, MLKEM, HAMILTONIAN, SPECTRAL, WICK, ERROR, SNR, COMPLEXITY, AMP, PROJ) — each with a status of `Proved`, `Refuted`, or `UnderSpecified`. It is an adversarial ledger that systematically evaluates and rejects unsupported mathematical claims.

The `cobalt-compiler/Lean4/ConductorSpec.lean` proves that the Rust sovereign conductor cannot omit routing a critical task to the human gate. The proof introduces `GhostState` to model Rust side effects and steps through `humanGate_criticalTask_requiresHuman → evaluateAll` monotonicity.

SPARK Ada with GNAT Prove covers the tensor parser: SHA-256, CRC-64, HMAC-SHA-256, bounded subtypes (`Blob_Offset`, `Tensor_Count`, `Rank`, `Dimension`).

Kani bounded model checking covers the NAND# architecture and GF-NAND: 31 verified proofs.

---

## Non-Commutative Torus

The non-commutative torus appears across 11 artifacts spanning five execution environments:

The **NCT Resonance Simulator** (`src/nct_resonance_simulator.py`) is the primary implementation. For irrational frequency α given as a continued fraction `[a₀; a₁, …, aₙ]`, it computes all convergents p_n/q_n via the three-term recurrence, evaluates the Diophantine lower bound |α − p_n/q_n| > C/q_n^μ, builds a resonance amplitude surface `A_n(ρ; ε, β) = β·(ρ/δ_n)^ε · e^{−γq_nρ} / (1 + (q_nρ)^κ)` where ε is the Hölder regularity exponent and β is the coupling amplitude, derives analytic threshold conditions, and generates a multi-page PDF scientific report with parameter sweeps.

The torus parameter **θ = 89/2462** is embedded as a live computational value in K and BQN execution kernels — it drives the angular phase increment in chaotic 8-step state transforms. In Verilog-A analog circuits, it parameterizes a cross-coupling capacitance matrix that forces state trajectories to avoid trivial limit cycles.

The **Weyl algebra claim ledger** (`formal-verification-paper/theorem_ledger.rs`) evaluates 50 claims about the operators U, V satisfying VU = e^{2πiθ}UV. The standard relation is proved. Claims about attack significance, eigenvalue isolation, and cryptanalysis are refuted by the ledger itself.

The **Malleability Engine** maps 256-bit digests deterministically to points on the Riemann critical line ρ_n = ½ + it_n using a precomputed table of the first 50 verified zero ordinates (Odlyzko/LMFDB). The Rust implementation is in `he-binary-functor/crypto/` with a working CLI.

The **Riemann ζ-zero Verilog-A circuit** physicalizes the Riemann-von Mangoldt density as an analog frequency spectrum. The Berry-Keating Hamiltonian H = xp is realized via OTA cross-coupling. The Riemann-Siegel Z-function drives a PLL to lock at zero crossings.

The **Yang-Baxter Taylor Vault** Taylor-expands R(λ) = Σ (λ^k/k!) R^(k) to finite order N, extracts coefficients, polynomial-encodes them, and seals the result cryptographically. The YBE residual after truncation is tracked and flagged.

---

## Quantum Layer

The quantum computer (`quantum_computer/`) is a full-featured circuit simulator: state/register/gate library (Pauli, Hadamard, CNOT, Toffoli, Fredkin), Shor's algorithm, Grover's search, VQE, QAOA, surface codes, stabilizer formalism, syndrome extraction, depolarizing/amplitude-damping/phase-flip noise models, circuit DAG optimizer, gate fusion, QASM serialization.

Within the financial twin, the quantum layer is **advisory only**. Its suggestions are never written to state. The deterministic approval gate is the only path to state mutation. The quantum layer cannot bypass this gate by design.

The **Demon's Hole** (`docs/demon_hole_quantum_circuit.md`) formalizes U_DH ∈ U(2^{2N}) — the Gao-Jafferis-Wall double-trace wormhole transfer operator — as a quantum circuit. Gate complexity lower bound: Ω(N² log²(N/ε)). The Susskind Complexity=Action conjecture resolution shows the demon pays computational work rather than thermal erasure cost. The Quipper Haskell DSL implements the recursive `invoke_demon_hole_rec` circuit generator.

The **Coherent Maxwell Demon** (`docs/coherent_maxwell_demon.md`) derives the generalized Landauer bound for a coherent register |+⟩^⊗N: ⟨W_erase⟩ = k_BT[S(ρ_Q) − C_rel(ρ_Q)] = −Nk_BT ln 2 (work gained). Net work per closed cycle: −2k_BT ln 2 per bit, sourced from quantum coherence as fuel. The Rust implementation computes the complete five-stage work budget.

---

## Technical Stack

| Domain | What | Languages |
|---|---|---|
| Production financial core | Event-sourced WORM ledger, rate-limited CLI | Python |
| IBM i financial logic | Logic-programming COBOL, ACH, Datalog storage | COBOL, RPGLE, DB2 for i |
| DSL compiler | Funnel DSL → COBOL / Prolog / Mercury | Python (RPGLE parser) |
| VSM-2500 ISA | P2/P3/P4 virtual machine, SM90 CUDA execution | C++, CUDA, SystemVerilog |
| VSM-2500 formal algebra | 20 Boolean axioms, instruction proofs | Lean 4 |
| NAND# tower | NAND-complete ISA + language + compiler | Rust, Haskell, EBNF |
| HE-Binary-Functor | Homomorphic encryption functor spec | 26 languages |
| Fibonacci Braid Ledger | Braid-encoded ledger | C, Haskell, BQN, x86 ASM, RV64I, C++ |
| Workerman Calculus | Refinement calculus + astronomy + braid | Haskell (LiquidHaskell) |
| NCT / Malleability | Resonance simulator, ζ-zero crypto | Python, Rust, Verilog-A, K, BQN |
| Quantum simulator | Full circuit simulator | Python |
| Multi-prover verification | Token model, ledger invariants | Lean 4, Coq, Isabelle, F*, Agda |
| Constraint harness | MXML execution engine | Python |
| Array verification | Array proofs with Mathlib | Lean 4 |
| Analog circuits | ζ-zeros, Chua chaos, Grover | Verilog-A |
| Formal crypto | IAMAC, GF-NAND, RSL, Yang-Baxter vault | Rust, Markdown specs |
| Hardware accelerator | Polynomial Wormhole Constraint | SystemVerilog, Why3, Rust |
| Self-hosting Datalog | Meta-circular evaluator | Soufflé Datalog |
| Combinatory mathematics | Madhava π, Qin Jiushao CRT | Unlambda |

---

## Build and Run

### Python Financial Twin (Docker)

```bash
docker build -t devflow-finance-twin .
docker run devflow-finance-twin CREATE_ACCOUNT --account_id ACC_001 --actor treasurer
docker run devflow-finance-twin POST_TRANSACTION --tx_id TX_001 \
    --from_account ACC_001 --to_account ACC_002 --amount 500.00
docker run devflow-finance-twin VERIFY_HISTORY
```

### Python directly

```bash
pip install -r requirements.txt
python src/cli.py CREATE_ACCOUNT --account_id ACC_001 --actor admin
python src/cli.py VERIFY_HISTORY
```

### Funnel DSL Compiler

```bash
python scripts/funnelc.py program.fnl --target cobol    # emit COBOL
python scripts/funnelc.py program.fnl --target prolog   # emit Prolog
python scripts/funnelc.py program.fnl --target mercury  # emit Mercury
```

### NCT Resonance Simulator

```bash
python src/nct_resonance_simulator.py \
    --cf "[0;1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]" \
    --eps 1.0 --beta 0.15 --C 0.25 --mu 2.0 \
    --out golden_resonance_report.pdf
```

### VSM-2500 P-Code VM

```bash
python src/pcode_vm_full_stack.py
```

### VSM-2500 CUDA (requires nvcc + SM90)

```bash
nvcc -O3 -arch=sm_90 -cubin src/vsm2500_isa_kernel.cu -o vsm2500.cubin
cuobjdump --dump-sass vsm2500.cubin > vsm2500.sass
```

### P2 Hardware Fabric (C++)

```bash
g++ -std=c++17 -O2 src/p2_hardware_parallel_fabric.cpp -o p2_fabric
./p2_fabric   # runs all 7 verification suites
```

### Lean 4 Proofs

```bash
cd lean
lake build
```

### Rust FSL Compiler

```bash
cd rust/fsl
cargo build --release
cargo test
```

### Malleability Engine CLI

```bash
cd he-binary-functor/crypto
cargo run -- 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

---

## License

**Triple-licensed:**

1. **AGPL-3.0-or-later** — for open-source use (WASM, PL/I, COBOL, C, NASM, Chisel, Scala)
2. **FSL-1.1** (Functional Source License) — for production use (all others)
3. **SNAPKITTY OPAQUE SOURCE LICENSE v1.0** — for proprietary components

See `LICENSE-AGPL-3.0`, `LICENSE-FSL-1.1`, `SNAPKITTY OPAQUE SOURCE LICENSE v1.0`.

```
Copyright (c) 2026 SnapKittyWest.
Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
EIN 42-697643
```

---

**Repository:** https://github.com/SNAPKITTYWEST/devflow-finance-twin
