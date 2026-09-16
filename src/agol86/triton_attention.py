# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

# triton_attention.py
import torch
import triton
import triton.language as tl

@triton.jit
def fused_attn_kernel(Q, K, V, Out, T, D, DH, HEADS, BLOCK_T: tl.constexpr):
    pid_h = tl.program_id(0)
    pid_i = tl.program_id(1)

    h = pid_h
    i = pid_i

    q_off = i * D + h * DH
    k_base = h * DH
    v_base = h * DH

    q = tl.load(Q + q_off + tl.arange(0, DH))
    scores = tl.zeros((T,), dtype=tl.float32)

    for j in range(T):
        k_off = j * D + k_base
        k = tl.load(K + k_off + tl.arange(0, DH))
        scores[j] = tl.sum(q * k) / tl.sqrt(DH)

    mask = tl.arange(0, T)
    scores = tl.where(mask > i, scores + (-1e9), scores)
    probs = tl.softmax(scores)

    out = tl.zeros((DH,), dtype=tl.float32)
    for j in range(T):
        v_off = j * D + v_base
        v = tl.load(V + v_off + tl.arange(0, DH))
        out += probs[j] * v

    out_off = i * D + h * DH
    tl.store(Out + out_off + tl.arange(0, DH), out)

def fused_causal_attention(q, k, v, heads):
    t, d = q.shape
    dh = d // heads
    out = torch.empty_like(q)

    grid = (heads, t)
    fused_attn_kernel[grid](
        q, k, v, out,
        T=t, D=d, DH=dh, HEADS=heads,
        BLOCK_T=1,
    )
    return out
