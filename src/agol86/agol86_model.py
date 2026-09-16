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

# agol86_model.py
import torch
from agol86_block import AGOL86Block

class AGOL86Model(torch.nn.Module):
    def __init__(self, layers=2, d=128, ff=256, heads=4, vocab=128):
        super().__init__()
        self.vocab = vocab
        self.embed = torch.nn.Embedding(vocab, d)
        self.blocks = torch.nn.ModuleList(
            [AGOL86Block(d=d, ff=ff, heads=heads) for _ in range(layers)]
        )
        self.proj = torch.nn.Linear(d, vocab)

    def forward(self, tokens):
        # tokens: [T]
        h = self.embed(tokens)          # [T,D]
        for blk in self.blocks:
            h = blk(h)                  # transformer residual stack
        logits = self.proj(h)          # [T,V]
        return logits
