# xslt-wasm

**XSLT→WASM Compiler** — Compiles XSLT stylesheets to WebAssembly via Rust compiler with JS/TS bindings.

## Subdirectories

| Directory | Language | Description |
|-----------|----------|-------------|
| [src/](src/) | Rust | Compiler core |
| [js/](js/) | JavaScript | JS bindings |
| [ts/](ts/) | TypeScript | TS bindings |
| [examples/](examples/) | XSLT | Example stylesheets |

## Architecture

```
XSLT Source → Parser → IR → WASM Codegen → .wasm
                    ↓
              JS/TS Bindings
```

## Build

```bash
# Rust compiler
cd src && cargo build --release

# JS bindings
cd js && npm install && npm run build

# TS bindings
cd ts && npm install && npm run build
```