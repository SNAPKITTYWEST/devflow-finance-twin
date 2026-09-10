import torch

def gelu(x):
    return torch.nn.functional.gelu(x)

def layernorm(x, eps=1e-5):
    mu = x.mean(-1, keepdim=True)
    var = ((x - mu)**2).mean(-1, keepdim=True)
    rstd = torch.rsqrt(var + eps)
    return (x - mu) * rstd, mu, rstd
