# Cryptographic Invertibility Bounds

Reversing a cryptographic hash function like SHA-256 implies finding a pre-image m such that H(m) = h for a given digest h. Mathematically, SHA-256 maps arbitrary-length byte arrays to a fixed 256-bit space via the Merkle-Damgård construction, making the mapping many-to-one and information-theoretically non-invertible. The compression function CF: {0,1}^{512} × {0,1}^{256} → {0,1}^{256} destroys entropy through non-linear bitwise operations and modular additions.

## Modular Arithmetic and Carry Loss

Direct analytical inversion fails primarily due to 32-bit modular addition (add mod 2^{32}). Addition is not a bijective mapping over bit combinations because carry bits discard information regarding which operands produced a specific sum. For instance, given a word sum z = x + y (mod 2^{32}), recovering x and y from z alone yields a search space of 2^{32} possible input pairs, compounding exponentially across the 64 rounds of the SHA-256 compression pipeline.

## Local Message Schedule Inversion

Unlike the non-linear mixing steps, the SHA-256 message schedule expansion transforms 16 initial 32-bit words (W_0 ... W_{15}) into 64 words (W_0 ... W_{63}) via linear bitwise rotations and shifts. Because this expansion relies solely on linear operations, it forms an invertible linear system over F_2. If an attacker or verifier possesses a sufficient subset of intermediate expanded words W_t, the initial 16-word message block can be recovered via Gaussian elimination or back-substitution.

## Automated Constraint Solving and SAT/SMT Reduction

Practical attempts to invert truncated versions of SHA-256 or analyze its pre-image resistance rely on automated theorem provers and Boolean Satisfiability (SAT) solvers. By bit-blasting the SPARK context structures into Logic Gate Networks or And-Inverter Graphs, solvers translate the Ada Unsigned_32 operations into boolean constraints. This allows search algorithms to explore valid pre-image paths under constrained input domains, bypassing brute-force O(2^{256}) complexity where structural weaknesses or reduced-round variants exist.

## Cryptographic One-Way Property

Mathematically reversing a cryptographic hash function like SHA-256 — mapping a 256-bit Digest back to its original arbitrary-length input data — is computationally infeasible. SHA-256 is engineered to be pre-image resistant, meaning that given a target hash h, finding any message m such that SHA-256(m) = h requires O(2^{256}) operations via brute force, far exceeding classical computational limits.

## Information Loss in the Compression Function

The underlying FIPS-180-4 compression function transforms a 512-bit message block and a 256-bit state through 64 rounds of non-linear bitwise operations. Reversing a single round or the full compression cycle fails due to fundamental arithmetic and logical information destruction:

- **Modular Addition (mod 2^{32})**: Standard addition discards carry bits, establishing a many-to-one mapping where multiple input pairs yield identical output sums.
- **Logical Ch and Maj Transformations**: The bitwise choice (Ch) and majority (Maj) operations are non-invertible because individual bit states are conditionally masked, overriding historical bit lineage.
- **Message Schedule Expansion**: The initial 16-word block is expanded into 64 words via linear bit-shifts and XORs. Although linear mixing is theoretically reversible in isolation, its interleaving with non-linear modular additions at every round step prevents analytical back-substitution.

## State Reconstruction vs. Pre-Image Attack

Within the zero-allocation SPARK context (sha256.ads), the Context record manages an intermediate working state (State_Array of 8 words) and an unpadded message buffer (Buf). While full digest reversal remains cryptanalytically intractable, state reconstruction is straightforward if the intermediate Context is captured in memory. Because the state update function is deterministic and pure, execution can be evaluated forward, but not inverted backward without explicit historical checkpoints.

## Formal Verification and Bounded Search Limits

When applying formal verification tools like Kani or SMT solvers to cryptographic primitives, attempting to prove preimage invertibility for arbitrary input spaces causes state-space explosion. However, for restricted input domains (such as structured ledger metadata or short fixed-width prefixes in the Fibonacci Braid Ledger), symbolic execution can verify collision resistance or partial inversion bounds within closed mathematical limits, reinforcing that cryptographic security relies on structural irreversibility rather than heuristic obscurity.
