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
