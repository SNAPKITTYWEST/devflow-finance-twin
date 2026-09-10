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
