# ============================================================================
# glm-evoke/core/blocks.py
# Dual-regime mask builder and schema generation
# License: GPL 2.0
# ============================================================================

import numpy as np


def build_mask(T, phase):
    """EXPLICIT dual-regime mask. phase='prefix' -> bidirectional;
    phase='decode' -> causal. Never inferred. Never hidden."""
    if phase == "prefix":
        return np.zeros((T, T), dtype=bool)  # all positions visible
    return np.triu(np.ones((T, T), dtype=bool), k=1)  # causal (decode)


def schema_for(cfg):
    """Canonical tensor-name -> shape contract. The loader verifies against this."""
    H, I = cfg["hidden_size"], cfg["intermediate_size"]
    s = {"root_norm": (H,)}
    for i in range(cfg["num_layers"]):
        p = f"layer.{i}."
        s.update({
            p + "norm1": (H,), p + "norm2": (H,),
            p + "q": (H, cfg["num_attention_heads"] * cfg["head_dim"]),
            p + "k": (H, cfg["num_kv_heads"] * cfg["head_dim"]),
            p + "v": (H, cfg["num_kv_heads"] * cfg["head_dim"]),
            p + "o": (cfg["num_attention_heads"] * cfg["head_dim"], H),
            p + "wg": (H, I), p + "wu": (H, I), p + "wd": (I, H),
        })
    return s
