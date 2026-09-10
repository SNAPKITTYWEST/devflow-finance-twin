// jit-webllm-toy-transformer.js
// Tiny decoder-only Transformer – pure JS, typed arrays, ready for WebGPU / WASM port
// Spec: vocab=512, d_model=64, n_heads=4, n_layers=2, d_ff=128, seq=32 (toy)
// ~180 lines. No FFI, no TensorFlow.js, no ONNX.
//
// How this relates to real WebLLM / JIT:
//   WebLLM (mlc-ai/web-llm) AOT-compiles via MLC-LLM + Apache TVM into WebGPU
//   shaders + WASM. This file is a pure, JIT-friendly reference: every op is
//   explicit, uses typed arrays, and can be mechanically lowered to WGSL compute
//   shaders or compiled to WASM. Same small dims as the BQN version.
//
// Next steps (production WebLLM):
//   import { CreateMLCEngine } from "@mlc-ai/web-llm";
//   const engine = await CreateMLCEngine("Llama-3.2-1B-Instruct-q4f16_1-MLC", {...});

"use strict";

// ─── Utilities ────────────────────────────────────────────────────────────
const f32 = (n) => new Float32Array(n);
const i32 = (n) => new Int32Array(n);

function matmul(A, B, m, k, n) { // A: m×k, B: k×n → C: m×n
  const C = f32(m * n);
  for (let i = 0; i < m; i++) {
    for (let j = 0; j < n; j++) {
      let s = 0;
      for (let p = 0; p < k; p++) s += A[i * k + p] * B[p * n + j];
      C[i * n + j] = s;
    }
  }
  return C;
}

function transpose(A, rows, cols) {
  const T = f32(rows * cols);
  for (let i = 0; i < rows; i++)
    for (let j = 0; j < cols; j++)
      T[j * rows + i] = A[i * cols + j];
  return T;
}

function softmax(x, len) { // stable, in-place friendly
  let max = -Infinity;
  for (let i = 0; i < len; i++) if (x[i] > max) max = x[i];
  let sum = 0;
  for (let i = 0; i < len; i++) {
    x[i] = Math.exp(x[i] - max);
    sum += x[i];
  }
  for (let i = 0; i < len; i++) x[i] /= sum;
  return x;
}

function layerNorm(x, dim) { // last-axis, no affine
  const n = x.length / dim;
  const out = f32(x.length);
  for (let i = 0; i < n; i++) {
    let mean = 0, var_ = 0;
    const base = i * dim;
    for (let j = 0; j < dim; j++) mean += x[base + j];
    mean /= dim;
    for (let j = 0; j < dim; j++) {
      const d = x[base + j] - mean;
      var_ += d * d;
    }
    const inv = 1 / Math.sqrt(var_ / dim + 1e-5);
    for (let j = 0; j < dim; j++) out[base + j] = (x[base + j] - mean) * inv;
  }
  return out;
}

function gelu(x) {
  const out = f32(x.length);
  for (let i = 0; i < x.length; i++) {
    const v = x[i];
    out[i] = 0.5 * v * (1 + Math.tanh(0.79788456 * (v + 0.044715 * v * v * v)));
  }
  return out;
}

// ─── Causal mask (boolean → large negative) ───────────────────────────────
function causalMask(seq) {
  const m = f32(seq * seq);
  for (let i = 0; i < seq; i++)
    for (let j = 0; j < seq; j++)
      m[i * seq + j] = j <= i ? 0 : -1e9;
  return m;
}

// ─── Single-head attention ────────────────────────────────────────────────
function singleHeadAttn(Q, K, V, seq, dHead) {
  const scale = 1 / Math.sqrt(dHead);
  const scores = matmul(Q, transpose(K, seq, dHead), seq, dHead, seq);
  for (let i = 0; i < scores.length; i++) scores[i] *= scale;

  const mask = causalMask(seq);
  for (let i = 0; i < scores.length; i++) scores[i] += mask[i];

  // row-wise softmax
  for (let i = 0; i < seq; i++) {
    const row = scores.subarray(i * seq, (i + 1) * seq);
    softmax(row, seq);
  }
  return matmul(scores, V, seq, seq, dHead);
}

