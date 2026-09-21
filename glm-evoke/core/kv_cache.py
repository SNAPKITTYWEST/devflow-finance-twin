# ============================================================================
# glm-evoke/core/kv_cache.py
# Paged KV-cache: block-paged, O(1) append, no realloc
# License: GPL 2.0
# ============================================================================

import hashlib
import json
import torch


class PagedKVCache:
    def __init__(
        self,
        num_layers,
        num_kv_heads,
        head_dim,
        max_pages,
        page_size,
        dtype=torch.float32,
    ):
        self.page_size = page_size
        self.max_pages = max_pages
        # physical pool: [L, max_pages*page_size, KVH, D]
        self.k = torch.zeros(
            num_layers, max_pages * page_size, num_kv_heads, head_dim, dtype=dtype
        )
        self.v = torch.zeros_like(self.k)
        self.allocated = 0
        self.page_map = []

    def append(self, layer_idx, k, v):
        """k,v: [B, T, KVH, D] (B=1 for decode loop). Appends, returns full cache view."""
        T = k.shape[1]
        need = self.allocated + T
        assert need <= self.max_pages * self.page_size, "KV-CACHE OVERFLOW"
        s = self.allocated
        self.k[layer_idx, s : s + T] = k[0]
        self.v[layer_idx, s : s + T] = v[0]
        return self.k[layer_idx, : s + T], self.v[layer_idx, : s + T]

    def state_hash(self):
        """Per-layer sha256 footprints — KV state is sealable too."""
        h = hashlib.sha256()
        for l in range(self.k.shape[0]):
            h.update(self.k[l].numpy().tobytes())
            h.update(self.v[l].numpy().tobytes())
        return h.hexdigest()

    def reset(self):
        self.allocated = 0
        self.page_map = []
