import torch
from agol_transformer import AGOLBlock

class AGOLModel(torch.nn.Module):
    def __init__(self, layers, d, ff, heads, vocab):
        super().__init__()
        self.embed = torch.nn.Embedding(vocab, d)
        self.blocks = torch.nn.ModuleList([AGOLBlock(d, ff, heads) for _ in range(layers)])
        self.out = torch.nn.Linear(d, vocab)

    def forward(self, x):
        h = self.embed(x)          # [T] -> [T,D]
        for blk in self.blocks:
            h = blk(h)             # transformer blocks
        return self.out(h)         # [T,V]
