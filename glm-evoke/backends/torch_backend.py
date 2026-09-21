# ============================================================================
# glm-evoke/backends/torch_backend.py
# L2: GLM dual-regime transformer, torch assembly
# GQA attention, interleaved RoPE, SwiGLU FFN, pre-norm residuals
# License: GPL 2.0
# ============================================================================

import torch
import torch.nn as nn
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.blocks import build_mask


class TorchBlock(nn.Module):
    def __init__(self, cfg, idx):
        super().__init__()
        H, I = cfg["hidden_size"], cfg["intermediate_size"]
        self.norm1 = nn.Parameter(torch.ones(H))
        self.norm2 = nn.Parameter(torch.ones(H))
        self.q = nn.Parameter(
            torch.randn(H, cfg["num_attention_heads"] * cfg["head_dim"]) * 0.02
        )
        self.k = nn.Parameter(
            torch.randn(H, cfg["num_kv_heads"] * cfg["head_dim"]) * 0.02
        )
        self.v = nn.Parameter(
            torch.randn(H, cfg["num_kv_heads"] * cfg["head_dim"]) * 0.02
        )
        self.o = nn.Parameter(
            torch.randn(cfg["num_attention_heads"] * cfg["head_dim"], H) * 0.02
        )
        self.wg = nn.Parameter(torch.randn(H, I) * 0.02)
        self.wu = nn.Parameter(torch.randn(H, I) * 0.02)
        self.wd = nn.Parameter(torch.randn(I, H) * 0.02)
        self.cfg, self.idx = cfg, idx
        hd = cfg["head_dim"]
        inv = 1.0 / (
            cfg["rope_theta"] ** (torch.arange(0, hd, 2).float() / hd)
        )
        fr = torch.outer(torch.arange(cfg["max_seq_len"]).float(), inv)
        self.register_buffer("cos", fr.cos()[None, None], persistent=False)
        self.register_buffer("sin", fr.sin()[None, None], persistent=False)

    def _rope(self, x, T):
        c, s = self.cos[:, :, :T], self.sin[:, :, :T]
        x1, x2 = x[..., 0::2], x[..., 1::2]
        out = torch.empty_like(x)
        out[..., 0::2] = x1 * c - x2 * s
        out[..., 1::2] = x1 * s + x2 * c
        return out

    def forward(self, x, phase, exec_log, kv_cache=None):
        B, T, _ = x.shape
        D = self.cfg["head_dim"]
        h = (
            x
            * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.cfg["norm_eps"])
            * self.norm1
        )
        q = (h @ self.q).view(B, T, -1, D)
        k = (h @ self.k).view(B, T, -1, D)
        v = (h @ self.v).view(B, T, -1, D)
        q, k = self._rope(q, T), self._rope(k, T)

        if kv_cache is not None:
            ck, cv = kv_cache.append(self.idx, k, v)
            k, v = ck[None], cv[None]
            kv_cache.allocated += T

        rep = q.shape[2] // k.shape[2]
        k, v = k.repeat_interleave(rep, dim=2), v.repeat_interleave(rep, dim=2)
        att = (q @ k.transpose(-2, -1)) / (D**0.5)
        mask = torch.from_numpy(build_mask(T, phase)).to(x.device)
        if kv_cache is not None and phase == "decode":
            mask = torch.zeros(T, k.shape[2], dtype=torch.bool, device=x.device)
        att = att.masked_fill(mask, float("-inf")).softmax(-1)
        o = (att @ v).reshape(B, T, -1) @ self.o
        x = x + o
        h2 = (
            x
            * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.cfg["norm_eps"])
            * self.norm2
        )
        x = x + (torch.nn.functional.silu(h2 @ self.wg) * (h2 @ self.wu)) @ self.wd
        if exec_log is not None:
            exec_log.record(self.idx, x)
        return x


class TorchGLM(nn.Module):
    def __init__(self, cfg, weights=None):
        super().__init__()
        self.cfg = cfg
        self.blocks = nn.ModuleList(
            [TorchBlock(cfg, i) for i in range(cfg["num_layers"])]
        )
        self.root_norm = nn.Parameter(torch.ones(cfg["hidden_size"]))
        if weights is not None:
            self.load_weights(weights)

    _MAP = [
        ("q", "q"),
        ("k", "k"),
        ("v", "v"),
        ("o", "o"),
        ("wg", "wg"),
        ("wu", "wu"),
        ("wd", "wd"),
        ("norm1", "norm1"),
        ("norm2", "norm2"),
    ]

    def load_weights(self, w):
        with torch.no_grad():
            for i, blk in enumerate(self.blocks):
                for attr, key in self._MAP:
                    p = f"layer.{i}.{key}"
                    getattr(blk, attr).copy_(torch.from_numpy(w[p]).float())
            self.root_norm.copy_(torch.from_numpy(w["root_norm"]).float())

    def forward(self, x, phase, exec_log, kv_cache=None):
        for blk in self.blocks:
            x = blk(x, phase, exec_log, kv_cache)
        return (
            x
            * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.cfg["norm_eps"])
            * self.root_norm
        )
