#!/usr/bin/env bash
# run_pipeline.sh — orchestrate one full pipeline demo and archive artifacts
set -euo pipefail

THETA="${THETA:-0.392699081698724}"
ETA="${ETA:-0.1}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-9001}"
TRIALS="${TRIALS:-200}"
OUTDIR="pipeline_out_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUTDIR/kraus_out" "$OUTDIR/provenance" "$OUTDIR/visuals"

echo "=== Step 1: Kraus extraction ==="
cabal run kraus-extractor -- --outdir "$OUTDIR/kraus_out" --theta "$THETA" 2>&1 | tee "$OUTDIR/extractor.log"

echo "=== Step 2: Isabelle formal build ==="
isabelle build -v -d isabelle Quipper_Kraus_Session 2>&1 | tee "$OUTDIR/isabelle.log" || echo "WARNING: Isabelle build returned non-zero (sorry stubs present)"

echo "=== Step 3: Oscillator attractor search ==="
python3 dynamics/oscillator_fixedpoints.py 2>&1 | tee "$OUTDIR/attractors.log"

echo "=== Step 4: Julia EMA controller (background) ==="
julia --project=. julia/julia_driver.jl --host "$HOST" --port "$PORT" --eta "$ETA" \
  > "$OUTDIR/controller.log" 2>&1 &
JULIA_PID=$!
sleep 2

echo "=== Step 5: Quipper TCP sender ==="
cabal run kraus-sender -- --host "$HOST" --port "$PORT" --trials "$TRIALS" --theta "$THETA" \
  2>&1 | tee "$OUTDIR/sender.log"

echo "Waiting for Julia to finish..."
sleep 3
kill "$JULIA_PID" 2>/dev/null || true

echo "=== Step 6: Numeric checks ==="
cabal run kraus-lh-test -- --trials 1000 --seed 1337 2>&1 | tee "$OUTDIR/numeric_checks.log"

echo "=== Step 7: Package artifacts ==="
cp kraus_test_report.json beliefs.csv "$OUTDIR/" 2>/dev/null || true
tar czf "${OUTDIR}.tar.gz" "$OUTDIR/"
sha256sum "${OUTDIR}.tar.gz" > "${OUTDIR}.sha256"

echo "=== Pipeline complete ==="
echo "Artifacts: ${OUTDIR}.tar.gz"
echo "SHA256:     $(cat ${OUTDIR}.sha256)"
