# RSI and Lua repairs

The combined scoped suite passes **54 tests**, including a native Lua runner that
executes **36 passing checks** and a separate complete-example run. There are no
expected failures or skipped tests. See [test output](rsi-test-results.txt),
[Lua check output](lua-test-results.jsonl), and [example output](lua-examples.txt).
These results cover RSI and the Lua engine, not unrelated repository components.

## Reproduce

From the repository root:

```sh
python -m pytest tests/test_dream_rsi.py tests/test_dream_rsi_extensions.py tests/test_dream_rsi_full.py tests/test_dream_rsi_phase23.py tests/test_dream_rsi_audit.py tests/test_lua_engine.py -q
python benchmarks/rsi_lua/run.py --lua /path/to/texlua
python benchmarks/rsi_lua/summarize.py
```

Python tests select `LUA_RUNTIME`, then `texlua`, then `lua`. The combined suite
requires Lua 5.3+ with FFI for its FFI checks. The tested environment is Python
3.12.10 and MiKTeX texlua reporting Lua 5.3. It does not silently skip Lua if the
runtime is absent. Native-library behavior is tested with explicit mocks; actual
C/Rust/Go libraries are not available here.

## RSI changes

- Both online loops enforce the non-root node limit inside each branch batch.
  Legacy exploration admits only whole unit-cost operations within a fractional
  budget. Layered custom executions reject nonfinite/negative costs and reported
  costs exceeding the remainder; an already executed external operation cannot
  be undone. External agents must bound their own execution costs.
- Replay checks cost before visiting/scoring a node. Layered replay applies the
  tighter policy/simulation limits, honors `max_worlds`, validates explicit limits,
  and reports world truncation through `budget_exhausted`. Node and cost limits
  are per world; replay counts the root as a visited node.
- Tree validation checks the root, both directions of parent links, duplicate
  links/IDs, reachability, cycles, finite scores, and non-negative finite costs.
  Deserialization validates, so JSONL loading rejects malformed worlds with a
  line-numbered error. Pool insertion copies caller trees; subsequent invalid
  mutation is checked before replay.
- Policies reject nonfinite budgets and non-integer limits. A zero pool bound
  produces an empty pool. Legacy `RunConfig.revisions` and `online_budget` now
  take effect. Synthetic evaluator validity flags gate scores, and finite-score
  validation is used online.
- `policy_improvement` compares the candidate and incumbent on the same pool.
  Candidate replay counters retain their existing meaning: they count revisions,
  excluding the incumbent evaluation. Eight prior expected-failure tests now
  assert repaired behavior normally; additional boundary tests cover both APIs.

## Lua changes

Both entry points use [metabinary_codec.lua](../../lua/metabinary_codec.lua) for
header packing, recursive encoding/decoding, checksum validation, and bounded
queries. Their public module names and builders remain available.

The canonical local layout is little-endian: 20 bytes of declared header fields,
four zero padding bytes, eight integrity bytes, then parameters and children.
Integrity begins at byte offset 24 and the body at offset 32, matching the
repository specification's offsets and the installed FFI struct layout.
The old 28-byte output is rejected rather than silently reinterpreted.

Serialization validates ranges, parameters, arity, cycles, and resource limits.
Deserialization returns the exact consumed byte count and verifies every subtree.
As a stream API, it permits trailing bytes; `validate` requires one exact block
and rejects trailing data. Both paths hash the header with integrity zeroed.
Depth is limited to 128, nodes to 10,000, and serialized/input bytes to 64 MiB.
Query traversal also rejects cycles and exceeds neither depth nor node limits.

The inherited checksum is now explicitly named **polynomial64**, a prototype
error-detection checksum. It is **not cryptographic BLAKE3** and does not establish
conformance to the specification's keyed integrity requirement. Tampering tests
verify detection of the exercised changes, not resistance to forged checksums.

Builders now expose fluent methods, retain the pure flag, supply introspection
metadata, and allow incremental construction before checking final arity.
Facade serialization returns bytes. ENCODE parameters are 11 bytes; multi-byte
factory parameters use little-endian order. The example syntax, missing
parameters, introspection crash, and unchecked performance calls were repaired.

FFI loaders select platform defaults before loading and handle null error
pointers without dereferencing them, including runtimes that do not compare null
cdata equal to `nil`. Final assembly defaults to Lua; explicit native validation
requests propagate unavailable/error statuses. Serialization still executes the
Lua codec. Native validation is additional checking, not native serialization.

## Evidence and limits

[Current measurements](../../benchmarks/rsi_lua/results/SUMMARY.md) include valid
Lua leaf round trips. All measured workloads verify their outputs. The driver
returns failure for either failed checks or failed measurements.

The [initial audit](RSI_LUA_AUDIT.md), [pre-repair measurements](../../benchmarks/rsi_lua/results/PRE_REPAIR.md),
and [pre-repair test log](rsi-pre-repair-tests.txt) remain historical evidence.
Relocation hashes and source-preservation records describe the organization
stage **before** these authorized algorithm repairs, not current source identity.
Current source and test hashes are recorded in the latest benchmark JSON.

The remaining limits are explicit: synthetic evaluators, random production UUIDs,
sequential online traversal, parallel-group metadata without worker execution,
per-world replay budgets, JSONL without concurrent-writer/crash-durability
guarantees, prototype checksum integrity, and unverified native libraries. None
is represented as a passing real-model, GPU, cryptographic, or deployment test.
