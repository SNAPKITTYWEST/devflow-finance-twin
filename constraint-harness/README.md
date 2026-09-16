# Constraint Harness

Production-oriented, modular constraint harness.

**Python is the execution substrate. MXML is the contract language. Datalog-style axioms are the constitution. PyTorch is optional.**

```
MXML → Parser → Constitution → State Machine → DAG Router
         → Python / PyTorch / Model Adapter → Validator → Seal
```

## Quick start

```bash
cd constraint-harness
python -m pytest tests/ -q
python -m constraint_harness.cli validate examples/basic.mxml
python -m constraint_harness.cli run examples/basic.mxml
python -m constraint_harness.cli run examples/parallel.mxml
```

No network, no PyTorch, and no external model are required for the core path.

## Architecture (layers remain independent)

| Layer | Path | Role |
|-------|------|------|
| MXML | `mxml/` | Parse & structurally validate contracts |
| Constitution | `constitution/` | Hard/soft axioms, fail-closed |
| Runtime | `runtime/` | Explicit state machine + executor |
| Scheduler | `scheduler/` | DAG + bounded concurrent execution |
| Commands | `commands/` | python / pytorch (optional) / model |
| Audit | `audit/` | Hashing + decision seal |
| Verification | `verification/` | Structural & constitutional checks |
| Adapters | `adapters/` | Model boundary (opaque providers) |

## Constitutional rules

- `UNKNOWN` or hard `FAIL` → `FAILED_CLOSED`
- Soft failures may produce `REVISE` (bounded by `max_revisions`)
- Quality scores never override hard axioms
- Precedence: `FAILED_CLOSED` > `REVISE` > `ACCEPT`

## Design decisions

- Minimal dependencies (stdlib only for core).
- PyTorch imported only inside `commands/pytorch_command.py`.
- Model providers sit behind `ModelAdapter`; no private weights or hidden state are claimed.
- State transitions are explicit and audited; illegal transitions raise.
- DAG rejects cycles, self-deps, and missing deps.

## Status

Phases 1–8 implemented and tested (parser, constitution, state machine, DAG, Python command path, verification hooks, provenance/seal).
PyTorch command degrades gracefully when torch is absent.
Model adapters are stubs ready for real providers.

## License

MIT
