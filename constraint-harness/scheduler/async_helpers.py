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

"""Async helpers (optional path). Core scheduler uses threads for simplicity."""

from __future__ import annotations

import asyncio
from typing import Any, Callable, Awaitable


async def bounded_gather(
    coros: list[Awaitable[Any]],
    max_concurrency: int = 8,
) -> list[Any]:
    sem = asyncio.Semaphore(max_concurrency)

    async def wrap(c: Awaitable[Any]) -> Any:
        async with sem:
            return await c

    return await asyncio.gather(*(wrap(c) for c in coros))
