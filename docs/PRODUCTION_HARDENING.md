# Production Hardening Guide

## Goal

Harden the Jungian Quantum Pipeline into a reproducible, auditable, and production-grade system that runs end-to-end: circuit simulation → Kraus extraction → measurement streaming → classical controller → formal verification.

---

## Primary outputs required

1. Production CI workflow that builds, tests, and verifies artifacts.
2. Hardened Haskell code with static checks and runtime guards.
3. Robust Kraus extraction with verified numeric tolerances and reproducible symbolic output.
4. Reliable IPC with schema validation and backpressure handling.
5. Formal verification artifacts that build deterministically.
6. Release bundle containing artifacts and a reproducible run script.

## Constraints

- All numeric tolerances must be explicit and parameterized.
- No floating-point equality checks; use norms and tolerances.
- All network endpoints must be configurable and authenticated in staging/production.
- Formal proofs must not depend on floating approximations; prefer symbolic definitions or rational approximations.

---

## Stepwise Workplan

### 1. Static analysis and type hardening

- Add and enforce static type checks and contracts for all Haskell modules.
- Add numeric invariants for angles, probabilities, and matrix shapes.
- Add a static verification pass that fails the build on any unchecked partial functions or unsafe casts.

### 2. Runtime guards and defensive coding

- Validate all external inputs: JSON messages, CLI args, environment variables.
- Enforce message size limits and schema validation for incoming IPC.
- Add exponential backoff and queueing for TCP sends and receives.
- Replace any deterministic or insecure RNG with a cryptographically suitable RNG for sampling in tests; allow seeded RNG for reproducible test runs.

### 3. Deterministic extraction and symbolic output

- Ensure Kraus extractor can produce symbolic definitions for parameterized gates when possible.
- When numeric output is necessary, export high-precision complex entries and a rational approximation routine that produces exact rational matrices for formal verification.
- Record the exact seed, environment, and binary hashes used to produce each artifact.

### 4. CI pipeline and reproducible build

CI stages in order:
1. **Checkout** and dependency install.
2. **Static checks**: linter, type checker, static verifier.
3. **Unit tests** for Haskell, Python, and Julia components.
4. **Integration tests**: run the full pipeline in a sandbox network namespace.
5. **Numerical verification**: run Kraus completeness and PSD checks with explicit tolerances.
6. **Formal verification**: build the formal session and fail on any `sorry` or unproven lemma.
7. **Artifact packaging**: produce `kraus_out/`, `beliefs.csv`, `proof_report.txt`, and a signed release bundle.

Ensure the CI environment is hermetic and records exact toolchain versions.

### 5. Testing matrix

- Unit tests for each function with edge cases.
- Property tests for Kraus completeness across random valid `theta` values.
- Regression tests that compare symbolic output to analytic expectations for the controlled-Ry case.
- Integration test that runs N trials and asserts empirical frequencies converge to theoretical probabilities within confidence bounds.

### 6. Security and operational controls

- Require authentication for any network endpoint in staging/production.
- Sanitize and limit any file writes and temporary directories.
- Add rate limits and circuit breakers for IPC to avoid DoS from noisy clients.
- Log sensitive events but never log secrets or private keys.

### 7. Observability and runbook

- Emit structured logs for each stage: simulation, extraction, send, receive, update, verification.
- Export metrics: trials per second, message latency, queue depth, completeness norm, min eigenvalue, formal build time.
- Provide a runbook with steps to reproduce a failing run, how to roll back, and how to re-run formal verification.

### 8. Release and reproducibility

- Produce a signed release bundle containing: source commit hash, built binaries, `kraus_out/`, `kraus_defs.thy`, `beliefs.csv`, and `proof_report.txt`.
- Include a reproducible run script that accepts a seed and produces identical artifacts when run in the same hermetic environment.

---

## Acceptance Criteria

### Functional

