import struct, json, os, hashlib
import torch, torch.nn as nn
import numpy as np

GGUFMAGIC, GGUFVERSION, ALIGN = b"GGUF", 3, 32
TU32, TSTR, TF32, TBOOL = 4, 8, 10, 11
Q4K_TYPE = 6

def gstr(s):
    b = s.encode(); return struct.pack("<Q", len(b)) + b

def kv(k, t, v):
    return gstr(k) + struct.pack("<I", t) + v

class GLMInvertedBlock(nn.Module):
    def __init__(self, dmodel=64, nheads=4):
        super().__init__()
        self.attn = nn.MultiheadAttention(dmodel, nheads, batch_first=True)
        self.ln1 = nn.LayerNorm(dmodel)
        self.mlp = nn.Sequential(nn.Linear(dmodel, dmodel*2), nn.GELU(), nn.Linear(d_model*2, dmodel))
        self.ln2 = nn.LayerNorm(dmodel)

    def forward(self, x):
        a, _ = self.attn(x, x, x); x = self.ln1(x + a)
        return self.ln2(x + self.mlp(x))

def quantize_q4k(flat):
    n = flat.shape[0]; pad = (-n) % 32
    padded = np.concatenate([flat, np.zeros(pad, dtype=np.float32)])
    blocks = padded.reshape(-1, 32)
    out = np.empty((blocks.shape[0], 20), dtype=np.uint8)

    for i, blk in enumerate(blocks):
        mx, mn = float(blk.max()), float(blk.min())
        scale = (mx - mn) / 15.0 if mx != mn else 1.0
        q = np.clip(np.round((blk - mn) / scale), 0, 15).astype(np.uint8)
        packed = (q[0::2] | (q[1::2] << 4)).astype(np.uint8)
        out[i, 0:2] = np.frombuffer(np.float16(scale).tobytes(), dtype=np.uint8)
        out[i, 2:4] = np.frombuffer(np.float16(mn).tobytes(), dtype=np.uint8)
        out[i, 4:] = packed

    return out, pad

def dequantize_q4k(q):
    nb = q.shape[0]
    out = np.empty(nb * 32, dtype=np.float32)

    for i in range(nb):
        scale = float(np.frombuffer(q[i, 0:2].tobytes(), dtype=np.float16)[0])
        mn = float(np.frombuffer(q[i, 2:4].tobytes(), dtype=np.float16)[0])
        packed = q[i, 4:]
        vals = np.empty(32, dtype=np.float32)
        vals[0::2] = (packed & 0x0F); vals[1::2] = (packed >> 4)
        out[i*32:(i+1)*32] = vals * scale + mn

    return out

print("=== Q4K-STYLE BLOCK QUANTIZATION ===")

torch.manual_seed(42)
model = GLMInvertedBlock()
fp32state = {n: p.contiguous() for n, p in model.state_dict().items()}

quantstate = {}
snrs = []
totalq = totalorig = 0

for name, t in fp32state.items():
    flat = t.numpy().flatten().astype(np.float32)
    norig = flat.size * 4
    totalorig += norig

    if flat.size < 32:
        quantstate[name] = ("FP32", t.numpy().copy())
        totalq += norig
        print(f" {name:<28} FP32 (small, {norig} B)")
    else:
        q, pad = quantize_q4k(flat)
        deq = dequantize_q4k(q)
        if pad: deq = deq[:-pad]

        mse = ((flat - deq)**2).mean(); sig = (flat**2).mean()
        snr = 10 * np.log10(sig / mse) if mse > 0 else float('inf')
        snrs.append(snr)

        quantstate[name] = ("Q4K", q, t.shape, pad)
        totalq += q.nbytes
        print(f" {name:<28} {norig:>6} B -> Q4K {q.nbytes:>6} B SNR={snr:.1f} dB")

ratio = totalq / totalorig * 100
print(f"\n TOTAL: {totalorig:,} B -> {totalq:,} B ({ratio:.1f}%) | avg SNR: {np.mean(snrs):.1f} dB")

