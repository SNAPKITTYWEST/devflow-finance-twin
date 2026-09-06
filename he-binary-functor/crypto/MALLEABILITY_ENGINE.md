# Malleability Engine

A **malleability engine** that, given a fixed-length digest (e.g. 256-bit hash), produces a deterministic family of points on the critical line that are related to the nontrivial zeros of the Riemann zeta function zeta(s).

```
digest --phi--> (n, t_n, rho_n, rho_bar_n, orbit)
```

The mapping phi is pure, total, and collision-resistant under the assumption that the underlying digest is (the construction does not claim to prove RH).

## Mathematical objects

Nontrivial zeros lie in the critical strip. Under RH they are of the form:

```
rho_n = 1/2 + i t_n , t_n > 0
rho_bar_n = 1/2 - i t_n
```

where (t_n) is the strictly increasing sequence of positive imaginary parts.

The engine never asserts RH; it only uses tabulated ordinates that have been independently verified to be zeros to high precision, and treats them as fixed public constants.

## Deterministic mapping phi

Let D be a digest interpreted as an unsigned integer in [0, 2^256).

1. **Index selection**: `n = 1 + (D mod N)`
2. **Ordinate**: `t = T[n]` (precomputed imaginary part)
3. **Critical-line points**: `rho = 1/2 + i t`, `rho_bar = 1/2 - i t`
4. **Malleable orbit**: `orbit(D) = { rho, rho_bar, 1/2 + i(t + delta_k), 1/2 - i(t + delta_k) | k = 0..K-1 }`
5. **Seal**: `seal(D) = FNV-1a-64(encode(n) || encode(t) || encode(orbit))`

## Invariants

- phi is a pure function: identical digest -> identical (n, t, rho, orbit, seal).
- n in {1 .. N}.
- t = T[n] is taken from a fixed, versioned table.
- All indices are bounds-checked.
- No floating-point non-determinism: ordinates stored as fixed-point or rational approximations.

## Relation to prior layers

The seal may be used as a ledger entry digest (cf. Fibonacci Braid Ledger) or as a seed for the NAND# array processor. The engine itself reduces only to table lookup, modular arithmetic and a fixed hash -- no external entropy.
