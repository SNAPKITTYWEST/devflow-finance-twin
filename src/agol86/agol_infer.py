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

# agol_infer.py
import torch
from agol_model import AGOLModel

def load_model(path, vocab=128, d=128, ff=256, heads=4, layers=2):
    model = AGOLModel(layers=layers, d=d, ff=ff, heads=heads, vocab=vocab).cuda()
    sd = torch.load(path, map_location="cuda")
    model.load_state_dict(sd)
    model.eval()
    return model

@torch.no_grad()
def infer_tokens(model, tokens):
    x = torch.tensor(tokens, dtype=torch.long, device="cuda")
    logits = model(x)
    probs = torch.softmax(logits, dim=-1)
    return probs

if __name__ == "__main__":
    model = load_model("agol_transformer.pt")
    tokens = [1, 2, 3, 4, 5, 6, 7, 8]
    probs = infer_tokens(model, tokens)
    print("probs shape:", probs.shape)
