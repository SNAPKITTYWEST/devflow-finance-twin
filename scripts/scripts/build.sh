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
set -e
echo "Building CUDA objects..."
nvcc -c -o vector_add.o vector_add.cu -Xcompiler -fPIC
echo "Compiling C shim..."
gcc -c -fPIC cuda_shim.c -o cuda_shim.o -I/usr/local/cuda/include
echo "Linking shared library libcuda_shim.so..."
gcc -shared -o libcuda_shim.so cuda_shim.o vector_add.o -L/usr/local/cuda/lib64 -lcudart -lcuda
echo "Compiling Pascal host (Free Pascal)..."
fpc -k"-Wl,-rpath,." -k"-L." gpu_host.pas -o gpu_host
echo "Build complete."
echo "Run: LD_LIBRARY_PATH=. ./gpu_host"
