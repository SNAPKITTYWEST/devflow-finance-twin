"""Optional PyTorch command. Core harness works without torch."""

from __future__ import annotations

from typing import Any


def run_pytorch(input_data: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
    try:
        import torch  # type: ignore
    except ImportError:
        return {
            "status": "unavailable",
            "reason": "PyTorch not installed",
            "note": "core harness does not require torch",
        }
    op = input_data.get("op", "info")
    if op == "info":
        return {
            "status": "ok",
            "torch_version": torch.__version__,
            "cuda_available": torch.cuda.is_available(),
        }
    if op == "tensor":
        data = input_data.get("data", [1.0, 2.0, 3.0])
        t = torch.tensor(data)
        return {"status": "ok", "shape": list(t.shape), "sum": float(t.sum())}
    return {"status": "error", "reason": f"unknown op {op}"}
