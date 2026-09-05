# Math & Arithmetic Dictionary

A comprehensive reference for all mathematical operations, arithmetic primitives, and formal notation used across the Devflow Finance Twin modules.

---

## 1. Boolean Algebra (NAND# / gfnand)

| Symbol | Operation | Definition | Module |
|--------|-----------|------------|--------|
| `NAND(a,b)` | Not-And | `NOT(AND(a,b))` | `gfnand/src/nand_lowering.rs` |
| `NOT(a)` | Negation | `NAND(a, a)` | `gfnand/src/nand_lowering.rs` |
| `AND(a,b)` | Conjunction | `NOT(NAND(a,b))` | `gfnand/src/nand_lowering.rs` |
| `OR(a,b)` | Disjunction | `NAND(NOT(a), NOT(b))` | `gfnand/src/nand_lowering.rs` |
| `XOR(a,b)` | Exclusive-Or | `NAND(NAND(a, NAND(a,b)), NAND(b, NAND(a,b)))` | `gfnand/src/nand_lowering.rs` |

**Gate counts (n-bit operations):**
- Half adder: 5 NAND gates → 2n+1 for n-bit ripple carry
- Full adder: 9 NAND gates → 9n-6 for n-bit add (including carry chain)
- n×n multiplier: 9n²-15n+6 NAND gates
- n-bit MAC (multiply-accumulate): 9n²-6n+6 NAND gates

---

## 2. Modular Arithmetic

| Expression | Meaning | Domain | Module |
|------------|---------|--------|--------|
| `x + y (mod 2^32)` | 32-bit modular addition | UInt32 | `tensor-parser/sha256.adb` |
| `x * y (mod 2^32)` | 32-bit modular multiplication | UInt32 | SHA-256 compression |
| `x XOR y` | Bitwise exclusive-or | UInt32 | SHA-256 mixing |
| `ROTR(x, n)` | Circular right rotation | UInt32 | SHA-256 sigma functions |
| `SHR(x, n)` | Logical right shift | UInt32 | SHA-256 sigma functions |
| `SHL(x, n)` | Logical left shift | UInt32 | SHA-256 message schedule |

**SHA-256 sigma functions:**
- `Σ₀(x) = ROTR(2,x) ⊕ ROTR(13,x) ⊕ ROTR(22,x)`
- `Σ₁(x) = ROTR(6,x) ⊕ ROTR(11,x) ⊕ ROTR(25,x)`
- `σ₀(x) = ROTR(7,x) ⊕ ROTR(18,x) ⊕ SHR(3,x)`
- `σ₁(x) = ROTR(17,x) ⊕ ROTR(19,x) ⊕ SHR(10,x)`

**Compression functions:**
- `Ch(x,y,z) = (x ∧ y) ⊕ (¬x ∧ z)`
- `Maj(x,y,z) = (x ∧ y) ⊕ (x ∧ z) ⊕ (y ∧ z)`

---

## 3. FNV-1a Hashing

| Constant | Value | Purpose |
|----------|-------|---------|
| FNV_OFFSET | `0xcbf29ce484222325` | Initial hash basis |
| FNV_PRIME | `0x100000001b3` | Multiplicative constant |

**Algorithm:**
```
hash = FNV_OFFSET
for each byte b:
    hash = hash XOR b
    hash = hash × FNV_PRIME
```

Used in: `block-lace/blocklace_ledger.hpp`, `block-lace/re_invoke.rs`

---

## 4. Fibonacci Numbers

| Notation | Definition | Values |
|----------|------------|--------|
| `F(n)` | Fibonacci sequence | F(0)=0, F(1)=1, F(n)=F(n-1)+F(n-2) |
| `φ` | Golden ratio | (1+√5)/2 ≈ 1.618033988 |
| `φ^n` | Fibonacci anyon Hilbert space dimension | Grows exponentially with strand count |

Used in: `fibonacci-braid-ledger/`, `he-binary-functor/`

---

## 5. Braid Group (Topological Quantum)

| Symbol | Operation | Axiom |
|--------|-----------|-------|
| `σ_i` | Braid generator (strand i over i+1) | — |
| `σ_i σ_{i+1} σ_i` | Left side of Yang-Baxter | = `σ_{i+1} σ_i σ_{i+1}` |
| `τ × τ` | Fibonacci anyon fusion | = `1 + τ` |
| `dim(H_n)` | Hilbert space dimension | = `φ^n` |

Used in: `fibonacci-braid-ledger/`, `he-binary-functor/fibonacci-braid-ledger/`

---

## 6. Fixed-Point Financial Arithmetic

| Notation | Meaning | Precision |
|----------|---------|-----------|
| `1000000000000000000` | Scale factor (10^18) | 18 decimal places |
| `int(amount × 10^18)` | Convert float to fixed-point | 64-bit integer |
| `value / 10^18` | Convert back to decimal | Display only |

