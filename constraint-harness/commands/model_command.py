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

"""Model adapter boundary. No private weights or hidden state."""

from __future__ import annotations

from typing import Any


def run_model(input_data: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
    """Stub: real providers live under adapters/."""
    prompt = input_data.get("prompt", "")
    return {
        "status": "ok",
        "provider": "stub",
        "prompt_len": len(prompt),
        "output": f"[stub response to: {prompt[:64]}]",
        "note": "external models remain behind adapter boundary",
    }
