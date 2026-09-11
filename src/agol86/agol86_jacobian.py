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

# agol86_jacobian.py
import torch

def agol86_jacobian_fd(f, x, h=1e-4):
    # x: flat vector [N]
    x = x.detach().clone()
    N = x.numel()
    J = torch.zeros(N, N, device=x.device)
    for col in range(N):
        xp = x.clone()
        xm = x.clone()
        xp[col] += h
        xm[col] -= h
        fp = f(xp).reshape(-1)
        fm = f(xm).reshape(-1)
        J[:, col] = (fp - fm) / (2*h)
    return J
