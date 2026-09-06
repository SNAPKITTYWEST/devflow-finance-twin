# User Guide

## Quick Start

### Prerequisites

- Python 3.11+
- Rust 1.75+ (for GFLOP→NAND)
- Node.js 18+ (for WASM)
- Lean 4 (for formal proofs)

### Installation

```bash
git clone https://github.com/SNAPKITTYWEST/devflow-finance-twin.git
cd devflow-finance-twin
```

### Running the Frontend

```bash
# Open the Quantum Shadow Ledger in your browser
open frontend/quantum_shadow_ledger.html
```

### Running the Python Reference

```bash
# Create an account
python src/cli.py --storage ledger.worm CREATE_ACCOUNT --account_id ACC_001 --balance 1000.0000

# Verify the WORM chain integrity
python src/cli.py --storage ledger.worm VERIFY_HISTORY
```

### Cold Boot Protocol

```bash
# Execute 3-phase cold boot
python -c "from src.cold_boot import cold_boot; cold_boot()"
```

### ICP Anchor (Cross-Chain)

```bash
# Anchor WORM state hash to Internet Computer canister
python -c "from src.icp_anchor import anchor_state; anchor_state('ledger.worm')"
```

### Testing

```bash
# Python baseline (122 tests)
python -m pytest tests/test_stack.py -v

# Lean 4 formal proofs
cd lean && lake build

# Kani bounded proofs
cd he-binary-functor/gfnand/kani && cargo kani
```

### Building WASM Modules

```bash
# Full build
make full

# Or individual layers
make wasm
make native
make asm
```

## Fibonacci Braid Ledger

### Interactive Instrument

The Quantum Shadow Ledger implements a 6-stage computational pipeline:

1. **Fibonacci**: Compute F(n) via closed-form
2. **Braid**: Generate reduced braid word
3. **Array**: Map to 8-element state vector
4. **NAND**: Verify via NAND gate DAG
5. **Crypto**: FNV-1a-64 hash
6. **Ledger**: Append-only seal

### Controls

- **FIB INDEX** (1-20): Select Fibonacci number
- **TAMPER**: Simulate seal corruption
- **NAND**: Toggle NAND visualization
- **QUANTUM**: Quantum shadow display
- **ADVERSARIAL**: Attack surface analysis
- **CTF MODE**: Mathematical challenges

## WASM Modules

| Module | Purpose |
|--------|---------|
| runtime.wasm | Core dispatch, store, alloc |
| isa.wasm | Binary instruction execution |
| worm_frame.wasm | Phase 17 serialization, Merkle |
| ledger_replay.wasm | Ledger verification |
| account_registry.wasm | Account CRUD |
| sha256.wat | Hash engine |

## Cold Boot Protocol

Three phases:

1. **ROM Anchor**: Verify firmware integrity (BLAKE3 root)
2. **Bridge Init**: Establish WORM buffer, storage keys
3. **Treasury Driver**: Enter main loop

## ICP Anchor

Anchors WORM state hash to Internet Computer canister for cross-chain verification.
