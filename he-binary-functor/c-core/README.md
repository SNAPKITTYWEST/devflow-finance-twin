# c-core

**C Call Fibre** — C implementation of the call fibre supervisor.

## Files

| File | Language | Description |
|------|----------|-------------|
| `call_core.c` | C | Call fibre supervisor |

## Purpose

Supervises call fibres in the binary functor architecture, managing stack frames, continuations, and tail-call optimization.

## Build

```bash
gcc call_core.c -o call_core
```