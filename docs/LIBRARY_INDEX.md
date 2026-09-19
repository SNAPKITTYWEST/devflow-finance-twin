# Devflow Finance Twin — Library Index

A directory-by-directory technical description of every significant subsystem.

---

## src/

**Primary runtime substrate.** ~60 source files across Python, Go, TypeScript, Pascal,
Ada, x86-64 ASM, CUDA, and Zig. Key files: `twin.py` (top-level finance twin
orchestrator), `cold_boot.py` (3-phase ROM Anchor → Bridge Init → Treasury Driver
cold-boot), `icp_anchor.py` (ICP canister-state anchor with WORM sync), `jax_gpt_model.py`
/ `jax_transformer_harness.py` (JAX transformer reference). The `a68/` subdirectory is
a complete Transformer in Algol 68 (22 files: tensors, attention, MLP, RoPE, normalization,
Jacobian, inference, serialization). `cuda/` has CUDA softmax and vector-add kernels.
`native/` holds Zig WASM loader and C WORM commit primitives. Connects to: wasm/,
sovereign/ledger/, finance/, he-binary-functor/.

---

## finance/

**Polyglot Sovereign Treasury Engine.** Production financial transaction layer in six
languages: COBOL (ACH origination, treasury pipeline, WORM bridge, ledger posting),
RPGLE (EOD batch driver, agent scheduler, wire ledger), PL/I (functor WORM pipeline,
treasury ledger), Scala/ZIO (async treasury coordination), C# (managed ledger gateway
with P/Invoke to native WORM), and a COBOL/DataWorm integration driver. Key programs:
`ACHRTRN.cbl`, `COBILT-DATAWORM.cbl`, `eod-driver.rpgle`, `treasury_ledger.pli`.
Connects to: sovereign/ledger/, wasm/ (sha256), datalog-engine/.

---

## dream_rsi/

**Recursive Self-Improvement Reconstruction.** Python package implementing the Dream-RSI
mechanism: recursive policy improvement through evolving, replayable discovery worlds.
Sub-packages: `core/` (RSIOrchestrator), `discovery/`, `policy/`, `replay/` (online/offline
separation), `simulator/` (SimulatorPool, BoundedSimulator), `evaluation/`
(AlgorithmEvaluator, MathematicalEvaluator, GPUKernelEvaluator), `persistence/` (JSONL
world storage), `tree.py` (serializable discovery tree), `cli.py`. Incumbent-preserving
candidate selection invariant enforced: `candidate_set[0]` is always the deployed policy.
122 tests passing. Connects to: src/ (JAX adapters), benchmarks/rsi_lua/.

---

## sovereign/

**Append-Only Event Ledger (Go).** `sovereign/ledger/` is a production-quality
immutable hash-chained event ledger in Go (2,170+ LOC: event.go, ledger.go,
serialization.go, io.go). Each event carries SHA-256 linkage to the previous event;
Merkle trees support efficient subset verification; API covers query, snapshot, seal,
checkpoint, and replication. Thread-safe via RWMutex. Canonical append-only store for
the entire system. Connects to: finance/, wasm/ (ledger_replay), constraint-harness/.

---

## semiconductor/

**Bottom-up SoC Design Suite.** `mosfet_to_cpu.py` builds a complete computing stack
in 7 levels: MOSFET switch-level (union-find charge propagation) → CMOS gates → gate
primitives → adder → 8-bit ALU → D flip-flop → accumulator CPU. The VHDL layer covers
`sk_transformer.vhd` (Q4.12 fixed-point Transformer, Weyl operator entity with
`WEYL_N = 2*QQ_W`), `sk_logic_cells.vhd` (ASIC cell library), `sk_attention_matvec.vhd`
(AXI4 attention unit). Spec docs cover EDA, RTL, fabrication, and packaging. MATLAB
reference in `transformer_matlab.m`. Connects to: he-binary-functor/ (NAND gates),
formal/ (RTL proofs).

---

## metal/

**SwiftTinyLLM + MetalTransformer — Apple Silicon INT4 Inference.** Swift Package
Manager project with MetalTransformer (library) and SwiftTinyLLM (executable) targets.
MetalTransformer: Llama-like GQA decoder, 32 layers, hidden 3072, 24Q/8KV heads,
INT4 packing at 1.51 GB. `Transformer.metal` covers embedding, RMSNorm, RoPE, INT4
QKV, causal attention, stable softmax, SwiGLU FFN, residuals, final norm, logits.
SwiftTinyLLM provides the byte-level inference frontend (ModelConfig, Tensor, SplitMix64
PRNG, ByteTokenizer, RMSNorm, SwiGLU, RoPE). KV cache is 512 MiB max context. Connects
to: apple-metal-inference/ (extended kernels), formal/ (SHREWDWeightLoader.lean).