- **IPC**: listener receives 100 messages within 30 seconds in a sandbox run and writes `beliefs.csv`.
- **Kraus completeness**: infinity norm of `sum K_m† K_m − I` < `1e-8`.
- **PSD**: minimum eigenvalue of each `K_m† K_m` ≥ `-1e-8`.
- **Formal**: formal session builds with no unproven lemmas.

### Quality

- All static checks pass with zero warnings.
- All unit and integration tests pass.
- CI artifacts are reproducible and signed.

### Security

- No plaintext secrets in logs or artifacts.
- Network endpoints require authentication in staging/production.

---

## CI Workflow Template

```yaml
name: CI Pipeline

on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          # Haskell: ghcup install ghc 9.4; cabal update
          # Python: pip install numpy scipy
          # Julia: julia --project -e 'using Pkg; Pkg.instantiate()'
          # Isabelle: download and add to PATH
          echo "Install toolchain from pinned manifest"

      - name: Static checks
        run: |
          hlint haskell/
          # liquid haskell/WeakMeasureKrausLH.hs
          # liquid haskell/KrausExtractor.hs

      - name: Unit tests
        run: |
          cabal test
          python3 -m pytest python/tests/
          julia --project -e 'include("julia/tests/test_ema.jl")'

      - name: Integration test
        run: |
          bash scripts/run_pipeline.sh --sandbox --trials 100 --theta 0.392699081698724

      - name: Numeric verification
        run: |
          ./kraus_extractor
          python3 python/check_kraus.py --tol 1e-8

      - name: Formal verification
        run: |
          isabelle build -v -d isabelle Quipper_Kraus_Session
          agda -v0 formal/agda/SymbolOscillatorInvariant.agda

      - name: Package artifacts
        run: |
          tar czf release-$(git rev-parse --short HEAD).tar.gz \
            kraus_out/ beliefs.csv proof_report.txt
          sha256sum release-*.tar.gz > release.sha256
```

---

## Key Metrics

| Metric | Target |
|--------|--------|
| `completeness_norm` = `‖∑ K_m†K_m − I‖_∞` | `< 1e-8` |
| `min_eig` = min eigenvalue of each `K_m†K_m` | `≥ -1e-8` |
| `msg_latency_ms` = median IPC roundtrip | `< 200 ms` |
| Isabelle build: no `sorry` | required |
| LH violations | 0 |

---

## Release Checklist

- [ ] All unit and integration tests pass.
- [ ] CI pipeline green and artifacts produced.
- [ ] Numeric checks within tolerance.
- [ ] Formal session builds with no `sorry`.
- [ ] Secrets and credentials rotated and not in repo.
- [ ] Monitoring dashboards configured and alerts set.
- [ ] Release bundle signed and uploaded to artifact store.
- [ ] Runbook and rollback instructions published.

---

## Agent Task Roster

| Agent | Input | Output |
|-------|-------|--------|
| A — Circuit & Sender | `theta`, `trials`, `host:port` | `sender.log`, `K_*.json` |
| B — Kraus Extractor | circuit, `n_sys`, `n_anc`, `theta` | `kraus_out/K_*.json`, `kraus_defs.thy` |
| C — Julia EMA Controller | `host:port`, `eta`, `symbols.json` | `beliefs.csv`, `beliefs_plot.png` |
| D — Isabelle Verifier | `kraus_defs.thy` | `Quipper_Kraus_Check.thy`, `proof_report.txt` |
| E — Hardening & CI | repo root | `.github/workflows/ci.yml`, `ci_report.txt` |

## Minimal Agent Prompt

```
Task: Implement one pipeline component (choose A–E). Follow the repo layout and produce the listed outputs.
Interfaces:
  - Quipper circuit: weakMeasureCircuit(theta)
  - Kraus extractor: runExtraction(n_sys, n_anc, simulateBasis, outdir, thetaSym)
  - Julia listener: listens on host:port, applies EMA with eta
Deliverables: logs, JSON artifacts, Isabelle .thy fragment, report (max 300 words).
Acceptance: pass automated checks (IPC, completeness, PSD, Isabelle build).
```
