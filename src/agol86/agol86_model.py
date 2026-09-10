# agol86_model.py
import torch
from agol86_block import AGOL86Block

class AGOL86Model(torch.nn.Module):
    def __init__(self, layers=2, d=128, ff=256, heads=4, vocab=128):
        super().__init__()
        self.vocab = vocab
        self.embed = torch.nn.Embedding(vocab, d)
        self.blocks = torch.nn.ModuleList(
            [AGOL86Block(d=d, ff=ff, heads=heads) for _ in range(layers)]
        )
        self.proj = torch.nn.Linear(d, vocab)

    def forward(self, tokens):
        # tokens: [T]
        h = self.embed(tokens)          # [T,D]
        for blk in self.blocks:
            h = blk(h)                  # transformer residual stack
        logits = self.proj(h)          # [T,V]
        return logits
