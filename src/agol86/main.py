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
from agol_model import AGOLModel
from agol_infer import infer_tokens
from export_onnx import export_onnx
from agol_jacobian import jacobian_fd
from mixed_precision_train import mp_train_step

def train_copy_step():
    model = AGOLModel(layers=2, d=128, ff=256, heads=4, vocab=128).cuda()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)

    x = torch.randint(0, 128, (8,), device="cuda")
    target = x.clone()

    logits = model(x)
    loss = torch.nn.functional.cross_entropy(logits, target)
    loss.backward()
    opt.step()

    torch.save(model.state_dict(), "agol86_transformer.pt")
    print("loss:", loss.item())
    return model

def jacobian_audit(model):
    x = torch.randint(0, 128, (8,), device="cuda").float()
    def f(vec):
        # simple projection: treat vec as embedding output
        return model.out(vec.view(8, -1))
    J = jacobian_fd(f, x)
    print("Jacobian shape:", J.shape)

if __name__ == "__main__":
    # 1. Train one copy-task step
    model = train_copy_step()

    # 2. Mixed-precision step (optional)
    mp_train_step()

    # 3. Inference
    probs = infer_tokens(model, [1, 2, 3, 4, 5, 6, 7, 8])
    print("probs shape:", probs.shape)

    # 4. ONNX export
    export_onnx()

    # 5. Jacobian audit
    jacobian_audit(model)
