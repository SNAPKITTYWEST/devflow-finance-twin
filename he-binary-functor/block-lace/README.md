# block-lace

**Block-Lace Topology** — Topological weaving of block sequences via non-Abelian braid generators with cryptographic sealing.

## Files

| File | Language | Description |
|------|----------|-------------|
| `blocklace_ledger.hpp` | C++ | Lock-free ledger node with FNV-1a-64 |
| `re_invoke.rs` | Rust | Re-invocation with NAND binary emission |
| `BlocklaceRefinements.hs` | Haskell/Liquid | Refinement types for block-lace |

## C++ Ledger Node

```cpp
struct BlocklaceEntry {
    uint64_t block_height;
    uint64_t parent_count;
    uint64_t parent_seals[4];
    uint64_t state_transition_id;
    uint8_t braid_len;
    int8_t braid_word[16];
    uint64_t self_seal;
};
```

- FNV-1a-64 seal computation
- Parent seal chaining (max 4 parents)
- Braid word embedding (max 16 generators)

## Rust Re-invocation

```rust
fn re_invoke_block_lace(
    ledger_entry: &mut LedgerEntry,
    block_word: &[i8],
    prev_seal: u64
) -> Result<u64, LedgerStatus>
```

- State transition via braid word application
- NAND binary emission for verification
- FNV-1a seal update

## Liquid Haskell Refinements

```haskell
type ParentCount = {v:Int | v >= 1 && v <= 4}
type BraidLen = {v:Int | v >= 0 && v <= 16}

validBlocklaceEntry :: BlocklaceEntry -> Bool
```

## Build

```bash
# C++
g++ -std=c++17 blocklace_ledger.hpp -o blocklace

# Rust
rustc re_invoke.rs

# Liquid Haskell
liquid BlocklaceRefinements.hs
```