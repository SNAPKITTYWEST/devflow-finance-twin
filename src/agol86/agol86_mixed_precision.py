# agol86_mixed_precision.py
import torch
from torch.cuda.amp import autocast, GradScaler
from agol86_model import AGOL86Model

def agol86_mp_step():
    model = AGOL86Model().cuda()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    scaler = GradScaler()

    x = torch.randint(0, 128, (8,), device="cuda")
    target = x.clone()

    opt.zero_grad(set_to_none=True)
    with autocast(dtype=torch.float16):
        logits = model(x)
        loss = torch.nn.functional.cross_entropy(logits, target)

    scaler.scale(loss).backward()
    scaler.step(opt)
    scaler.update()

    print("AGOL‑86 MP loss:", loss.item())
