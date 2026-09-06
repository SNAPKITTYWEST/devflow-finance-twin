# crypto

**Cryptographic Primitives Research** — Novel cryptographic constructions from the Recursive-Step Logic (RSL) architecture.

## Subdirectories

| Directory | Language | Description |
|-----------|----------|-------------|
| (root) | Mixed | All crypto files at root |

## Files

| File | Language | Description |
|------|----------|-------------|
| `IAMAC.md` | Markdown | Inverted Algebraic MAC (homomorphic) |
| `iamac.rs` | Rust | IAMAC implementation with tests |
| `MALLEABILITY_ENGINE.md` | Markdown | Riemann ζ zeros malleability engine |
| `zeros.rs` | Rust | 50 tabulated ζ zeros |
| `malleability.rs` | Rust | Core malleability mapping |
| `main.rs` | Rust | CLI driver |
| `RSL_ARCHITECTURE.md` | Markdown | 10 candidate primitives overview |
| `TRIGONOMETRIC_QTM.md` | Markdown | Trigonometric Quantum Turing Machine |
| `EVOLUTIONARY_CONVERGENCE_4.md` | Markdown | 5-epoch convergence matrix |
| `kernel.rs` | Rust | Braid state transition kernel |
| `seal_chain.rs` | Rust | WORM seal chain (FNV-1a-64) |
| `convergence.rs` | Rust | Convergence matrix data |
| `YANG_BAXTER_TAYLOR_VAULT.md` | Markdown | Reverse Yang-Baxter Taylor vault |

## RSL Architecture (10 Primitives)

| ID | Primitive | Status |
|----|-----------|--------|
| P01 | Constraint-Satisfaction Hash (CSH-256) | Experimental |
| P02 | Relational State Machine MAC (RSMMAC-256) | Experimental |
| P03 | Datalog-Closure KDF (DCKDF) | Experimental |
| P04 | Braid-Permutation Cipher (BPC-128) | Experimental |
| P05 | Answer-Set Commitment (ASC-256) | Experimental |
| P06 | Recursive Constraint Signature (RCS-256) | Experimental |
| P07 | Fixed-Point Random Source (FPRS-256) | Experimental |
| P08 | Determinism-Preserving AEAD (DPAE-128) | Experimental |
| P09 | Recursive Relation Permutation (RRP-256) | Experimental |
| P10 | Constraint-Binding State Integrity (CBSI-256) | Experimental |

## Key Implementations

| Primitive | File | Language |
|-----------|------|----------|
| IAMAC | `iamac.rs` | Rust |
| Malleability Engine | `malleability.rs`, `zeros.rs` | Rust |
| Braid Kernel | `kernel.rs` | Rust |
| Seal Chain | `seal_chain.rs` | Rust |
| Trig QTM | `TRIGONOMETRIC_QTM.md` | Lean 4 theorem |
| Yang-Baxter Vault | `YANG_BAXTER_TAYLOR_VAULT.md` | Markdown |

## Build & Test

```bash
# Rust crypto
cd crypto && cargo test

# Malleability CLI
cargo run -- 0123456789abcdef...

# Kani (in gfnand/kani)
cargo kani
```

## Key Results

| Primitive | Result |
|-----------|--------|
| IAMAC | Homomorphic: MAC(a)+MAC(b)=MAC(a+b) |
| Malleability | Deterministic ζ-zero mapping from digest |
| Braid Kernel | 7 tests passing (reject/oob, accept, deterministic) |
| Seal Chain | FNV-1a-64, tamper detection |
| Trig QTM | Lean 4 sledgehammer theorem |
| Yang-Baxter | Compressed vault with cryptographic seal |