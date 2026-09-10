import torch

def causal_attention(q, k, v, heads):
    t, d = q.shape
    dh = d // heads
    qh = q.view(t, heads, dh)
    kh = k.view(t, heads, dh)
    vh = v.view(t, heads, dh)

    scores = torch.einsum("thd,Thd->htT", qh, kh) / (dh**0.5)
    mask = torch.triu(torch.ones(t, t, device=q.device) * -1e9, diagonal=1)
    scores = scores + mask

    probs = torch.softmax(scores, dim=-1)
    out = torch.einsum("htT,Thd->thd", probs, vh)
    return out.reshape(t, d), probs
