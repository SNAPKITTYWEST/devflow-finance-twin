#!/usr/bin/env bash
# haskell/test_runner.sh — build and run KrausLHTest with given trials and seed
set -euo pipefail

TRIALS="${1:-1000}"
SEED="${2:-1337}"
OUTDIR="kraus_out"
PROVDIR="provenance"

mkdir -p "$OUTDIR" "$PROVDIR"

echo "Building KrausLHTest..."
cabal build exe:kraus-lh-test 2>&1

echo "Running KrausLHTest (trials=$TRIALS seed=$SEED)..."
cabal run exe:kraus-lh-test -- --trials "$TRIALS" --seed "$SEED"

echo "Checking outputs..."
[ -f kraus_test_report.json ] || { echo "FAIL: kraus_test_report.json not produced"; exit 1; }

echo "test_runner.sh complete."
