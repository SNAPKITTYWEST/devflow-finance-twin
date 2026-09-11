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

# main_agol86.py
import torch
from agol86_model import AGOL86Model
from agol86_infer import agol86_infer_tokens
from agol86_export_onnx import export_agol86_onnx
from agol86_jacobian import agol86_jacobian_fd
from agol86_mixed_precision import agol86_mp_step

def train_copy_step():
    model = AGOL86Model().cuda()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)

    x = torch.randint(0, 128, (8,), device="cuda")
    target = x.clone()

    logits = model(x)
    loss = torch.nn.functional.cross_entropy(logits, target)
    loss.backward()
    opt.step()

    torch.save(model.state_dict(), "agol86.pt")
    print("AGOLâ€‘86 loss:", loss.item())
    return model

def jacobian_audit(model):
    # audit projection layer on a flat vector
    x = torch.randn(8 * 128, device="cuda")
    def f(vec):
        return model.proj(vec.view(8, 128))
    J = agol86_jacobian_fd(f, x)
    print("AGOLâ€‘86 Jacobian shape:", J.shape)

if __name__ == "__main__":
    m = train_copy_step()
    agol86_mp_step()
    probs = agol86_infer_tokens(m, [1,2,3,4,5,6,7,8])
    print("AGOLâ€‘86 probs shape:", probs.shape)
    export_agol86_onnx()
    jacobian_audit(m)
