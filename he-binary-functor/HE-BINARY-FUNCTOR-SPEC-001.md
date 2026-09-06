# BINARY FUNCTOR ARCHITECTURE FOR HOMOMORPHIC ENCRYPTION
## Formal Specification — Recursive Transformation Blocks

**Document ID:** `HE-BINARY-FUNCTOR-SPEC-001`
**Version:** `1.0.0`
**Classification:** Cryptographic Primitive — Deterministic Binary Transformation System
**Scheme Target:** CKKS (Approximate Arithmetic) / BFV (Exact Arithmetic) — Parameterizable
**No Lisp Runtime. No Interpreter. No Hidden State.**

---

## 1. FORMAL BINARY FUNCTOR SPECIFICATION

### 1.1 Binary Domain Definition

```
B = {0, 1} // Base binary domain
Bⁿ = {0, 1}ⁿ // n-bit binary vectors
B* = ⋃ₙ Bⁿ // Variable-length binary sequences
```

### 1.2 Functor Signature

```
F : Bⁿ → Bᵐ × Status
```

Where:
- `n` = input bit-width (explicit, fixed per functor instance)
- `m` = output bit-width (explicit, fixed per functor instance)
- `Status ∈ {OK, INVALID_INPUT, INVALID_PARAM, OVERFLOW, NOISE_EXCEEDED, COMPOSITION_ERROR}`

### 1.3 Functor Structure (Binary Functor Record)

```
struct BinaryFunctor {
    opcode: u16 // Operation identifier
    version: u8 // Schema version
    input_width: u32 // n (bits)
    output_width: u32 // m (bits)
    param_len: u32 // Parameter bit-length
    params: B* // Transformation parameters (fixed per instance)
    child_count: u16 // Number of child blocks (0 = leaf)
    children: BinaryFunctor[] // Child functors (recursive)
    integrity: u64 // Blake3(key || encoded_functor) truncated
}
```

### 1.4 Required Functor Properties

| Property | Requirement |
|----------|-------------|
| **Determinism** | `∀x ∈ Bⁿ: F(x) = F(x)` (identical inputs → identical outputs) |
| **Totality on Valid Domain** | `∀x ∈ ValidDomain(F): F(x).status = OK` |
| **Explicit Failure** | `∀x ∉ ValidDomain(F): F(x).status ≠ OK` |
| **Composition Closure** | `F₁ ∘ F₂` produces a valid `BinaryFunctor` |
| **Identity Existence** | `∃ I: I.input_width = I.output_width ∧ ∀x: I(x) = (x, OK)` |

---

## 2. RECURSIVE TRANSFORMATION BLOCK SPECIFICATION

### 2.1 Block Header (Fixed 32 Bytes)

```
┌─────────────────────────────────────────────────────────────────┐
│                     BLOCK HEADER (32 bytes)                     │
├──────────┬──────────┬──────────┬──────────┬──────────┬──────────┤
│  u16 op  │  u8 ver  │ u8 flags │ u32 in_w │ u32 out_w│ u32 p_len│
├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
│ u16 child│ u16 rsvd │    u64 integrity_check                     │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
```

**Field Definitions:**
- `op`: Operation code (see Section 3)
- `ver`: Schema version (current = 1)
- `flags`: Bit 0 = has_children, Bit 1 = is_leaf, Bit 2 = pure (no side effects), Bits 3-7 = reserved
- `in_w`: Input bit-width (0 = dynamic, determined at composition)
- `out_w`: Output bit-width (0 = dynamic)
- `p_len`: Parameter bit-length (bytes = ceil(p_len/8))
- `child`: Number of child blocks
- `rsvd`: Reserved (must be 0)
- `integrity_check`: BLAKE3(key || header || params || children) truncated to 64 bits

### 2.2 Block Body (Variable)

```
BLOCK = HEADER || PARAMS || CHILDREN
PARAMS = raw bytes (length = ceil(p_len/8))
CHILDREN = concat(encode_block(child_i) for i in 0..child-1)
```

### 2.3 Encoding Rules

1. **Little-endian** for all multi-byte integers
2. **Bit-packed** parameters where applicable (no byte alignment padding within params)
3. **Children concatenated** in composition order (left-to-right = first-to-last applied)
4. **Integrity check** covers: `header (with integrity=0) || params || children`

### 2.4 Valid Block Predicate

```
ValidBlock(b) ≡
  b.header.integrity == ComputeIntegrity(b) ∧
  b.header.child == count(b.children) ∧
  (b.header.flags & 0x01) != 0 ⇔ b.header.child > 0 ∧
  (b.header.flags & 0x02) != 0 ⇔ b.header.child == 0 ∧
  ∀c ∈ b.children: ValidBlock(c)
```

---

## 3. OPCODE DEFINITIONS