meta = (kv("general.architecture", TSTR, gstr("sovereign-glm-block"))
       + kv("general.name", TSTR, gstr("Sovereign GLM Block Q4K"))
       + kv("sovereign-glm-block.embeddinglength", TU32, struct.pack("<I", 64))
       + kv("sovereign-glm-block.attention.headcount", TU32, struct.pack("<I", 4))
       + kv("sovereign-glm-block.filetype", TSTR, gstr("Q4_K (4.5-bit effective)"))
       + kv("general.quantization", TSTR, gstr("blockwise 32-value, fp16 scale+min, packed nibbles"))
       + kv("general.quantization_snr_db", TF32, struct.pack("<f", float(np.mean(snrs))))
       + kv("general.quantized_version_available", TBOOL, struct.pack("<B", 1)))

tensorinfos = b""
datablob = b""
order = sorted(quantstate, key=lambda n: quantstate[n][1].nbytes if quantstate[n][0]=='Q4K' else quantstate[n][1].size*4, reverse=True)

for name in order:
    e = quantstate[name]
    if e[0] == "Q4K":
        blob, nbytes, isq = e[1].tobytes(), e[1].nbytes, True
    else:
        blob, nbytes, is_q = e[1].tobytes(), e[1].size*4, False

    info = gstr(name) + struct.pack("<I", Q4K_TYPE if isq else 0)
    info += struct.pack("<Q", 1) + struct.pack("<Q", nbytes)
    info += struct.pack("<Q", len(datablob))
    tensorinfos += info
    datablob += blob
    datablob += b"\x00" * ((ALIGN - len(datablob) % ALIGN) % ALIGN)

header = GGUFMAGIC + struct.pack("<I", GGUFVERSION) + struct.pack("<Q", len(quantstate)) + struct.pack("<Q", 8)
ggufbytes = header + meta + tensorinfos + datablob

qpath = "/mnt/data/sovereignglmblockq4k.gguf"
open(qpath, "wb").write(ggufbytes)
qsize, qsha = os.path.getsize(qpath), hashlib.sha256(ggufbytes).hexdigest()

print(f"\n=== Q4K GGUF ===\n {qpath}\n {qsize:,} B | sha256={qsha[:20]}...")

print("\n=== INFERENCE FIDELITY TEST ===")

modelq = GLMInvertedBlock()
deqstate = {}

for name, e in quantstate.items():
    if e[0] == "Q4K":
        d = dequantize_q4k(e[1])
        if e[3]: d = d[:-e[3]]
        deqstate[name] = torch.from_numpy(d.reshape(e[2]).astype(np.float32))
    else:
        deqstate[name] = torch.from_numpy(e[1].copy())

modelq.load_state_dict(deqstate)
model.eval(); modelq.eval()

torch.manual_seed(7)
x = torch.randn(1, 16, 64)

with torch.no_grad():
    y32, yq = model(x), modelq(x)
    relmse = ((y32-yq)**2).mean().item() / (y32**2).mean().item()
    cos = torch.nn.functional.cosine_similarity(y32.flatten(), yq.flatten(), dim=0).item()

print(f" relative MSE : {relmse:.6f} ({relmse*100:.3f}%)")
print(f" cosine similarity: {cos:.6f}")
print(f" max |delta| : {float((y32-yq).abs().max()):.6f}")
print(f" fidelity : {'EXCELLENT' if cos > 0.99 else 'GOOD' if cos > 0.95 else 'DEGRADED'}")

manifest = {
    "manifestversion": "v1",
    "modelname": "sovereign-glm-block",
    "totalparameters": 33472,
    "quantization": {
        "method": "Q4K-style blockwise (32-value blocks)",
        "fp32bytes": totalorig,
        "q4kbytes": totalq,
        "compressionpct": round(ratio, 1),
        "avgsnrdb": round(float(np.mean(snrs)), 1),
        "inferencecosinesimilarity": round(cos, 6),
        "inferencerelativemse": round(relmse, 8)
    },
    "files": [
        {"filename": "sovereignglmblockq4k.gguf", "format": "gguf", "quant": "Q4K", "sizebytes": qsize, "sha256": qsha}
    ]
}

json.dump(manifest, open("/mnt/data/manifest.json", "w"), indent=2)
print("[manifest.json updated]")
