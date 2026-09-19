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
set -Eeuo pipefail

###############################################################################
# publish-watch.sh â€” Watches .inbox/ and auto-publishes when files appear
#
# Start it once, leave it running. Drop files into .inbox/ and they get
# published automatically.
#
# Usage:
#   ./publish-watch.sh           Watch and auto-publish
#   ./publish-watch.sh --dry     Watch but only dry-run (preview, no commit)
###############################################################################

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INBOX="${REPO_ROOT}/.inbox"
PUBLISHER="${REPO_ROOT}/publish.sh"
POLL_INTERVAL=5  # seconds between checks
DRY_FLAG=""

if [[ "${1:-}" == "--dry" ]]; then
    DRY_FLAG="--dry-run"
    echo "[WATCHER] Dry-run mode â€” will preview but not commit"
fi

# Create inbox if missing
mkdir -p "$INBOX"

echo "[WATCHER] Monitoring ${INBOX}"
echo "[WATCHER] Drop files in .inbox/ â€” they publish automatically"
echo "[WATCHER] Press Ctrl+C to stop"
echo ""

while true; do
    # Count files in inbox (excluding conflicts dir)
    file_count="$(find "$INBOX" -type f ! -path "$INBOX/conflicts/*" 2>/dev/null | wc -l)"
    file_count="$(printf '%s' "$file_count" | tr -d '[:space:]')"

    if [[ "$file_count" -gt 0 ]]; then
        echo ""
        echo "[WATCHER] Detected ${file_count} file(s) in .inbox/"
        echo "[WATCHER] Publishing..."
        echo ""
        bash "$PUBLISHER" $DRY_FLAG || true
        echo ""
        echo "[WATCHER] Done. Resuming watch..."
    fi

    sleep "$POLL_INTERVAL"
done
