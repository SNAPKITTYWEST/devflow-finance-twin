# Architecture Deep Reference

> Five-layer architecture with full component diagrams, interface boundaries, data flow between layers, execution model, boot sequence, state management, error propagation, and configuration hierarchy.
> Repository: devflow-finance-twin
> Generated: 2026-09-19

---

## Table of Contents

1. [Overview: The Inverted Monorepo](#1-overview-the-inverted-monorepo)
2. [Layer 0 — Physics and Silicon](#2-layer-0--physics-and-silicon)
3. [Layer 1 — Binary Semantics and Hardware Description](#3-layer-1--binary-semantics-and-hardware-description)
4. [Layer 2 — Compilers, Languages, and Formal Proofs](#4-layer-2--compilers-languages-and-formal-proofs)
5. [Layer 3 — Finance, Runtime, and Execution Infrastructure](#5-layer-3--finance-runtime-and-execution-infrastructure)
6. [Layer 4 — AI Execution, Self-Improvement, and Semantic Computing](#6-layer-4--ai-execution-self-improvement-and-semantic-computing)
7. [Cross-Layer Interface Boundaries](#7-cross-layer-interface-boundaries)
8. [Execution Model](#8-execution-model)
9. [Boot Sequence](#9-boot-sequence)
10. [State Management](#10-state-management)
11. [Error Propagation](#11-error-propagation)
12. [Configuration Hierarchy](#12-configuration-hierarchy)
13. [Component Diagrams (Text-form)](#13-component-diagrams-text-form)
14. [Data Flow Between Layers](#14-data-flow-between-layers)
15. [Security and Governance Architecture](#15-security-and-governance-architecture)

---

## 1. Overview: The Inverted Monorepo

### Design Principle

The central architectural assertion is **binary primacy**: the binary representation is the ground truth, not the artifact. In a traditional pipeline, human-readable source is compiled into a binary. In the Inverted Monorepo, the **NAND# specification** is the authoritative definition of all computation. Every higher-level representation — Lean 4 proofs, Rust code, x86-64 assembly, Verilog-A circuits, APL combinators — is a provably equivalent **projection** of NAND# semantics.

The refinement preservation invariant:
```
EXECUTE(LOWER(e)) == EVAL(e)
```
means that lowering an expression to NAND# and executing it in hardware must produce the same result as evaluating it in its source language. This invariant is mechanically verified by Lean 4, Coq, and Kani across the codebase.

### Five Horizontal Layers

```
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 4: AI Execution, Self-Improvement, and Semantic Computing       │
│  dream_rsi/ │ vsm2500/ │ apple-metal-inference/ │ classifier/          │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 3: Finance, Runtime, and Execution Infrastructure               │
│  finance/ │ sovereign/ (ledger) │ wasm/ │ constraint-harness/          │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 2: Compilers, Languages, and Formal Proofs                      │
│  cobalt-compiler/ │ qflow/ │ kernel-language/ │ formal/ │ asp/         │
│  languages/ │ isa-jvm/ │ haskell/ │ src/a68/ │ rust/fsl/              │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 1: Binary Semantics and Hardware Description                    │
│  he-binary-functor/ │ assembly-120-strict-model/ │ apple6502x86/       │
│  vsm2500/ (ISA) │ lua/ (metabinary) │ gpu/                            │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 0: Physics and Silicon                                          │
│  semiconductor/ │ physics/ │ apple-metal-inference/ (analog)           │
│  quantum_computer/ │ astre-vault/ │ retro-gpu/                         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Layer 0 — Physics and Silicon

### Purpose

Layer 0 represents the literal physical substrate of computation. Every component here models or simulates hardware at the transistor, gate, circuit, or quantum level. This layer answers the question: "Given the laws of physics, what computation is possible?"

### Components

#### 2.1 Semiconductor Stack (`semiconductor/`)

The semiconductor directory implements a complete 7-level abstraction stack from individual MOSFET transistors to a CPU:

```
Level 7: Accumulator CPU with program ROM
Level 6: D flip-flops (edge-triggered register elements)
Level 5: Adder/ALU (ripple-carry adder, comparator, barrel shifter)
Level 4: Combinational logic (half-adder, full-adder, MUX, DEMUX)
Level 3: CMOS gates (NAND, NOR, INV, AND, OR, XOR constructed from CMOS)
Level 2: NMOS/PMOS switch-level simulation (four-valued logic: L/H/Z/X)
Level 1: MOSFET transistors (union-find charge propagation)
```

The four-valued logic system (`L.ZERO`, `L.ONE`, `L.Z` high-impedance, `L.X` unknown) enables accurate modeling of tri-state buses and don't-care conditions. Charge propagation uses union-find: all transistors connected to a net form a union-find component, and the dominant driver (strong H or L) determines the net value.

Above the 7-layer simulation, `semiconductor/` contains a 3nm FinFET SoC design targeting 10 TOPS for edge AI inference. The VHDL RTL for the transformer compute core includes `sk_weyl` — an entity implementing the real-form D_theta Weyl operator on a 2q-dimensional vector space. This makes Weyl group theory a literal hardware component:
```vhdl
entity sk_weyl is
    generic (Q : positive := 8);  -- 2q-dimensional space, q=4
    port (
        clk    : in  std_logic;
        theta  : in  real_vector(0 to Q-1);
        v_in   : in  complex_vector(0 to 2*Q-1);
        v_out  : out complex_vector(0 to 2*Q-1)
    );
end entity sk_weyl;
```

#### 2.2 Quantum Computer (`quantum_computer/`)

Pure-Python quantum state vector simulator. Architecture:

```
quantum_computer/
├── core/state.py         State vector: 2^n complex amplitudes
├── core/matrix.py        Dense complex matrix operations
├── gates/__init__.py     Standard gates: H, X, Y, Z, CNOT, CCNOT, S, T, Rx, Ry, Rz
├── circuit/circuit.py    Circuit construction
├── circuit/dag.py        DAG-based circuit representation
├── circuit/optimizer.py  Gate cancellation, rotation merging
├── circuit/scheduler.py  Depth-minimizing gate scheduler
├── noise/advanced.py     Kraus noise models (depolarizing, amplitude damping, T1/T2)
├── algorithms/advanced.py    VQE, QAOA, quantum phase estimation
├── algorithms/topological.py Fibonacci/Ising anyon models
└── vm/simulator.py       State vector simulation engine
```

The simulator computes: `|ψ'⟩ = U|ψ⟩` for gate U, `ρ' = Σ_k K_k ρ K_k†` for Kraus channel, `prob(0) = |⟨0|ψ⟩|²` for measurement.

#### 2.3 Physics Simulation (`physics/`)

Three subsystems:

**Hawking Radiation (MATLAB):** Discrete model of Hawking radiation using Bogoliubov transformation. Outgoing modes are superpositions: `b_out = α a_in + β a_in†` where |α|² - |β|² = 1. Thermal spectrum: `⟨n⟩ = 1/(exp(ω/T_H) - 1)` at Hawking temperature `T_H = ℏκ/(2πck_B)`.

**Julia RWPT:** Parallel random-walk particle transport. Particle trajectories sampled from exponential free-path distributions; scattering via phase functions; absorption by Beer-Lambert law. Parallelized via `@threads` over particle batches. FPGA acceleration via AXI-stream interface.

**Isabelle/HOL Jungian Dynamics:** Formal verification of Lindblad master equation as completely positive trace-preserving (CPTP) semigroup. Key theorem: `ρ(t) = exp(L·t)[ρ(0)]` where L is the Lindbladian, and this map is CPTP for all t ≥ 0.

#### 2.4 Retro-GPU (`retro-gpu/`)

Simplified SIMT GPU simulator in Occam, OCaml, SML, and Modula-2. Architecture:

```
Grid
└── Thread Block × N
    ├── Warp × 32 threads
    │   ├── Register File (128 × 32-bit registers per thread)
    │   ├── Predicate Registers (8 × 1-bit per thread)
    │   └── Program Counter (shared across warp, SIMT)
    ├── Shared Memory (48 KB per block)
    └── Barrier Counter (synchronization)
Global Memory (4 GB)
Tensor Core Unit (GEMM accelerator)
```

The four language implementations (Occam, OCaml, SML, Modula-2) must produce identical outputs on the GEMM test kernel — this cross-language equivalence is verified by the `retro-gpu/ocaml/tests/test_full_pipeline.ml` test.

#### 2.5 ASTRE Vault (`astre-vault/`)

RDF/OWL semantic reasoning engine. Provides:
- **OWL DL tableau solver** (`astra_owl_solver.py`): consistency checking for the constraint constitution ontology
- **RCC-8 spatial propagation** (`rcc8_spatial.py`): spatial relation constraint solving for multi-agent topology
- **MATLAB math vault** (`astra_math_vault.m`): symbolic math for physics calibration

---

## 3. Layer 1 — Binary Semantics and Hardware Description

### Purpose

Layer 1 establishes the **NAND# binary ISA** as the ground truth of all computation, maps hardware description languages onto physical circuits, and provides the binary serialization format that all higher layers use for provenance records.

### Components

#### 3.1 NAND# ISA (`he-binary-functor/nand-architecture/`)

The NAND# instruction word is 16 bits:

```
Bit  15 14 13 | 12 11 10  9 | 8  7  6  5 | 4  3  2  1  0
     opcode(3) | dest(4)    | srcA(4)    | srcB/imm(5)
```

Opcode table (8 opcodes, 3-bit encoding):

| Opcode | Binary | Operation |
|--------|--------|-----------|
| NAND   | 000    | dest ← ~(srcA & srcB) |
| LOAD   | 001    | dest ← MEM[srcB] |
| STORE  | 010    | MEM[srcB] ← srcA |
| BRANCH | 011    | if dest != 0: PC ← PC + imm5 |
| CALL   | 100    | PUSH(PC); PC ← srcA |
| RET    | 101    | PC ← POP() |
| HALT   | 110    | halt execution |
| NOP    | 111    | no operation |

Register file: 16 × 64-bit registers (`r0`–`r15`). `r0` is always zero (like RISC-V `x0`). Memory: 32-bit address space, byte-addressable, little-endian.

The refinement preservation predicate is formally stated in Lean 4:
```lean
theorem refinement_preservation (e : Expr) :
  EXECUTE (LOWER e) = EVAL e := by
  induction e with
  | Lit n => simp [LOWER, EXECUTE, EVAL]
  | Add a b ih_a ih_b => ...
```

#### 3.2 HE-Binary Functor (`he-binary-functor/`)

The homomorphic encryption binary functor layer. Contains:

- `nand-architecture/` — NAND# specification (Lean 4 + Rust)
- `verilog-a/` — Analog computing: Grover search, anyon braids, Riemann zeta as translinear circuits
- `bqn/` — BQN array language `¬∧` combinator for NAND
- `gfnand/` — Rust GFLOP→NAND extractor with 31 Kani harnesses

The `gfnand/` Rust crate carries 31 Kani bounded model-checking harnesses:
- NAND truth-table correctness (`¬(a∧b)` for all 2-bit inputs)
- Half-adder behavior (sum = XOR, carry = AND)
- Arithmetic intensity bounds (GFLOP/NAND ratio for transformer workloads)
- Refinement preservation (EXECUTE(LOWER(e)) == EVAL(e) for arithmetic expressions)

#### 3.3 Assembly 120-Strict Model (`assembly-120-strict-model/`)

120 assembly modules, each with defined interface and exact LOC count. Modules are numbered; the existing files cover modules 8, 9, 11, 15, 18, 19, 20 plus firmware initialization (module 16) and the AVX2 NAND kernel. The "strict" constraint means each module's exported symbol set is fixed at design time — no new symbols may be added without a formal interface change.

Module interface format (documented in module header comments):
```asm
; MODULE: 08_neural_accelerator_engine
; EXPORTED SYMBOLS: NA_LOAD_PARAM, NA_BINARY_OP, NA_COMMIT_RESULT, NA_FLUSH_PIPELINE
; IMPORTED SYMBOLS: DIAG_STATUS_ADDR (from module 20)
; LOC: 750 (strict)
; INTERFACE VERSION: 1.0
```

#### 3.4 Apple 6502×86 Cross-Architecture (`apple6502x86/`)

6502+x86 hybrid: authentic 6502 semantics (register set, addressing modes, stack conventions) executing on x86 host via instruction emulation. The 6502 address space is mapped into x86 virtual address space; 6502 instructions are decoded and emulated by x86 code in the monitor/boot modules. This demonstrates that the NAND# ISA can be projected onto heterogeneous instruction sets.

#### 3.5 Metabinary Lua (`lua/`)

Binary serialization for NAND# words and HE-binary AST nodes. The metabinary format is the canonical wire format for:
- NAND# instruction streams (as packed 16-bit words)
- HE-binary functor AST nodes (opcode + children + payload)
- WORM block headers (64-byte fixed-size)
- Constraint-harness MXML contract binary encoding

The 55-opcode table covers: arithmetic (ADD, SUB, MUL, NEG), relinearization (RELINEARIZE, KEY_SWITCH, ROTATE), modulus management (MOD_SWITCH, RESCALE, MOD_UP), encoding (ENCODE, DECODE, ENCRYPT, DECRYPT), noise (NOISE_ESTIMATE, NOISE_ASSERT, BOOTSTRAP), composition (COMPOSE, PARALLEL, CONDITIONAL, ITERATE).

---

## 4. Layer 2 — Compilers, Languages, and Formal Proofs

### Purpose

Layer 2 transforms high-level languages (Prolog, quantum circuits, BLISS-derived kernel language, Algol 68, APL, Lisp) into executable NAND# representations, while formal proof assistants (Lean 4, Coq, Isabelle, Agda, F*, Dafny) verify the correctness of those transformations.

### Components

#### 4.1 Cobalt Compiler (`cobalt-compiler/`)

Haskell compiler: Prolog source → x86-64 executable. Pipeline:
```
Prolog source
    │ parse (Definite Clause Grammar)
    ▼
Prolog AST
    │ type-check (Liquid Haskell refinement types)
    ▼
Typed AST + refinement constraints
    │ lower (Cobalt IR)
    ▼
Cobalt IR (SSA form)
    │ optimize (LLVM-style passes)
    ▼
x86-64 assembly (NASM syntax)
    │ assemble + link
    ▼
executable (ELF)
```

The Liquid Haskell bridge: Cobalt uses LiquidHaskell refinement types to carry predicate annotations from Prolog clause guards into the x86-64 output. A Prolog clause `f(X) :- X > 0, ...` generates a LiquidHaskell refinement `{v: Int | v > 0}` which the Cobalt backend verifies is preserved through register allocation.

#### 4.2 QFlow Compiler (`qflow/`)

Haskell compiler for QFlow quantum dataflow DSL. Pipeline:
```
.qflow source
    │ lex (Alex lexer)
    ▼
Token stream
    │ parse (Happy parser)
    ▼
QFlow AST (Circuit, Instruction, Gate, Qubit)
    │ type-check (qubit linearity: each qubit used exactly once)
    ▼
Typed AST
    │ emit
    ▼
Quipper Circ monad code (Haskell)
```

Qubit linearity: the QFlow type system enforces that no qubit is used in more than one gate application before a measurement, preventing quantum cloning (no-cloning theorem compliance).

#### 4.3 Kernel Language Compiler (`kernel-language/`)

C-hosted compiler for a language inspired by BLISS/PL/M/CORAL 66, targeting NVIDIA Ampere (SM80) via PTX. Pipeline:
```
.kl source
    │ lex (hand-written lexer)
    ▼
Token stream
    │ parse (recursive descent)
    ▼
AST (module, proc, statement, expression)
    │ lower to IR (3-address SSA form)
    ▼
SSA IR
    │ optimize (constant folding, DCE, LICM)
    ▼
Optimized IR
    │ register allocate (linear scan, 128 regs)
    ▼
Register-allocated IR
    │ emit PTX
    ▼
.ptx file → nvcc → .cubin
```

Oberon runtime integration: `oberon/Kernel.Mod` provides memory allocation, GC tracing, and timer access as imported procedures callable from `.kl` source via `IMPORT Kernel`.

#### 4.4 ASP Engine (`asp/`)

Complete Answer Set Programming solver in Go. Architecture:
```
asp/
├── lexer/     Tokenize .lp files
├── parser/    Parse to logical form (rules, facts, constraints)
├── ast/       AST types
├── semantics/ Grounding (variable instantiation from domain)
├── solver/    DPLL-style conflict-driven clause learning (CDCL)
├── propagation/ Unit propagation + arc consistency
└── tests/     Conformance tests
```

The ASP solver implements the stable model semantics (Gelfond-Lifschitz 1988). Evaluation: ground program → Boolean formula → DPLL search with watched literals. Conflict analysis: 1-UIP (Unique Implication Point) scheme producing conflict clauses. Used by the datalog-engine and constraint-harness for hard constraint checking.

#### 4.5 Formal Verification (`formal/`)

Multi-prover formal verification suite:

| Proof Assistant | Coverage |
|-----------------|---------|
| Lean 4 | NAND# refinement preservation, zero-sorry policy (31 sorries closed), VSM-2500 algebra |
| Coq | Linear algebra, token verification |
| Isabelle/HOL | Jungian dynamics, GKSL semigroup, Kraus operator extraction |
| Agda | Dependent type constructions |
| F* | Cryptographic protocol verification |
| Dafny | ISA invariant verification |
| SPARK Ada | SHA-256 (FIPS-180-4), CRC-64, HMAC-SHA-256 |
| Kani (Rust) | 31 bounded model-checking harnesses |

The adversarial verification suite (`formal/token-verification/`) encodes the same theorem in all five proof assistants simultaneously, plus a `recursive/` subdirectory with a counterproof in all five and `self_critique.md`.

#### 4.6 Algol 68 Transformer (`src/a68/`)

22-file implementation of a decoder Transformer in Algol 68 (1968). Subsystems: embedding, multi-head attention with RoPE, MLP, layer normalization, Jacobian computation, inference loop, and serialization. This is the primary demonstration that the NAND# projection matrix applies to historically significant languages.

#### 4.7 Rust FSL (`rust/fsl/`)

Formal Specification Language in Rust. Subsystems:
- `assert_q/` — AssertQ reactive constraint store (formula, propagation, solver)
- `crux/` — Crux/SAW verification backend (AST, Lean monad stack, Omega test, Z3 backend, SAS backend)
- `eclipse_parlog/` — Eclipse/Parlog constraint logic programming (CLP(FD) domain, suspension, search)
- `qa5/` — QA5 reactive theorem prover (clause, prover, resolution, unification, strategy, racket morph)
- `cbmc*.rs` — CBMC bounded model checking harnesses for binary semantics
- `sovereign_neural_saas_core.rs` — VSM-2500 VirtualParameter algebra in Rust
- `theorem_ledger.rs` — Append-only proven theorem registry

#### 4.8 Datalog Engine (`datalog-engine/`)

Pure-Python Datalog evaluator. Evaluation algorithm: bottom-up semi-naive evaluation.
```
Initialize: delta_new = EDB facts
Repeat:
  delta_old = delta_new
  For each rule r in IDB:
    Apply r to (delta_old ∪ IDB_prev) to get new_tuples
    delta_new += new_tuples - IDB_prev
  IDB_prev += delta_new
Until delta_new = ∅
```

Stratified negation: topological sort of the dependency graph (edge from pred A to pred B if A's rule body contains ¬B). Each stratum computed to fixpoint before the next stratum uses its results.

---

## 5. Layer 3 — Finance, Runtime, and Execution Infrastructure

### Purpose

Layer 3 implements the production financial infrastructure and the runtime substrate that governs execution across all layers. It is the "operating system" of the architecture: process scheduling, append-only audit logs, cryptographic provenance, and the financial transaction rails.

### Components

#### 5.1 Polyglot Finance Stack (`finance/`)

The Sovereign Treasury Engine spans five languages:

| Language | Module | Role |
|----------|--------|------|
| COBOL | ACHRTRN, COBILT-ACH-TREASURY, LEDGWYCB | ACH origination, treasury bridge, ledger WORM |
| RPGLE | Agent transaction scheduler, end-of-day batch | IBM i style batch processing |
| PL/I | Treasury ledger, functor pipeline | Core ledger operations |
| Scala/ZIO | Concurrent coordination | ZIO effect-based concurrency |
| C# | Managed gateway | .NET managed interface |

COBOL modules follow enterprise naming conventions:
- `ACHRTRN` — ACH return transaction processor
- `COBILT-ACH-TREASURY` — ACH-to-treasury bridge
- `LEDGWYCB` — Ledger write-once COBOL bridge

Data flow: external ACH entries → ACHRTRN (COBOL) → COBILT-ACH-TREASURY (COBOL) → sovereign ledger (Go) → WORM block (LEDGWYCB) → verified Lean 4 proof.

#### 5.2 Sovereign Ledger (`sovereign/`)

2,170+ LOC Go implementation. Features:
- **SHA-256-chained event store**: each event record carries `prev_hash = SHA256(prev_record)`, forming an immutable chain
- **Merkle tree support**: `MerkleRoot(events[]) -> [32]byte` for efficient batch inclusion proofs
- **Thread-safe**: `sync.RWMutex` protecting the event slice; multiple readers, exclusive writer
- **Query API**: `Query(filter EventFilter) []Event` with filters by aggregate ID, event type, time range
- **Snapshot API**: `Snapshot(seq int) LedgerSnapshot` for point-in-time views
- **Replication API**: `Replicate(target LedgerSink)` for streaming all events to a follower
- **Sealing**: `Seal() SealRecord` — creates an immutable seal record over the current chain

Event record schema:
```go
type Event struct {
    Seq         int64
    AggregateID string
    EventType   string
    Payload     []byte
    OccurredAt  time.Time
    PrevHash    [32]byte
    Hash        [32]byte
}
```

#### 5.3 WASM Modules (`wasm/`)

Six WebAssembly modules providing a sandboxed execution environment:

| Module | Language | Function |
|--------|----------|---------|
| `runtime.wasm` | AssemblyScript | Core runtime: memory, scheduler |
| `isa.wasm` | AssemblyScript | NAND# ISA interpreter |
| `worm_frame.wasm` | Rust | WORM block frame construction |
| `ledger_replay.wasm` | Rust | Ledger event replay |
| `account_registry.wasm` | AssemblyScript | Account registry CRUD |
| `sha256.wasm` | Rust | SHA-256 hash (FIPS-180-4) |

The six modules communicate via shared linear memory: module boundaries are memory regions defined in a shared `memory_layout.h` header. No module can write outside its allocated region (enforced by WASM sandboxing + custom segment descriptors).

#### 5.4 Constraint Harness (`constraint-harness/`)

14-state state machine governing constraint-driven AI request processing. The harness wraps every AI model call (Python, PyTorch, external model API) in a constitutional evaluation sequence.

State machine (`runtime/states.py`):
```
RECEIVE → PARSE → CONSTITUTION_CHECK → DECOMPOSE → ROUTE → DISPATCH
    → SUPERVISE → VALIDATE → CROSS_CHECK → SYNTHESIZE → FINALIZE → RETURN

Exceptional transitions:
    any state → FAILED_CLOSED (hard constitutional violation)
    CONSTITUTION_CHECK / VALIDATE / CROSS_CHECK → REVISE (soft violation, retry)
    REVISE → CONSTITUTION_CHECK (re-evaluate after revision)
    REVISE → DISPATCH (skip to dispatch after revision)
```

Constitutional axioms evaluated at `CONSTITUTION_CHECK`:
- `authorization` — agent is authorized for the task
- `determinism` — request input is deterministic (no random state injection)
- `provenance` — input carries valid provenance hash
- `scope_limit` — payload does not exceed configured size limits
- `format_validity` — MXML schema validation passes
- `safety` — semantic content safety check

The MXML (Machine eXchange Markup Language) schema (`constraint-harness/mxml/`) defines the canonical exchange format for AI requests: XML-like structured documents with typed fields, required provenance metadata, and constitutional axiom annotations.

Audit trail: every state transition generates an `AuditEvent` with: `execution_id`, `from_state`, `to_state`, `task_id`, `input_hash` (SHA-256 of input, truncated to 16 hex chars), `timestamp`, `reason`. The event is appended to the execution's immutable history.

Decision sealing: at `FINALIZE`, a `DecisionRecord` is computed carrying: `execution_id`, `request_hash`, `result_hash`, `axiom_results`, `state_history`, `timestamp`, `decision`, `seal = SHA256(canonical_json(record_without_seal))`.

#### 5.5 Schema (`schema/`)

Two SQL schema files (IBM Db2 dialect):
- `ORC_SCHEMA.sql` — Orchestrator task queue: ORCTASK (task queue), ORCLOG (operational log), ORCAUD (audit trail per task)
- `schema-extended.sql` — Event-sourced treasury: EVENT_STORE (append-only, monotonic sequence), RAIL_SUBMISSIONS, RAIL_NOTIFICATIONS

The `EVENT_STORE.SEQUENCE_NUM` column has a `UNIQUE` constraint enforcing strict monotonicity. The `EVENT_STORE.PROCESSED` column defaults to 'N'; set to 'Y' by the consumer after processing. This enables exactly-once processing semantics when combined with a distributed lock on the consumer.

---

## 6. Layer 4 — AI Execution, Self-Improvement, and Semantic Computing

### Purpose

Layer 4 implements three distinct AI execution models: (1) Dream-RSI, a recursive self-improvement reconstruction using policy evolution over historical worlds; (2) the Apple Metal inference stack for real on-device LLM inference; and (3) VSM-2500, a binary-semantic virtual machine that rejects floating-point tensors.

### Components

#### 6.1 Dream-RSI (`dream_rsi/`)

Recursive self-improvement orchestrator. The RSI loop:

```
Round t:
  1. RSIOrchestrator.run_online_exploration(policy_t, discovery_agent)
     → DiscoveryTree T_t (new nodes added by FixedDiscoveryAgent.propose/execute)
  2. WorldStore.add(T_t) → historical world pool H_t = {T_1, ..., T_t}
  3. PolicyDeveloper.generate_revisions(policy_t, M) → {π_0=policy_t, π_1, ..., π_M}
  4. For each candidate π_i:
       For each world T_j in H_t:
         HistoricalReplay.evaluate(π_i, T_j) → score_ij
       candidate_i.score = mean(score_ij)
  5. winner = argmax(candidate.score)
     if winner.score < π_0.score: winner = π_0  [incumbent safety]
  6. policy_{t+1} = winner
```

Package layout:
```
dream_rsi/
├── core/orchestrator.py    RSIOrchestrator (main loop)
├── core/legacy.py          DreamRSI (legacy flat API)
├── discovery/agent.py      FixedDiscoveryAgent (hash-derived proposals)
├── evaluation/protocol.py  EvaluatorProtocol (score validation)
├── policy/                 SearchPolicy, PolicyDeveloper
├── replay/                 HistoricalReplay (offline, no discovery calls)
├── simulator/              SimulatorPool, BoundedWorld
├── experiments/runner.py   ExperimentRunner + baselines
├── persistence/            JSONL historical-world storage
├── metrics/collector.py    MetricsCollector (6 metric types)
└── tree.py                 DiscoveryTree (serializable)
```

Metrics collected per run:
- `discovery_agent_calls` — online exploration only
- `online_executions` — discovery tree node additions
- `replay_evaluations` — historical world evaluations (offline)
- `offline_evaluations` — same as replay (alias)
- `policy_revisions` — revisions generated (rounds × M)
- `compute_budget` — total compute units consumed

#### 6.2 Apple Metal Inference (`apple-metal-inference/`)

Llama-like 3B INT4 decoder Transformer targeting Apple Silicon Metal GPU. 15 dedicated compute kernels in Metal Shading Language:

| Kernel | Purpose |
|--------|---------|
| `embedding_lookup` | Token embedding table lookup |
| `rms_norm` | RMS layer normalization |
| `rope_encode` | Rotary position encoding (RoPE) |
| `q_proj`, `k_proj`, `v_proj` | Q/K/V projections |
| `attention_scores` | QKᵀ/√d_k |
| `softmax` | Attention weight normalization |
| `attention_combine` | Weighted value combination |
| `o_proj` | Output projection |
| `ffn_gate`, `ffn_up`, `ffn_down` | SwiGLU feed-forward |
| `int4_dequantize` | INT4 weight dequantization |
| `kv_cache_update` | KV cache write |
| `kv_cache_read` | KV cache read |
| `logits` | Final vocabulary projection |

INT4 quantization: weights stored as 4-bit integers with per-group (size 32) scale factors (float16). Dequantization: `w_f16 = int4_val * scale`. KV cache: `key_cache[layer, head, seq, dim]` and `value_cache[layer, head, seq, dim]` stored in device memory; capacity = `max_seq_len * n_heads * head_dim * sizeof(float16)`.

#### 6.3 VSM-2500 (`vsm2500/`)

Binary-semantic Virtual Machine. Explicit rejection of: floating-point tensors, softmax selection, probabilistic sampling. All computation over 128-bit Virtual Parameter (VP) objects.

VP algebra operations:
| Operation | Symbol | Definition |
|-----------|--------|------------|
| VP_AND | ∧ | Bitwise AND of 128-bit VP words |
| VP_OR | ∨ | Bitwise OR |
| VP_XOR | ⊕ | Bitwise XOR |
| VP_NAND | ↑ | Bitwise NAND = ~AND |
| VP_NOR | ↓ | Bitwise NOR = ~OR |
| VP_IMPL | → | Bitwise implication = ~A OR B |
| VP_SELECT | ?: | Deterministic selection by popcount comparison |
| VP_COMPOSE | ∘ | Concatenation of VP sequences |

`VP_SELECT` replaces softmax: given candidates C_1, ..., C_n, select `argmax_i(popcount(C_i))`. No randomness, no floating-point. Deterministic and reproducible.

H100 SASS bridge (`vsm2500_h100_sass_bridge.cu`): maps VSM opcodes onto NVIDIA Hopper SM90 CUDA instructions. VP words stored in 128-bit SIMD registers (`__int128` on SM90). `VP_AND` → `LDAR.128`, `VP_NAND` → `NOT+AND.128`.

#### 6.4 Classifier (`classifier/`)

Multi-head Go classification system. Three-layer architecture:
```
Input bytes
    │
    ▼
Router.Route(input) → ordered head list
    │
    ▼
Head.Infer(input) × N heads (parallel, N goroutines)
    │
    ▼
Aggregate(NoulChoices) → FinalLabel, Confidence
    │
    ▼
DecisionEnvelope (with audit trail)
```

Backends: `CPUBackend` (parallel goroutines, semaphore-limited), `BatchPipeline` (sequential classifier chain with short-circuit). Advanced variants: `HierarchicalClassifier`, `EnsembleClassifier`, `CalibratedClassifier`.

---

## 7. Cross-Layer Interface Boundaries

### Layer 0 → Layer 1 Interface

**MOSFET→NAND Bridge:** `semiconductor/mosfet_to_cpu.py` exports a `CPU` object with `step()`, `load_program()`, `read_memory()`. Layer 1 consumes this as a reference implementation to validate the NAND# execution model.

**Quantum→Classical Bridge:** `quantum_computer/vm/simulator.py` measurement results (bit strings) are consumed by Layer 1's NAND# program loader as classical input data.

**Physics→Calibration Bridge:** `physics/julia-rwpt/RWPT.jl` produces calibration profiles (scattering cross-sections, absorption coefficients) that the `astre-vault/astra_math_vault.m` validates against analytical Lindblad solutions. These calibration profiles feed into the constraint-harness context for physics-domain requests.

### Layer 1 → Layer 2 Interface

**NAND# → Compiler Input:** The NAND# specification is the target of all Layer 2 compilers. Each compiler emits `.nand` bytecode (binary, 16-bit words) that the NAND# ISA interpreter in `he-binary-functor/` executes.

**Metabinary → AST Encoding:** Layer 2 compiler intermediate representations are serialized using the Lua metabinary format for storage in the WORM block store. An AST node's binary encoding is its canonical form for provenance hashing.

**Assembly → Verification Input:** `assembly-120-strict-model/` module interfaces are consumed by Lean 4 proofs in `formal/` as axioms. The assembly module declares its behavior, and the formal proof verifies that behavior is consistent with the NAND# refinement predicate.

### Layer 2 → Layer 3 Interface

**Compiled Programs → Ledger Events:** Each compilation result (bytecode) is recorded as a `ledger_event` with type `COMPILE_ARTIFACT`, carrying: source hash, compiler version, output hash, verification status. This creates an immutable record linking source to binary.

**Formal Proofs → Constitution:** Proven theorems (from `rust/fsl/theorem_ledger.rs`) are loaded into the constraint-harness constitution as `PROVED` axiom facts. A request that requires a property `P` checks: `theorem_ledger.has_proved(P)` as part of the `CONSTITUTION_CHECK` state.

**ORC Schema → Constraint Harness Scheduler:** The `ORC_SCHEMA.ORCTASK` table is the persistent backing store for the constraint-harness scheduler. `scheduler/dag.py` reads tasks from the ORC table, builds a dependency DAG, and dispatches them in topological order.

### Layer 3 → Layer 4 Interface

**Ledger → RSI Persistence:** Dream-RSI uses the sovereign ledger to persist historical worlds. Each `WorldStore.add(tree)` call writes a `WORLD_COMMIT` event to the ledger, ensuring that the historical world pool is recoverable after process restart.

**Constitution → RSI Policy Filter:** The constraint-harness constitution axioms constrain which policy revisions are valid. `PolicyDeveloper.generate_revisions()` calls the constitution evaluator on each candidate; candidates that violate hard axioms are filtered before scoring.

**Classifier → Dispatch Route:** The `classifier/` system determines routing within the constraint-harness `ROUTE` state. `Router.Route(input)` invokes the classifier to decide which command handler processes the request.

---

## 8. Execution Model

### Primary Execution Contexts

The repository defines five distinct execution contexts:

#### 8.1 Online RSI Execution Context
- **Entry:** `RSIOrchestrator.run(prompt, rounds, revisions_per_round)`
- **Determinism:** UUID generation is patchable for reproducible benchmarks; wall-clock time excluded from scoring
- **Concurrency:** Single-threaded Python; policy evaluation is sequential
- **Termination:** Always terminates (bounded rounds, bounded revisions, finite discovery tree)
- **Failure mode:** `DiscoveryAgent.execute()` raises → exception propagates to orchestrator → metrics recorded, round skipped

#### 8.2 Constraint Harness Execution Context
- **Entry:** `StateMachine.transition(State.RECEIVE)` followed by executor transitions
- **Determinism:** Every state transition is deterministic given the same input and axiom set
- **Concurrency:** `scheduler/async_helpers.py` uses `asyncio` event loop; DAG-parallel dispatching of independent sub-tasks
- **Termination:** Guaranteed (FAILED_CLOSED absorbs all error transitions; RETURN and FAILED_CLOSED have no outgoing edges)
- **Failure mode:** Any `IllegalTransitionError` → logged + FAILED_CLOSED

#### 8.3 Metal Inference Execution Context
- **Entry:** Metal `CommandQueue.makeCommandBuffer()` → encode kernels → commit
- **Determinism:** Metal kernels are deterministic for same input weights/activations; INT4 dequantization is exact
- **Concurrency:** GPU parallel; CPU host waits for `CommandBuffer.waitUntilCompleted()`
- **Termination:** GPU kernel timeout (default 30s) → Metal error → logged + fallback to CPU
- **KV cache management:** Fixed-size `max_seq_len` cache; evicts oldest entries (FIFO) when full

#### 8.4 VSM-2500 Execution Context
- **Entry:** `vsm2500_execute(program: &[u16], params: &[VirtualParameter]) -> Vec<VirtualParameter>`
- **Determinism:** Fully deterministic (no floating-point, no random)
- **Concurrency:** H100 SASS bridge uses CUDA cooperative groups
- **Termination:** Bounded by instruction count (HALT opcode or step limit)
- **Failure mode:** Undefined opcode → `VSM_FAULT` trap to host; out-of-bounds memory → `VSM_SEGFAULT`

#### 8.5 Finance Transaction Execution Context
- **Entry:** ACH entry arrives at COBOL ACHRTRN module
- **Determinism:** Fully deterministic (COBOL COMPUTE has defined overflow behavior)
- **Concurrency:** RPGLE jobs run in separate IBM i job queues; Go sovereign ledger uses `sync.Mutex`
- **Termination:** Each transaction has a hard timeout (COBOL PARM-based); timeout → RETURN-CODE 99
- **Failure mode:** All COBOL failures write return codes; PL/I failures raise conditions caught by ON-unit handlers

### Instruction Fetch-Decode-Execute Cycle (NAND# Reference)

```
1. FETCH:
   word = MEM16[PC]
   PC += 2

2. DECODE:
   opcode = (word >> 13) & 0x7
   dest   = (word >>  9) & 0xF
   srcA   = (word >>  5) & 0xF
   srcB   = (word >>  0) & 0x1F  // or immediate (5-bit signed)

3. EXECUTE (opcode dispatch):
   switch opcode:
     NAND:   R[dest] = ~(R[srcA] & R[srcB])
     LOAD:   R[dest] = MEM64[R[srcB]]
     STORE:  MEM64[R[srcB]] = R[srcA]
     BRANCH: if R[dest] != 0: PC += sign_extend5(srcB) * 2
     CALL:   STACK.push(PC); PC = R[srcA]
     RET:    PC = STACK.pop()
     HALT:   halt
     NOP:    (nothing)

4. WRITEBACK: (incorporated in EXECUTE for NAND#)

5. REPEAT
```

---

## 9. Boot Sequence

### Full System Boot Sequence

The complete boot sequence for a devflow-finance-twin process spans hardware simulation, firmware initialization, and application startup:

```
T=0: Power-on reset (apple6502x86/boot/boot.asm or firmware.asm for x86)
     ├── apple6502x86: RESET_VECTOR → RESET_HANDLER ($E000)
     │   ├── SEI, LDX #$FF / TXS (stack init)
     │   ├── CPU_INIT: zero A,X,Y; clear flags
     │   ├── MEM_INIT: zero-fill $0000–$01FF, init zero-page
     │   ├── ROM_INIT: copy ROM image from host
     │   └── JMP MONITOR_ENTRY
     │
     └── x86 path (assembly-120-strict-model/firmware.asm):
         ├── FIRMWARE_INIT: disable interrupts, clear firmware state
         ├── CPU_VECTOR_TABLE_SETUP: LIDT, install 32 exception handlers + 16 IRQ handlers
         ├── ISA_INITIALIZATION: init NAND# register file, set PC to entry vector
         ├── X86_BRIDGE_CONFIG: NAND#↔x86 address translation, segment descriptors
         └── INTERRUPT_HANDLER_REGISTER: all vectors → APIC enable

T=1: NAND# ISA initialization (assembly-120-strict-model/PHASE_2_CPU_EXECUTION_ENGINE.asm)
     ├── CPU_FETCH: load first instruction word from PC
     ├── CPU_DECODE: extract opcode/dest/srcA/srcB
     ├── CPU_EXECUTE: dispatch via jump table
     └── CPU_WRITEBACK: write result

T=2: Kernel-language runtime initialization (kernel-language/runtime/)
     ├── cpl_bridge.c: initialize CPL binding table
     ├── st80_runtime.c: initialize Smalltalk-80 primitive dispatch table
     └── oberon/Kernel.Mod: Kernel.New (bump-pointer alloc), Kernel.GetTimer

T=3: Constraint harness initialization (constraint-harness/)
     ├── Load constitution (constitution.py): axiom set
     ├── Load MXML schema (mxml/schema.py)
     ├── Initialize state machine (runtime/transitions.py): current = RECEIVE
     ├── Initialize audit log (audit/): empty history
     └── Initialize scheduler (scheduler/dag.py): empty task DAG

T=4: Sovereign ledger initialization (sovereign/)
     ├── Open or create event store (SQLite or in-memory)
     ├── Verify chain integrity (recompute all hashes)
     ├── Load genesis block (or create if empty)
     └── Set current sequence number

T=5: Finance stack initialization (finance/)
     ├── COBOL programs: initial WORKING-STORAGE initialization
     ├── RPGLE: data area initialization
     ├── Go sovereign ledger: connect to DB2 via ODBC driver
     └── Scala/ZIO: fiber runtime startup

T=6: RSI orchestrator initialization (dream_rsi/)
     ├── RSIOrchestrator(): empty simulator pool, empty world store
     ├── FixedDiscoveryAgent(): seed RNG from config
     ├── MetricsCollector(): zero all counters
     └── Optional: load historical worlds from JSONL persistence

T=7: Apple Metal inference initialization (apple-metal-inference/)
     ├── MTLCreateSystemDefaultDevice()
     ├── Load all 15 compiled .metallib kernels
     ├── Allocate KV cache buffers (max_seq_len × n_heads × head_dim × 2 bytes)
     ├── Load INT4 quantized weights from .safetensors file
     └── Create MTLCommandQueue

T=8: System ready — accepting requests
```

### Cold Boot vs. Warm Boot

**Cold boot:** Full T=0 through T=8 sequence. All state initialized fresh.

**Warm boot (constraint harness restart):** Skip T=0–T=2. Reload ledger from persistent store (T=4), reload constitution (T=3 partial), restore scheduler state from ORC_SCHEMA (ORCTASK table), reload theorem ledger (from theorem_ledger.json). RSI world store reloaded from JSONL persistence if configured.

**Hot restart (Metal inference context switch):** KV cache cleared (or snapshot-restored), weights remain in GPU memory. Restart from T=7 Metal initialization only.

---

## 10. State Management

### Immutable State (Append-Only)

Three systems enforce append-only immutability:

1. **Sovereign Ledger Events:** Once written, events are never modified. `Event.Hash = SHA256(payload + PrevHash)`. Any modification is detectable by hash chain verification.

2. **WORM Blocks:** Write-Once Read-Many blocks. Once `Chisel.io.sealed = true`, all write operations return error. The hardware model enforces this at the register level.

3. **Constraint Harness Audit History:** `StateMachine.history: list[AuditEvent]` is append-only. No `AuditEvent` is ever removed or modified. `DecisionRecord.seal` cryptographically commits the complete history.

### Mutable State (Controlled)

1. **RSI Discovery Tree:** Nodes are added but never removed. Node fields (`score`, `cost`, `metadata`) are set once on creation. Parent-child relationships are immutable after creation.

2. **KV Cache:** Mutable (overwritten on each forward pass). Eviction policy: FIFO when `seq_len >= max_seq_len`. The cache is not persisted across process restart.

3. **ORC Task State:** `ORCTASK.STATUS` transitions: `NEW → RUNNING → DONE | FAILED`. The state machine is enforced by DB2 CHECK constraints and application-level validation. Retry increments `RETRY_COUNT`.

4. **Constraint Harness State Machine Current State:** `StateMachine.current` is a single mutable field. Mutated only by `transition()` which validates legality before mutation.

### State Synchronization

1. **Sovereign Ledger (Go):** `sync.RWMutex` — multiple readers, exclusive writer. `Append(event)` acquires write lock, computes hash, appends, releases. `Query(filter)` acquires read lock.

2. **RSI World Store (Python):** Python's GIL provides implicit serialization for CPython. `WorldStore.add()` and `WorldStore.get()` are not explicitly locked.

3. **Constraint Harness Scheduler (asyncio):** `asyncio.Lock` per task in the DAG. Dependency resolution uses `asyncio.Event` — a task becomes ready when all dependencies signal their event.

4. **Classifier Audit Log (Go):** `sync.Mutex` protecting the audit log slice. `AuditLog.Append()` acquires lock, appends, releases. `AuditLog.Export()` acquires read lock, serializes.

---

## 11. Error Propagation

### Error Classification

The repository uses a three-tier error classification:

| Tier | Name | Behavior | Examples |
|------|------|----------|---------|
| T1 | Hard constitutional failure | → FAILED_CLOSED immediately, no retry | Authorization failure, provenance hash mismatch |
| T2 | Soft constitutional violation | → REVISE (up to max_revisions), then FAILED_CLOSED | Format validity failure, scope limit exceeded |
| T3 | Transient runtime error | → retry with exponential backoff | DB connection timeout, Metal command buffer timeout |

### Error Propagation Paths

**Constraint Harness:**
```
Any state:
  T1 error → transition(FAILED_CLOSED) → log AuditEvent → return DecisionEnvelope(FAILED_CLOSED)
  T2 error → transition(REVISE) → increment revision_count
    if revision_count >= max_revisions → transition(FAILED_CLOSED)
    else → transition(CONSTITUTION_CHECK) or transition(DISPATCH)
  T3 error → retry up to max_retries with exponential backoff
    after max_retries → treat as T1
```

**RSI Orchestrator:**
```
DiscoveryAgent.execute() raises:
  → log exception in metrics (error_count++)
  → skip current node proposal
  → continue to next proposal (no global abort)

PolicyDeveloper.generate_revisions() raises:
  → log exception
  → use incumbent policy only (candidate_set = [policy_0])
  → incumbent safety guarantee holds (winner = policy_0)

WorldStore.add() raises:
  → log exception
  → world not added to pool
  → next round uses smaller pool (no crash)
```

**Sovereign Ledger:**
```
Append hash mismatch (detected in Verify()):
  → LedgerCorruptionError (T1 equivalent)
  → Process should halt and alert (cannot auto-recover from corruption)

Append timeout (DB connection):
  → retry up to 3× with 100ms backoff
  → after 3 failures: LedgerUnavailableError → caller handles (T3)
```

**Metal Inference:**
```
MTLCommandBuffer error:
  → MTLCommandBufferStatus.error
  → Error domain = MTLCommandBufferErrorDomain
  → Log error, clear KV cache, retry inference
  → After 3 retries: fall back to CPU path (slower but functional)

Metal device lost:
  → T1: requires process restart and Metal re-initialization
```

### Cross-Layer Error Propagation

Layer 4 errors do not propagate to Layer 3 uninstrumented. The constraint-harness (Layer 3) wraps all Layer 4 calls:
```python
try:
    result = command.execute(context)
    sm.transition(State.VALIDATE, input_data=result)
except ConstitutionViolationError as e:
    sm.transition(State.FAILED_CLOSED, reason=str(e))
except Exception as e:
    audit.log_exception(e, execution_id=sm.execution_id)
    sm.transition(State.FAILED_CLOSED, reason=f"unexpected: {e!r}")
```

This ensures that any exception in Layer 4 (Metal inference crash, RSI exception, VSM fault) results in a `FAILED_CLOSED` decision with a full audit trail, rather than an unhandled exception propagating to the caller.

---

## 12. Configuration Hierarchy

### Configuration Sources (highest to lowest precedence)

```
1. Environment variables (process-level, runtime)
   DEVFLOW_LEDGER_URL, DEVFLOW_CONSTITUTION_PATH, DEVFLOW_MAX_REVISIONS
   DEVFLOW_METAL_MAX_SEQ_LEN, DEVFLOW_ORC_DB_URL

2. config/ directory files (YAML/JSON, per-environment)
   config/
   ├── base.yaml          Defaults for all environments
   ├── development.yaml   Dev overrides
   ├── production.yaml    Prod overrides
   └── test.yaml          Test overrides (patches UUID, disables Metal)

3. .continuity/decisions.json (architectural decisions)
   Read-only at runtime. Not used for runtime configuration.
   Used by tooling to validate that code matches recorded decisions.

4. Compiled-in defaults (code constants)
   dream_rsi/: RunConfig defaults (rounds=10, revisions=4)
   constraint-harness/: StateMachine defaults (max_revisions=3)
   classifier/: CPUBackend defaults (maxConcurrency=GOMAXPROCS)
```

### Key Configuration Parameters

| Parameter | Layer | Default | Description |
|-----------|-------|---------|-------------|
| `DEVFLOW_LEDGER_URL` | L3 | `sqlite:///sovereign.db` | Sovereign ledger database URL |
| `DEVFLOW_MAX_REVISIONS` | L4 | 3 | Max REVISE transitions before FAILED_CLOSED |
| `DEVFLOW_RSI_ROUNDS` | L4 | 10 | Default RSI rounds per run |
| `DEVFLOW_RSI_REVISIONS` | L4 | 4 | Policy revisions per RSI round |
| `DEVFLOW_METAL_MAX_SEQ_LEN` | L4 | 2048 | Metal inference KV cache capacity |
| `DEVFLOW_METAL_DEVICE_ID` | L4 | 0 | Metal device index |
| `DEVFLOW_CONSTITUTION_PATH` | L3 | `constitution.yaml` | Constitution axiom set path |
| `DEVFLOW_ORC_DB_URL` | L3 | (required) | ORC schema DB2 connection string |
| `DEVFLOW_WASM_MEMORY_PAGES` | L3 | 64 | WASM linear memory pages (64KB each) |
| `DEVFLOW_CLASSIFIER_CONCURRENCY` | L4 | `GOMAXPROCS` | Classifier goroutine concurrency limit |

### .continuity/ Architectural Memory

The `.continuity/` directory is a specialized configuration artifact — not runtime config, but architectural memory:
```
.continuity/
├── decisions.json         Design decisions (question/answer/commit/tags/relationships)
├── decisions.jsonl        Append-only log of all decisions
├── code-links.json        Cross-file dependency graph
├── drift-snapshot.json    Detected code-decision divergences
└── audit-cache.json       Cached audit results
```

Decision record schema:
```json
{
  "id": "DEC-001",
  "question": "Why does the constraint harness use 14 states?",
  "answer": "Each state represents a distinct semantic phase...",
  "commit": "abc123",
  "tags": ["architecture", "constraint-harness"],
  "relationships": {
    "supersedes": [],
    "relatedTo": ["DEC-007"],
    "causes": ["DEC-012"]
  }
}
```

---

## 13. Component Diagrams (Text-form)

### Full System Component Diagram

```
External Input
    │
    ▼
┌───────────────────────────────┐
│   Layer 4: AI Execution       │
│  ┌──────────┐ ┌──────────┐   │
│  │ dream_rsi│ │  VSM-    │   │
│  │ (RSI     │ │  2500    │   │
│  │  loop)   │ │  (binary │   │
│  └────┬─────┘ │  VM)     │   │
│       │       └────┬─────┘   │
│  ┌────▼──────────┐ │         │
│  │Apple Metal    │ │         │
│  │Inference      │ │         │
│  │(15 kernels)   │ │         │
│  └────┬──────────┘ │         │
│       │             │         │
│  ┌────▼─────────────▼───┐    │
│  │ classifier/ (Go)      │    │
│  └────────────┬──────────┘   │
└───────────────┼───────────────┘
                │
                ▼
┌───────────────────────────────┐
│   Layer 3: Finance/Runtime    │
│  ┌──────────────────────┐     │
│  │ constraint-harness/  │     │
│  │ (14-state SM)        │     │
│  └──────────┬───────────┘     │
│             │                 │
│  ┌──────────▼───────────┐     │
│  │ sovereign ledger (Go)│     │
│  │ SHA-256 chained      │     │
│  └──────────┬───────────┘     │
│             │                 │
│  ┌──────────▼───────────┐     │
│  │ finance/ (COBOL/RPGLE│     │
│  │ PL/I/Scala/C#)       │     │
│  └──────────┬───────────┘     │
│             │                 │
│  ┌──────────▼───────────┐     │
│  │ wasm/ (6 modules)    │     │
│  └──────────────────────┘     │
└───────────────────────────────┘
                │
                ▼
┌───────────────────────────────┐
│   Layer 2: Compilers/Proofs   │
│  cobalt/ qflow/ kernel-lang/  │
│  asp/   formal/  rust/fsl/    │
│  isa-jvm/ datalog/ src/a68/   │
└───────────────────────────────┘
                │
                ▼
┌───────────────────────────────┐
│   Layer 1: Binary/Hardware    │
│  he-binary-functor/ (NAND#)   │
│  assembly-120/ apple6502x86/  │
│  lua/ (metabinary) gpu/       │
└───────────────────────────────┘
                │
                ▼
┌───────────────────────────────┐
│   Layer 0: Physics/Silicon    │
│  semiconductor/ quantum_comp/ │
│  physics/ retro-gpu/          │
│  astre-vault/                 │
└───────────────────────────────┘
```

---

## 14. Data Flow Between Layers

### Upward Data Flows (L0 → L4)

```
semiconductor/ MOSFET simulation
    → outputs: CPU execution trace (list of register states)
    → consumed by: assembly-120-strict-model/ validation tests (L1)

quantum_computer/ state vector
    → outputs: measurement bit strings
    → consumed by: languages/futhark/ Wigner distribution (L2)

physics/julia-rwpt/ RWPT
    → outputs: particle transport calibration profiles (JSON)
    → consumed by: astre-vault/ OWL solver (L0→L0 internal) and
      constraint-harness/ constitution context (L0→L3)

retro-gpu/ execution trace
    → outputs: JSONL trace per instruction
    → consumed by: kernel-language/ codegen tests (L1→L2)
```

### Downward Data Flows (L4 → L0)

```
dream_rsi/ policy
    → outputs: SearchPolicy (parameter set)
    → consumed by: constraint-harness/ constitution evaluator (L4→L3)
    → consumed by: classifier/ routing decisions (L4→L4)

vsm2500/ VP computation result
    → outputs: 128-bit VirtualParameter words
    → consumed by: sovereign ledger event payload (L4→L3)
    → consumed by: assembly-120/ NA_COMMIT_RESULT (L4→L1)

apple-metal-inference/ inference result
    → outputs: logit tensor (vocab_size floats)
    → consumed by: constraint-harness/ result validation (L4→L3)
```

### Horizontal Data Flows (within layers)

```
L2: cobalt-compiler/ → formal/lean/ (compiled program as proof input)
L2: rust/fsl/theorem_ledger → constraint-harness/constitution (proved theorems as axioms)
L3: sovereign ledger ← finance/COBOL (ACH events written to ledger)
L3: ORC_SCHEMA ← constraint-harness/scheduler (task persistence)
L4: dream_rsi/persistence ← dream_rsi/core (world JSONL serialization)
L4: classifier/ ← apple-metal-inference/ (logit → label routing)
```

---

## 15. Security and Governance Architecture

### Cryptographic Provenance Chain

Every data object in the repository carries a cryptographic provenance chain:

```
Source file → SHA-256 hash (recorded in latest.json)
    → compiled artifact → SHA-256 hash (recorded in ledger COMPILE_ARTIFACT event)
    → test result → SHA-256 hash (recorded in ledger TEST_RESULT event)
    → deployment → SHA-256 hash (recorded in WORM block)
    → runtime decision → SHA-256 seal (constraint harness DecisionRecord)
```

No artifact can enter a downstream layer without its hash being recorded in the sovereign ledger. This enforces the principle of **determinism and provenance as first-class properties**.

### License Architecture

Three license layers apply simultaneously:

1. **AGPL-3.0** — Copyleft; any network-accessible service using this code must release modifications
2. **FSL-1.1** (Functional Source License) — Commercial use restricted to licensor-approved use cases for 2 years, then converts to Apache 2.0
3. **Sovereign Leviathan Node License** — Additional overlay in Lean 4, Haskell, and Python source headers; primarily attribution and covenant terms

License headers in Python/Haskell source:
```
SOVEREIGN LEVIATHAN NODE LICENSE
License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
```

### Zero-Sorry Formal Verification Policy

The Lean 4 codebase enforces a zero-`sorry` policy documented in `ZeroSorryCore.lean` (DEED-ENOCHIAN_ZERO_SORRY_CORE-080). All 31 previously open sorries have been closed. CI enforcement: `grep -r "sorry" formal/lean/ --include="*.lean" | grep -v "-- sorry"` must return empty.

### Governance: .continuity/ AI-Assisted Architectural Memory

The `.continuity/` system provides governance continuity across human and AI contributor boundaries. Design decisions are auto-drafted from commits (using the commit message and diff as input), carry relationship fields (supersedes, relatedTo, causes), and are linked to commit hashes. `drift-snapshot.json` records divergences detected between code and recorded decisions, enabling architectural drift detection before it becomes technical debt.

---

*End of ARCHITECTURE_DEEP.md*