### 3.1 Core Arithmetic (CKKS/BFV Common)

| Opcode | Mnemonic | Description | In/Out Width |
|--------|----------|-------------|--------------|
| `0x0001` | `IDENTITY` | Pass-through | n → n |
| `0x0010` | `ADD` | Ciphertext + Ciphertext | 2c → c |
| `0x0011` | `ADD_PLAIN` | Ciphertext + Plaintext | c + p → c |
| `0x0012` | `SUB` | Ciphertext - Ciphertext | 2c → c |
| `0x0020` | `MUL` | Ciphertext × Ciphertext | 2c → c' (degree 2) |
| `0x0021` | `MUL_PLAIN` | Ciphertext × Plaintext | c + p → c |
| `0x0030` | `NEG` | Additive inverse | c → c |

### 3.2 Relinearization & Key Switching

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| `0x0100` | `RELINEARIZE` | Degree-2 → Degree-1 using relin keys |
| `0x0101` | `KEY_SWITCH` | Switch ciphertext between keys |
| `0x0102` | `ROTATE` | Slot rotation (CKKS) / automorphism (BFV) |

### 3.3 Modulus Management

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| `0x0200` | `MOD_SWITCH` | Modulus reduction (qᵢ → qⱼ) |
| `0x0201` | `RESCALE` | CKKS rescaling (divide by Δ, drop modulus) |
| `0x0202` | `MOD_UP` | Modulus raising (for key switching) |

### 3.4 Encoding/Decoding

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| `0x0300` | `ENCODE` | Plaintext → Polynomial (CKKS: complex → R; BFV: int → R) |
| `0x0301` | `DECODE` | Polynomial → Plaintext |
| `0x0302` | `ENCRYPT` | Plaintext + PublicKey → Ciphertext |
| `0x0303` | `DECRYPT` | Ciphertext + SecretKey → Plaintext |

### 3.5 Noise & Error Management

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| `0x0400` | `NOISE_ESTIMATE` | Compute noise bound |
| `0x0401` | `NOISE_ASSERT` | Fail if noise > threshold |
| `0x0402` | `BOOTSTRAP` | Full bootstrapping (recursive) |

### 3.6 Composition & Control

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| `0xF000` | `COMPOSE` | Sequential composition (children) |
| `0xF001` | `PARALLEL` | Parallel composition (children independent) |
| `0xF002` | `CONDITIONAL` | Branch on predicate (child0: pred, child1: then, child2: else) |
| `0xF003` | `ITERATE` | Fixed-count iteration (param = count, child = body) |

---

## 4. BINARY LAYOUT SPECIFICATION

### 4.1 Complete Block Encoding

```
encode_block(F: BinaryFunctor) → B*:
    header = pack(
        F.opcode,       // u16
        F.version,      // u8
        F.flags,        // u8
        F.input_width,  // u32
        F.output_width, // u32
        F.param_len,    // u32
        F.child_count,  // u16
        0               // u16 reserved
    )
    integrity = BLAKE3(KEY || header || F.params || encode_children(F.children))[0:8]
    header[24:32] = integrity
    return header || F.params || concat(encode_block(c) for c in F.children)
```

### 4.2 Parameter Encoding by Opcode

| Opcode | Parameter Structure |
|--------|---------------------|
| `ADD`/`SUB`/`MUL` | None (children provide operands) |
| `ADD_PLAIN`/`MUL_PLAIN` | Plaintext polynomial (N coefficients × log₂(q) bits) |
| `RELINEARIZE` | Relinearization key index (u16) |
| `ROTATE` | Rotation amount (i16) + Galois key index (u16) |
| `MOD_SWITCH` | Target modulus index (u8) |
| `RESCALE` | Scale factor Δ (u64, fixed-point) |
| `ENCODE` | Encoding parameters: scale (u64), slots (u16), batch (u8) |
| `ENCRYPT` | Public key reference (u32) |
| `DECRYPT` | Secret key reference (u32) |
| `NOISE_ASSERT` | Max noise bound (u64, log₂ scale) |
| `ITERATE` | Iteration count (u32) |

### 4.3 Ciphertext Binary Representation

```
Ciphertext = {
    degree: u8       // 1 (normal) or 2 (pre-relin)
    level: u8        // Current modulus chain index
    scale: u64       // CKKS: 2^scale; BFV: 1
    components: u8   // Number of polynomials (2 for degree-1, 3 for degree-2)
    poly[0]: Poly    // c₀
    poly[1]: Poly    // c₁
    poly[2]?: Poly   // c₂ (if degree=2)
}

Poly = {
    N: u16           // Ring dimension (power of 2)
    coeffs: u64[N]   // Coefficients in RNS representation (per modulus)
}
```

### 4.4 Key Material Representation

