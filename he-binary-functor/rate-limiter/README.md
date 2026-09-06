# rate-limiter

**Rate Limiter Kernel** — RISC-V assembly implementation with Liquid Haskell formal verification.

## Files

| File | Language | Description |
|------|----------|-------------|
| `rate_limiter.asm` | RISC-V ASM | Assembly implementation |
| `RateLimiter.hs` | Haskell/Liquid | Refinement type specification |

## Specification

```haskell
{-@ type Rate = {v:Int | v >= 0 && v <= 1000} @-}
{-@ limit :: n:Int -> {v:Rate | v <= n} @-}
limit :: Int -> Int
```

## Build

```bash
# Liquid Haskell
liquid RateLimiter.hs

# RISC-V Assembly
riscv64-unknown-elf-as rate_limiter.asm -o rate_limiter.o
```