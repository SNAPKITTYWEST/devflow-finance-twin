# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

#!/usr/bin/env bash
# haskell/test_runner.sh â€” build and run KrausLHTest with given trials and seed
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
