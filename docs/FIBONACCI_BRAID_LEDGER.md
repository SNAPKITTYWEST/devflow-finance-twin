<p align="center">
  <img src="./docs/assets/hero-05.gif" width="420">
  <img src="./docs/assets/hero-04.png" width="420">
</p>

<p align="center">
  <strong>Recursive Cryptographic Primitives from Logic, State, and Braid Algebra</strong>
</p>

<p align="center">
  EXPERIMENTAL RESEARCH
</p>

---

## Core Model

```
RELATION
    |
    v
CONSTRAINT
    |
    v
STATE
    |
    v
RECURSIVE STEP
    |
    v
INVARIANT
    |
    v
SEAL
```

---

## About

Fibonacci Braid Ledger is an experimental research framework for
investigating cryptographic constructions based on deterministic
recursive state transitions.

The system explores the reduction of relational logic into a compact
recursive-step computational model.

---

## Architecture

```
FIBONACCI STATE F_n = F_{n-1} + F_{n-2}
       |
       v
MATRIX ENCODING  2x4 Matrix [FIB(n) -> binary]
       |
       v
BRAID WORD  W = [sigma]
       |
  +----+----+
  |    |    |
  v    v    v
BIFURCATION -> ADVERSARIAL -> CRYSTALLIZATION
  |    |    |
  +----+----+
       |
       v
MALBOLGE LAYER  X_{n+1} = transform(X_n, STATE_n)
       |
       v
RECURSIVE STEP CORE  S_{n+1} = T(sigma_i, S_n)
       |
       v
INVARIANT  valid_state /\ chain_valid /\ bounds
       |
       v
SEAL  Seal_n = H(Seal_{n-1} || C(S_n))
       |
       v
NEXT RECURSIVE STATE
```

---

## Research Lineage

```
Prolog
    |
    v
Logic Reduction
    |
    v
Datalog
    |
    v
Mercury
    |
    v
MUMPS Mini-Syntax
    |
    v
Constraint Systems
    |
    v
Recursive-Step Programming
    |
    v
Cryptographic State Machines
```

---

## Braid Algebra Formalization

### State Definition

```
B_0 : State -- initial, refined {s | Valid(s) /\ s = zero}
```

### Transition Function

```
T : Generator x State -> State
T(sigma_i, B_n) = B_{n+1}
```

### Example Word

```
W = [sigma_1, sigma_2^{-1}, sigma_1, sigma_3]
```

### Computation Trace

```
B_0
  | sigma_1
  v {B_1 | B_1 = T(sigma_1, B_0) /\ Invariant(B_1)}
B_1
  | sigma_2^{-1}
  v
B_2
  | sigma_1
  v
B_3
  | sigma_3
  v
B_4
```

### Refinement Type

```
fn braid_step(s: &State, g: Generator<8>) -> State {
    transition(s, &Word::singleton(g)) // s + contrib(g)
}

braid_step : (g:Generator<S> x s:{s:State|Valid(s)}) ->
             {s':State | s' = s + contrib(g) /\ Valid(s')}
```

---

## Bifurcation and Convergence

### Bifurcation

```
         +-- S_{n+1,A} where P_A(S)
S_n -- split |
         +-- S_{n+1,B} where P_B(S)
```

```
BIFURCATE(S_n, constraint)
  A = T(sigma_A, S_n)
  B = T(sigma_B, S_n)
  require C(A) == C(B) or Join(A,B) defined
```

### Convergence

```
A --+
    +-- CONVERGENCE -> S_{n+1} = join(A,B)
B --+
```

```
join : (a:{s|P_A(s)} x b:{s|P_B(s)}) -> {s| Q(s)} where Q => P
```

---

## Adversarial Transform and Crystallization

```
X_n : ExecutionImage
X_{n+1} = transform(X_n, STATE_n)

where transform : Image x State -> Image
and transform is deliberately hostile:
  not idempotent, not monotonic
```

```
BRAID STATE B_n
     |
     v
TRANSFORM(X_n, B_n) -> X_{n+1}
     |
     v
CRYSTALLIZATION C(X_{n+1})
     |
     v
INVARIANT CHECK
```

### Transient States

```
TRANSIENT S~
  +-- ~Invariant(S~) -> discard
  v
C(S~) = canonicalize(S~)  // sort, normalize, reduce braid word

C(S) = { s:State | Invariant(s) /\ s = canonical_form(S~) }
```

### Sealing

```
Seal_n = H(Seal_{n-1} || C(S_n))
```

---

## Verification Protocol

