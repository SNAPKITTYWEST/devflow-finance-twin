# Evolutionary Convergence Matrix — Iteration 4

## Matrix

| Iter | Paradigm | Mechanism | Memory / execution bound |
|------|----------|-----------|---------------------------|
| 0 | Prolog | Unification + DFS backtracking | Unbounded heap, trail stack |
| 1 | Custom logic | Directed evaluation graphs | Fixed-width register sets |
| 2 | Datalog | Stratified fixpoint / relation closure | Bounded relational arrays |
| 3 | Mercury / ASP | Mode-directed compile / stable models | Static allocation |
| **4** | **Braid-Crypto Fibration** | **Non-Abelian generators + WORM seals** | **O(1) stack, append-only log** |

## Iteration 4 thesis

ASP-style constraints (integrity, stratified negation bounds) and M/MUMPS-style global arrays converge into a **deterministic transition kernel**:

- Every step is a total function on a fixed-width state word.
- Malformed generators are rejected (no search, no trail).
- Accepted steps update a braid-derived state vector and append a WORM seal.
- No runtime backtracking; no open-world assumption at execution time.

```
generator sigma_i / sigma_i^{-1}
        | (bounds check)
state_vector' = f(state_vector, i, sign)
        |
WormRecord(epoch, mask, payload, prev_seal)
        |
append-only log
```

## Invariants

1. `braid_generator in {+/-1, +/-2, +/-3, +/-4}` or reject.
2. `evaluate_step` is pure given `(state, next_generator)`.
3. Seal chain is FNV-1a-64; any byte flip fails verification.
4. Stack depth of the kernel is O(1); no recursive resolution.
5. Stratification analogue: generators applied in epoch order; no negative cycle across epochs (append-only monotonicity).

## Relation to prior layers

- Generators match the Fibonacci Braid Ledger alphabet (B_5, gens 1..4).
- Seals use the same FNV family as WormDB / ledger.
- Rejection of `|g| not in [1,4]` matches `ValidWord` / ISA bounds.
