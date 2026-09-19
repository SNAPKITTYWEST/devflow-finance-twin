# Metabinary Lua source map

This directory contains two standalone prototype codecs, a builder facade, and
FFI integration declarations. The [audit](../docs/audits/RSI_LUA_AUDIT.md) documents
reproduced format and builder failures. “Production-ready” comments in source do
not establish working round trips or native backend support.

| File | Role |
|---|---|
| `metabinary.lua` | Opcode tables, header/AST codec, validation predicates, NAND word codec, tree queries. |
| `metabinary_complete.lua` | Independent codec copy plus configuration, backend registration flags, and high-level factories. |
| `metabinary_builder_facade.lua` | Builder validation and factories; `serialize()` currently returns an AST. |
| `metabinary_ffi_bindings.lua` | FFI declarations and C/Rust/Go loaders; matching native libraries required separately. |
| `metabinary_final_assembly.lua` | Requires the base codec, FFI bindings, and facade; serialization remains Lua-based. |
| `example_usage_all_backends.lua` | Example script; currently fails syntax validation. |

Files remain at their existing paths to preserve `require` names and source
variants. Documentation lives here and in `docs/audits/`; audit and performance
tooling lives under `benchmarks/rsi_lua/` rather than being mixed into the engine.

Run from the repository root, with a compatible Lua interpreter:

```sh
lua benchmarks/rsi_lua/lua_audit.lua
python benchmarks/rsi_lua/run.py --lua /path/to/lua
```

The audit script prints JSON lines containing both successes and failures. On
this machine it ran under MiKTeX `texlua` (Lua 5.3). The measured subset does not
execute homomorphic encryption, GPU kernels, or native C/Rust/Go backends. See
[benchmark methodology](../benchmarks/rsi_lua/README.md) for exact limitations.
