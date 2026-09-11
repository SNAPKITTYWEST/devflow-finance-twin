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

"""Machine-readable audit event types."""

from __future__ import annotations

EVENT_TYPES = frozenset({
    "execution_started",
    "contract_loaded",
    "axiom_evaluated",
    "task_created",
    "task_routed",
    "task_started",
    "task_completed",
    "verification_started",
    "verification_completed",
    "revision_started",
    "state_transition",
    "execution_committed",
    "execution_failed_closed",
    "decision_sealed",
})