// ─── Multi-head attention ─────────────────────────────────────────────────
function multiHeadAttn(X, Wq, Wk, Wv, Wo, seq, dModel, nHeads) {
  const dHead = dModel / nHeads;
  const Q = matmul(X, Wq, seq, dModel, dModel);
  const K = matmul(X, Wk, seq, dModel, dModel);
  const V = matmul(X, Wv, seq, dModel, dModel);

  // split heads → nHeads × (seq × dHead)
  const heads = [];
  for (let h = 0; h < nHeads; h++) {
    const Qh = f32(seq * dHead), Kh = f32(seq * dHead), Vh = f32(seq * dHead);
    for (let i = 0; i < seq; i++) {
      for (let j = 0; j < dHead; j++) {
        const idx = i * dModel + h * dHead + j;
        Qh[i * dHead + j] = Q[idx];
        Kh[i * dHead + j] = K[idx];
        Vh[i * dHead + j] = V[idx];
      }
    }
    heads.push(singleHeadAttn(Qh, Kh, Vh, seq, dHead));
  }

  // concat
  const O = f32(seq * dModel);
  for (let h = 0; h < nHeads; h++) {
    const H = heads[h];
    for (let i = 0; i < seq; i++)
      for (let j = 0; j < dHead; j++)
        O[i * dModel + h * dHead + j] = H[i * dHead + j];
  }
  return matmul(O, Wo, seq, dModel, dModel);
}

// ─── MLP ──────────────────────────────────────────────────────────────────
function mlp(X, W1, W2, seq, dModel, dFF) {
  const h = gelu(matmul(X, W1, seq, dModel, dFF));
  return matmul(h, W2, seq, dFF, dModel);
}

// ─── Transformer block ────────────────────────────────────────────────────
function transformerBlock(X, params, seq, dModel, nHeads, dFF) {
  const { Wq, Wk, Wv, Wo, W1, W2 } = params;
  let a = multiHeadAttn(X, Wq, Wk, Wv, Wo, seq, dModel, nHeads);
  for (let i = 0; i < X.length; i++) a[i] += X[i]; // residual
  a = layerNorm(a, dModel);

  let m = mlp(a, W1, W2, seq, dModel, dFF);
  for (let i = 0; i < a.length; i++) m[i] += a[i]; // residual
  return layerNorm(m, dModel);
}

// ─── Full model ───────────────────────────────────────────────────────────
function createModel(cfg) {
  const { vocab, dModel, nHeads, nLayers, dFF, seq } = cfg;
  const rand = (n) => {
    const a = f32(n);
    for (let i = 0; i < n; i++) a[i] = (Math.random() - 0.5) * 0.02;
    return a;
  };

  const Emb = rand(vocab * dModel);
  const Pos = rand(seq * dModel);
  const blocks = [];
  for (let l = 0; l < nLayers; l++) {
    blocks.push({
      Wq: rand(dModel * dModel), Wk: rand(dModel * dModel),
      Wv: rand(dModel * dModel), Wo: rand(dModel * dModel),
      W1: rand(dModel * dFF), W2: rand(dFF * dModel)
    });
  }
  const Unemb = rand(vocab * dModel); // tied or separate

  return function forward(tokens) { // tokens: Int32Array length ≤ seq
    const s = tokens.length;
    let X = f32(s * dModel);
    for (let i = 0; i < s; i++) {
      const tok = tokens[i];
      for (let j = 0; j < dModel; j++)
        X[i * dModel + j] = Emb[tok * dModel + j] + Pos[i * dModel + j];
    }
    for (const b of blocks) X = transformerBlock(X, b, s, dModel, nHeads, dFF);
    X = layerNorm(X, dModel);

    // logits = X @ Unembᵀ
    return matmul(X, transpose(Unemb, vocab, dModel), s, dModel, vocab);
  };
}

// ─── Demo ─────────────────────────────────────────────────────────────────
const cfg = { vocab: 512, dModel: 64, nHeads: 4, nLayers: 2, dFF: 128, seq: 32 };
const model = createModel(cfg);

const toks = i32(8);
for (let i = 0; i < 8; i++) toks[i] = (i * 7 + 3) % 512;

console.time("forward");
const logits = model(toks);
console.timeEnd("forward");
console.log("logits shape:", toks.length, "×", cfg.vocab);
console.log("first 5 logits of token 0:", Array.from(logits.subarray(0, 5)));
