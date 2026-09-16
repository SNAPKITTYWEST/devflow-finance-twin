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

# mixed_precision_train.py
import torch
from torch.cuda.amp import autocast, GradScaler
from agol_model import AGOLModel

def main():
    model = AGOLModel(layers=2, d=128, ff=256, heads=4, vocab=128).cuda()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    scaler = GradScaler()

    seq = 8
    x = torch.randint(0, 128, (seq,), device="cuda")
    target = x.clone()

    for step in range(10):
        opt.zero_grad(set_to_none=True)
        with autocast(dtype=torch.float16):
            logits = model(x)
            loss = torch.nn.functional.cross_entropy(logits, target)

        scaler.scale(loss).backward()
        scaler.step(opt)
        scaler.update()

        print(f"step {step} loss {loss.item()}")

if __name__ == "__main__":
    main()
