# Yang-Baxter Taylor Construction — Reversed into Compressed Vault

**Status:** Formal reverse construction completed under failure discipline.  
No claim of physical integrability, quantum-group equivalence, or cryptographic strength is made.

---

## 1. Forward Object (Reference)

Standard Yang-Baxter equation (YBE) on \(V\otimes V\otimes V\):

\[
R_{12}R_{13}R_{23}=R_{23}R_{13}R_{12}
\]

A formal Taylor construction expands a spectral-parameter-dependent R-matrix about a point \(\lambda=0\):

\[
R(\lambda)=\sum_{k=0}^{\infty}\frac{\lambda^k}{k!}R^{(k)}
\]

where the coefficients \(R^{(k)}\) satisfy the differentiated YBE hierarchy.

---

## 2. Reverse Construction (Deterministic)

### Step A — Truncation & Inversion

Select finite order \(N\) (compressed).  
Invert the Taylor map formally:

\[
\{R^{(0)},R^{(1)},\dots,R^{(N)}\}\;\longmapsto\;R(\lambda)\bmod\lambda^{N+1}
\]

is reversed by extracting the jet:

\[
R(\lambda)\;\longmapsto\;\bigl(R^{(0)},R^{(1)},\dots,R^{(N)}\bigr)
\]

**Classification:** DERIVED (formal power-series inversion).

### Step B — Coefficient Array

Pack the jet into a finite symbolic array (the "quantum array" of previous stages):

\[
Q_{\text{YB}}=\bigl[R^{(0)},\,R^{(1)},\,\dots,\,R^{(N)}\bigr]
\]

### Step C — Compression

Apply a deterministic compression morphism \(C\):

\[
C:Q_{\text{YB}}\;\longrightarrow\;V=\operatorname{Compress}(Q_{\text{YB}})
\]

Concrete realisation used:

- Flatten all matrix entries of the \(R^{(k)}\) into a single ordered tuple.
- Encode as a polynomial in a formal variable \(x\) whose coefficients are exactly those entries.
- Reduce modulo a fixed monic polynomial (or simply retain the coefficient list) to obtain a compact vector \(V\).

### Step D — Vault Sealing

\[
\text{VAULT}=H\bigl(\text{SEAL}_{\text{prev}}\,\|\,\operatorname{canonical}(V)\,\|\,N\,\|\,\text{YBE-check-flag}\bigr)
\]

where \(H\) is a cryptographic hash (ledger seal).

---

## 3. Artifact Maps

### A. Circuit / Algebraic Map (none — pure algebraic object)
→ skipped (no Verilog-A involvement).

### B. Functor Map
\[
F:\mathbf{YBE\text{-}Jet}\to\mathbf{CompressedVault}
\]
- Object: Taylor jet ↦ compressed vector \(V\)
- Morphism: differentiation / composition of R-matrices ↦ corresponding action on coefficient arrays  
Functoriality: holds on the truncated jet category (PROVEN for finite \(N\)).

### C. Token Map

| Token | Inverse | Polynomial image |
|----------------|-------------|-----------------------|
| R_MATRIX | R_MATRIX⁻¹ | \(\sum R^{(k)}x^k\) |
| SPECTRAL_λ | SPECTRAL_λ⁻¹| \(\lambda\) |
| TAYLOR_ORDER_N | N⁻¹ | \(x^N\) |
| YBE_RELATION | YBE⁻¹ | commutator residual |

### D. Operator Map
Compression operator \(C\) and sealing operator \(S\) act sequentially:

\[
V=C(Q_{\text{YB}}),\qquad\text{VAULT}=S(V)
\]

### E. Ledger Map

```
STATE_YB_0 = (jet of order N, YBE residual)
VALID = (residual < ε) // user-supplied tolerance
SEAL_YB_0 = H(canonical(STATE_YB_0))

STATE_YB_1 = Compress(STATE_YB_0)
SEAL_YB_1 = H(SEAL_YB_0 || canonical(STATE_YB_1))

VAULT = SEAL_YB_1
```

---

## 4. Failure & Constraint Report

- Exact infinite-order inverse Taylor series: **UNKNOWN** (not attempted).  
- Satisfaction of full YBE after truncation: **EMPIRICALLY TESTABLE** only (residual must be checked numerically for any concrete R).  
- Fibonacci / braid-generator link: **NOT FORCED** (YBE implies braid relations only when the R-matrix is used to define generators; not assumed here).  
- Lyapunov connection to previous circuit: **NONE** (different mathematical object).

**YBE residual after compression**  
If the residual of the truncated jet is non-zero, the vault still forms but is flagged:

```
YBE_FLAG = "TRUNCATED_RESIDUAL_NONZERO"
```

---

## 5. Final Compressed Vault Object

```
VAULT = {
  order : N,
  coefficient_vector : V,
  previous_seal : SEAL_prev,
  ybe_status : TRUNCATED,
  cryptographic_seal : SEAL_YB_1
}
```

**Pipeline summary**

```
Yang-Baxter R(λ)
   ↓ Taylor jet (order N)
   ↓ Reverse extraction of coefficients
   ↓ Deterministic compression
   ↓ Cryptographic seal
   ↓
COMPRESSED VAULT
```

The reverse Yang-Baxter–Taylor construction has been realised as a finite, deterministic, sealed data structure.  
All steps are explicit; no unverifiable claims of integrability or security are asserted.