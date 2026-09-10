"""Text execution-trace viewer."""

from __future__ import annotations

from typing import Any


def format_trace(trace: list[dict[str, Any]]) -> str:
    lines = ["PC OP REGS[0..7]", "-" * 50]
    for e in trace:
        regs = e.get("regs", [])
        reg_s = " ".join(f"{v:4d}" for v in regs[:8])
        lines.append(f"{e.get('pc', 0):04d} {e.get('op', '?'):16s} {reg_s}")
    return "\n".join(lines)


def print_trace(trace: list[dict[str, Any]]) -> None:
    print(format_trace(trace))
