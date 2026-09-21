# ============================================================================
# glm-evoke/models/make_checkpoint.py
# Synthetic GLM checkpoint generator
# Structured binary blob + sha256 manifest for gate testing
# License: GPL 2.0
# ============================================================================

import hashlib
import json
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.blocks import schema_for


def build(root, cfg, seed=0):
    os.makedirs(root, exist_ok=True)
    schema = schema_for(cfg)
    rng = np.random.default_rng(seed)
    entries, blob, offset, truth = [], [], 0, {}

    for key, shape in schema.items():
        a = (rng.standard_normal(shape) * 0.02).astype(np.float32)
        truth[key] = a
        b = a.tobytes()
        blob.append(b)
        entries.append([key, list(shape), "fp32", offset, len(b)])
        offset += len(b)

    with open(os.path.join(root, "shard0.bin"), "wb") as f:
        f.write(b"".join(blob))

    manifest = {"shards": [{"file": "shard0.bin", "tensors": entries}]}
    raw = json.dumps(manifest, sort_keys=True).encode()
    manifest["expected_sha256"] = hashlib.sha256(raw).hexdigest()

    with open(os.path.join(root, "manifest.json"), "wb") as f:
        f.write(json.dumps(manifest, indent=1).encode())

    truth["_hash"] = manifest["expected_sha256"]
    return truth, schema
