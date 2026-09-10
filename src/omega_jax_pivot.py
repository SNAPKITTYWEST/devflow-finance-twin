"""
OMEGA / JAX PIVOT
=================

INPUT
  PyTorch TransformerBlock
  PyTorch CausalSelfAttention

TARGET
  Pure functional JAX
  No nn.Module
  No torch
  No PyTorch runtime
  Explicit parameter PyTrees

PRESERVE EXACTLY
  Pre-LayerNorm
  Residual attention
  Residual MLP
  QKV fused projection
  n_head
  head_dim = d_model / n_head
  Q/K/V reshape
  head transpose
  QK^T
  1 / sqrt(head_dim)
  upper-triangular causal mask
  softmax over final axis
  attention @ V
  head merge
  output projection
  GELU
  4*d_model MLP expansion

JAX PRIMITIVES
  jax.numpy
  jax.nn.softmax
  jax.nn.gelu
  jax.jit
  jax.grad
  jax.vmap

PARAMETER TREE
  embedding
  blocks[]
    ln1
      scale
      bias
    attn
      c_attn
        weight
        bias
      c_proj
        weight
        bias
    ln2
      scale
      bias
    mlp
      fc1
        weight
        bias
      fc2
        weight
        bias
  final_ln

FORWARD CONTRACT

  x = embedding[token_ids]

  for block in blocks:

      h = layer_norm(x, block.ln1)

      qkv = linear(h, block.attn.c_attn)

      split qkv into q, k, v

      reshape:
        [B,T,C]
          ->
        [B,H,T,D]

      scores =
        q @ transpose(k)
        / sqrt(D)

      causal_mask =
        upper triangular positions above diagonal

      scores[future positions] = -infinity

      weights =
        softmax(scores, axis=-1)

      y =
        weights @ v

      reshape:
        [B,H,T,D]
          ->
        [B,T,C]

      attention_output =
        linear(y, c_proj)

      x =
        x + attention_output

      h =
        layer_norm(x, block.ln2)

      mlp_output =
        linear(
          GELU(
            linear(h, fc1)
          ),
          fc2
        )

      x =
        x + mlp_output

  x = final_layer_norm(x)

  logits = x @ lm_head

  return logits


VERIFICATION CONTRACT
=====================

TEST 01
  embedding shape

TEST 02
  QKV shape

TEST 03
  [B,T,C] -> [B,H,T,D]

TEST 04
  causal mask

TEST 05
  future-token attention == masked

TEST 06
  attention rows sum to 1

TEST 07
  residual dimensions

TEST 08
  MLP dimensions

TEST 09
  block output dimensions

TEST 10
  deterministic initialization

TEST 11
  JAX eager vs JAX JIT

TEST 12
  JAX forward vs supplied PyTorch forward

TEST 13
  gradient existence

TEST 14
  gradient shapes

TEST 15
  batched vmap equivalence

TEST 16
  autoregressive leakage test


OMEGA RULE
==========

Do NOT introduce:

  RoPE
  GQA
  MoE
  FlashAttention
  RMSNorm
  SwiGLU
  KV cache
  quantization
  custom CUDA
  Triton
  XLA-specific rewrites

until this baseline passes numerical parity.

BASELINE FIRST.
OPTIMIZATION SECOND.
"""

import math
import torch
import torch.nn as nn
import torch.nn.functional as F

class TransformerBlock(nn.Module):
    def __init__(self, d_model, n_head):
        super().__init__()
        self.ln1 = nn.LayerNorm(d_model)
        self.attn = CausalSelfAttention(d_model, n_head)
        self.ln2 = nn.LayerNorm(d_model)
        self.mlp = nn.Sequential(
            nn.Linear(d_model, 4 * d_model),
            nn.GELU(),
            nn.Linear(4 * d_model, d_model)
        )

    def forward(self, x):
        x = x + self.attn(self.ln1(x))
        x = x + self.mlp(self.ln2(x))
        return x

class CausalSelfAttention(nn.Module):
    def __init__(self, d_model, n_head):
        super().__init__()
        self.n_head = n_head
        self.head_dim = d_model // n_head
        self.c_attn = nn.Linear(d_model, 3 * d_model)
        self.c_proj = nn.Linear(d_model, d_model)

    def forward(self, x):
        B, T, C = x.size()
        q, k, v = self.c_attn(x).split(C, dim=2)

        q = q.view(B, T, self.n_head, self.head_dim).transpose(1, 2)
        k = k.view(B, T, self.n_head, self.head_dim).transpose(1, 2)
        v = v.view(B, T, self.n_head, self.head_dim).transpose(1, 2)

        att = (q @ k.transpose(-2, -1)) * (1.0 / math.sqrt(self.head_dim))
        mask = torch.triu(torch.full((T, T), float('-inf'), device=x.device), diagonal=1)
        att = F.softmax(att + mask, dim=-1)

        y = (att @ v).transpose(1, 2).contiguous().view(B, T, C)
        return self.c_proj(y)
