# occam-b-bscl — Wordcode Machine

A minimal compiler/runtime stack: **OCCAM + B + BSCL → common IR →
Wordcode → Wordcode Machine → native execution.** Not a small Java:
no objects, no GC, no class files, no JIT — words, registers, stacks,
processes, channels, deterministic scheduling.

## Build
    make # builds ./occamb
    make test # builds and runs the test suite

## CLI
    occamb build examples/factorial.b -o fact.wc
    occamb run fact.wc [--trace]
    occamb disassemble fact.wc
    occamb dump fact.wc
    occamb check examples/factorial.b
    occamb selftest

## Layout
See the source tree: `include/`, `src/`, `examples/`, `tests/`,
`docs/` (ARCHITECTURE.md, WORDCODE.md, MEMORY.md, CONCURRENCY.md).