---

## apple-metal-inference/

**Extended Metal Kernel Library.** 15 MSL kernel files: `int4_transformer.metal`,
`fused_qkv_tiled.metal`, `gqa_strided.metal`, `attention.metal`, `kv_cache.metal`,
`linear.metal`, `matmul.metal`, `mlp.metal`, `normalization.metal`, `output.metal`,
`residual.metal`, `rope.metal`, `lora_delta.metal`, `decode.metal`, `embedding.metal`.
`Gate/` source adds Python-side routing, entropy, session management, and directive
guard/crypto. `Common/` host interface provides INT4 runtime, KV test harness, block
layout headers, adapter slots. Extends metal/ with LoRA delta, tiled QKV fusion, strided
GQA, and Python gate layer. Connects to: metal/, vsm2500/.

---

## formal/

**Multi-Prover Formal Verification Suite.** Five subdirectories: `lean/` (ZeroSorryCore,
31 sorries closed, VSM binary semantics, Enochian engine, Malbolge, Bifrost, SHREWD
weight loader), `linear-algebra/` (Lean 4 + Coq + Isabelle proofs), `tlm-jxcl/` (token-ledger
model in Dafny, Frama-C, Agda, Coq, F*, Isabelle, Lean with counterexample registry),
`token-verification/` (Lean 4 token spec + `sovereign_attractor.lean` +
`topological_quench.lean`), `verification-paper/` (LaTeX paper "From Keyword Refusal to
Recursive Verification" with proof status lattice). Zero `sorry` policy enforced across
all Lean 4 files. Connects to: wasm/ (sha256 obligations), he-binary-functor/ (NAND
proofs), haskell/ (Isabelle .thy export).

---

## haskell/

**Quantum Haskell Toolchain.** `KrausExtractor.hs` (simulates basis states, extracts Kraus
operators K_m = ⟨m|_A U |0⟩_A, exports JSON and Isabelle .thy), `KrausLH.hs` (Liquid
Haskell refinement types on Kraus operators), `WeakMeasureCircuit.hs`, `PhaseEstimationQuipper.hs`,
`QuipperTcpSenderLH.hs`, `CliIsa.hs`, `X86BatchAssembler.hs`. `fsl/` contains FSL
annotations. Depends on Quipper, hmatrix, LiquidHaskell. No `.cabal` file (gap).
Connects to: cobalt-compiler/ (shared cabal), quantum_computer/, formal/ (Isabelle export).

---

## rust/fsl (cobalt-compiler/src)

**Cobalt Compiler + FSL Bridge.** The Rust crate (`cobalt-compiler/src/`) provides the
FSL (Formal Specification Language) parser, SMT integration, and bounded verification.
The Haskell package (`cobalt.cabal`) is a Prolog-to-x86-64 compiler: `Cobalt/Dense.hs`
and `Cobalt/Trilock.hs` are core functor representations; `MagicCobalt.hs` orchestrates
vault transform + crystal fold + trilock hash + x86-64 emission; `Language/` provides
the Liquid Haskell bridge (flag `lh-bridge`). Connects to: haskell/, he-binary-functor/.

---

## constraint-harness/

**MXML-Based AI Constraint Execution System.** Eight-layer Python package: MXML parser,
Constitution (hard/soft axiom engine, fail-closed), Runtime (explicit state machine),
Scheduler (DAG with bounded concurrency), Commands (Python/PyTorch/model execution),
Audit (FNV-1a-64 + decision seal), Verification, Adapters (ModelAdapter boundary).
Constitutional precedence: FAILED_CLOSED > REVISE > ACCEPT. Phases 1–8 tested; model
adapters are stubs. CLI: `python -m constraint_harness.cli validate examples/basic.mxml`.
Connects to: sovereign/ledger/ (decision sealing), dream_rsi/.

---

## quantum_computer/

**Python Quantum Simulation Stack.** Packages: `core/`, `algorithms/`, `circuit/`,
`error_correction/`, `gates/`, `hardware/`, `noise/`, `serialization/`, `vm/`,
`validation/`. Currently stub/primitive — interfaces defined, minimal implementations.
`vm/` is a quantum virtual machine; `circuit/` handles circuit construction; `gates/`
covers standard and parametrized gates. Connects to: haskell/ (Quipper export),
he-binary-functor/qsharp/, he-binary-functor/cuda-q/.

---

## isa-jvm/

**JVM ISA Layer.** ISA specification and runtime for a JVM-targeted instruction set,
with compiler, runtime, tools, tests, and examples. Bridges high-level JVM semantics
to the NAND# binary ISA. Connects to: cobalt-compiler/ (Prolog compiler), he-binary-functor/.

---

## asp/

**Answer Set Programming Engine (Go).** Complete ASP parser and solver: lexer, recursive
descent parser (rules, directives, aggregates, constraints), AST, semantics/grounding,
constraint propagation, CDNL solver with heuristic and search modules. `souffle_symbolic_agent.py`
in src/ uses this for relational reasoning. Connects to: datalog-engine/, cobalt-compiler/,
constraint-harness/.

---

## cobalt-compiler/

**Prolog-to-x86-64 Haskell Compiler.** Cabal project (cobalt v0.2.0). Core: `Dense.hs`
(dense functor algebra), `Trilock.hs` (trilock hash), `MagicCobalt.hs` (vault transform,
crystal fold, x86-64 emission), `X86BatchAssembler.hs`. Optional `lh-bridge` flag requires
`liquid-fixpoint`. Connects to: haskell/, isa-jvm/ (alternate backend), he-binary-functor/.

---

## qflow/

**Quantum Dataflow DSL (Haskell).** Cabal project (qflow v0.1.0): `Lexer.hs`, `AST.hs`,
`Parser.hs`. Supports typed channel and quantum operation graphs; compiler/ directory
present but IR/codegen not yet implemented (parse stage only). Connects to: haskell/,
quantum_computer/, he-binary-functor/.

---

## vsm2500/

**Virtual Semantic Machine 2500.** Binary-semantic virtual intelligence architecture
rejecting floating-point tensors. Files: `vsm2500_specification.txt` (128-bit Virtual
Parameter objects: VP_ID, VP_DOMAIN, VP_STATE, VP_POLARITY, VP_BINDING, VP_SCOPE,
VP_TRANSITION, VP_FLAGS), `vsm2500_core.sv` (SystemVerilog deterministic register-memory-graph
machine), `vsm2500_h100_sass_bridge.cu` (Hopper SM90 VSM opcodes: BIND, UNBIND, PROVE,
VERIFY, ROUTE, FORK, JOIN, COMPOSE, COMMIT, ROLLBACK), multiple C++ fabric layers.
Every state transition carries proof obligations. Connects to: apple-metal-inference/,
he-binary-functor/, formal/ (vsm_binary_semantics.lean).

---

## retro-gpu/

**Occam CSP-Based GPU Simulator.** Occam-language parallel GPU model with `.occ` process
files for ALU, GlobalMemory, Registers, SharedMemory, Synchronization, Tensor, and Warp.
`src/` contains C Occam runtime; `documentation/` architecture notes; `modula2/`,
`ocaml/`, `sml/` contain translated versions. Models GPU warp-level parallelism using
Occam channels (CSP) rather than CUDA. Connects to: vsm2500/, kernel-language/.

---

## he-binary-functor/

**Ahmad Ali Parr Binary Functor Architecture — Full Deliverables.** 30+ subdirectories
across 20+ languages. Key research lines:
1. **Fibonacci Braid Ledger** — lock-free C++, x86-64 + RV64I ASM, BQN, Liquid Haskell,
   ~8,500-word research paper, 9 `.bten` tensor fixtures
2. **NAND# Architecture** — 16-bit fixed ISA, grammar, array semantics, omega model,
   self-refining bootstrap, FSL annotations, Kani verification
3. **GFLOP→NAND Extractor (gfnand/)** — Rust parser + IR + NAND lowering, 31 Kani harnesses
4. **Verilog-A analog circuits** — Chua circuit, Lyapunov verification, Riemann zeta,
   SPARK-to-Verilog-A, Grover core, many-world anyon braid
5. **block-lace topology** — C++ ledger node, Rust, Liquid Haskell
6. APL, BQN, K, Uiua, Circom ZK, CUDA-Q, Q#, SystemVerilog, XSLT→WASM, SGL
Connects to: every other subsystem through binary semantics grounding.

---

## assembly-120-strict-model/

**x86-64 Assembly Firmware and Neural/Graphics Subsystems.** NASM/YASM files:
`firmware.asm`, `08_neural_accelerator_engine.asm`, `09_graphics.asm`, `11_toolbox.asm`,
`15_scheduler.asm`, `18_dylan_runtime.asm`, `PHASE_2_CPU_EXECUTION_ENGINE.asm`,
`fibonacci_braid_x86.asm`, `bit_pattern_kernel_avx2.asm`. Subdirs: `boot/`, `memory/`,
`monitor/`, `rom/`. Connects to: semiconductor/ (accumulator CPU), he-binary-functor/
(Fibonacci Braid x86).

---

## apple6502x86/

**Multi-Language Cross-Architecture Toolkit.** Implementations across Ada, APL, braid,
Chisel, lisp, prolog, logtalk, futhark, eclipse, mathematics, ptx, topos, and x86_64 —
organized around the 6502/x86 architecture boundary. Cross-compilation and semantic
equivalence reference. Connects to: languages/, he-binary-functor/.

---

## languages/

**Multi-Language Reference Implementations.** Same constructs expressed in ada, apl,
braid, chisel, eclipse, futhark, lisp, logtalk, mathematics/topology, prolog, ptx,
topos, and x86_64. Serves as the cross-language reference matrix for the Inverted
Monorepo's projection semantics. Connects to: he-binary-functor/, cobalt-compiler/,
assembly-120-strict-model/.

---

## wasm/

**WASM Runtime Modules (6 compiled binaries + WAT sources).** `runtime.wasm`,
`isa.wasm`, `worm_frame.wasm`, `ledger_replay.wasm`, `account_registry.wasm`,
`sha256.wasm`. WASM ISA implements the core instruction set; WORM frame provides
append-only write semantics; ledger_replay enables deterministic transaction replay;
account_registry manages account state; sha256 provides cryptographic integrity.
Licensed under standard + `LICENSE-RECURSIVE-INFECTION` (viral copyleft). Connects
to: src/ (wasm_loader.zig, loader.ts), sovereign/ledger/, finance/.

---

## datalog-engine/

**Datalog Reasoning Engine.** Implements a Datalog interpreter/compiler. Used by
the `COBILT-DATAWORM.cbl` COBOL program as a persistent query substrate in place of
SQL, making the financial transaction store queryable via Datalog rules. Connects
to: finance/, asp/, constraint-harness/.

---

## kernel-language/

**BLISS+PL/M+CORAL 66 Kernel Compiler.** Hand-written C compiler for a kernel language
combining BLISS (word-oriented, BIND/OWN/LOCAL), PL/M (BASED variables, AT-addressed,
bit-field extraction), and CORAL 66 (BEGIN/END, PRIORITY/DEADLINE/BOUNDED real-time
annotations, deterministic barrier discipline). Targets NVIDIA Ampere SM_86. Layout:
`include/` (all compiler headers), `src/` (all phases + Chaitin graph-coloring register
allocator), `examples/`, `oberon/` (Oberon-style modules), `runtime/` (CPL bridge + Smalltalk-80
annotation runtime). Connects to: retro-gpu/, vsm2500/.

---

## physics/

**Physics Simulation and Mathematical Research.** `hawking-radiation/`, `julia-rwpt/`
(Julia random-walk path tracer), `jungian-dynamics/`. Supports theoretical underpinning
of the Weyl algebra (semiconductor/) and analog Verilog-A circuits (he-binary-functor/).
Connects to: semiconductor/, he-binary-functor/verilog-a/.

---

## astre-vault/

**Mathematical Vault and Spatial Reasoning.** `astra-vault.unl` (Datalog facts, UNL
format), `astra_math_vault.m` (MATLAB), `astra_owl_solver.py` (OWL ontology solver),
`rcc8_spatial.py` (RCC-8 qualitative spatial reasoning). Provides the ontological and
spatial constraint layer for constraint-harness constitution and VSM-2500 routing.
Connects to: constraint-harness/, asp/.

---

## benchmarks/

**Performance Benchmarks.** `rsi_lua/` — Lua RSI benchmark suite with `results/SUMMARY.md`.
Provides controlled comparisons between Dream-RSI, RecursiveFixedExploration, and
SimpleTESBaseline. Reference measurement platform for the 22,000 LOC engineering
budget claim. Connects to: dream_rsi/.

---

## polyglot/

**Turing-Complete Multi-Language Infrastructure.** Go, Rust, and C implementations of
the same polyglot AST builder with unified error codes and fail-closed validation.
Turing machine implementations: `turing_binary_foundation.go`, `turing_cfg_ptm.go`,
`turing_quipper_jcl.go`. `interop_ffi.h` defines the cross-language FFI boundary.
`asm/` subdirectory for assembly-level polyglot fragments. Connects to: he-binary-functor/,
haskell/ (Quipper), asp/.
