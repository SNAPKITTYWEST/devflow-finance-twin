# Repository Organization Manifest

Generated: 2026-09-10

---

## Actions Performed

| # | Original Path | New Path | Classification | Reason | References Updated | Status |
|---|---------------|----------|----------------|--------|-------------------|--------|
| 1 | `formal-verification-paper/main.aux` | (removed from git) | GENERATED ARTIFACT | LaTeX build output, reproducible from main.tex | N/A | DONE |
| 2 | `formal-verification-paper/main.log` | (removed from git) | GENERATED ARTIFACT | LaTeX build output, reproducible from main.tex | N/A | DONE |
| 3 | `formal-verification-paper/main.out` | (removed from git) | GENERATED ARTIFACT | LaTeX build output, reproducible from main.tex | N/A | DONE |
| 4 | `assembly-120-strict-model/isa-examples/arith.isa` | (removed) | EXACT DUPLICATE | Identical to `isa-jvm/examples/arith.isa` (MD5 match) | N/A — no references | DONE |
| 5 | `assembly-120-strict-model/isa-examples/channel.isa` | (removed) | EXACT DUPLICATE | Identical to `isa-jvm/examples/channel.isa` (MD5 match) | N/A — no references | DONE |
| 6 | `assembly-120-strict-model/isa-examples/memory.isa` | (removed) | EXACT DUPLICATE | Identical to `isa-jvm/examples/memory.isa` (MD5 match) | N/A — no references | DONE |
| 7 | `assembly-120-strict-model/isa.wat` | (removed) | EXACT DUPLICATE | Identical to `wasm/isa.wat` (MD5 match) | N/A — no references | DONE |
| 8 | `assembly-120-strict-model/treasury_worm_ipl.asm` | (removed) | EXACT DUPLICATE | Identical to `x86_64/treasury_worm_ipl.asm` (MD5 match) | N/A — no references | DONE |
| 9 | `assembly-120-strict-model/fib_braid.asm` | (removed) | EXACT DUPLICATE | Identical to `he-binary-functor/fibonacci-braid-ledger/fib_braid.asm` (MD5 match) | N/A — no references | DONE |
| 10 | `funnelc.py` | `scripts/funnelc.py` | SCRIPT | Standalone compiler with zero references. Belongs with other scripts. | None required (zero imports/refs) | DONE |
| 11 | `Sovereign_Harmony.pdf` | `docs/Sovereign_Harmony.pdf` | DOCUMENTATION | 790KB PDF in root. Belongs with docs. | `CHANGELOG.md` updated | DONE |
| 12 | `.gitignore` | `.gitignore` (updated) | CONFIGURATION | Added missing patterns: `target/`, LaTeX artifacts | N/A | DONE |
| 13 | `formal-verification-paper/.gitignore` | (created) | CONFIGURATION | Local gitignore for LaTeX build artifacts | N/A | DONE |

## Files Preserved (no action needed)

| File | Classification | Reason for Preservation |
|------|----------------|------------------------|
| `assembly-120-strict-model/bit_pattern_kernel_avx2.asm` | CORE SOURCE | Unique AVX2 kernel (27 KB), no duplicate |
| `assembly-120-strict-model/cbmc_binary_semantics.rs` | CORE SOURCE | Standalone version, differs from `rust/fsl/src/` module |
| `assembly-120-strict-model/fibonacci_braid_x86.asm` | CORE SOURCE | Related but different hash from other braid asm |
| `assembly-120-strict-model/.gitkeep` | CONFIGURATION | Directory intent marker |
| `wasm/*.wasm` (6 files) | GENERATED ARTIFACT | Intentionally tracked — used by Dockerfile, avoids build dep |
| `formal-verification-paper/main.pdf` | DOCUMENTATION | Intentionally tracked research output |
| `formal-verification-paper/theorem_ledger.rs` | RESEARCH | Code artifact associated with paper |
| `cobalt-compiler/LiquidOps/Kernel.hs` | CORE SOURCE | Educational version, registered in cobalt.cabal |
| `cobalt-compiler/Language/Fixpoint/LiquidOps/Kernel.hs` | CORE SOURCE | LH bridge version, behind flag in cobalt.cabal |

## Uncommitted Changes (pre-existing, not part of this audit)

| File | Change | Notes |
|------|--------|-------|
| `README.md` | Expanded from ~100 to ~750 lines | Comprehensive documentation overhaul |
| `rust/fsl/src/lib.rs` | Removed `pub mod datalog;` and `pub mod jitter_machine;` | Removing references to nonexistent modules |
