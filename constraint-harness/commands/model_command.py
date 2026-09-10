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
