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

# agol86_infer.py
import torch
from agol86_model import AGOL86Model

def load_agol86(path, vocab=128, d=128, ff=256, heads=4, layers=2):
    model = AGOL86Model(layers=layers, d=d, ff=ff, heads=heads, vocab=vocab).cuda()
    sd = torch.load(path, map_location="cuda")
    model.load_state_dict(sd)
    model.eval()
    return model

@torch.no_grad()
def agol86_infer_tokens(model, tokens):
    x = torch.tensor(tokens, dtype=torch.long, device="cuda")
    logits = model(x)
    probs = torch.softmax(logits, dim=-1)
    return probs
