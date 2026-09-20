# CBMC Bounded Model Checking Harnesses

Verification harnesses for all C and CUDA (host-side) code in devflow-finance-twin.

## Usage

```bash
# Run all harnesses
bash cbmc/run_all.sh

# Run a single harness
cbmc cbmc/harness_worm_commit.c src/native/worm_commit.c \
     -I src/native --bounds-check --pointer-check --unwind 10
```

## Targets

| Harness | Source | Properties Verified |
|---------|--------|-------------------|
| `harness_worm_commit.c` | `src/native/worm_commit.c` | Hash output fills 64 chars, magic preserved, record_count monotonic |
| `harness_fb_ledger.c` | `he-binary-functor/fibonacci-braid-ledger/fbLedger.c` | Array bounds (entries[count]), seal chain, word stack overflow, fib bounds |
| `harness_fibraid.c` | `he-binary-functor/fibonacci-braid-ledger/fibraid.c` | nent <= 32, word len <= 16, generator magnitude, chain linkage |
| `harness_ledger.c` | `he-binary-functor/fibonacci-braid-ledger/ledger.c` | nent <= 32, word len <= 8, generator magnitude [1,3] |
| `harness_word.c` | `he-binary-functor/fibonacci-braid-ledger/word.c` | gen_ok bounds, reduce output <= input, word_ok consistency |
| `harness_call_core.c` | `he-binary-functor/c-core/call_core.c` | Slot bounds [0,32), active == alive count, restarts <= 5 |
| `harness_worker.c` | `he-binary-functor/kernel/worker.c` | err_count in [0,5], phase transitions, epoch monotonicity |
| `harness_frama_memory.c` | `formal/tlm-jxcl/frama-c/memory.c` | InBounds, alignment, NoCodeOverlap, fetch within code region |
| `harness_frama_parser.c` | `formal/tlm-jxcl/frama-c/binary_parser.c` | Header magic, version, section bounds, entry point within code |
| `harness_frama_stack.c` | `formal/tlm-jxcl/frama-c/execution_stack.c` | Stack underflow/overflow, sp alignment, push/pop inverse |
| `harness_cuda_vsm.c` | `vsm2500/vsm2500_h100_sass_bridge.cu` | Register index bounds [0,32), trace buffer index, opcode dispatch |

## Requirements

- CBMC 6.0+ (`cbmc --version`)
- GCC or Clang (for preprocessing CUDA stubs)
