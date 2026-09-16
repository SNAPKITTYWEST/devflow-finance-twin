# Contributing Guide

## Commit message conventions

| Area | Commit message |
|---|---|
| Haskell core (weak measurement) | `feat(quipper): implement controlled-Ry weak-measurement circuit and analytic Kraus derivation` |
| Haskell IPC sender | `fix(ipc): replace deterministic RNG with statevector sampling fallback; add robust TCP framing` |
| Kraus extractor | `feat(kraus): implement unitary builder and Kraus extractor; export numeric + Isabelle fragments` |
| Python simulator | `chore(sim): add portable Python state-vector simulator for gate-list fallback` |
| Julia controller | `feat(julia): add EMA controller, CSV recorder, and optional plotting` |
| Isabelle theories | `chore(isabelle): add kraus_defs.thy and Quipper_Kraus_Check.thy proofs (CPTP + EMA lemmas)` |
| Liquid Haskell | `chore(lh): add Liquid Haskell specs for numeric bounds and I/O invariants` |
| Tests | `test(ci): add unit, property, and integration tests for extraction and IPC` |
| CI | `ci: add hermetic CI workflow with numeric checks and formal build stage` |
| Docs | `docs: add README, run_pipeline.sh, and production hardening runbook` |
| Security | `sec: add input schema validation, rate limiting, and secrets handling guidelines` |
| Release | `release: add reproducible release bundle and signing script` |

---

## Human-centered principles

**Why this matters**
This pipeline touches three communities: *researchers* (who need reproducible Kraus artifacts), *engineers* (who need robust, auditable systems), and *human stakeholders* (who need clear, trustworthy outputs and safe operational practices). Hardening is not just about passing tests — it's about making the system predictable, explainable, and safe for people who depend on it.

**Principles to follow**
- **Clarity over cleverness.** Prefer explicit, well-documented code paths and error messages that a human operator can act on quickly.
- **Reproducibility first.** Every artifact must be traceable to a commit, toolchain version, and seed. Store provenance metadata with outputs.
- **Fail fast, fail safe.** When something goes wrong, the system should stop producing misleading artifacts and surface a clear remediation path.
- **Human-readable observability.** Logs, metrics, and alerts should be written for a human on call: what happened, why it matters, and what to do next.
- **Privacy and minimal exposure.** Never log secrets; minimize persisted sensitive data; document data retention and deletion procedures.

---

## Operator checklist

- **Runbook pointer:** `docs/runbook.md` — one-page incident steps (stop pipeline, collect logs, revert to last signed bundle, notify stakeholders).
- **Quick health checks:** `make smoke` runs IPC ping, Kraus completeness check, and a short Isabelle build; returns pass/fail.
- **Key metrics:** completeness_norm, min_eig, trials_per_sec, msg_latency_ms, formal_build_time.
- **Escalation:** who to call (names/roles), where to paste logs, and how to reproduce locally.

---

## PR description template

**Title:** `<type>(scope): short imperative summary`

**Summary:** One paragraph describing what changed and why, written for a non-specialist reviewer.

**What I changed:** bullet list of functional changes and files touched.

**Why it matters:** short explanation of user/operator impact.

**How to test:** step-by-step commands for local verification (smoke tests).

**Safety checks:** list of automated checks added (unit, property, numeric, formal).

**Rollback plan:** exact git commands and artifact to restore.

---

## Reviewer checklist

- [ ] Code is documented and follows naming conventions.
- [ ] Liquid Haskell specs added/updated where applicable.
- [ ] Unit tests cover edge cases and run locally.
- [ ] Integration test executed in sandbox and passed.
- [ ] Numeric tolerances are explicit and justified.
- [ ] Isabelle build passes with no `sorry`.
- [ ] Runbook updated if operational behavior changed.
- [ ] Security review: no secrets in logs or commits.

---

## Prioritized next actions

1. **Commit & push** the Haskell, Python, Julia, and Isabelle artifacts with the commit messages above.
2. **Run `make smoke`** locally and capture the output; attach to the PR.
3. **Open PR** using the PR template; tag one domain expert and one on-call operator.
4. **Run CI** and confirm numeric checks and formal build succeed.
5. **Sign release** only after CI green and a manual smoke test by an operator.

---

## Release notes template

**Release X.Y — Jungian Quantum Pipeline (hardened)**
This release makes the pipeline production-ready: deterministic Kraus extraction, robust IPC, formal verification in Isabelle, and a reproducible release bundle. Operators get a one-page runbook and automated health checks; researchers get traceable, symbolic Kraus artifacts. The system now fails safely and provides clear remediation steps for human responders.