```
STATE_n
  |
  v
BRAID STEP sigma_i
  |
  v
+----------------+
| ADVERSARY      | mutate / split / inject malformed W
| X = Adv(S_{n+1}) |
+-------+--------+
        v
  CONSTRAINT CHECK
   / \
FAIL   PASS
 |      |
REJECT  CRYSTALLIZE -> SEAL
```

---

## Formal Specification

```
A |- P_BRBC(S_0, W=[sigma_1..sigma_k]):
  S_0 <- init() {s|Valid(s)}
  Seal_0 <- H(0 || C(S_0))
  for i=1..k:
    B = BraidStep(sigma_i, S_{i-1})
    X = AdversarialTransform(B)  // identity in defender mode
    if ~Invariant(X): REJECT
    S_i = Crystallize(X)  // Option, None -> REJECT
    Seal_i = H(Seal_{i-1} || S_i)  // FNV-1a 64 or SHA-256
  return Seal_k
```

### Invariant Preservation

```
valid_state(S_n) /\ valid_transition(S_n, S_{n+1}) -> valid_state(S_{n+1})
chain_valid: forall i>0. S_i.prev_hash = hash(S_{i-1})
```

---

## Recursive-Step Language

```
S: STATE    -- establish state, refined {s|Valid}
B: sigma_1  -- braid transition, refined {g|ValidGen}
B: sigma_2^{-1}
A: STATE    -- adversarial transform, may be identity
C: STATE    -- crystallization C(S)
I: STATE    -- invariant check
K: STATE    -- bind K = H(K_prev || C(S))
R: STATE    -- recurse
```

---

## Candidate Primitives

| ID | Primitive | Status |
|---|---|---|
| P01 | Recursive State Hash | Experimental |
| P02 | Braid State Permutation | Experimental |
| P03 | Constraint Commitment | Experimental |
| P04 | Recursive MAC | Experimental |
| P05 | State KDF | Experimental |
| P06 | Transition PRF | Experimental |
| P07 | Fibonacci Diffusion | Experimental |
| P08 | NAND Recursive Primitive | Experimental |
| P09 | Quantum Shadow Primitive | Experimental |
| P10 | Ledger Seal Primitive | Experimental |

---

## Interactive Instrument

**[Open Quantum Shadow Ledger](./frontend/quantum_shadow_ledger.html)**

6-stage pipeline: Fibonacci -> Braid -> Array -> NAND -> Crypto -> Seal

---

## Visual Research Archive

<p align="center">
  <img src="./docs/assets/hero-01.mp4" width="280" poster="./docs/assets/hero-02.jpg">
  <img src="./docs/assets/hero-02.jpg" width="280">
  <img src="./docs/assets/hero-03.jpg" width="280">
</p>

<p align="center">
  <img src="./docs/assets/hero-04.png" width="280">
  <img src="./docs/assets/hero-05.gif" width="280">
</p>

---

## Demonstration

### Part 1
[Video Demo Part 1](./docs/assets/demo-part1.mp4) -- Core braid state transitions and seal generation

### Part 2
[Video Demo Part 2](./docs/assets/demo-part2.mp4) -- Adversarial transform and crystallization

### Part 3
[Video Demo Part 3](./docs/assets/demo-part3.mp4) -- NAND recursive primitive

### Part 4
[Video Demo Part 4](./docs/assets/demo-part4.mp4) -- Full ledger verification

---

## Verification

- **Invariant Preservation**: valid_state(S_n) /\ valid_transition(S_n,S_{n+1}) -> valid_state(S_{n+1})
- **Chain Validity**: forall i>0. S_i.prev_hash = hash(S_{i-1})
- **Seal Integrity**: FNV-1a-64 structural seal, any byte flip fails verification
- **Formal Proofs**: Lean 4 deed files with 0 sorry policy

---

## Cryptanalysis

- **Attack Model**: Chosen-message, chosen-braid, adaptive adversary
- **Differential**: Compute delta-W, measure delta-Seal
- **Algebraic**: Solve braid word problem from seal
- **Constraint**: Analyze invariant satisfaction frequency
- **Bounded**: Kani proof harnesses for 31 bounded instances

---

## Documentation

- [User Guide](./USER.md)
- [About Us](./ABOUT.md)
- [Ledger](./LEDGER.md)
- [Math Dictionary](./MATH_DICTIONARY.md)
- [Inverted Monorepo](./INVERTED_MONOREPO.md)
- [Security Policy](./SECURITY.md)
- [Changelog](./CHANGELOG.md)

---

## License

Dual-licensed: AGPL-3.0 (WASM/PL-I/COBOL/C/NASM/Chisel/Scala) and FSL-1.1 (all others).

```
Copyright (c) 2026 SnapKittyWest.
Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
EIN 42-697643
```
