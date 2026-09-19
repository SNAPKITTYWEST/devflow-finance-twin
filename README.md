# Dream-RSI Reconstruction

This repository contains an independent implementation of the publicly described **mechanism** behind Dream-RSI: recursive self-improvement through evolving, replayable worlds.

It is not Google's or DeepMind's proprietary implementation. It does not claim access to private source code, internal prompts, training data, or unreleased reproduction scripts.

## Package layout

```text
dream_rsi/
├── core/          online orchestration and recursive loop
├── discovery/     fixed discovery agent and domain evaluators
├── policy/        executable exploration policies and revisions
├── replay/        historical replay without live discovery calls
├── simulator/     bounded world simulation and world pools
├── evaluation/    evaluator contracts and score validation
├── experiments/   controlled baselines and experiment runner
├── persistence/   JSONL historical-world storage
├── tree.py        serializable discovery tree
└── cli.py         command-line entry point

docs/              source-faithfulness and architecture notes
tests/             invariant, integration, and failure-mode tests
```

## Architecture

```text
Current policy πt
      │
      ▼
Online exploration + fixed discovery agent
      │
      ▼
Discovery tree Tt
      │
      ▼
SimulatorPool = {H1, H2, ..., Ht}
      │
      ▼
Policy developer creates {πt, π1, ..., πM}
      │
      ▼
Historical replay, no discovery-agent calls
      │
      ▼
Incumbent-safe selection and deployment
```

The discovery agent solves the domain task. The policy-development agent changes only exploration control: branching, ordering, parallel grouping, termination, and budget allocation.

## Recursive loop

Each round performs:

1. Run bounded online exploration with the deployed policy.
2. Persist the resulting tree as a historical world.
3. Add the world to the simulator pool.
4. Keep the deployed policy as candidate zero.
5. Generate at most `M` policy revisions.
6. Replay every candidate across accumulated worlds.
7. Select the highest-scoring candidate, retaining the incumbent on regression.
8. Deploy the selected policy for the next round.

The candidate guarantee is explicit:

```text
candidate_set[0] = deployed_policy
winner = argmax(candidate.score)
if winner.score < candidate_set[0].score:
    winner = candidate_set[0]
```

Therefore the deployed replay score cannot decrease under the same replay objective.

## Online/offline separation

Online execution calls `FixedDiscoveryAgent.propose()` and `.execute()`. It creates new nodes and evaluator results. Offline replay traverses existing nodes only. The replay engine has no call path to the discovery agent.

Metrics distinguish:

- `discovery_agent_calls`
- `online_executions`
- `replay_evaluations`
- `offline_evaluations`
- `policy_revisions`
- `compute_budget`

A replay evaluation is not a new discovery-agent execution.

## Replay semantics

A policy is executable Python logic. It decides:

- whether to stop
- how many recorded branches to select
- branch ordering
- parallel group size
- maximum depth
- node and cost budgets

If a policy asks for more branches than a historical node contains, replay records `sparse_requests` and uses only recorded children. It never fabricates an outcome.

## Domains

The same RSI machinery can run with:

- `AlgorithmEvaluator`
- `MathematicalEvaluator`
- `GPUKernelEvaluator`

Only the evaluator changes. The tree, policy, replay, budget, metrics, and selection machinery remain shared.

## Baselines

`RecursiveFixedExploration` runs the same discovery agent and evaluator without policy adaptation. `SimpleTESBaseline` uses a fixed FIFO controller. `Dream-RSI` adapts the executable policy through historical replay.

For controlled comparisons, use identical task, initial policy, discovery agent, evaluator, rounds, and budget.

## Failure-mode guarantees

- **Policy regression:** incumbent remains deployed.
- **Replay overfitting:** candidates are evaluated over the accumulated simulator pool.
- **Tree sparsity:** missing branches are counted, never invented.
- **Infinite exploration:** depth, node, and cost limits terminate online and replay work.
- **Candidate explosion:** `PolicyDeveloper.maximum_candidates` and per-run revision limits bound policy search.
- **Malformed worlds:** tree validation rejects broken parent/child links before persistence or simulation.

## Run

```bash
python -m dream_rsi.cli "improve a sorting algorithm" --rounds 3 --revisions 4
python -m pytest tests/test_dream_rsi.py tests/test_dream_rsi_full.py tests/test_dream_rsi_phase23.py
```

## Source-faithfulness split

### DOCUMENTED

The public mechanism: fixed discovery agent, evolving exploration policy, discovery trees, historical replay, accumulated worlds, separation of discovery and policy-development agents, and incumbent-preserving candidate selection.

### INFERRED

The exact node fields, replay traversal details, evaluator-result schema, budget accounting, sparse-branch behavior, persistence format, metric names, baseline protocol, and adapter boundaries.

### RECONSTRUCTED

All code in `dream_rsi/`, the deterministic discovery stand-in, synthetic domain evaluators, policy mutation operators, simulator implementation, JSONL persistence, CLI, baselines, and tests.

## 22,000 LOC engineering budget

The design brief estimates approximately 22,000 implementation lines across orchestration, discovery trees, replay, policy representation, policy generation, evaluation, parallel exploration, adapters, experiments, persistence, metrics, CLI, and validation.

That number is an **engineering budget for a complete production reconstruction**. It is not a measurement of Google's or DeepMind's private source code and must never be reported as one.

The exact current implementation count is reproducible from a checkout:

```bash
find dream_rsi -type f -name '*.py' -print0 | xargs -0 cat | wc -l
```

No generated filler is required to reach the budget. Production expansion should add real capabilities, tests, and integrations while preserving the invariants above.
