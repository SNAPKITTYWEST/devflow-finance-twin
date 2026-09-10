# agol86_attention.py
import torch

def agol86_causal_attention(q, k, v, heads):
    # q,k,v: [T,D]
    T, D = q.shape
    Dh = D // heads

    qh = q.view(T, heads, Dh)
    kh = k.view(T, heads, Dh)
    vh = v.view(T, heads, Dh)

    scores = torch.einsum("thd,Thd->htT", qh, kh) / (Dh**0.5)
    mask = torch.triu(torch.ones(T, T, device=q.device) * -1e9, diagonal=1)
    scores = scores + mask

    probs = torch.softmax(scores, dim=-1)
    out = torch.einsum("htT,Thd->thd", probs, vh)
    return out.reshape(T, D), probs
