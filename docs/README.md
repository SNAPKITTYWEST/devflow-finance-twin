# Dream-RSI reconstruction documentation

## Status

This is an independent mechanism reconstruction, not a proprietary source recovery.

## Phase plan

- Phase 1: package boundaries and shared interfaces.
- Phase 2: bounded simulator, multi-world replay, baselines, domain runner.
- Phase 3: documentation, persistence validation, and failure-mode coverage.

The implementation is intentionally auditable: the policy is code, the world is serializable, and replay uses recorded outcomes.
