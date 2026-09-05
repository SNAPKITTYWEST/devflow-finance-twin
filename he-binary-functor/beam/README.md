# beam

**BEAM Assembly** — Erlang/BEAM call functor implementation.

## Files

| File | Language | Description |
|------|----------|-------------|
| `call_functor.erl` | Erlang | Call functor for BEAM VM |

## Purpose

Implements the call functor for the BEAM virtual machine, enabling interop between the binary functor architecture and Erlang processes.

## Build

```bash
erlc call_functor.erl
```