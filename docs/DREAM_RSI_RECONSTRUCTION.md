# Dream-RSI reconstruction

## Overview

For the current source layout, tested limits, and unresolved edge cases, read the
[RSI package guide](../dream_rsi/README.md) and [RSI/Lua audit](audits/RSI_LUA_AUDIT.md).
Both implementation generations use synthetic hash-based domain scores.

This package reconstructs the public Dream-RSI mechanism as a compact, auditable policy-improvement loop. The discovery agent remains fixed during a run. The policy-development agent revises only the controller logic. Offline replay uses historical trees and no live discovery calls.

## Architecture

The core design is:

- fixed discovery agent proposes and executes candidates
- discovery tree stores decisions, traces, and scores
- simulator pool accumulates multiple historical worlds
- policy developer proposes candidate policies
- replay evaluates candidates against historical data
- incumbent is kept unless a later policy strictly improves score

## Loop

1. Deploy current policy.
2. Perform online exploration.
3. Record the new historical world.
4. Add it to the simulator pool.
5. Generate candidate policies.
6. Replay each candidate against all historical trees.
7. Keep the best candidate and continue.

## Policy representation

The policy is executable logic that decides how many branches to launch, how to order them, when to terminate, and how to use the budget.

## Replay semantics

The replay engine traverses recorded nodes and reuses their recorded evaluator results. It never reruns the discovery agent. It counts sparse branch requests instead of inventing missing branches.

## Online vs offline separation

Online work is expensive and executes the real discovery agent. Offline work is cheap and works from historical replay only.

## Candidate-selection guarantee

The currently deployed policy is included in the candidate set. Selection does
not reduce its replay score on that same historical pool. Adding a new world
changes the average, so scores across successive rounds can decrease. This is
not a guarantee of improved real-world task performance.

## Experimental methodology

Use the same discovery agent, same task, same budget, and same initial policy when comparing fixed exploration, SimpleTES-style baselines, and Dream-RSI.

## Exact LOC count

The implementation count is determined by the checked-out source, not by a hard-coded estimate:

```bash
find dream_rsi -type f -name '*.py' -print0 | xargs -0 cat | wc -l
```

The approximately 22,000 LOC number in the brief is an engineering budget, not evidence about a private Google source tree.
