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

import torch

def causal_attention(q, k, v, heads):
    t, d = q.shape
    dh = d // heads
    qh = q.view(t, heads, dh)
    kh = k.view(t, heads, dh)
    vh = v.view(t, heads, dh)

    scores = torch.einsum("thd,Thd->htT", qh, kh) / (dh**0.5)
    mask = torch.triu(torch.ones(t, t, device=q.device) * -1e9, diagonal=1)
    scores = scores + mask

    probs = torch.softmax(scores, dim=-1)
    out = torch.einsum("htT,Thd->thd", probs, vh)
    return out.reshape(t, d), probs
