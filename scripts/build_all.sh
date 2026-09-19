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

#!/bin/sh
# build_all.sh
# Build sequence for full package:
# 1) Build CUDA objects and shared lib
# 2) Build C shim
# 3) Build Pascal host
# 4) Build Ada/SPARK project and run GNATprove
set -e

echo "Step 1: Build CUDA/PTX and shared lib..."
./synthesize_ptx.sh

echo "Step 2: Build Pascal host..."
fpc -k"-Wl,-rpath,." -k"-L." gpu_host.pas -o gpu_host

echo "Step 3: Build Ada/SPARK memory manager (compile only)..."
gprbuild -P memory_manager.gpr

echo "Step 4: Run GNATprove (may take time)..."
./prove_memory_manager.sh

echo "All build steps completed. Run: LD_LIBRARY_PATH=. ./gpu_host"
