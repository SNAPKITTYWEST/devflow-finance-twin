# Raw Metal Transformer

Apple Silicon-only, dependency-free Metal compute reference for incremental inference with per-row signed INT4 weights and FP16 activations/accumulation. It is an implementation target for a compressed ~3B decoder Transformer, not Apple's Siri implementation or weights.

## Model and memory contract

The default design is Llama-like GQA: 32 layers, hidden size 3072, intermediate size 8192, 24 query heads, 8 KV heads, head dimension 128, vocabulary 32,000, context 4096. It has approximately 3.0B logical parameters. INT4 packed weights require 1.50 GB for payload plus one FP16 scale per output row and optional zero-point metadata (roughly 1.51 GB total; embeddings and output may be separately configured). This is compression, not deletion of parameters.

For one layer, KV cache is `context * kv_heads * head_dim * 2 * sizeof(float16)`: 4096*8*128*2*2 = 16 MiB. Across 32 layers it is 512 MiB at maximum context. Hidden activations are O(hidden) for token-by-token decoding; the workspace is O(hidden + vocab) and is reused between kernels. Weights are immutable shared buffers; the KV cache is a private/shared-storage buffer selected by the host.

The shader separates compressed weights, dequantization, computation, and accumulation. `qmatvec_i4` and `qkv_projection_i4` unpack signed nibbles and multiply by per-row scales while accumulating in float. The host owns tokenizer policy and next-token selection.

## Build/run

```text
xcodebuild -scheme MetalTransformer -destination 'platform=macOS' test
```

The package is intentionally a small host-side interface rather than an inference framework. `MetalTransformer.swift` loads `Transformer.metal`, allocates aligned buffers, and exposes `encodeToken`/`generate`. Supply a real tokenizer and a packed checkpoint using the documented layouts.

The kernels are deterministic for fixed buffers and command ordering. GPU timing and utilization are device/OS dependent and must be measured with Xcode GPU counters; no benchmark number is claimed here.

## Audit contract

`Transformer.metal` contains dedicated kernels for embedding, RMSNorm, RoPE, INT4 matvec/QKV, attention scores with causal masking, stable softmax, attention-times-V, output projection, SwiGLU, residuals, final normalization, and logits. Every kernel has bounds checks. The Swift host uses one command queue, explicit command buffers, shared/private storage choices, 256-byte alignment for dynamic offsets, and completion synchronization.
