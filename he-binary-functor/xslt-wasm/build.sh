#!/bin/bash
# XSLT → WASM Build Pipeline
# Requires: rustup target wasm32-unknown-unknown, wasm-bindgen-cli

set -e

echo "=== XSLT → WASM Build Pipeline ==="

# Step 1: Build Rust compiler
echo "[1/4] Building Rust XSLT compiler..."
cd src
cargo build --release --target wasm32-unknown-unknown 2>/dev/null || {
    echo "  Installing wasm32 target..."
    rustup target add wasm32-unknown-unknown
    cargo build --release --target wasm32-unknown-unknown
}
cd ..

# Step 2: Generate .wat from sample XSLT
echo "[2/4] Generating WAT from sample XSLT..."
if [ -f examples/sample.xslt ]; then
    cargo run --release -- compile examples/sample.xslt -o output/xslt_sample.wat
fi

# Step 3: WAT → WASM (if wabt installed)
echo "[3/4] Converting WAT → WASM..."
if command -v wat2wasm &> /dev/null; then
    wat2wasm output/xslt_sample.wat -o output/xslt_sample.wasm
    echo "  Produced: output/xslt_sample.wasm"
else
    echo "  wat2wasm not found — install wabt for WASM output"
    echo "  brew install wabt  OR  apt install wabt"
fi

# Step 4: Bundle JS host
echo "[4/4] Bundling JS host runtime..."
if command -v node &> /dev/null; then
    echo "  JS host: js/xslt_host.js"
    echo "  Usage: node js/xslt_host.js output/xslt_sample.wasm input.xml"
fi

echo "=== Build Complete ==="
