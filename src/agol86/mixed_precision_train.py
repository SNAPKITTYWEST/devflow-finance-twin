# mixed_precision_train.py
import torch
from torch.cuda.amp import autocast, GradScaler
from agol_model import AGOLModel

def main():
    model = AGOLModel(layers=2, d=128, ff=256, heads=4, vocab=128).cuda()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    scaler = GradScaler()

    seq = 8
    x = torch.randint(0, 128, (seq,), device="cuda")
    target = x.clone()

    for step in range(10):
        opt.zero_grad(set_to_none=True)
        with autocast(dtype=torch.float16):
            logits = model(x)
            loss = torch.nn.functional.cross_entropy(logits, target)

        scaler.scale(loss).backward()
        scaler.step(opt)
        scaler.update()

        print(f"step {step} loss {loss.item()}")

if __name__ == "__main__":
    main()
