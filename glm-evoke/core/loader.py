# ============================================================================
# glm-evoke/core/loader.py
# L1: Checkpoint ingestion with hard gates (manifest hash, shapes, coverage)
# License: GPL 2.0
# ============================================================================

import hashlib
import json
import os
import numpy as np


class GateError(AssertionError):
    """A verification gate failed. The build aborts. No silent fallback."""
    pass


class CheckpointLoader:
    def __init__(self, root, schema):
        self.root = root
        self.schema = schema

    def ingest(self):
        # ---- GATE 1: manifest integrity ----
        mpath = os.path.join(self.root, "manifest.json")
        raw = open(mpath, "rb").read()
        manifest = json.loads(raw)
        claimed = manifest.pop("expected_sha256", None)
        actual = hashlib.sha256(
            json.dumps(manifest, sort_keys=True).encode()
        ).hexdigest()
        if claimed is not None and claimed != actual:
            raise GateError(f"CHECKPOINT INTEGRITY FAILURE: {actual}")

        # ---- GATES 2 & 3: shapes + coverage ----
        tensors, seen = {}, set()
        for shard in manifest["shards"]:
            with open(os.path.join(self.root, shard["file"]), "rb") as f:
                blob = f.read()
                for key, shape, dtype, offset, nbytes in shard["tensors"]:
                    t = self._decode(blob[offset : offset + nbytes], shape, dtype)
                    exp = self.schema.get(self._strip(key))
                    if exp is None:
                        raise GateError(f"UNKNOWN KEY: {key}")
                    if tuple(shape) != tuple(exp):
                        raise GateError(
                            f"SHAPE VIOLATION: {key} {shape} != {exp}"
                        )
                    tensors[key] = t
                    seen.add(self._strip(key))
        missing = set(self.schema) - seen
        if missing:
            raise GateError(f"MISSING KEYS: {sorted(missing)}")
        tensors["_hash"] = claimed or actual
        return tensors

    @staticmethod
    def _strip(key):
        """layer.3.q -> layer.q for schema lookup (index-agnostic contract)."""
        parts = key.split(".")
        if parts[0] == "layer" and len(parts) > 1 and parts[1].isdigit():
            return "layer." + ".".join(parts[2:])
        return key

    @staticmethod
    def _decode(buf, shape, dtype):
        if dtype == "fp32":
            return np.frombuffer(buf, np.float32).reshape(shape).copy()
        if dtype == "fp16":
            return np.frombuffer(buf, np.float16).reshape(shape).astype(np.float32)
        if dtype == "bf16":
            u16 = np.frombuffer(buf, np.uint16)
            f32 = (u16.astype(np.uint32) << 16).view(np.float32)
            return f32.reshape(shape).copy()
        raise GateError(f"UNSUPPORTED DTYPE: {dtype}")
