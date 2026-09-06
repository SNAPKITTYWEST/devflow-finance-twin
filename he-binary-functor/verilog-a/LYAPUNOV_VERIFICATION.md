# Lyapunov Exponent Verification Report

**Target system:** `zeta_unfold_node` (Verilog-A)

## 1. Dynamical System Extraction (PROVEN)

From the supplied module the continuous-time relations are:

\[
\begin{align*}
v &= V(\text{in},\text{out}) \\
f &= \ln\left(\frac{|v|}{2\pi e}+1\right) \\
i &= \frac{d}{dt}\bigl(C_b\, f\, v\bigr) \\
v &= L_b\,\frac{di}{dt} + v\, f
\end{align*}
\]

Rearrangement of the last equation yields the algebraic constraint

\[
v(1-f) = L_b\frac{di}{dt}.
\]

The system is therefore a **nonlinear differential-algebraic equation (DAE)** of index at least 1, containing:

- a logarithmic singularity at \(v=0\),
- explicit time derivatives on both charge-like and flux-like terms,
- state-dependent coefficients.

## 2. Analytical Lyapunov Spectrum

**Result: UNKNOWN / NOT COMPUTABLE IN CLOSED FORM**

- The vector field is non-polynomial and non-Lipschitz at \(v=0\).
- No explicit first-order ODE form \(\dot{\mathbf{x}}=F(\mathbf{x})\) on a smooth manifold is available without regularisation or index reduction.
- Consequently, the Jacobian \(DF\) required for the continuous QR / continuous SVD algorithm cannot be written in closed form.
- No exact Lyapunov exponents (largest or spectrum) can be derived analytically.

**Classification:** Analytical verification = **FAILED**.

## 3. Numerical Verification Protocol (DERIVED)

A practical numerical estimate proceeds as follows:

1. Regularise the logarithm (e.g. \(\ln(\sqrt{v^2+\varepsilon^2}/(2\pi e)+1)\), \(\varepsilon\sim10^{-12}\)).
2. Convert the DAE to an explicit ODE by index reduction or by treating \(i\) and \(v\) as differential states with a small parasitic conductance.
3. Integrate two nearby trajectories \(\mathbf{x}(t)\) and \(\mathbf{x}(t)+\delta_0\) with a stiff solver (e.g. `ode15s` / `CVODE`).
4. Renormalise the separation vector at intervals \(\Delta t\) and accumulate

\[
\lambda_{\max}\approx\frac{1}{T}\sum_{k}\ln\frac{\|\delta_k\|}{\|\delta_0\|}.
\]

5. Repeat for an orthonormal set of perturbations to obtain the full spectrum (Benettin algorithm).

**Expected qualitative behaviour (CONJECTURED from structure):**

- The logarithmic term can produce expansive regions when \(|v|\) is moderate.
- The inductive and capacitive derivative terms introduce energy storage that may stabilise or destabilise depending on parameter values.
- Presence of a singularity at the origin suggests the possibility of finite-time blow-up or discontinuous Lyapunov exponents.

No numerical value is reported here because no concrete initial condition, time horizon, or regularisation parameter was supplied.

## 4. Invariant & Ledger Update

```
LYAPUNOV_STATUS = {
    analytical : FAILED,
    numerical : PROTOCOL_DEFINED,
    value : UNKNOWN,
    fibonacci : FALSE, // still no Fibonacci recurrence
    valid : TRUE // protocol itself is well-defined
}

SEAL_LYAP = H( SEAL_1 || "Lyapunov analytical failure" || protocol_hash )
```

## 5. Summary

| Aspect | Status | Classification |
|-------------------------------|-----------------|------------------|
| Existence of closed-form λ | No | PROVEN |
| Smooth ODE form | Not available | PROVEN |
| Numerical estimation possible | Yes (after regularisation) | DERIVED |
| Concrete numerical values | Not computed | UNKNOWN |
| Chaotic / stable character | Undetermined | CONJECTURED |

**Final statement:**  
Analytical Lyapunov exponents for `zeta_unfold_node` **cannot be verified**.  
A deterministic numerical protocol has been defined and sealed.  
Execution of that protocol requires additional simulation parameters (initial state, tolerance, regularisation, integration interval).