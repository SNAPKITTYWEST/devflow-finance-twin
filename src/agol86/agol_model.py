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
from agol_transformer import AGOLBlock

class AGOLModel(torch.nn.Module):
    def __init__(self, layers, d, ff, heads, vocab):
        super().__init__()
        self.embed = torch.nn.Embedding(vocab, d)
        self.blocks = torch.nn.ModuleList([AGOLBlock(d, ff, heads) for _ in range(layers)])
        self.out = torch.nn.Linear(d, vocab)

    def forward(self, x):
        h = self.embed(x)          # [T] -> [T,D]
        for blk in self.blocks:
            h = blk(h)             # transformer blocks
        return self.out(h)         # [T,V]
