# agol86_block.py
import torch
from agol86_activ import gelu
from agol86_attention import agol86_causal_attention

class AGOL86Block(torch.nn.Module):
    def __init__(self, d, ff, heads):
        super().__init__()
        self.ln1 = torch.nn.LayerNorm(d)
        self.ln2 = torch.nn.LayerNorm(d)

        self.wq = torch.nn.Linear(d, d)
        self.wk = torch.nn.Linear(d, d)
        self.wv = torch.nn.Linear(d, d)
        self.wo = torch.nn.Linear(d, d)

        self.w1 = torch.nn.Linear(d, ff)
        self.w2 = torch.nn.Linear(ff, d)

        self.heads = heads

    def forward(self, x):
        # x: [T,D]
        y = self.ln1(x)
        q = self.wq(y)
        k = self.wk(y)
        v = self.wv(y)

        attn_out, _ = agol86_causal_attention(q, k, v, self.heads)
        x = x + self.wo(attn_out)

        y = self.ln2(x)
        mlp = self.w2(gelu(self.w1(y)))
        return x + mlp
