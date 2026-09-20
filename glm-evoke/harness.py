# ============================================================================
# glm-evoke/harness.py
# L3/L4: Dual-backend engine, ExecutionSeal, ExecLog
# Observable execution records — no hidden reasoning traces
# License: GPL 2.0
# ============================================================================

import hashlib
import json
import time
import numpy as np


class ExecutionSeal:
    """Auditable state-transition record. Append-only event log + gate ledger."""

    def __init__(self, cfg, weight_hash):
        self.log = {
            "weight_hash": weight_hash,
            "seed": cfg.get("seed", 0),
            "gate_results": {},
            "events": [],
            "closed": False,
        }

    def gate(self, name, fn):
        t0 = time.time()
        try:
            detail, ok = str(fn()), "PASS"
        except Exception as e:
            detail, ok = str(e), "FAIL"
        self.log["gate_results"][name] = {
            "status": ok,
            "detail": detail,
            "elapsed_ms": round((time.time() - t0) * 1000, 2),
        }
        return ok == "PASS"

    def event(self, name, **kw):
        self.log["events"].append({"t": round(time.time(), 6), "name": name, **kw})

    def close(self, state_hash, kv_hash=None):
        self.log["state_hash"] = state_hash
        if kv_hash:
            self.log["kv_state_hash"] = kv_hash
        self.log["closed"] = True
        return hashlib.sha256(
            json.dumps(self.log, sort_keys=True, default=str).encode()
        ).hexdigest()


class ExecLog:
    """Per-block fp footprint — the observable execution record."""

    def __init__(self):
        self.records = []

    def record(self, idx, x):
        x = (
            x.detach().cpu().numpy()
            if hasattr(x, "detach")
            else np.asarray(x)
        )
        self.records.append(
            {
                "block": idx,
                "mean": float(x.mean()),
                "std": float(x.std()),
                "sha256": hashlib.sha256(x.tobytes()).hexdigest()[:16],
            }
        )

    def state_hash(self):
        return hashlib.sha256(
            json.dumps(self.records, sort_keys=True).encode()
        ).hexdigest()


class GLMEvokeEngine:
    def __init__(self, cfg, backend="torch", weights=None):
        self.cfg = cfg
        self.backend = backend
        self.seal = ExecutionSeal(
            cfg, weights.get("_hash", "unknown") if weights else "unknown"
        )

        if backend == "torch":
            import torch

            torch.manual_seed(cfg.get("seed", 0))
            from backends.torch_backend import TorchGLM

            self.model = TorchGLM(cfg, weights)
            self.xp = torch

        else:
            raise ValueError(f"unknown backend: {backend}")

    def forward(self, x, phase):
        if self.backend == "torch":
            log = ExecLog()
            return self.model(x, phase, log), log
        return None, None
