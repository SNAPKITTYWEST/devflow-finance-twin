# devflow-finance-twin

> Sovereign BaaS ledger stack — IBM i authoritative core, formal verification harness, quantum circuits, cryptographic primitives, and polyglot proof infrastructure.

## Architecture

```
C# REST API
  └── LedgerGateway / CobolGateway (binary struct marshal → IBM i program call)
        └── COBOL FSL Supervisors (TXN-FSL / ACH-FSL / RTP-FSL / LEDGER-GATEWAY)
              └── RPGLE Programs (POSTTRAN / REVTRAN / ADJTRAN / EOD / TREASURY)
                    └── DB2 for i (authoritative double-entry ledger)
                          └── Formal Verification Layer (Lean4, Coq, Isabelle, F*, Agda)
                                └── Constraint Harness (Runtime verification + proof obligations)
```

---

## Repository Organization

### **Core Financial Infrastructure**

| Directory | Description |
|-----------|-------------|
| `cobol/` | IBM i COBOL FSL supervisors (ACH, RTP, transaction state machines) |
| `rpgle/` | IBM i RPGLE programs (posting engine, EOD, treasury) |
| `csharp/` | C# API layer, gateways, rail adapters (LedgerGateway, CobolGateway) |
| `schema/` | DB2 for i DDL — ledger schema, ACH tables, event sourcing |
| `pli/` | PL/I bridge programs and data structure marshaling |

### **Formal Verification & Proofs**

| Directory | Description |
|-----------|-------------|
| `lean/` | Lean 4 formal proofs (constraint harness, ledger invariants) |
| `lean-proofs/` | Extended Lean proof library |
| `formal-token-verification/` | Multi-prover token verification (Lean, Coq, F*, Isabelle, Agda) |
| `formal-verification-paper/` | Research papers and verification artifacts |
| `linear-algebra-verification/` | Matrix operation proofs (Coq, Isabelle, Lean) |
| `constraint-harness/` | Runtime constraint verification with proof obligations |

### **Quantum Computing**

| Directory | Description |
|-----------|-------------|
| `quantum_computer/` | Full quantum circuit simulator (~1500 LOC across modules) |
| `quantum_computer/core/` | Quantum state, registers, complex numbers, matrix ops |
| `quantum_computer/circuit/` | Circuit representation, DAG, optimizer, scheduler |
| `quantum_computer/algorithms/` | Advanced quantum algorithms (Shor, Grover, VQE, QAOA) |
| `quantum_computer/gates/` | Quantum gate library (Pauli, Hadamard, CNOT, Toffoli, etc.) |
| `quantum_computer/error_correction/` | Surface codes, stabilizer formalism, syndrome extraction |
| `quantum_computer/noise/` | Noise models (depolarizing, amplitude damping, phase flip) |
| `quantum_computer/vm/` | Quantum VM simulator with measurement and state collapse |
| `quantum_computer/tests/` | Comprehensive test suite (test_full.py, test_extended.py) |
| `spiral-detection/` | Quantum spiral detection (Quipper, Silq, SAS, MATLAB) |

### **Assembly & Low-Level Code**

| Directory | Description |
|-----------|-------------|
| `assembly-120-strict-model/` | Assembly/ISA strict model collection |
| `assembly-120-strict-model/bit_pattern_kernel_avx2.asm` | AVX2 SIMD cryptographic kernel |
| `assembly-120-strict-model/fibonacci_braid_x86.asm` | Fibonacci braid ledger (x86-64) |
| `assembly-120-strict-model/treasury_worm_ipl.asm` | Treasury WORM IPL (z/Architecture s390x) |
| `assembly-120-strict-model/isa.wat` | WebAssembly binary ISA execution engine |
| `assembly-120-strict-model/cbmc_binary_semantics.rs` | CBMC GOTO binary semantics (~400 LOC) |
| `x86_64/` | x86-64 assembly (quantum validation, treasury WORM) |
| `ptx/` | CUDA PTX assembly |
| `isa-jvm/` | Hand-rolled ISA with reference interpreter |

### **Cryptographic Primitives & Hardware**

| Directory | Description |
|-----------|-------------|
| `he-binary-functor/` | Homomorphic encryption binary functor framework |
| `he-binary-functor/crypto/` | Cryptographic primitives and malleability engine |
| `he-binary-functor/nand-architecture/` | NAND gate architecture with self-refinement |
| `he-binary-functor/fibonacci-braid-ledger/` | Fibonacci braid ledger (x86, BQN, Liquid Haskell) |
| `he-binary-functor/tensor-parser/` | Tensor parser with cryptographic invertibility |
| `he-binary-functor/verilog-a/` | Analog Verilog-A implementations (Riemann zeta, SPARK) |
| `he-binary-functor/circom/` | Zero-knowledge circuit definitions |
| `he-binary-functor/cuda-q/` | CUDA-Q quantum kernels |
| `chisel/` | Chisel hardware design language implementations |

### **Datalog & Logic Programming**

| Directory | Description |
|-----------|-------------|
| `datalog-engine/` | Datalog storage engine (replaces SQL persistence) |
| `prolog/` | Prolog logic programs and unification |
| `logtalk/` | Object-oriented logic programming extensions |
| `eclipse/` | ECLiPSe constraint logic programming |

### **Array & Tensor Languages**

