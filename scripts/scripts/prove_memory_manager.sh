#!/bin/sh
# prove_memory_manager.sh
# Run GNATprove on the memory manager package
# Usage: ./prove_memory_manager.sh
set -e
echo "Running GNATprove on Memory_Manager..."
gnatprove -P memory_manager.gpr -a -j0
echo "GNATprove finished. Inspect results in 'gnatprove' output."