```
SecretKey = { N: u16, coeffs: u64[N] }                    // Ternary/hamming weight distribution
PublicKey = { pk0: Poly, pk1: Poly }                       // (-(a·s + e), a)
RelinearizationKey = { rlk0: Poly, rlk1: Poly }           // For each decomposition level
GaloisKey = { gk0: Poly, gk1: Poly }                       // Per rotation index
```

---

## 5. MAPPING: LISP HE OPERATIONS → BINARY FUNCTORS

### 5.1 Original Lisp Operations (Recovered Mathematical Semantics)

| Lisp Function | Mathematical Operation | Binary Functor(s) |
|---------------|------------------------|-------------------|
| `he-add` | `ct₁ + ct₂` | `ADD` (leaf) |
| `he-add-plain` | `ct + pt` | `ADD_PLAIN` (leaf, param=pt) |
| `he-mul` | `ct₁ × ct₂` | `MUL` → `RELINEARIZE` → `RESCALE` (composition) |
| `he-mul-plain` | `ct × pt` | `MUL_PLAIN` (leaf, param=pt) |
| `he-rotate` | `σₖ(ct)` | `ROTATE` (leaf, param=k) |
| `he-rescale` | `⌊ct / Δ⌉` | `RESCALE` (leaf, param=Δ) |
| `he-mod-switch` | `ct mod qⱼ` | `MOD_SWITCH` (leaf, param=j) |
| `he-encrypt` | `Enc(pk, pt)` | `ENCODE` → `ENCRYPT` (composition) |
| `he-decrypt` | `Dec(sk, ct)` | `DECRYPT` → `DECODE` (composition) |
| `he-boot` | `Bootstrap(ct)` | `BOOTSTRAP` (recursive block) |

### 5.2 Composition Patterns

**Ciphertext Multiplication (CKKS):**
```
MUL_BLOCK = COMPOSE {
    children: [
        MUL,                          // Degree-2 product
        RELINEARIZE {param: rlk_idx}, // Degree-2 → Degree-1
        RESCALE {param: scale}        // Level--, scale adjust
    ]
}
```

**Ciphertext Addition:**
```
ADD_BLOCK = ADD // Single leaf (no relin/rescale needed)
```

**Rotation + Relinearization (BFV):**
```
ROTATE_BLOCK = COMPOSE {
    children: [
        ROTATE {param: k},
        KEY_SWITCH {param: gk_idx}
    ]
}
```

---

## 6. RECURSIVE EXECUTION MODEL

### 6.1 Execution State

```
struct ExecState {
    memory: B*              // Linear memory arena (pre-allocated)
    mem_ptr: u64            // Current allocation pointer
    key_store: KeyStore     // Immutable key material (read-only)
    modulus_chain: u64[]    // q₀ > q₁ > ... > qₗ
    noise_budget: u64       // Current noise bound (log₂)
    status: Status
}
```

### 6.2 Execution Algorithm

```
execute_block(block: Block, input: B*, state: ExecState) → (B*, Status):
    // 1. DECODE
    header = decode_header(block)
    params = decode_params(block, header)
    children = decode_children(block, header)

    // 2. VALIDATE
    if not ValidBlock(block): return (∅, INVALID_INPUT)
    if input.len != header.in_w and header.in_w != 0: return (∅, INVALID_INPUT)

    // 3. EXECUTE TRANSFORM (leaf) or COMPOSE (internal)
    if header.child == 0: // LEAF
        (output, status) = execute_leaf(header.opcode, input, params, state)
    else: // INTERNAL (COMPOSE/PARALLEL/ITERATE)
        (output, status) = execute_composite(header.opcode, children, input, params, state)

    // 4. VERIFY OUTPUT WIDTH
    if status == OK and header.out_w != 0 and output.len != header.out_w:
        return (∅, INVALID_INPUT)

    return (output, status)
```

---

## 7. ALGEBRAIC INVARIANTS

### 7.1 Identity Laws

```
I = BinaryFunctor{op=IDENTITY, in_w=n, out_w=n, child=0}

∀F: ValidFunctor(F) ∧ F.input_width = n ∧ F.output_width = m:
    compose(I_n, F) ≡ F
    compose(F, I_m) ≡ F
```

### 7.2 Associativity of Composition

```
∀F₁, F₂, F₃: ValidFunctor ∧ Compatible(F₁, F₂) ∧ Compatible(F₂, F₃):
    compose(compose(F₁, F₂), F₃) ≡ compose(F₁, compose(F₂, F₃))
```

### 7.3 Homomorphic Correctness (CKKS)

For all `x ∈ ℂ^(N/2)`, `F` composed of `{ADD, MUL, ROTATE, RESCALE, CONJUGATE}`:

```
Let Enc = ENCODE ∘ ENCRYPT
Let Dec = DECRYPT ∘ DECODE
Let Eval(F) = binary_functor_to_circuit(F)

Dec(Eval(F)(Enc(x))) ≈ F(x) + ε
where |ε| < 2^(-scale) × noise_factor(F, params)
```

