# FIBONACCI BRAID LEDGER
## Dense Deterministic Append-Only State Machine

### I. ARCHITECTURE

**Core Principle**: Ledger indexed by Fibonacci position. Each entry contains a braid word and produces a deterministic state transition. Integrity chain binds all entries.

**Invariant**:
```
s_n = s_0 XOR H(w_0) XOR H(w_1) XOR ... XOR H(w_n)
e_n = H(e_{n-1} || entry[n])
```

### II. DATA REPRESENTATION

**Entry** (24 bytes packed):
- u16 n: Fibonacci index
- u16 prev: previous state
- u8 op: 0=append 1=inverse 2=reduce
- u8 len: word length 0..MAX_WORD
- i8 word[8]: generators +k/-k, k in [1..MAX_STRAND-1]
- u16 state: resulting state
- u32 seal: integrity hash

**Generator Encoding**: +k = positive crossing, -k = inverse crossing, k in {1,2,3}

### III. FIBONACCI

Precomputed u16 table, F(0)..F(20). F(20)=6765 fits u16. No runtime arithmetic.

### IV. BRAID WORDS

Free reduction: cancel adjacent inverses (sigma_i sigma_i^-1 -> epsilon). Non-commuting generators left as-is. Stored words are syntactically normalized.

### V. SEAL CHAIN

FNV-1a style mix: `s = (s << 5) XOR byte`. Each seal depends on previous seal + all entry fields. Modification of any entry invalidates all subsequent seals.

### VI. STATE TRANSITION

`s' = transit(s, word)` where `transit p (g:gs) = transit (p*3 + |g|) gs`

### VII. VERIFICATION

- Seal chain: recompute each seal from previous, compare
- State invariant: recompute each state from accumulated XOR, compare
- Word validity: all generators in valid range
- Chain continuity: each entry's prev matches previous entry's state

### VIII. LIMITATIONS

- Max 48 entries (F(0)..F(47) with u64 index)
- Non-cryptographic hash (FNV-1a) — not for adversarial environments
- In-memory only — no disk persistence
- Single-threaded — no concurrent appends
- Braid reduction is syntactic only, not canonical form
