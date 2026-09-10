# ddp_train.py
import os
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from agol_model import AGOLModel

def setup_ddp():
    dist.init_process_group(backend="nccl")
    torch.cuda.set_device(int(os.environ["LOCAL_RANK"]))

def cleanup_ddp():
    dist.destroy_process_group()

def main():
    setup_ddp()
    rank = dist.get_rank()
    device = torch.device("cuda", int(os.environ["LOCAL_RANK"]))

    model = AGOLModel(layers=2, d=128, ff=256, heads=4, vocab=128).to(device)
    ddp_model = DDP(model, device_ids=[device])

    opt = torch.optim.Adam(ddp_model.parameters(), lr=1e-3)

    seq = 8
    x = torch.randint(0, 128, (seq,), device=device)
    target = x.clone()

    logits = ddp_model(x)
    loss = torch.nn.functional.cross_entropy(logits, target)

    loss.backward()
    opt.step()

    if rank == 0:
        print("DDP loss:", loss.item())

    cleanup_ddp()

if __name__ == "__main__":
    main()
