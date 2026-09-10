# devflow-finance-twin

> Sovereign BaaS Ledger Stack — IBM i authoritative core, deterministic event sourcing, formal verification, quantum circuits, and a polyglot proof infrastructure.

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%203.0-blue.svg)](LICENSE-AGPL-3.0)
[![License: FSL-1.1](https://img.shields.io/badge/License-FSL%201.1-green.svg)](LICENSE-FSL-1.1)

---

This repository is a sustained argument about determinism. Every component — the IBM i logic vault, the financial twin, the virtual semantic machine, the NAND tower, the braid ledger, the refinement calculus — is an implementation of the same thesis: computation should be fully accountable, every transition should carry its provenance, and the gap between mathematical specification and machine execution should be closed, not managed.

---

## Table of Contents

- [Production Financial Core](#production-financial-core)
- [COBILT — Logic Programming on IBM i](#cobilt--logic-programming-on-ibm-i)
- [Funnel DSL](#funnel-dsl)
- [VSM-2500 — Virtual Semantic Machine](#vsm-2500--virtual-semantic-machine)
- [NAND# Architecture](#nand-architecture)
- [HE-Binary-Functor](#he-binary-functor)
- [Fibonacci Braid Ledger](#fibonacci-braid-ledger)
- [Workerman Calculus](#workerman-calculus)
- [IAMAC — Additive Homomorphic MAC](#iamac--additive-homomorphic-mac)
- [GF-NAND](#gf-nand)
- [Non-Commutative Torus](#non-commutative-torus)
- [Quantum Layer](#quantum-layer)
- [Constraint Harness and MXML](#constraint-harness-and-mxml)
- [Omega JAX Pivot](#omega-jax-pivot)
- [Formal Verification](#formal-verification)
- [Build and Run](#build-and-run)
- [License](#license)

---

## Production Financial Core

The financial engine is event-sourced. State is never stored directly — it is always reconstructed by replaying an immutable chain of events forward from genesis. The WORM (Write Once Read Many) storage appends each event as a JSON record linked to the previous by SHA-256. The in-memory state — account balances, transactions, invoices, obligations — is rebuilt on every startup by walking the chain. `verify_ledger_consistency()` rebuilds the chain independently and confirms the resulting state hash matches, providing a complete integrity check with no external dependencies.

Every executed operation produces a Decision Seal: a SHA-256 digest of the event ID, actor, operation, previous state hash, resulting state hash, timestamp, and metadata. Each seal is chained to the prior seal. The seal chain is a cryptographic proof of every decision the system has ever made.

Monetary arithmetic uses 18-decimal `Decimal` throughout. No floating point enters the financial path. The quantum layer can suggest — it cannot write. The deterministic approval gate is the only path from suggestion to state.

The CLI is the production entry point. Docker runs non-root with pip removed at runtime.

---

## COBILT — Logic Programming on IBM i

The COBILT family embeds logic computation into IBM i COBOL. These programs run on the platform that processes the majority of the world's financial transactions. The insight is that you do not need a new runtime to get logic programming — you can implement the kernel inside the platform you already trust.

**COBILT-VAULT** is a logic vault with predicate evaluation, rule combinators, unification, and a hash-chained event log, all implemented in COBOL's EVALUATE/PERFORM dispatch. Unification uses SPACES as the unbound variable marker: if either argument is SPACES it is overwritten with the other; if both are non-SPACES they must match; otherwise the operation fails. The hash chain uses a STRING concatenation of key + value + authority + previous hash into a 64-byte PIC X field. Every write advances the chain. The journal IS the database — fact assertions are immutable journal entries, and state is always the result of replaying the journal.

**COBILT-DATAWORM** is a Datalog persistence layer. Facts are asserted into a journal; assertions cannot be undone, only retracted by adding a RETRACTED entry. Queries match against the indexed predicate and argument. The working-storage model is streaming: one active fact record, one active binding, one active rule — the journal provides the full history. `DW-FACT-STORE` is a no-op because the journal entry IS the store.

**COBILT-ACH-TREASURY** handles ACH treasury routing with the same logic engine. `QUERY`, `UNIFY`, `BACKTRACK` are first-class operations alongside `CREATE-BATCH`, `ROUTE-PAYMENT`, `SETTLE`, `RECONCILE`.

These are not demonstrations of what COBOL could theoretically support. They are working implementations of logic computation on IBM i that require no external runtime, no assembler, and no departure from the platform's security model.

---

## Funnel DSL

Funnel is a business-rules language for IBM i that compiles to COBOL, Prolog, or Mercury. It is parsed entirely inside RPGLE with JSON emission via YAJL.

A Funnel program declares types (enums), records (typed structs), file bindings (VSAM/DB2 key mappings), rules (boolean-valued predicates), and procedures (sequenced statements). Statements are `REQUIRE expr`, `LOAD record(keys) AS alias`, `SAVE alias`, `IF/THEN/ELSE`, and `FAIL "message"`. Rules are first-class — a procedure calls rules by name, and the compiler proves what each rule evaluates before generating target code.

The Python compiler (`scripts/funnelc.py`) is a complete lexer, recursive-descent parser, typed IR, and three code generation backends. The COBOL backend generates full IBM i COBOL with file-control entries, working-storage layouts, and READ/REWRITE logic. The Prolog backend generates Horn clauses. The Mercury backend generates mode-directed predicates.

---

## VSM-2500 — Virtual Semantic Machine

The VSM-2500 is a formal model of what AI inference looks like when you refuse to leave determinism. It is a register-memory-graph machine with binary semantic primitives, constitutional constraints, and proof obligations on every state transition.

The central question VSM-2500 answers is: what does a language model look like if every value has a type, every operation carries a proof obligation, every transition preserves provenance, and no probabilistic selection is permitted? The answer is a virtual machine with 128-bit semantic registers, a viral springboard propagation mechanism, a constraint engine, a proof obligation ledger, and a routing function that selects next states by binary compatibility score rather than probability distribution.

The **Virtual Parameter** is the primitive object: a 128-bit structured word encoding ID, domain, current state, polarity (neutral / positive / negative / contradictory), binding reference, scope, last transition, and flags. Polarity is tracked explicitly. A parameter that reaches the contradictory state (B11) freezes and cannot transition further. VP_VALIDITY must pass before every use.

The **Viral Springboard** is the sole propagation mechanism. Every state transition is mediated by a springboard: create seed, validate against constraint set and proof obligations, apply transition rule, produce child state, attach provenance, commit or reject. There is no other way for state to change.

The **P-Code VM** (`src/pcode_vm_full_stack.py`) implements this as an executable Python virtual machine with a type-strict tagged stack, residual stream (the transformer's running activation), KV cache (32 layers × 32 heads × 4096 slots), Mixture-of-Experts router with minimum-activation gates that cannot be turned off (FORMAL_VERIF, LOWLEVEL_SYS, POLYGLOT_COMPILE are always active), attention primitives (scaled dot-product), AIRGAP isolation checks, and fault recovery with WORM trace. Every value pushed to the stack carries a TypeTag. Every arithmetic operation dispatches by type. Non-finite floats raise an invariant violation before they can propagate.

The **CUDA stack** takes the ISA all the way to SM90 execution. Five `.cu` files implement the full P2/P3/P4 chain: P2 is the 32-lane hardware parallel fabric with crystallization (speculative→committed state), mirror hashing (per-lane integrity), and barrier network; P3 is the 64-bit binary ISA; P4 is the control-word microcode layer. None of these fabricate SASS — toolchain-generated only.

The **SystemVerilog RTL** implements the binary ALU, synchronous register file (32×128-bit), and springboard controller as a synthesizable circuit. The testbench exercises the full sequence: BIND, SPRING, PROPAGATE, COMMIT, HALT.

The **Lean 4 proofs** formally verify the binary algebra underlying VSM-2500: 20 Boolean axioms (and_comm, xor_self_inverse, de_morgan_1, de_morgan_2, double_negation, absorption_1/2, distributivity, identity, annihilation...), word-level operators, comparison semantics, and invariant preservation chains. Zero `sorry`.

---

## NAND# Architecture

NAND# proves that one gate is enough. Every Boolean operation, every arithmetic function, every control flow construct reduces to NAND. The architecture is a complete tower from a 16-bit ISA to a self-hosting compiler.

The **NAND ISA** has one compute opcode: `NAND rd, ra, rb → R[rd] ← ¬(R[ra] ∧ R[rb])`. R0 is hardwired to 0. The binary format is a contiguous sequence of 16-bit little-endian words, no header, entry at address 0, with the round-trip guarantee `∀w. encode(decode(w)) = w`.

The **NAND# language** compiles through: AST → typed SSA IR with explicit shapes → element-wise expansion → scalar NAND graph → register allocation (linear scan, ≤16 registers) → NAND ISA binary. The compiler is self-hosting: `compiler₀` in Rust compiles a subset; the output `compiler₁` is a NAND binary that compiles the full language.

The **EBNF** carries liquid-type-style refinements as grammar productions. `FibIndex<N>`, `Ledger<Type,N>`, `Generator<N>`, `Word<N>` are domain types built into the grammar. In-bounds array indexing is a syntax-level invariant. Braid group generators σᵢ and σᵢ⁻¹ are grammar terminals.

The **Cobalt compiler** takes Prolog Horn clauses through `expandUntilCrystal → crystalize → crystalFold` (depth-bounded term rewriting) and `vaultTransform` (structural inversion of atom names and argument order), then emits x86 bytes with per-unit `trilockHash` integrity seals. The ISA is a Haskell GADT — illegal encodings are unrepresentable. The macro library is bilingual (Arabic and English).

---

## HE-Binary-Functor

A formal specification for a recursive homomorphic encryption binary functor system, implemented in 26 languages simultaneously.

A `BinaryFunctor` is a deterministic total function `F : Bⁿ → Bᵐ × Status`. The block header is 32 bytes: opcode (u16), version (u8), flags (u8), input width (u32), output width (u32), parameter length (u32), child count (u16), reserved (u16), Blake3 integrity (u64). Composition is closed. Identity exists. Execution is deterministic. Failures are always explicit — the Status is part of every return.

The same spec is implemented in: APL, Beam/Erlang, BQN, C, Circom, CUDA-Q, Fibonacci Braid Ledger, GF-NAND, Haskell/Workerman, K, Lean 4, NAND#, QRisp, Q#, Rust, SGL, SystemVerilog, SPARK Ada (tensor-parser), Uiua, Verilog-A, Why3, XSLT-WASM. All target the same 32-byte block header and the same composition invariants. The point is not portability — it is proof that the specification is implementation-independent.

---

## Fibonacci Braid Ledger

The Fibonacci Braid Ledger uses braid group words as state transition records. The key claim is that the braid word IS the cryptographic commitment — not "state plus a hash of state," but state whose very representation encodes both the transition history and the integrity proof.

Every ledger entry has a braid word drawn from B₅ generators {σ₁, σ₂, σ₃, σ₄} and their inverses. The `transit` function accumulates `p × 3 + |g|` over the word's generators with the previous hash as seed — a polynomial evaluation over the word. The `seal` function computes `(s << 5) XOR g` for each generator, initialized with `(prev XOR (n << 16) XOR state)`. The LiquidHaskell refinement type enforces as a compile-time invariant: `st e == transit (prev e) (word e)` — the state field IS the polynomial evaluation. You cannot write a state that doesn't match its word.

Fibonacci indexing bounds the ledger a priori: entries are indexed by Fibonacci position, capped at F(20) = 6765. This is not arbitrary — Fibonacci growth is the slowest superlinear growth, giving natural bounds without constants.

The BQN implementation (`braid.bqn`) defines braid inversion as `Inv ← -∘⌽` (reverse and negate) and cancellation as a left fold that pops the accumulator whenever σᵢ · σᵢ⁻¹ would otherwise appear. `Reduce` gives the canonical form of any braid word.

Implemented in 6 languages simultaneously (C, Haskell, BQN, x86-64 ASM, RV64I assembly, C++) with each implementation tracing back to the same mathematical definition.

---

## Workerman Calculus

The Workerman Calculus is a refinement type system where Yang-Baxter satisfaction is a binary operator in the type language, astronomical objects are base types, and WORM-sealed ROM reads carry their seals in the type.

The refinement language `Reft` contains: variables, literals, function application, arithmetic, `SphericalSine`, `GreatCircle`, and `YangBaxter` as binary operators; `TrigAnn` for `sin[e]`, `cos[e]`, `period[p](e)` annotations; `Epi` for Ptolemaic epicycle terms with deferent, epicycle, mean motion, and anomaly; `BraidWord` subject to Yang-Baxter normalization; `FlopRom` for WORM-sealed ROM lookups where the seal is part of the type; and `SphereCoord` for RA/Dec celestial coordinates.

`BraidWord` equality is equality of normal forms. Normalization runs to fixed point applying three rewrite rules: σᵢσᵢ⁻¹ → ε (cancellation), σᵢσⱼ → σⱼσᵢ when |i−j| ≥ 2 (far commutativity), σᵢσⱼσᵢ → σⱼσᵢσⱼ when |i−j| = 1 (braid relation). Termination is proven by lexicographic measure.

`YangBaxter` as a type-level binary operator means you can write a refinement predicate asserting that two operations satisfy the Yang-Baxter relation — i.e., that they safely commute in any order. This is a type system that reasons about commutativity of computation as a formal property.

The **SGL** (Spherical Geometry Library) gives `Angle`, `Length`, `Radius`, `Point2` (lat/lon), `Point3` (unit sphere), `PointOn`, `GreatCircle`, and `Arc` as distinct types that prevent coordinate-system confusion at the type level.

---

## IAMAC — Additive Homomorphic MAC

IAMAC is a polynomial MAC over GF(p) with additive homomorphism, designed for aggregation: `IAMAC(key, msg_a + msg_b) = IAMAC(key, msg_a) + IAMAC(key, msg_b)` over the prime field.

The field is `p = 0xFFFFFFFFFFFFFFC5` (2⁶⁴ − 59). The message is a vector of u64 values treated as polynomial coefficients. `compute_iamac(key, message, eval_point)` evaluates `P(eval_point) = Σᵢ mᵢ · eval_pointⁱ mod p` then multiplies by `key`. Multiplication uses u128 intermediate to prevent overflow before reducing mod p.

The homomorphism property is the core claim: two MACs computed under the same key can be added and the result equals the MAC of the sum of the messages. This enables verifiable aggregation — you can combine partial results and verify the combination without access to the original messages.

---

## GF-NAND

GF-NAND lowers multi-bit arithmetic IR to a NAND DAG where all operations are polynomial operations mod 2.

The IR graph (`ir.rs`) nodes are: `Var` (named variable, width), `Constant` (u64, width), `Add`, `Mul`, `Mac` (acc + a×b), `ShiftRight`, `CompareLt`, `Select` (ternary). Edges are implicit — each node holds IrNodeIds into the Vec.

The NAND DAG (`nand_lowering.rs`) uses hash-consing: `nand(a, b)` checks a deduplication cache before inserting. `not(a)` is `nand(a,a)`. `and`, `or`, `xor` are all built from `nand` and `not`. `half_adder` gives XOR (sum) and AND (carry). `full_adder` chains two half adders with an OR carry. `add_words` chains full adders into a ripple-carry adder over NandRef slices.

The constant zero is synthesized as `not(nand(x, not(x)))` = `not(1)` = `0` — using an input and its own negation to generate a structural constant without external input. Every arithmetic operation ultimately reduces to this DAG.

Kani bounded model checking verifies the formal refinement properties with 31 proofs.

---

## Non-Commutative Torus

The non-commutative torus appears across 11 artifacts as a model of what happens when you force irrational frequencies through deterministic systems — the resonance spikes that emerge when Diophantine approximation hits constraints.

The **NCT Resonance Simulator** (`src/nct_resonance_simulator.py`) takes an irrational frequency α as a continued fraction `[a₀; a₁, …, aₙ]`, computes all convergents p_n/q_n via three-term recurrence, evaluates the Diophantine lower bound, builds the amplitude surface `A_n(ρ; ε, β) = β·(ρ/δ_n)^ε · e^{−γq_nρ} / (1 + (q_nρ)^κ)` where ε is Hölder regularity and β is coupling amplitude, and derives analytic threshold conditions. Output is a multi-page PDF scientific report.

The **torus parameter θ = 89/2462** is embedded as a live computational value in K and BQN kernels where it drives angular phase shifts in chaotic state transforms. The initial state vector in BQN is `⟨65.0, θ, π, 0.0⟩` — 65.0 is explicitly labeled the "target plaintext." In Verilog-A analog circuits, θ parameterizes the cross-coupling capacitance matrix.

The **Weyl algebra claim ledger** (`formal-verification-paper/theorem_ledger.rs`) is a 1068-line Rust program containing 500 formal claims across 10 families (TORUS, MLKEM, HAMILTONIAN, SPECTRAL, WICK, ERROR, SNR, COMPLEXITY, AMP, PROJ), each evaluated against evidence and marked `Proved`, `Refuted`, or `UnderSpecified`. It is an adversarial ledger that systematically evaluates and rejects unsupported mathematical claims about the torus and Weyl algebra. The standard relation `VU = e^{2πiθ}UV` is proved. Claims about attack significance, secret isolation, and cryptanalysis are refuted by the ledger itself.

The **Malleability Engine** (`he-binary-functor/crypto/`) is a working Rust CLI that maps 256-bit digests deterministically to points on the Riemann critical line ρ_n = ½ + it_n using Odlyzko/LMFDB zero ordinates. The **IAMAC** additive homomorphism and the Malleability Engine's multiplicative structure compose into a framework for verified aggregation over ζ-zero orbits.

The **Riemann ζ-zero Verilog-A circuit** physicalizes the Riemann-von Mangoldt density as an analog frequency spectrum. Berry-Keating Hamiltonian H = xp is realized via OTA cross-coupling. The circuit forces eigenvalues into the GUE distribution.

---

## Quantum Layer

The quantum computer is a full-featured circuit simulator: state, registers, gate library (Pauli, Hadamard, CNOT, Toffoli, Fredkin), Shor, Grover, VQE, QAOA, surface codes, stabilizer formalism, depolarizing/amplitude-damping/phase-flip noise, circuit DAG optimizer, gate fusion, QASM serialization.

In the financial twin the quantum layer is advisory only. Its output is discarded before any state change. This is enforced in code, not just policy.

The **Demon's Hole** (`docs/demon_hole_quantum_circuit.md`) formalizes the Gao-Jafferis-Wall double-trace wormhole transfer operator U_DH ∈ U(2^{2N}) as a quantum circuit. Gate complexity lower bound: Ω(N² log²(N/ε)). The Susskind Complexity=Action resolution shows the demon pays computational work rather than thermal erasure. The Quipper Haskell DSL implements the recursive circuit generator with SYK boundary scramblers, GJW entanglers, and time-reversed unscrambling.

The **Coherent Maxwell Demon** derives the generalized Landauer bound for a register initialized in |+⟩^⊗N: work gained per erasure is k_BT[S(ρ) − C_rel(ρ)] = −Nk_BT ln 2. Net work per closed cycle: −2k_BT ln 2 per bit, sourced from quantum coherence as fuel. The Rust implementation computes the full five-stage work budget.

---

## Constraint Harness and MXML

MXML (Machine eXecution Markup Language) is an XML dialect for constrained multi-agent task graphs. A `<runtime>` element contains resource limits, constitutional axioms, typed commands with isolation levels, and a task DAG with dependency declarations.

The execution engine runs through a state machine: `RECEIVE → PARSE → CONSTITUTION_CHECK → DECOMPOSE → ROUTE → DISPATCH → SUPERVISE → VALIDATE → CROSS_CHECK → ACCEPT` (or `FAILED_CLOSED` or `REVISE`). The constitution evaluates axioms in order: authorization (hard), schema validity (hard), provenance completeness (hard), quality threshold (soft). Any hard failure causes `FAILED_CLOSED` regardless of soft results. The closed-world assumption is explicit: absence of positive evidence → UNKNOWN → FAILED_CLOSED.

The constitution axioms are specified as Datalog rules (in `constitution/datalog.py` as documentation): `authorized(Agent, Task) :- allowed(Agent, Task), has_capability(Agent, Task)`. The Python evaluator implements these rules with explicit fail-closed semantics.

---

## Omega JAX Pivot

`src/omega_jax_pivot.py` is a formal translation contract. It contains a PyTorch reference implementation of a causal transformer block (pre-LayerNorm, fused QKV projection, multi-head attention, causal mask, MLP with 4×expansion and GELU) and a specification of the exact JAX translation required.

The "OMEGA RULE" forbids introducing RoPE, GQA, MoE, FlashAttention, RMSNorm, SwiGLU, KV cache, or quantization until the baseline passes 16 verification tests: shape checks, causal mask correctness, attention row sums, JAX JIT vs eager equivalence, numerical parity with PyTorch, gradient existence and shapes, vmap equivalence, autoregressive leakage test. The JAX translation code is not present in this file — only the contract. Implementation must satisfy the contract before optimization begins.

---

## Formal Verification

Lean 4 proofs: BorrowchainStorageEngine, BifrostCapabilityExchange, EnochianEngine, MalbolgePTXKernel, SHREWDWeightLoader, ZeroSorryCore, VSM-2500 binary algebra (20 axioms, zero sorry), array verification (ArrayVerificationExamples with 10 sections all complete, ArrayVerification_Template as a starter scaffold).

Multi-prover token model in `formal-token-verification/`: Lean 4, Coq, F*, Isabelle/HOL, Agda — five proof assistants on the same specification.

SPARK Ada with GNAT Prove covers the BTEN tensor format: SHA-256, CRC-64, HMAC-SHA-256, bounded subtypes verified.

Kani bounded model checking: 31 proofs for NAND# and GF-NAND.

`cobalt-compiler/Lean4/ConductorSpec.lean` proves the sovereign conductor cannot bypass the human gate for critical tasks. Introduces `GhostState` to model Rust side effects and proves the routing invariant through `evaluateAll` monotonicity.

---

## Build and Run

### Python Financial Twin

```bash
docker build -t devflow-finance-twin .
docker run devflow-finance-twin CREATE_ACCOUNT --account_id ACC_001 --actor treasurer
docker run devflow-finance-twin POST_TRANSACTION \
    --tx_id TX_001 --from_account ACC_001 --to_account ACC_002 --amount 500.00
docker run devflow-finance-twin VERIFY_HISTORY
```

### Funnel DSL Compiler

```bash
python scripts/funnelc.py program.fnl --target cobol
python scripts/funnelc.py program.fnl --target prolog
python scripts/funnelc.py program.fnl --target mercury
```

### P-Code VM (VSM-2500 Python reference)

```bash
python src/pcode_vm_full_stack.py
```

### NCT Resonance Simulator

```bash
python src/nct_resonance_simulator.py \
    --cf "[0;1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]" \
    --eps 1.0 --beta 0.15 --C 0.25 --mu 2.0 --out report.pdf
```

### P2 Hardware Parallel Fabric

```bash
g++ -std=c++17 -O2 src/p2_hardware_parallel_fabric.cpp -o p2_fabric && ./p2_fabric
```

### VSM-2500 CUDA (SM90 required)

```bash
nvcc -O3 -arch=sm_90 -cubin src/vsm2500_isa_kernel.cu -o vsm2500.cubin
cuobjdump --dump-sass vsm2500.cubin
```

### Lean 4 Proofs

```bash
cd lean && lake build
```

### Rust FSL Compiler

```bash
cd rust/fsl && cargo build --release && cargo test
```

### Malleability Engine

```bash
cd he-binary-functor/crypto
cargo run -- 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

---

## License

**Triple-licensed:**

1. **AGPL-3.0-or-later** — open-source use
2. **FSL-1.1** (Functional Source License) — production use
3. **SNAPKITTY OPAQUE SOURCE LICENSE v1.0** — proprietary components

```
Copyright (c) 2026 SnapKittyWest.
Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
EIN 42-697643
```

**Repository:** https://github.com/SNAPKITTYWEST/devflow-finance-twin
