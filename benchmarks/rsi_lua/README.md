# RSI and Lua benchmarks

[Measured summary](results/SUMMARY.md) · [Raw results](results/latest.json) ·
[Audit and edge cases](../../docs/audits/RSI_LUA_AUDIT.md)

Run from the repository root:

```sh
python benchmarks/rsi_lua/run.py --samples 7 --batch 5 --lua /path/to/lua
python benchmarks/rsi_lua/summarize.py
```

On this Windows machine:

```powershell
& 'C:\Users\jessi\AppData\Local\Programs\Python\Python312\python.exe' benchmarks/rsi_lua/run.py --lua 'C:\Users\jessi\AppData\Local\Programs\MiKTeX\miktex\bin\x64\texlua.exe'
& 'C:\Users\jessi\AppData\Local\Programs\Python\Python312\python.exe' benchmarks/rsi_lua/summarize.py
```

Python workloads need only the standard library. Tests use pytest. Omitting
`--lua` runs RSI and records Lua as `not_run`; it does not invent Lua numbers.
`--output` selects another JSON destination. The summary script reads the default
`results/latest.json`. Each run overwrites that default snapshot.

## Workloads and controls

- **Online RSI:** layered runs at 1/10/50 rounds and 0/4/8 revisions; legacy runs
  at the same round counts with default revisions. Separate engine defaults
  mean these are not matched speedup comparisons.
- **Replay:** 1/10/100 copies of a 63-node, depth-five binary tree. Policy allows
  128 nodes/cost units and depth ten. Each replay must visit 63 nodes and charge
  62 units per world. Recorded scores are synthetic.
- **Persistence:** JSON and JSONL round trips preserve the full tree. JSONL
  includes temporary file/directory creation and cleanup; it is not an fsync or
  crash-durability benchmark.
- **Lua:** both codec copies run header packing, serialization alone, a batch of
  256 NAND decodes, and leaf node counting. Format and builder failures are
  reported separately. Neither header packing nor serialization timing proves
  a usable wire format.

Python replaces UUID generation only inside benchmark fixtures, starting at the
same counter for each online operation. Production UUID behavior is unchanged.
Each measurement warms up once, then collects seven samples of five operations
by default. Work counters must match the warm-up result. Timing includes engine
construction and benchmark consistency checks; these are small local workloads.

Lua warms up each workload for 100 operations and collects seven samples. Loop
counts are 10,000 for packing/serialization, 1,000 batches of 256 decodes, and
100,000 for leaf queries. Lua sample counts are fixed in `lua_audit.lua` and are
independent of Python's CLI options. Garbage collection runs before each timed
Lua sample. Lua's CPU clock and Python's wall clock measure different things.

The JSON includes all samples, workload counters, runtime details, source hashes,
Lua stdout/stderr, and check outcomes. Benchmark-driver success means measurements
were recorded; it does not mean the separately recorded audit checks passed.
No native backend, encrypted computation, or GPU performance is claimed.
