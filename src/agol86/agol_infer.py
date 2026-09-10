# agol_infer.py
import torch
from agol_model import AGOLModel

def load_model(path, vocab=128, d=128, ff=256, heads=4, layers=2):
    model = AGOLModel(layers=layers, d=d, ff=ff, heads=heads, vocab=vocab).cuda()
    sd = torch.load(path, map_location="cuda")
    model.load_state_dict(sd)
    model.eval()
    return model

@torch.no_grad()
def infer_tokens(model, tokens):
    x = torch.tensor(tokens, dtype=torch.long, device="cuda")
    logits = model(x)
    probs = torch.softmax(logits, dim=-1)
    return probs

if __name__ == "__main__":
    model = load_model("agol_transformer.pt")
    tokens = [1, 2, 3, 4, 5, 6, 7, 8]
    probs = infer_tokens(model, tokens)
    print("probs shape:", probs.shape)
