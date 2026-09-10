# agol86_export_onnx.py
import torch
from agol86_model import AGOL86Model

def export_agol86_onnx(path="agol86.onnx", vocab=128, d=128, ff=256, heads=4, layers=2):
    model = AGOL86Model(layers=layers, d=d, ff=ff, heads=heads, vocab=vocab).cuda()
    model.eval()
    dummy = torch.randint(0, vocab, (8,), device="cuda")

    torch.onnx.export(
        model,
        dummy,
        path,
        input_names=["tokens"],
        output_names=["logits"],
        opset_version=17,
        dynamic_axes={"tokens": {0: "seq_len"}, "logits": {0: "seq_len"}},
    )
