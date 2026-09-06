# kernel

**State Machine Kernels** — 3 Haskell specs + 3 RISC-V assemblies + C worker implementing recursive-step state machines.

## Files

| File | Language | Description |
|------|----------|-------------|
| `state_machine_1.hs` | Haskell | Spec 1 |
| `state_machine_2.hs` | Haskell | Spec 2 |
| `state_machine_3.hs` | Haskell | Spec 3 |
| `sm1.asm` | RISC-V | Assembly 1 |
| `sm2.asm` | RISC-V | Assembly 2 |
| `sm3.asm` | RISC-V | Assembly 3 |
| `worker.c` | C | C worker implementation |

## Structure

Each kernel implements a deterministic state transition:

```
STATE_{n+1} = T(STATE_n, INPUT_n)
```

With invariants checked at each step.

## Build

```bash
# Haskell
ghc state_machine_*.hs

# RISC-V
riscv64-unknown-elf-as sm*.asm -o sm*.o

# C
gcc worker.c -o worker
```