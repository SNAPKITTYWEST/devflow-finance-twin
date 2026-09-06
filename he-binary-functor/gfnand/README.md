# gfnand

**GFLOP→NAND Extractor** — Extracts floating-point operations from tensor descriptors, lowers them to NAND gate DAGs, and verifies the compilation with Kani bounded model checking.

## Subdirectories

| Directory | Language | Description |
|-----------|----------|-------------|
| [src/](src/) | Rust | Core pipeline: parser, IR, nand_lowering, metrics, refinement |
| [kani/](kani/) | Rust/Kani | 31 bounded verification harnesses |
| [bqn/](bqn/) | BQN | Workload analysis (workload.bqn) |

## Source Files

| File | Description |
|------|-------------|
| `src/parser.rs` | Tensor descriptor parsing, dtype handling, operator analysis |
| `src/ir.rs` | Intermediate representation (IR) with graph nodes |
| `src/nand_lowering.rs` | NAND DAG construction, gate library (add, mul, mac) |
| `src/metrics.rs` | FLOP/NAND conversion metrics, arithmetic intensity |
| `src/refinement.rs` | Refinement types for NAND, pointer arithmetic |

## Pipeline

```
Tensor Descriptors → Parser → IR Graph → NAND Lowering → Gate DAG → Metrics
                                    ↓
                              Kani Verification (31 proofs)
```

## Kani Proofs (31 total)

| Proof | Description |
|-------|-------------|
| `nand_truth_table` | NAND gate truth table |
| `half_adder_correctness` | Half adder from NAND |
| `arithmetic_intensity_non_zero` | Intensity > 0 |
| `nand_half_adder_refined` | Refined NAND half adder |
| `array_unrolling_bounds` | Affine bound escape check |
| `refined_nand_preservation` | Refinement type preservation |

## Build & Test

```bash
# Build
cd src && cargo build

# Kani verification
cd kani && cargo kani

# BQN workload
# Run in BQN: workload.bqn
```

## Key Metrics

| Operation | NAND Gates | Depth |
|-----------|------------|-------|
| n-bit ADD | 9n - 6 | 3n + 2 |
| n×n MUL | 9n² - 15n + 6 | 6n - 4 |
| n-bit MAC | 9n² - 6n + 6 | 6n + 2 |