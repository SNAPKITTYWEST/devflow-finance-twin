# RESEARCH PROGRAM: NOVEL CRYPTOGRAPHIC PRIMITIVES FROM RECURSIVE-STEP LOGIC ARCHITECTURE

## EXECUTIVE SUMMARY

This document presents a research portfolio of **10 candidate cryptographic primitives** derived from a unified **recursive-step logic (RSL) architecture** combining relational programming, Datalog-style fixed-point semantics, Mercury-style determinism declarations, MUMPS mini-syntax, and Answer Set Programming (ASP) constraint systems.

**Critical disclaimer**: These are **research candidates**, not production cryptographic primitives. Each construction is specified mathematically and is suitable for independent analysis. None claim proven security until subjected to peer review and cryptanalysis.

**Scope**: The primitives span hash functions, MACs, KDFs, authenticated encryption, signatures, commitments, permutations, and state integrity mechanisms.

---

## PART I: RECURSIVE-STEP LOGIC ARCHITECTURE

### Core Abstraction

The RSL architecture models cryptographic computation as iterated **state transitions constrained by declarative specifications**.

```
STATE_n = (m_n, c_n, a_n, s_n)
  m_n: main data vector
  c_n: constraint register
  a_n: auxiliary state
  s_n: seal/tag

CONSTRAINTS_n (via Datalog rules)
  query(m_n, c_n) :- fact(m_n), rule(...)
  Compute fixed point via iterated SLD resolution

TRANSITION_n (deterministic function)
  STATE_{n+1} = delta(STATE_n, deriv_n)
  delta must be pure, deterministic, total (Mercury-style)

INVARIANT_n (logical assertion)
  Valid(STATE_{n+1}) = AND inv_i(STATE_{n+1})

SEAL_n (cryptographic commitment)
  seal_n = H(STATE_{n+1} || seal_{n-1})
```

### MUMPS Mini-Language Syntax

```
statement ::= S | I | T | K | R | A
  S: STATE define fields
  I: INVARIANT assertions
  T: TRANSITION state update
  K: KEEP looping condition
  R: RULE Datalog derivation
  A: ASSERT output commitment
```

### Unifying Principles

1. **Determinism**: Every transition is pure and deterministic (Mercury-style).
2. **Constraint declarativity**: Rules are expressed declaratively; proof search is implicit.
3. **Fixed-point semantics**: Datalog rules iterate to fixed-point.
4. **State sealing**: Every transition binds to a cryptographic seal.
5. **Invariant enforcement**: Assertions guard every transition.
6. **Termination**: Looping is bounded; execution is finite.

---

## PART II: THE 10 CANDIDATE PRIMITIVES

### PRIMITIVE 1: CONSTRAINT-SATISFACTION HASH (CSH-256)

- **Category**: Cryptographic Hash Function
- **Construction**: Constraint-driven fixed-point iteration
- **Input**: Arbitrary bitstring M
- **Output**: 256-bit digest D
- **Rounds**: 80 (fixed)
- **State**: M_n (256-bit), C_n (64-bit), A_n (128-bit), Seal_n (256-bit)
- **Core**: Datalog fixed-point replaces fixed permutation network
- **Key Insight**: Computation path determined by logical constraint satisfaction
- **Security**: Collision resistance (pending analysis)
- **Quantum**: Likely resistant (no obvious quantum speedup for fixed-point)

### PRIMITIVE 2: RELATIONAL STATE MACHINE MAC (RSMMAC-256)

- **Category**: Message Authentication Code
- **Construction**: State machine with relational state compression
- **Input**: Message M, Key K (256-bit)
- **Output**: 256-bit authentication tag T
- **Rounds**: 128 (fixed)
- **Core**: MAC based on relational inference (Datalog-style) + GCD constraint
- **Novelty**: Explicit relation set as compressible state
- **Security**: Existential unforgeability under CMA

### PRIMITIVE 3: DATALOG-CLOSURE KEY DERIVATION FUNCTION (DCKDF-256/512)

