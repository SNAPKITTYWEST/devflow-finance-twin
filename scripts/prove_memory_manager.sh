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
# prove_memory_manager.sh
# Run GNATprove on the memory manager package
# Usage: ./prove_memory_manager.sh
set -e
echo "Running GNATprove on Memory_Manager..."
gnatprove -P memory_manager.gpr -a -j0
echo "GNATprove finished. Inspect results in 'gnatprove' output."
