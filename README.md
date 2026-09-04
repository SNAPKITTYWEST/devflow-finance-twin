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

Deterministic financial digital twin with WORM storage, cryptographic audit, quantum isolation, and sovereign-grade native execution.

A ledger that does not trust its current state — it reconstructs it from provable history. The runtime executes in WebAssembly, not Python.

## Architecture

| Component | Source | License | Language |
|-----------|--------|---------|----------|
| **WASM Runtime** | `wasm/runtime.wat` | AGPL-3.0 | WebAssembly Text |
| **Binary ISA** | `wasm/isa.wat` | AGPL-3.0 | WebAssembly Text |
| **WORM Frame** | `wasm/worm_frame.wat` | AGPL-3.0 | WebAssembly Text |
| **Ledger Replay** | `wasm/ledger_replay.wat` | AGPL-3.0 | WebAssembly Text |
| **Account Registry** | `wasm/account_registry.wat` | AGPL-3.0 | WebAssembly Text |
| **SHA-256** | `wasm/sha256.wat` | AGPL-3.0 | WebAssembly Text |
| **Lean 4 Proofs** | `lean/` (10 deed files) | FSL-1.1 | Lean 4 |
| **Ada Firmware** | `ada/` | FSL-1.1 | Ada 2012 |
| **Haskell ISA** | `haskell/CliIsa.hs` | FSL-1.1 | Haskell |
| **PTX Kernels** | `ptx/` | FSL-1.1 | CUDA/PTX |
| **Native Loader** | `ada/loader.adb` + `src/native/wasm_loader.zig` | FSL-1.1 | Ada + Zig |
| **x86_64 ASM** | `x86_64/quantum_validation.s` | FSL-1.1 | GAS |

## Quick Start

```bash
# Compile WASM modules
node compile_wasm.js

# Build native Ada+Zig loader (requires Zig + GNAT)
zig build
gnatmake -I ada ada/loader.adb -largs -Llib -lloader

# Run native WASM engine
node -e "
const fs = require('fs');
const wabt = require('wabt');
wabt().then(async w => {
  const mod = w.parseWat('runtime.wat', fs.readFileSync('wasm/runtime.wat','utf8'));
  const {buffer} = mod.toBinary();
  const {instance} = await WebAssembly.instantiate(buffer);
  instance.exports.initialize();
  console.log('Engine initialized, phase:', instance.exports.engine_tick());
});
"
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

## Threat Model

- **WORM & Merkle Chain**: Every record contains `prev_hash` = SHA-256(previous record). Tampering breaks chain validation.
- **WASM Sandboxing**: Runtime executes in WebAssembly linear memory sandbox, no system access.
- **Fixed-Point Arithmetic**: 18-decimal fixed-point for financial calculations, no floating-point drift.
- **Quantum Isolation**: Quantum layer is sandboxed; outputs are suggestions pending deterministic approval.
- **Lean 4 Proofs**: 10 deed files, 0 sorry policy, formal verification of core invariants.

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
│   └── quantum_validation.s
├── src/                           # Source code (FSL-1.1)
│   ├── native/
│   │   └── wasm_loader.zig        # Zig WASM runtime layer
│   ├── loader.ts                  # Legacy TypeScript loader
│   ├── cli_isa.ts
│   ├── worm.py                    # Legacy reference
│   ├── twin.py                    # Legacy reference
│   ├── audit.py                   # Legacy reference
│   └── quantum.py                 # Legacy reference
├── build.zig                      # Zig build script
├── tests/
│   └── test_stack.py
├── LICENSE-FSL-1.1
├── LICENSE-AGPL-3.0
└── compile_wasm.js
```

## License

This repository uses **dual licensing**:

### WebAssembly Files (WAT/WASM)
**GNU Affero General Public License v3.0** ([LICENSE-AGPL-3.0](LICENSE-AGPL-3.0))

Applies to: `wasm/runtime.wat`, `wasm/runtime.wasm`, `wasm/isa.wat`, `wasm/isa.wasm`, `wasm/worm_frame.wat`, `wasm/worm_frame.wasm`, `wasm/ledger_replay.wat`, `wasm/ledger_replay.wasm`, `wasm/account_registry.wat`, `wasm/account_registry.wasm`, `wasm/sha256.wat`, `wasm/sha256.wasm`

### All Other Files
**Functional Source License v1.1** ([LICENSE-FSL-1.1](LICENSE-FSL-1.1))

Applies to: Lean 4, Ada, Haskell, PTX/CUDA, TypeScript, Zig, x86_64 assembly, and all other source files.

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