- **Category**: Key Derivation Function
- **Construction**: Transitive closure of relational constraints
- **Input**: Seed X, Context I, Length L
- **Output**: K in {0,1}^L
- **Core**: Compute transitive closure of Datalog rules
- **Novelty**: KDF based on transitive closure rather than HMAC
- **Security**: Pseudorandomness and forward secrecy

### PRIMITIVE 4: BRAID-PERMUTATION CIPHER (BPC-128)

- **Category**: Block cipher / Permutation primitive
- **Construction**: Braid-group word composition as state transition
- **Input**: Plaintext P (128-bit), Round key K_i (256-bit)
- **Output**: Ciphertext C (128-bit)
- **Rounds**: 10 (fixed)
- **Core**: Braid words as round-dependent permutations via group homomorphism
- **Security**: Indistinguishability under CPA

### PRIMITIVE 5: ANSWER-SET COMMITMENT (ASC-256)

- **Category**: Commitment scheme
- **Construction**: Stable models of ASP programs
- **Input**: Message m, Randomness r (256-bit)
- **Output**: Commitment com (256-bit)
- **Core**: Commitment from stable model computation
- **Novelty**: Logic programming as commitment mechanism
- **Security**: Binding + Hiding (pending analysis)

### PRIMITIVE 6: RECURSIVE CONSTRAINT SIGNATURE (RCS-256)

- **Category**: Digital signature scheme
- **Construction**: Constraint propagation and recursive proof
- **Input**: Message m, Private key sk, Public key pk
- **Output**: Signature sigma
- **Core**: Signature as proof of constraint satisfaction
- **Security**: Existential unforgeability under CMA

### PRIMITIVE 7: FIXED-POINT RANDOM SOURCE (FPRS-256)

- **Category**: PRNG / Randomness extractor
- **Construction**: Iterated fixed-point computation
- **Input**: Seed X (256-bit), Length L
- **Output**: Pseudorandom R in {0,1}^(8L)
- **Core**: Set-based state with reachability expansion
- **Security**: Pseudorandomness (next-bit unpredictability)

### PRIMITIVE 8: DETERMINISM-PRESERVING AUTHENTICATED ENCRYPTION (DPAE-128)

- **Category**: AEAD
- **Construction**: Mercury-style determinism declarations + relational state
- **Input**: Plaintext M, Key K (256-bit), Nonce N (128-bit), Associated data A
- **Output**: Ciphertext C + Authentication tag T (128-bit)
- **Core**: Explicit determinism contract + Datalog authentication
- **Security**: IND-CPA + INT-CTXT

### PRIMITIVE 9: RECURSIVE RELATION PERMUTATION (RRP-256)

- **Category**: Permutation primitive
- **Construction**: Relation composition and transitive closure
- **Input**: Data X (256-bit), Rounds r
- **Output**: Permuted data X_r (256-bit)
- **Core**: Transitive closure of relations induces permutation via cycle detection
- **Security**: Pseudorandom permutation

### PRIMITIVE 10: CONSTRAINT-BINDING STATE INTEGRITY (CBSI-256)

- **Category**: Authenticated state mechanism
- **Construction**: Constraint satisfaction with recursive binding
- **Input**: State S, Key K (256-bit), Witness W
- **Output**: Authenticated state container (S, T, W_new)
- **Core**: Integrity via constraint satisfaction + recursive witness accumulation
- **Security**: State integrity + history binding

---

## Cross-Reference to Repository

| Primitive | Repository Location |
|-----------|-------------------|
| CSH-256 | `he-binary-functor/nand-architecture/` |
| RSMMAC-256 | `he-binary-functor/crypto/` |
| DCKDF | `he-binary-functor/crypto/` |
| BPC-128 | `he-binary-functor/fibonacci-braid-ledger/` |
| ASC-256 | `he-binary-functor/crypto/` |
| RCS-256 | `he-binary-functor/nand-architecture/refinement/` |
| FPRS-256 | `he-binary-functor/crypto/` |
| DPAE-128 | `he-binary-functor/crypto/` |
| RRP-256 | `he-binary-functor/nand-architecture/array/` |
| CBSI-256 | `he-binary-functor/block-lace/` |