Used in: `src/worm.py`, `src/twin.py`

---

## 7. CRC-64 Polynomial

| Constant | Value | Standard |
|----------|-------|----------|
| Polynomial | `0x42F0E1EBA9EA3693` | ISO 3309 |
| Init value | `0xFFFFFFFFFFFFFFFF` | All ones |
| Final XOR | `0xFFFFFFFFFFFFFFFF` | Complement |

Used in: `tensor-parser/crc64.ads`, `tensor-parser/crc64.adb`

---

## 8. HMAC-SHA-256

**Construction:**
```
HMAC(K, M) = H((K' ⊕ opad) ∥ H((K' ⊕ ipad) ∥ M))
```

Where:
- `K' = K` if |K| ≤ 64, else `H(K)` padded to 64 bytes
- `ipad = 0x36` repeated 64 times
- `opad = 0x5C` repeated 64 times
- `H` = SHA-256

Used in: `tensor-parser/hmac_sha256.ads`, `tensor-parser/hmac_sha256.adb`

---

## 9. Verilog-A Analog Computing

| Symbol | Physical Meaning | Formula |
|--------|-----------------|---------|
| `V_T` | Thermal voltage | `kT/q ≈ 25.85 mV` at 300K |
| `I_D` | Drain current (subthreshold) | `I_S · exp(V_GS / nV_T)` |
| `I_c1 · I_c2 = I_c3 · I_c4` | Translinear identity | Product of currents in loop |
| `g_m` | Transconductance | `∂I_D / ∂V_GS` |
| `f_T` | Transit frequency | `g_m / (2π·C_gs)` |
| `PHI_HALF` | φ/2 | `0.8090169943749474` |

Used in: `verilog-a/trig_braid_processor.va`, `verilog-a/trig_processor.va`, `verilog-a/braid_trig_processor.va`

---

## 10. Refinement Type Notation

| Symbol | Meaning | Example |
|--------|---------|---------|
| `{v:T \| P(v)}` | Refined type | `{v:Int \| v ≥ 0 ∧ v < 16}` |
| `∀x. P(x)` | Universal quantifier | `∀s. s.reg[0] = 0` |
| `∃x. P(x)` | Existential quantifier | `∃m. H(m) = h` |
| `P ⟹ Q` | Implication | `ValidProg(p) ⟹ Preserves(c,p)` |
| `∧` | Logical AND | `v = 0 ∨ v = 1` |
| `∨` | Logical OR | — |
| `⊕` | XOR / exclusive-or | Bitwise operation |
| `⊓` | Meet (greatest lower bound) | Lattice theory |
| `⊔` | Join (least upper bound) | Lattice theory |
| `mod` | Modular reduction | `x mod 2^32` |

Used in: `gfnand/src/refinement.rs`, `nand-architecture/refinement/`, `block-lace/BlocklaceRefinements.hs`

---

## 11. Kani Verification Predicates

| Predicate | Meaning | Bounded By |
|-----------|---------|------------|
| `kani::any()` | Nondeterministic value | Type bounds |
| `kani::assume(cond)` | Path constraint | Exploration limit |
| `assert!(cond)` | Proof obligation | Must hold for all inputs |

Used in: `gfnand/kani/src/verification.rs`

---

## 12. SPARK Ada Contracts

| Contract | Meaning |
|----------|---------|
| `with SPARK_Mode => On` | Enable static verification |
| `Pre => expr` | Precondition |
| `Post => expr` | Postcondition |
| `Global => null` | Pure function, no side effects |
| `Inline` | Inline expansion |
| `pragma Loop_Invariant` | Loop correctness |

Used in: `tensor-parser/sha256.ads`, `tensor-parser/crc64.ads`, `tensor-parser/hmac_sha256.ads`

---

## 13. WORM Merkle Chain

| Operation | Formula |
|-----------|---------|
| Record hash | `SHA-256(prev_hash ‖ timestamp ‖ account_id ‖ data ‖ seq)` |
| Chain validation | `∀i. record[i].prev_hash = SHA-256(record[i-1])` |
| Tamper detection | Any modification breaks `record[i].prev_hash` link |

Used in: `src/worm.py`

---

## 14. GFLOP→NAND Metrics

| Metric | Formula | Description |
|--------|---------|-------------|
| FLOP count | `Σ (2 × M × N × K)` for MatMul | Total floating-point operations |
| NAND node count | `gates_per_op × count` | Total NAND gates |
| NAND depth | `depth_per_op` | Critical path length |
| Arithmetic intensity | `FLOPs / bytes` | Compute-to-memory ratio |
| Memory bytes | `Σ (element_count × dtype_size)` | Total memory footprint |

Used in: `gfnand/src/metrics.rs`
