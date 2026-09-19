# Dream-RSI Reconstruction

This is an independent, auditable reconstruction of the **mechanism** in the supplied Dream-RSI brief. It is not Google's proprietary implementation, and the `~22,000 LOC` number is treated as an engineering budget rather than a measurement of Google's source.

## Status

Two implementation generations are preserved here. The first slice now lives in
each package's `legacy.py`; layered implementations have descriptive filenames.
The import collisions have been repaired. Budget and tree-validation defects
remain open in the [source audit](../docs/audits/RSI_LUA_AUDIT.md).

## Organization and API selection

| Concern | First implementation | Layered implementation |
|---|---|---|
| Loop | `core/legacy.py`: `DreamRSI`, `RunConfig` | `core/orchestrator.py`: `RSIOrchestrator` |
| Discovery | `discovery/legacy.py`: `DiscoveryAgent` | `discovery/agent.py`: `FixedDiscoveryAgent` |
| Policy | `policy/legacy.py`: `ExplorationPolicy`, `PolicyDeveloper` | `policy/engine.py`: `SearchPolicy`, `PolicyDeveloper` |
| Replay | `replay/legacy.py`: `ReplayEngine`, `SimulatorPool` | `replay/engine.py`: `HistoricalReplay`; `simulator/pool.py` |
| Evaluation | `evaluation/legacy.py` | `evaluation/protocol.py` |
| Metrics | `metrics/legacy.py` | `metrics/collector.py` |
| Persistence | `persistence/legacy.py`: `WorldStore` | `persistence/worlds.py`: `WorldStore` |
| Experiments | `experiments/legacy.py`: `ExperimentRunner` | `experiments/runner.py`: `ExperimentRunner` |

`tree.py` is shared. No implementation was discarded. The relocation manifest is
in [docs/audits](../docs/audits/rsi-relocations.json).

Top-level `dream_rsi` exports and the CLI select the first implementation.
`dream_rsi.experiments.ExperimentRunner` and `dream_rsi.persistence.WorldStore`
also retain its API; `LayeredExperimentRunner` names the layered runner.
`dream_rsi.policy.PolicyDeveloper` is the layered developer, whereas the
top-level `dream_rsi.PolicyDeveloper` is legacy. Use explicit implementation
module imports when composing components; the two policy/agent types are not
interchangeable. Existing layered imports continue to work unchanged.

For the layered loop:

```python
from dream_rsi.core.orchestrator import RSIOrchestrator

result = RSIOrchestrator().run("synthetic task", rounds=3, revisions=4)
print(result["metrics"])
```

## Legacy CLI

Run it with:

```bash
python -m dream_rsi.cli "improve a sorting algorithm" --rounds 3 --domain algorithm
```

## Architecture

`DreamRSI` owns the loop. `DiscoveryAgent` is fixed and is called only by `online_exploration`. `ExplorationPolicy` is executable controller code: it decides branch count, ordering, stopping, depth, and budget. `DiscoveryTree` stores decisions, candidates, traces, evaluator results, score, cost, and metadata. `ReplayEngine` traverses stored nodes and never imports or invokes the discovery agent. `SimulatorPool` accumulates all historical trees.

## RSI loop

1. Generate one new tree with the deployed policy.
2. Add it to the simulator pool.
3. Keep the deployed policy as candidate `0`.
4. Generate bounded policy revisions.
5. Replay every candidate against every historical tree.
6. Select the maximum-scoring candidate and deploy it.

The incumbent is always in the candidate set, so selection guarantees `score(next) >= score(current)` under the same replay objective. A candidate cannot invent a missing branch: replay records sparsity and uses only recorded children.

## Online/offline separation

Online work calls `DiscoveryAgent.propose` and `execute`, then evaluates the result through a domain adapter. Offline work only reads `evaluator_result` from historical nodes. Metrics separately record discovery-agent calls, online executions, replay evaluations, and offline evaluations.

## Domains and baselines

The same RSI machinery supports `AlgorithmEngineering`, `MathematicalOptimization`, and `GPUKernelEngineering`. `RecursiveFixedExploration` and `SimpleTESBaseline` provide fixed-policy comparison scaffolding. Controlled experiments should use the same task, discovery agent, evaluator, initial policy, and budget.

## Source-faithfulness labels

- **DOCUMENTED:** the two-agent separation, evolving policies, discovery trees, historical replay, accumulated worlds, and incumbent-preserving selection described in the supplied brief.
- **INFERRED:** tree fields, score aggregation across worlds, sparsity handling, budget accounting, and adapter boundaries.
- **RECONSTRUCTED:** hash-derived proposals, synthetic domain evaluators, mutation operators, and CLI. Proposal inputs include random parent UUIDs, so repeated tasks alone do not reproduce identical runs.

## Failure modes

- **Policy regression:** the incumbent is retained by `PolicyDeveloper.select_best`.
- **Replay overfitting:** candidates are scored against historical worlds; this does not establish generalization to unseen worlds.
- **Tree sparsity:** unavailable branches are not fabricated; `sparse_requests` is counted.
- **Exploration bounds:** limits exist, but branch batches and costly nodes can overshoot; see the executable audit cases.
- **Candidate explosion:** developers cap candidate counts. Legacy `RunConfig.revisions` is ignored, and layered `SimulationBudget.max_worlds` is unused.

## Tests and benchmarks

```sh
python -m pytest tests/test_dream_rsi.py tests/test_dream_rsi_extensions.py tests/test_dream_rsi_full.py tests/test_dream_rsi_phase23.py tests/test_dream_rsi_audit.py -q -rx
python benchmarks/rsi_lua/run.py
```

The audit suite distinguishes passing tests from strict expected failures for
unresolved defects. [Benchmark instructions](../benchmarks/rsi_lua/README.md)
explain fixture IDs, timing, operation counts, and synthetic-score limitations.

## Exact LOC count

Use the repository's counting command for the exact current reconstruction count:

```bash
find dream_rsi -type f -name '*.py' -print0 | xargs -0 cat | wc -l
```

This README intentionally does not claim that the compact first slice is 22,000 LOC. The target is an architectural expansion budget, not evidence about any private source tree.
