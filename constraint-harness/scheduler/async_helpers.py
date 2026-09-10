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