| Directory | Description |
|-----------|-------------|
| `apl/` | APL implementations (Metatron pipeline, evidence gates) |
| `he-binary-functor/bqn/` | BQN array programming (Fibonacci braid, tensor ops) |
| `he-binary-functor/k/` | K array language implementations |
| `he-binary-functor/uiua/` | Uiua stack-based array language (quantum entanglement) |
| `jitter-machine/` | JIT compiler (BQN, assembly) |

### **Functional Programming & Type Theory**

| Directory | Description |
|-----------|-------------|
| `haskell/` | Haskell implementations (Workerman calculus) |
| `scala/` | Scala implementations |
| `lisp/` | Common Lisp and Scheme implementations |
| `rust/` | Rust implementations (FSL compiler, CBMC semantics) |
| `rust/fsl/` | Formal Specification Language compiler |

### **Verification Tools**

| Directory | Description |
|-----------|-------------|
| `cobalt-compiler/` | Cobalt compiler with Liquid types and physics modules |
| `he-binary-functor/why3/` | Why3 deductive verification |
| `astre-vault/` | ASTRA-VAULT (Unlambda closure + MATLAB, RCC-8 spatial reasoning, OWL semantics) |

### **Frontend & Visualization**

| Directory | Description |
|-----------|-------------|
| `frontend/` | Web frontend (quantum shadow ledger visualization) |
| `wasm/` | WebAssembly modules |

### **Documentation & Examples**

| Directory | Description |
|-----------|-------------|
| `docs/` | Architecture documentation and papers |
| `examples/` | Example programs and use cases |
| `tests/` | Integration tests and test harnesses |

### **Build & Scripts**

| Directory | Description |
|-----------|-------------|
| `scripts/` | Build scripts and automation |
| `src/` | Core source modules (cold boot, ICP anchor, quantum) |
| `assets/` | Static assets and resources |

---

## Key Components

### Quantum Computer (`quantum_computer/`)

Full-featured quantum circuit simulator with:
- **State Management**: Complex quantum states with amplitude/phase
- **Gates**: Complete gate library (Pauli, Hadamard, CNOT, Toffoli, Fredkin, etc.)
- **Algorithms**: Shor's algorithm, Grover's search, VQE, QAOA, quantum annealing
- **Error Correction**: Surface codes, stabilizer formalism, syndrome extraction
- **Noise Models**: Depolarizing, amplitude damping, phase flip, thermal relaxation
- **Optimization**: Circuit optimization, gate fusion, scheduler
- **Serialization**: Circuit export/import (JSON, QASM)

### CBMC Binary Semantics (`assembly-120-strict-model/cbmc_binary_semantics.rs`)

Dense bit-vector and symbolic execution semantics (~400 LOC):
- BitVec representation (concrete + symbolic)
- Byte-addressable memory with endianness
- Binary/unary operator evaluation (bit-precise)
- SSA environment and expression evaluator
- Assertion/assumption lowering to FSL IR

### Constraint Harness (`constraint-harness/`)

Runtime verification with proof obligations:
- Constitution-based constraints
- MXML verification markup
- Runtime audit trail
- Scheduler integration
- Adapter framework for multiple backends

### Fibonacci Braid Ledger (`he-binary-functor/fibonacci-braid-ledger/`)

Bounded machine representation with:
- x86-64 assembly implementation
- BQN array programming version
- Liquid Haskell formal specification
- Braid word reduction
- Ledger state transitions

---

## COBOL Programs

### ACH-FSL
Production ACH batch/entry lifecycle library.  
REXX → COBOL → Logic → DB2 → External ACH Adapter.

### Datalog Storage Engine
Replaces SQL persistence entirely.  
REXX → COBOL → Datalog → DATAWORM.

---

## RPGLE Programs

### EOD (End-of-Day)
Orchestration driver running on IBM i.  
Steps: FinalizePendingJournals → AgeHolds → PostRailSettlements → ReconcileDay

---

## Schema (DB2 for i)

Extended DB2 DDL:

| Table | Purpose |
|-------|---------|
| `LEDGERS` / `JOURNALS` / `JOURNAL_LINES` | Core double-entry ledger |
| `EVENT_LOG` | Replayable event log (binary payload, sequence-keyed) |
| `RAIL_SUBMISSIONS` | ACH / RTP / FedNow / Wire submission tracking |
| `RAIL_NOTIFICATIONS` | Inbound rail notifications (SETTLEMENT / RETURN / ACK) |
| `EOD_RUNS` | End-of-day run log with status + summary |
| `CONCURRENCY_CHECKS` | Harness output (double-entry invariant checks) |

---

## Build & Test

### Quantum Computer
```bash
cd quantum_computer
python -m tests.test_full
python -m tests.test_extended
```

### Constraint Harness
```bash
cd constraint-harness
pytest tests/
```

### FSL Compiler
```bash
cd rust/fsl
cargo build --release
cargo test
```

---

## License

Dual licensed:
- **AGPL-3.0-or-later** for open source use
- **FSL-1.1** (Functional Source License) for production use
- **SNAPKITTY OPAQUE SOURCE LICENSE v1.0** for proprietary components

See `LICENSE-AGPL-3.0`, `LICENSE-FSL-1.1`, and `SNAPKITTY OPAQUE SOURCE LICENSE v1.0`.

---

## Contributors

**Ahmad Ali Parr** (ahmedparr93@gmail.com)
- CBMC binary semantics
- Treasury WORM IPL (z/Architecture)
- Fibonacci braid ledger
- Quantum algorithms
- Formal verification proofs

---

## Security

See `SECURITY.md` for vulnerability reporting.

---

**Repository**: https://github.com/SNAPKITTYWEST/devflow-finance-twin
