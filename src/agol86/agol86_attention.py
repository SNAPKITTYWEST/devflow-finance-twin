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

# agol86_attention.py
import torch

def agol86_causal_attention(q, k, v, heads):
    # q,k,v: [T,D]
    T, D = q.shape
    Dh = D // heads

    qh = q.view(T, heads, Dh)
    kh = k.view(T, heads, Dh)
    vh = v.view(T, heads, Dh)

    scores = torch.einsum("thd,Thd->htT", qh, kh) / (Dh**0.5)
    mask = torch.triu(torch.ones(T, T, device=q.device) * -1e9, diagonal=1)
    scores = scores + mask

    probs = torch.softmax(scores, dim=-1)
    out = torch.einsum("htT,Thd->thd", probs, vh)
    return out.reshape(T, D), probs
