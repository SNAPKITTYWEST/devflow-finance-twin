# Dream-RSI Reconstruction

This is an independent, auditable reconstruction of the **mechanism** in the supplied Dream-RSI brief. It is not Google's proprietary implementation, and the `~22,000 LOC` number is treated as an engineering budget rather than a measurement of Google's source.

## Status

The first functional slice is implemented under `dream_rsi/`. It is deliberately compact rather than padded to an arbitrary LOC target. The next expansion should add production adapters, distributed persistence, experiment reporting, and a larger validation suite without changing the invariants below.

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
- **RECONSTRUCTED:** the deterministic hash-free in-memory implementation, synthetic domain evaluators, mutation operators, and CLI.

## Failure modes

- **Policy regression:** the incumbent is retained by `PolicyDeveloper.select_best`.
- **Replay overfitting:** candidates are scored against the complete `SimulatorPool`, not one tree.
- **Tree sparsity:** unavailable branches are not fabricated; `sparse_requests` is counted.
- **Infinite exploration:** depth, node, and cost budgets stop online and replay traversal.
- **Candidate explosion:** revision count and replay work are bounded by the developer and run configuration.

## Exact LOC count

Use the repository's counting command for the exact current reconstruction count:

```bash
find dream_rsi -type f -name '*.py' -print0 | xargs -0 cat | wc -l
```

This README intentionally does not claim that the compact first slice is 22,000 LOC. The target is an architectural expansion budget, not evidence about any private source tree.
