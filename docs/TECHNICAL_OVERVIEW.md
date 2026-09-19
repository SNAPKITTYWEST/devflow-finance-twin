# Devflow Finance Twin — Technical Overview

## What It Is

Devflow Finance Twin is a research and engineering monorepo developed by Ahmad Ali Parr
(SnapKittyWest, Bel Esprit D'Accord Irrevocable Trust) that simultaneously pursues several
interlocking technical ambitions: a formally verified polyglot financial infrastructure,
a bottom-up semiconductor simulator, a binary-first compiler toolchain, an alternative
non-tensor AI execution model, a recursive self-improvement reconstruction, and a
production-grade Apple Silicon inference stack. The result is ~1,237 files across 50+
top-level directories in over 40 programming languages, organized around a principle
called the **Inverted Monorepo**.

The project's scope — verified payments infrastructure spanning MOSFET physics through
COBOL ACH origination to Lean 4 proofs — is not that of a typical software product. It
is closer to a comprehensive computational theory expressed as executable code: every
level of abstraction is present, from individual transistors to recursive policy improvement.

---

## Design Philosophy

### Binary Primacy

The central architectural assertion is that the binary representation should be the ground
truth, not the artifact. In a traditional pipeline, human-readable source is compiled into
a binary. In the Inverted Monorepo, the **NAND# specification** — a compact binary ISA
with a 16-bit instruction word (3-bit opcode, 4-bit destination, 4-bit source A, 5-bit
source B/immediate) — is the authoritative definition of all computation. Every higher-level
representation is a projection of NAND# semantics. The refinement preservation invariant
is: `EXECUTE(LOWER(e)) == EVAL(e)`.

This means Rust code in `gfnand/`, Lean 4 proofs in `formal/lean/`, Verilog-A analog
circuits in `he-binary-functor/verilog-a/`, and x86-64 assembly in
`assembly-120-strict-model/` are not separate implementations — they are provably
equivalent projections of a single binary specification.

### Zero-Sorry Formal Verification

The Lean 4 codebase enforces a zero-`sorry` policy, documented in `ZeroSorryCore.lean`
(DEED-ENOCHIAN_ZERO_SORRY_CORE-080, unifying DEED-071 through DEED-079). Thirty-one
sorries were closed in a single consolidation commit. The multi-prover suite extends
further: Coq covers linear algebra and token verification; Isabelle `.thy` exports are
generated from `KrausExtractor.hs`; Dafny, F*, and Agda appear in the tlm-jxcl formal
subdirectory; SPARK Ada provides mechanically verified SHA-256 (FIPS-180-4), CRC-64, and
HMAC-SHA-256; Rust/Kani covers 31 bounded model-checking harnesses. No single proof
assistant's trusted kernel is the sole guarantor of correctness.

### Determinism and Provenance as First-Class Properties

Across every subsystem, two properties are treated as non-negotiable: every computation
must be **deterministic** (pure functions, no hidden state), and every state transition
must carry a **provenance record** (append-only ledger, hash chain). The sovereign ledger
in Go enforces this at runtime: a SHA-256-chained event store with Merkle proof support
and explicit sealing. The six WASM modules (runtime, ISA, WORM frame, ledger replay,
account registry, sha256) are the deployed binary expression of these invariants in a
sandboxed execution environment.

---

## How the Subsystems Relate

The repo can be read as five horizontal layers arranged from physics to policy:

### Layer 0 — Physics and Silicon

`semiconductor/mosfet_to_cpu.py` implements a complete 7-level stack from individual
MOSFET transistors (union-find charge propagation, NMOS/PMOS switch-level simulation with
four-valued logic L.ZERO/ONE/Z/X) through CMOS gates, combinational logic, adder/ALU,
D flip-flops, and an accumulator CPU with program ROM. This is the literal bottom of the
abstraction tower.

Above it, `semiconductor/` contains a 3nm FinFET SoC design targeting 10 TOPS for edge
AI inference, with VHDL RTL for the transformer compute core — including a `sk_weyl` entity
implementing the real-form D_theta Weyl operator on a 2q-dimensional vector space, making
Weyl group theory a literal hardware component.

### Layer 1 — Binary Semantics and Hardware Description

The NAND# specification (`he-binary-functor/nand-architecture/`) establishes the binary
ISA. The analog computing layer (`he-binary-functor/verilog-a/`) translates quantum
algorithms (Grover search, anyon braids) and the Riemann zeta function into
continuous-time Verilog-A translinear circuits, connecting algebraic number theory to
physical simulation.

### Layer 2 — Compilers, Languages, and Formal Proofs

Three Haskell compilers operate here. The **Cobalt compiler** translates Prolog to x86-64
with a Liquid Haskell refinement type bridge. The **Qflow compiler** parses a quantum
dataflow DSL. The **KrausExtractor** builds unitaries from Quipper circuits and extracts
Kraus operators for decoherence modeling.

The **Algol 68 transformer** (`src/a68/`, 22 files) implements a complete decoder
Transformer in a language from 1968 — embedding, attention with RoPE, MLP, normalization,
Jacobian, inference, and serialization — making it among the few known implementations of
a large language model in Algol 68.

The **ASP engine** provides a complete Answer Set Programming solver in Go. The
**kernel-language compiler** targets NVIDIA Ampere using a language derived from BLISS,
PL/M, and CORAL 66.

### Layer 3 — Finance, Runtime, and Execution Infrastructure

The polyglot finance layer implements a production **Sovereign Treasury Engine**: COBOL
for ACH origination and WORM bridge, RPGLE for end-of-day batch processing (IBM i style),
PL/I for treasury ledger and functor pipeline, Scala/ZIO for concurrent coordination,
and C# for the managed gateway. These are not toy implementations — the COBOL programs
follow enterprise naming conventions (ACHRTRN, COBILT-ACH-TREASURY, LEDGWYCB); the RPGLE
programs implement IBM-style agent transaction scheduling.

The **Sovereign Ledger** in Go provides the runtime substrate: 2,170+ LOC, thread-safe,
hash-chained, Merkle-backed, query/snapshot/replication APIs.

### Layer 4 — AI Execution, Self-Improvement, and Semantic Computing

Three distinct AI execution models sit at the top:

**Apple Metal inference stack** (`metal/`, `apple-metal-inference/`): Llama-like 3B INT4
decoder Transformer in Metal Shading Language with 15 dedicated kernels, targeting Apple
Silicon without external dependencies.

**VSM-2500** (`vsm2500/`): A binary-semantic virtual machine that explicitly rejects
floating-point tensors and softmax selection. All computation is over 128-bit Virtual
Parameter objects with deterministic binary semantic algebra. The H100 SASS bridge
(`vsm2500_h100_sass_bridge.cu`) maps VSM opcodes onto Hopper SM90 CUDA.

**Dream-RSI** (`dream_rsi/`): An independent reconstruction of recursive self-improvement
using a discovered-tree-based policy system where incumbent-safe candidate selection
ensures replay score cannot decrease on the same historical world pool.

---

## Technically Distinctive Elements

### The .continuity/ AI-Assisted Code Continuity System

The repository contains a `.continuity/` directory operating as an AI-assisted architectural
memory layer: `decisions.json` (design decisions linked to commit hashes with
question/answer/tags/relationships schema), `decisions.jsonl` (append-only log),
`code-links.json` (cross-file dependency graph), `drift-snapshot.json` (detected
divergences between code and recorded decisions), `audit-cache.json`. Decisions are
auto-drafted from commits and carry relationship fields (supersedes, relatedTo, causes).
This preserves architectural intent across human and AI contributor boundaries.

### The GFLOP→NAND Extractor

The `gfnand/` crate (Rust, within `he-binary-functor/`) extracts NAND-gate counts and
arithmetic intensity metrics from floating-point GFLOP specifications, carrying 31 Kani
bounded model-checking harnesses — proofs of NAND truth-table correctness, half-adder
behavior, arithmetic intensity bounds, and refinement preservation.

### Cross-Domain Projection Matrix

The NAND(a,b) operation appears as a Rust function (gfnand/), a Verilog NAND gate
(semiconductor/), a Lean 4 proof term (formal/lean/), a RISC-V `andn` instruction
(fibonacci-braid-ledger/), and a BQN `¬∧` combinator (he-binary-functor/bqn/). New
language projections must satisfy the refinement preservation predicate.

### Multi-Prover Adversarial Verification

`formal/token-verification/` encodes the same token model theorem in Lean 4, Coq,
Isabelle, Agda, and F* simultaneously, with a `recursive/` subdirectory containing a
counterproof in all five, plus `self_critique.md`, `failed_claims.md`, and
`recursive_counterproof.md`. This is adversarial formal verification against the
project's own claims.

### Fibonacci Braid Ledger as Cryptographic Primitive

The Fibonacci Braid Ledger treats Fibonacci numbers as the generator of a non-Abelian
braid group: state transition S_{n+1} = T(sigma_i, S_n) applies a braid word operator to
a Fibonacci-encoded state, producing a seal chain Seal_n = H(Seal_{n-1} || C(S_n)).
Implemented in lock-free C++, x86-64 assembly, RV64I assembly, BQN, and Liquid Haskell,
with a rigorous research paper (~8,500 words) and binary `.bten` test fixtures.

---

## License and Governance

Dual-licensed under **AGPL-3.0** and **FSL-1.1** (Functional Source License), with an
additional "Sovereign Leviathan Node License" overlay in Lean 4, Haskell, and Python
source headers. The Bel Esprit D'Accord Irrevocable Trust (EIN 42-697643) holds copyright.
The project operates under a stated research philosophy of full determinism, bounded
execution, append-only audit trails, and formal proofs where possible — properties
architecturally enforced rather than aspirationally described.
