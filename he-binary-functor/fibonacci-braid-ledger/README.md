# fibonacci-braid-ledger

**Core FBL Research** — The Fibonacci Braid Ledger is the central experimental research framework investigating cryptographic constructions from braid algebra, array languages, and recursive state transitions.

## Subdirectories

| Directory | Language | Description |
|-----------|----------|-------------|
| [asm_x86/](asm_x86/) | x86-64 ASM | Assembly implementations (fib_braid_ledger.asm, assembly.asm) |
| [bqn/](bqn/) | BQN | Array algebra: fibonacci.bqn, braid.bqn, ledger.bqn, tests.bqn, ledger_full.bqn |
| [cpp/](cpp/) | C++ | Lock-free ledger: fib_braid_ledger.hpp, fbl_ledger.hpp, test_fib_braid_ledger.cpp, main.cpp |
| [test_fixtures/](test_fixtures/) | Binary | 6 BTEN test vectors: corrupted_seal, inconsistent_bytecount, misalignment, payload_truncation, offset_overflow, invalid_rank |

## Key Files at Root

| File | Language | Description |
|------|----------|-------------|
| `FBL_RESEARCH_PAPER.md` | Markdown | ~8500 word research paper |
| `LiquidHaskell.hs` | Haskell | Refinement type specs |
| `LiquidHaskell_full.hs` | Haskell | Full refinement specs |
| `fib_braid_ledger.c` | C | C implementation |
| `fib_braid_ledger.h` | C | C header |

## Pipeline

```
Fibonacci F(n) → Braid Word W = [σ] → Array State S ∈ ℤ⁸ → NAND DAG → FNV-1a Seal → Ledger
```

## Build

```bash
# C++
cd cpp && g++ -std=c++17 -O3 main.cpp -o fbl

# BQN
# Run in BQN REPL: fibonacci.bqn, braid.bqn, ledger.bqn

# x86-64 ASM
cd asm_x86 && nasm -f elf64 assembly.asm && ld assembly.o -o assembly
```

## Research Paper

See `FBL_RESEARCH_PAPER.md` for the complete ~8500 word paper covering:
- Braid group algebra and Fibonacci anyons
- Array state transitions via BQN
- NAND gate compilation
- Cryptographic sealing
- Experimental results