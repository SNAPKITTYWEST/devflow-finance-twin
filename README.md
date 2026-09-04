# Devflow Finance Twin

[![License: FSL-1.1](https://img.shields.io/badge/License-FSL--1.1-blue.svg)](LICENSE-FSL-1.1)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-green.svg)](LICENSE-AGPL-3.0)
[![Lean 4](https://img.shields.io/badge/Lean-4-orange.svg)](lean/)
[![WebAssembly](https://img.shields.io/badge/WebAssembly-black.svg)](wasm/)
[![Ada](https://img.shields.io/badge/Ada-2012-purple.svg)](ada/)
[![Zig](https://img.shields.io/badge/Zig-0.13-orange.svg)](src/native/)
[![Haskell](https://img.shields.io/badge/Haskell-9.6-teal.svg)](haskell/)
[![CUDA](https://img.shields.io/badge/CUDA-12.0-brightgreen.svg)](ptx/)
[![x86_64](https://img.shields.io/badge/x86__64-Assembly-red.svg)](x86_64/)
[![PL/I](https://img.shields.io/badge/PL%2FI-Mainframe-blue.svg)](pli/)
[![COBOL](https://img.shields.io/badge/COBOL-Mainframe-green.svg)](cobol/)
[![Scala](https://img.shields.io/badge/Scala-3.3-red.svg)](scala/)
[![Chisel](https://img.shields.io/badge/Chisel-Hardware-orange.svg)](chisel/)

Deterministic financial digital twin with WORM storage, cryptographic audit, quantum isolation, and sovereign-grade native execution.

A ledger that does not trust its current state — it reconstructs it from provable history. The runtime executes in WebAssembly, not Python.

## Architecture

### WASM Runtime Layer (AGPL-3.0)
| Component | Source | Description |
|-----------|--------|-------------|
| **WASM Runtime** | `wasm/runtime.wat` | Core dispatch, store, alloc |
| **Binary ISA** | `wasm/isa.wat` | Binary instruction execution |
| **WORM Frame** | `wasm/worm_frame.wat` | Phase 17 serialization, Merkle accumulator, log clearing |
| **Ledger Replay** | `wasm/ledger_replay.wat` | Ledger verification |
| **Account Registry** | `wasm/account_registry.wat` | Account CRUD |
| **SHA-256** | `wasm/sha256.wat` | Hash engine |

### Sovereign Treasury Engine (DEED-089)
| Component | Source | License | Language |
|-----------|--------|---------|----------|
| **PL/I Ledger** | `pli/treasury_ledger.pli` | AGPL-3.0 | PL/I |
| **PL/I Functor** | `pli/functor_worm.pli` | AGPL-3.0 | PL/I |
| **PL/I Records** | `pli/treasury_records.pli` | AGPL-3.0 | PL/I |
| **COBOL Bridge** | `cobol/worm_bridge.cob` | AGPL-3.0 | COBOL |
| **C WORM Commit** | `src/native/worm_commit.c` | AGPL-3.0 | C |
| **C WORM Header** | `src/native/worm_block.h` | AGPL-3.0 | C |
| **NASM Serialization** | `x86_64/treasury_serialization.nasm` | AGPL-3.0 | NASM |
| **Chisel Accelerator** | `chisel/WormHardwareAccelerator.scala` | AGPL-3.0 | Chisel |
| **Scala Pure** | `scala/SovereignTreasuryPipeline.scala` | AGPL-3.0 | Scala |
| **Scala ZIO** | `scala/SovereignTreasuryZIO.scala` | AGPL-3.0 | Scala |

### Formal Verification & Native (FSL-1.1)
| Component | Source | License | Language |
|-----------|--------|---------|----------|
| **Lean 4 Proofs** | `lean/` (12 deed files) | FSL-1.1 | Lean 4 |
| **Ada Firmware** | `ada/` | FSL-1.1 | Ada 2012 |
| **Native Loader** | `ada/loader.adb` + `src/native/wasm_loader.zig` | FSL-1.1 | Ada + Zig |
| **Haskell ISA** | `haskell/CliIsa.hs` | FSL-1.1 | Haskell |
| **PTX Kernels** | `ptx/` | FSL-1.1 | CUDA/PTX |
| **x86_64 ASM** | `x86_64/quantum_validation.s` | FSL-1.1 | GAS |
| **TypeScript** | `src/loader.ts` (legacy) | FSL-1.1 | TypeScript |

## Quick Start

```bash
# Full build (all layers)
make full

# Or build individual layers:
make wasm              # WASM modules via Node.js + wabt.js
make native            # C + NASM compilation
make asm               # x86_64 assembly
make zig-loader        # Ada+Zig native loader (requires Zig + GNAT)
make scala-pipeline    # Scala pure + ZIO pipeline (requires sbt)
make chisel            # Chisel hardware generation (requires sbt)

# Run Python baseline tests
make test
```

## Python Legacy (Reference Only)

```bash
# Legacy Python reference implementation (preserved for behavioral verification)
python src/cli.py --storage ledger.worm CREATE_ACCOUNT --account_id ACC_001 --balance 1000.0000
python src/cli.py --storage ledger.worm VERIFY_HISTORY
```

## Testing

```bash
# Python baseline (3/3 tests pass)
python -m pytest tests/test_stack.py -v
```

Tests cover:
- Deterministic replay & account balances
- Adversarial WORM tampering detection (hash mismatch)
- Quantum adapter isolation

## Sovereign Deeds (Lean 4 Formal Verification)

| Deed | Description | Sorries |
|------|-------------|---------|
| DEED-071 | EnochianEngineRoot — Glyphs, Phases, Aethyrs, Watchtowers | 0 |
| DEED-072 | EnochianEngineExecution — Instruction semantics, phase execution | 0 |
| DEED-073 | MalbolgeProcessorRoot — Ternary processor, trytes, invariants | 0 |
| DEED-074 | MalbolgePTXKernel — RTX 3080 PTX assembly | 0 |
| DEED-075 | EnochianMalbolgeIntegration — Call9/Call16 integration | 0 |
| DEED-076 | BifrostCapabilityExchange — Capability system, handshake | 0 |
| DEED-077 | SHREWDWeightLoader — Neural network weights, inference | 0 |
| DEED-078 | BorrowchainStorageEngine — Blockchain storage | 0 |
| DEED-079 | FirmwareCreationEngine — BIOS/UEFI firmware | 0 |
| DEED-080 | EnochianZeroSorryCore — All sorries closed, unified state | 0 |
| DEED-087 | WORM Frame Serialization, Merkle Accumulator, Log Clearing | 0 |
| DEED-088 | Native WASM Loader — Ada+Zig, replaces TypeScript | 0 |
| DEED-089 | Sovereign Treasury Engine — PL/I, COBOL, C, NASM, Chisel, Scala full stack | 0 |

## Threat Model

- **WORM & Merkle Chain**: Every record contains `prev_hash` = SHA-256(previous record). Tampering breaks chain validation.
- **WASM Sandboxing**: Runtime executes in WebAssembly linear memory sandbox, no system access.
- **Fixed-Point Arithmetic**: 18-decimal fixed-point for financial calculations, no floating-point drift.
- **Quantum Isolation**: Quantum layer is sandboxed; outputs are suggestions pending deterministic approval.
- **Lean 4 Proofs**: 12 deed files, 0 sorry policy, formal verification of core invariants.

## Layer Wiring

```text
            ┌─────────────────────────────────────────────┐
            │          Scala + ZIO Pipeline                │
            │  (effectful, resource-safe, streaming)       │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │        Scala Pure Pipeline                   │
            │  (functor-driven, deterministic serialize)   │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │     C WORM Commit (worm_commit.c)           │
            │  (SHA-256, append-only write, fsync)         │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │  NASM Serialization Bridge                   │
            │  (fixed-offset byte shifting, FFI dispatch)  │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │  Chisel Hardware Accelerator                 │
            │  (WORM buffer, crypto fold, AXI interface)   │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │  PL/I → COBOL Bridge                         │
            │  (mainframe serialization, WORKING-STORAGE)  │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │  WASM Modules (6 modules, 2906-604 bytes)   │
            │  (runtime, ISA, worm_frame, ledger, acct)    │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │  Ada + Zig Native Loader                     │
            │  (state machine, validation, memory mgmt)    │
            └──────────────────┬──────────────────────────┘
                               │
            ┌──────────────────▼──────────────────────────┐
            │  x86-64 / CUDA Hardware                      │
            │  (RTX 3080 kernels, quantum validation)      │
            └─────────────────────────────────────────────┘
```

## Project Structure

```
devflow-finance-twin/
├── lean/                          # Lean 4 formal verification (FSL-1.1)
│   ├── EnochianEngineRoot.lean
│   ├── EnochianEngineExecution.lean
│   ├── MalbolgeProcessorRoot.lean
│   ├── MalbolgePTXKernel.lean
│   ├── EnochianMalbolgeIntegration.lean
│   ├── BifrostCapabilityExchange.lean
│   ├── SHREWDWeightLoader.lean
│   ├── BorrowchainStorageEngine.lean
│   ├── FirmwareCreationEngine.lean
│   └── ZeroSorryCore.lean
├── wasm/                          # WebAssembly runtime (AGPL-3.0)
│   ├── runtime.wat / runtime.wasm
│   ├── isa.wat / isa.wasm
│   ├── worm_frame.wat / worm_frame.wasm
│   ├── ledger_replay.wat / ledger_replay.wasm
│   ├── account_registry.wat / account_registry.wasm
│   └── sha256.wat / sha256.wasm
├── pli/                           # PL/I Treasury Engine (AGPL-3.0)
│   ├── treasury_ledger.pli
│   ├── functor_worm.pli
│   └── treasury_records.pli
├── cobol/                         # COBOL WORM Bridge (AGPL-3.0)
│   └── worm_bridge.cob
├── chisel/                        # Chisel Hardware Accelerator (AGPL-3.0)
│   └── WormHardwareAccelerator.scala
├── scala/                         # Scala Pipeline (AGPL-3.0)
│   ├── SovereignTreasuryPipeline.scala
│   ├── SovereignTreasuryZIO.scala
│   └── build.sbt
├── ada/                           # Ada firmware + loader (FSL-1.1)
│   ├── loader.adb / loader.ads
│   ├── unsigned_types.ads
│   ├── cli_isa.adb / cli_isa.ads
│   ├── malbolge_firmware.adb / malbolge_firmware.ads
│   └── enochian_boot.adb / enochian_boot.ads
├── haskell/                       # Haskell ISA (FSL-1.1)
│   └── CliIsa.hs
├── ptx/                           # CUDA/PTX kernels (FSL-1.1)
│   ├── malbolge_step_kernel.cu
│   └── host_launcher.cu
├── x86_64/                        # x86_64 assembly (FSL-1.1)
│   ├── treasury_serialization.nasm
│   └── quantum_validation.s
├── src/                           # Source code
│   ├── native/                    # Native runtime (FSL-1.1 + AGPL-3.0)
│   │   ├── wasm_loader.zig        # Zig WASM runtime layer (FSL-1.1)
│   │   ├── worm_commit.c          # C WORM commit (AGPL-3.0)
│   │   └── worm_block.h           # C WORM header (AGPL-3.0)
│   ├── loader.ts                  # Legacy TypeScript loader (FSL-1.1)
│   ├── cli_isa.ts
│   ├── worm.py                    # Legacy reference
│   ├── twin.py                    # Legacy reference
│   ├── audit.py                   # Legacy reference
│   └── quantum.py                 # Legacy reference
├── tests/
│   └── test_stack.py
├── Makefile                       # Full build system
├── build.zig                      # Zig build script
├── compile_wasm.js                # WASM compilation
├── LICENSE-FSL-1.1
├── LICENSE-AGPL-3.0
└── README.md
```

## License

This repository uses **dual licensing**:

### WebAssembly Files (WAT/WASM)
**GNU Affero General Public License v3.0** ([LICENSE-AGPL-3.0](LICENSE-AGPL-3.0))

Applies to: `wasm/runtime.wat`, `wasm/runtime.wasm`, `wasm/isa.wat`, `wasm/isa.wasm`, `wasm/worm_frame.wat`, `wasm/worm_frame.wasm`, `wasm/ledger_replay.wat`, `wasm/ledger_replay.wasm`, `wasm/account_registry.wat`, `wasm/account_registry.wasm`, `wasm/sha256.wat`, `wasm/sha256.wasm`, `pli/treasury_ledger.pli`, `pli/functor_worm.pli`, `pli/treasury_records.pli`, `cobol/worm_bridge.cob`, `src/native/worm_commit.c`, `src/native/worm_block.h`, `x86_64/treasury_serialization.nasm`, `chisel/WormHardwareAccelerator.scala`, `scala/SovereignTreasuryPipeline.scala`, `scala/SovereignTreasuryZIO.scala`

### All Other Files
**Functional Source License v1.1** ([LICENSE-FSL-1.1](LICENSE-FSL-1.1))

Applies to: Lean 4, Ada, Haskell, PTX/CUDA, TypeScript, Zig, Scala (build.sbt), x86_64 assembly, and all other source files.

Converts to **Apache License 2.0** two (2) years after initial distribution.

### Copyright

```
Copyright (c) 2026 SnapKittyWest.
Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
EIN 42-697643
```

### SPDX Identifiers

```
SPDX-License-Identifier: AGPL-3.0-or-later (WAT/WASM files)
SPDX-License-Identifier: FSL-1.1 (all other files)
```