### 7.4 Homomorphic Correctness (BFV)

For all `m ∈ R_t`, `F` composed of `{ADD, MUL, ROTATE}`:

```
Dec(Eval(F)(Enc(m))) = F(m) (exact, if noise < q/2t)
```

---

## 8. CRYPTOGRAPHIC CORRECTNESS CONDITIONS

### 8.1 Parameter Constraints (CKKS)

| Parameter | Constraint | Rationale |
|-----------|------------|-----------|
| `N` | Power of 2, 2¹⁰ ≤ N ≤ 2¹⁶ | Ring dimension |
| `q = ∏ qᵢ` | q₀ > q₁ > ... > qₗ, each qᵢ ≡ 1 (mod 2N) | RNS-friendly primes |
| `Δ` | Δ < qₗ / 2 | Scale fits in lowest modulus |
| `σ` | σ = 3.2 (typical) | Gaussian error distribution |
| `h` | h ≤ N/2 | Hamming weight of secret key |
| `L` | L ≤ 10 (typical) | Modulus chain depth |

---

## 9. SERIALIZATION / DESERIALIZATION RULES

### 9.1 Block Serialization (Canonical)

```
serialize(F: BinaryFunctor) → bytes:
    return encode_block(F) // As defined in Section 4.1
```

### 9.2 Block Deserialization

```
deserialize(data: bytes) → (BinaryFunctor, bytes_remaining):
    header = unpack(data[0:32])
    if not verify_integrity(header, data): raise IntegrityError
    params = data[32 : 32 + ceil(header.p_len/8)]
    offset = 32 + ceil(header.p_len/8)
    children = []
    for i in 0..header.child_count-1:
        child, offset = deserialize(data[offset:])
        children.append(child)
    return BinaryFunctor{...header, params, children}, data[offset:]
```

---

## 10. VALIDATION RULES

### 10.1 Static Validation (Pre-Execution)

```
StaticValidate(F):
    1. ValidBlock(F)                    // Structural integrity
    2. F.input_width > 0 ∨ F.child > 0 // Determinable width
    3. F.output_width > 0 ∨ F.child > 0
    4. ∀c ∈ F.children: StaticValidate(c) // Recursive
    5. OpcodeValid(F.opcode)           // Known opcode
    6. ParamLenMatches(F.opcode, F.param_len) // Param size correct
    7. ChildArityMatches(F.opcode, F.child_count)
    8. NoCycles(F)                     // DAG check
```

---

## 11. TEST VECTORS

### 11.1 Identity Functor

```
Input: 0x01 0x00 0x03 0x00 0x00 0x00 0x20 0x00 0x00 0x00 0x20 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
Params: (empty)
Input Data: 0xDE 0xAD 0xBE 0xEF (32 bits)
Expected Output: 0xDE 0xAD 0xBE 0xEF (32 bits)
Status: OK
```

### 11.2 CKKS Addition

```
F = ADD {in_w=2048, out_w=1024, child=0}
Input: ct1 || ct2 (each: degree=1, level=5, N=4096, scale=2^40)
Expected: ct_sum (degree=1, level=5, scale=2^40)
Status: OK
```

### 11.3 CKKS Multiplication Chain

```
F = COMPOSE { MUL, RELINEARIZE {rlk_idx=0}, RESCALE {scale=2^40} }
Input: ct1 || ct2 (level=5)
Status: OK
```

---

## 12. MIGRATION MAP

| Category | Original (Lisp) | Binary Functor Architecture | Status |
|----------|-----------------|----------------------------|--------|
| **Data Representation** | Cons cells, vectors | Flat binary buffers (B*), explicit widths | **Transformed** |
| **Function Application** | `(func arg1 arg2)` | `execute_block(F, input, state)` | **Transformed** |
| **Composition** | `(compose f g)` | `COMPOSE` block with children | **Transformed** |
| **Macros** | `defmacro`, `macrolet` | **Eliminated** | **Removed** |
| **Dynamic Typing** | Runtime type tags | Static widths in block headers | **Removed** |
| **Garbage Collection** | Automatic | Explicit memory arena | **Transformed** |
| **Error Handling** | Conditions | Explicit `Status` return values | **Transformed** |
| **REPL/Interpreter** | Interactive eval | **Eliminated** | **Removed** |
| **Polynomial Arithmetic** | Custom Lisp bignum | RNS representation, fixed-width u64 | **Preserved** |
| **NTT/FFT** | Recursive Lisp functions | Iterative in-place NTT | **Preserved** |
| **Noise Tracking** | Global variables | Explicit `noise_budget` in `ExecState` | **Transformed** |

---

**END OF SPECIFICATION**
