# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

#!/usr/bin/env python3
"""
Pure JAX Transformer Harness

Functional transformer implementation derived from the supplied PyTorch
pre-LayerNorm causal self-attention architecture.

Dependencies:
    jax
    jaxlib

The implementation keeps model parameters in JAX PyTrees and exposes
forward, loss, gradients, JIT, generation, verification, serialization,
and a small command-line harness.
"""

from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Tuple

import jax
import jax.numpy as jnp
import jax.nn as jnn


Array = jax.Array
PyTree = Any


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class TransformerConfig:
    vocab_size: int = 256
    d_model: int = 128
    n_head: int = 4
    n_layer: int = 4
    mlp_ratio: int = 4
    max_seq_len: int = 128
    dropout: float = 0.0
    layer_norm_eps: float = 1e-5
    seed: int = 0

    def validate(self) -> None:
        if self.vocab_size <= 0:
            raise ValueError("vocab_size must be positive")
        if self.d_model <= 0:
            raise ValueError("d_model must be positive")
        if self.n_head <= 0:
            raise ValueError("n_head must be positive")
        if self.d_model % self.n_head != 0:
            raise ValueError("d_model must be divisible by n_head")
        if self.n_layer <= 0:
            raise ValueError("n_layer must be positive")
        if self.mlp_ratio <= 0:
            raise ValueError("mlp_ratio must be positive")
        if self.max_seq_len <= 0:
            raise ValueError("max_seq_len must be positive")
        if self.dropout < 0.0 or self.dropout >= 1.0:
            raise ValueError("dropout must satisfy 0 <= dropout < 1")

    @property
    def head_dim(self) -> int:
        return self.d_model // self.n_head

    @property
    def mlp_dim(self) -> int:
        return self.mlp_ratio * self.d_model


# ---------------------------------------------------------------------------
# Array and shape helpers
# ---------------------------------------------------------------------------

def as_array(x: Any, dtype: Optional[Any] = None) -> Array:
    return jnp.asarray(x, dtype=dtype)


def check_rank(x: Array, rank: int, name: str) -> None:
    if x.ndim != rank:
        raise ValueError(f"{name} must have rank {rank}, got {x.ndim}")


def check_last_dim(x: Array, size: int, name: str) -> None:
    if x.shape[-1] != size:
        raise ValueError(
            f"{name} last dimension must be {size}, got {x.shape[-1]}"
        )


def flatten_tree_size(tree: PyTree) -> int:
    leaves = jax.tree_util.tree_leaves(tree)
    return sum(int(leaf.size) for leaf in leaves)


def tree_all_finite(tree: PyTree) -> bool:
    leaves = jax.tree_util.tree_leaves(tree)
    return all(bool(jnp.all(jnp.isfinite(leaf))) for leaf in leaves)


def tree_max_abs(tree: PyTree) -> float:
    leaves = jax.tree_util.tree_leaves(tree)
    if not leaves:
        return 0.0
    return float(max(float(jnp.max(jnp.abs(x))) for x in leaves))


# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------

def fan_in_scale(fan_in: int) -> float:
    return 1.0 / math.sqrt(float(fan_in))


def init_weight(
    key: Array,
    fan_in: int,
    fan_out: int,
    dtype: Any = jnp.float32,
) -> Array:
    scale = fan_in_scale(fan_in)
    return (
        jax.random.normal(
            key,
            shape=(fan_in, fan_out),
            dtype=dtype,
        )
        * scale
    )


def init_bias(
    size: int,
    dtype: Any = jnp.float32,
) -> Array:
    return jnp.zeros((size,), dtype=dtype)


def init_linear(
    key: Array,
    fan_in: int,
    fan_out: int,
    dtype: Any = jnp.float32,
) -> Dict[str, Array]:
    weight_key, _ = jax.random.split(key)
    return {
        "weight": init_weight(
            weight_key,
            fan_in,
            fan_out,
            dtype,
        ),
        "bias": init_bias(
            fan_out,
            dtype,
        ),
    }


def init_layer_norm(
    d_model: int,
    dtype: Any = jnp.float32,
) -> Dict[str, Array]:
    return {
        "scale": jnp.ones((d_model,), dtype=dtype),
        "bias": jnp.zeros((d_model,), dtype=dtype),
    }


def init_embedding(
    key: Array,
    vocab_size: int,
    d_model: int,
    dtype: Any = jnp.float32,
) -> Array:
    scale = fan_in_scale(d_model)
    return (
        jax.random.normal(
            key,
            (vocab_size, d_model),
            dtype=dtype,
        )
        * scale
    )


def init_attention(
    key: Array,
    d_model: int,
    dtype: Any = jnp.float32,
) -> Dict[str, Any]:
    k_qkv, k_proj = jax.random.split(key)
    return {
        "c_attn": init_linear(
            k_qkv,
            d_model,
            3 * d_model,
            dtype,
        ),
        "c_proj": init_linear(
            k_proj,
            d_model,
            d_model,
            dtype,
        ),
    }


def init_mlp(
    key: Array,
    d_model: int,
    mlp_dim: int,
    dtype: Any = jnp.float32,
) -> Dict[str, Any]:
    k_fc1, k_fc2 = jax.random.split(key)
    return {
        "fc1": init_linear(
            k_fc1,
            d_model,
            mlp_dim,
            dtype,
        ),
        "fc2": init_linear(
            k_fc2,
            mlp_dim,
            d_model,
            dtype,
        ),
    }


def init_block(
    key: Array,
    config: TransformerConfig,
    dtype: Any = jnp.float32,
) -> Dict[str, Any]:
    k_attn, k_mlp = jax.random.split(key)
    return {
        "ln1": init_layer_norm(
            config.d_model,
            dtype,
        ),
        "attn": init_attention(
            k_attn,
            config.d_model,
            dtype,
        ),
        "ln2": init_layer_norm(
            config.d_model,
            dtype,
        ),
        "mlp": init_mlp(
            k_mlp,
            config.d_model,
            config.mlp_dim,
            dtype,
        ),
    }


def init_transformer(
    key: Array,
    config: TransformerConfig,
    dtype: Any = jnp.float32,
) -> Dict[str, Any]:
    config.validate()

    keys = jax.random.split(
        key,
        config.n_layer + 2,
    )

    blocks = tuple(
        init_block(
            keys[index + 1],
            config,
            dtype,
        )
        for index in range(config.n_layer)
    )

    return {
        "token_embedding": init_embedding(
            keys[0],
            config.vocab_size,
            config.d_model,
            dtype,
        ),
        "blocks": blocks,
        "final_ln": init_layer_norm(
            config.d_model,
            dtype,
        ),
        "lm_head": init_linear(
            keys[-1],
            config.d_model,
            config.vocab_size,
            dtype,
        ),
    }


# ---------------------------------------------------------------------------
# Primitive layers
# ---------------------------------------------------------------------------

def linear(
    x: Array,
    params: Mapping[str, Array],
) -> Array:
    return jnp.matmul(
        x,
        params["weight"],
    ) + params["bias"]


def layer_norm(
    x: Array,
    params: Mapping[str, Array],
    eps: float = 1e-5,
) -> Array:
    mean = jnp.mean(
        x,
        axis=-1,
        keepdims=True,
    )
    variance = jnp.mean(
        jnp.square(x - mean),
        axis=-1,
        keepdims=True,
    )
    normalized = (
        x - mean
    ) / jnp.sqrt(
        variance + eps,
    )
    return (
        normalized * params["scale"]
        + params["bias"]
    )


def token_embedding(
    embedding: Array,
    token_ids: Array,
) -> Array:
    return embedding[token_ids]


def gelu(
    x: Array,
) -> Array:
    return jnn.gelu(x)


# ---------------------------------------------------------------------------
# Causal mask
# ---------------------------------------------------------------------------

def causal_mask(
    sequence_length: int,
) -> Array:
    return jnp.triu(
        jnp.ones(
            (
                sequence_length,
                sequence_length,
            ),
            dtype=bool,
        ),
        k=1,
    )


def additive_causal_mask(
    sequence_length: int,
    dtype: Any = jnp.float32,
) -> Array:
    mask = causal_mask(sequence_length)
    return jnp.where(
        mask,
        jnp.asarray(-jnp.inf, dtype=dtype),
        jnp.asarray(0.0, dtype=dtype),
    )


# ---------------------------------------------------------------------------
# Attention tensor transformations
# ---------------------------------------------------------------------------

def split_qkv(
    qkv: Array,
    d_model: int,
) -> Tuple[Array, Array, Array]:
    check_last_dim(
        qkv,
        3 * d_model,
        "qkv",
    )
    q, k, v = jnp.split(
        qkv,
        3,
        axis=-1,
    )
    return q, k, v


def reshape_heads(
    x: Array,
    n_head: int,
) -> Array:
    check_rank(
        x,
        3,
        "head input",
    )
    batch, sequence, channels = x.shape
    if channels % n_head != 0:
        raise ValueError(
            "channel dimension must be divisible by n_head"
        )
    head_dim = channels // n_head
    return x.reshape(
        batch,
        sequence,
        n_head,
        head_dim,
    ).transpose(
        0,
        2,
        1,
        3,
    )


def merge_heads(
    x: Array,
) -> Array:
    check_rank(
        x,
        4,
        "head tensor",
    )
    batch, heads, sequence, head_dim = x.shape
    return x.transpose(
        0,
        2,
        1,
        3,
    ).reshape(
        batch,
        sequence,
        heads * head_dim,
    )


# ---------------------------------------------------------------------------
# Causal self-attention
# ---------------------------------------------------------------------------

def scaled_dot_product_attention(
    q: Array,
    k: Array,
    v: Array,
    causal: bool = True,
) -> Tuple[Array, Array]:
    head_dim = q.shape[-1]

    scores = jnp.matmul(
        q,
        jnp.swapaxes(
            k,
            -1,
            -2,
        ),
    )

    scores = scores / jnp.sqrt(
        jnp.asarray(
            head_dim,
            dtype=q.dtype,
        ),
    )

    if causal:
        sequence_length = q.shape[-2]
        mask = causal_mask(
            sequence_length,
        )
        scores = jnp.where(
            mask[None, None, :, :],
            -jnp.inf,
            scores,
        )

    weights = jnn.softmax(
        scores,
        axis=-1,
    )

    output = jnp.matmul(
        weights,
        v,
    )

    return output, weights


def causal_self_attention(
    params: Mapping[str, Any],
    x: Array,
    n_head: int,
) -> Tuple[Array, Array]:
    check_rank(
        x,
        3,
        "attention input",
    )

    batch, sequence, d_model = x.shape

    qkv = linear(
        x,
        params["c_attn"],
    )

    q, k, v = split_qkv(
        qkv,
        d_model,
    )

    q = reshape_heads(
        q,
        n_head,
    )

    k = reshape_heads(
        k,
        n_head,
    )

    v = reshape_heads(
        v,
        n_head,
    )

    y, weights = scaled_dot_product_attention(
        q,
        k,
        v,
        causal=True,
    )

    y = merge_heads(
        y,
    )

    output = linear(
        y,
        params["c_proj"],
    )

    return output, weights


# ---------------------------------------------------------------------------
# MLP
# ---------------------------------------------------------------------------

def feed_forward(
    params: Mapping[str, Any],
    x: Array,
) -> Array:
    x = linear(
        x,
        params["fc1"],
    )
    x = gelu(x)
    x = linear(
        x,
        params["fc2"],
    )
    return x


# ---------------------------------------------------------------------------
# Transformer block
# ---------------------------------------------------------------------------

def transformer_block(
    params: Mapping[str, Any],
    x: Array,
    config: TransformerConfig,
) -> Tuple[Array, Array]:
    normalized = layer_norm(
        x,
        params["ln1"],
        config.layer_norm_eps,
    )

    attention_output, weights = causal_self_attention(
        params["attn"],
        normalized,
        config.n_head,
    )

    x = x + attention_output

    normalized = layer_norm(
        x,
        params["ln2"],
        config.layer_norm_eps,
    )

    mlp_output = feed_forward(
        params["mlp"],
        normalized,
    )

    x = x + mlp_output

    return x, weights


# ---------------------------------------------------------------------------
# Transformer forward
# ---------------------------------------------------------------------------

def transformer_hidden(
    params: Mapping[str, Any],
    token_ids: Array,
    config: TransformerConfig,
) -> Tuple[Array, Tuple[Array, ...]]:
    check_rank(
        token_ids,
        2,
        "token_ids",
    )

    if token_ids.shape[1] > config.max_seq_len:
        raise ValueError(
            "sequence exceeds max_seq_len"
        )

    x = token_embedding(
        params["token_embedding"],
        token_ids,
    )

    attention_history: List[Array] = []

    for block in params["blocks"]:
        x, weights = transformer_block(
            block,
            x,
            config,
        )
        attention_history.append(weights)

    x = layer_norm(
        x,
        params["final_ln"],
        config.layer_norm_eps,
    )

    return x, tuple(attention_history)


def transformer(
    params: Mapping[str, Any],
    token_ids: Array,
    config: TransformerConfig,
) -> Array:
    hidden, _ = transformer_hidden(
        params,
        token_ids,
        config,
    )

    return linear(
        hidden,
        params["lm_head"],
    )


# ---------------------------------------------------------------------------
# Loss
# ---------------------------------------------------------------------------

def cross_entropy(
    logits: Array,
    targets: Array,
) -> Array:
    log_probs = jnn.log_softmax(
        logits,
        axis=-1,
    )

    selected = jnp.take_along_axis(
        log_probs,
        targets[..., None],
        axis=-1,
    )

    return -jnp.mean(
        selected[..., 0],
    )


def next_token_loss(
    params: Mapping[str, Any],
    token_ids: Array,
    config: TransformerConfig,
) -> Array:
    if token_ids.shape[1] < 2:
        raise ValueError(
            "next_token_loss requires at least two tokens"
        )

    inputs = token_ids[:, :-1]
    targets = token_ids[:, 1:]

    logits = transformer(
        params,
        inputs,
        config,
    )

    return cross_entropy(
        logits,
        targets,
    )


def loss_and_grad(
    params: Mapping[str, Any],
    token_ids: Array,
    config: TransformerConfig,
) -> Tuple[Array, PyTree]:
    value, grads = jax.value_and_grad(
        next_token_loss,
    )(
        params,
        token_ids,
        config,
    )
    return value, grads


# ---------------------------------------------------------------------------
# JIT compiled entry points
# ---------------------------------------------------------------------------

def build_jitted_forward(
    config: TransformerConfig,
):
    return jax.jit(
        lambda params, token_ids:
        transformer(
            params,
            token_ids,
            config,
        )
    )


def build_jitted_loss(
    config: TransformerConfig,
):
    return jax.jit(
        lambda params, token_ids:
        next_token_loss(
            params,
            token_ids,
            config,
        )
    )


def build_jitted_loss_grad(
    config: TransformerConfig,
):
    return jax.jit(
        jax.value_and_grad(
            lambda params, token_ids:
            next_token_loss(
                params,
                token_ids,
                config,
            )
        )
    )


# ---------------------------------------------------------------------------
# Optimizer: minimal Adam
# ---------------------------------------------------------------------------

def zeros_like_tree(
    tree: PyTree,
) -> PyTree:
    return jax.tree_util.tree_map(
        jnp.zeros_like,
        tree,
    )


def tree_map2(
    fn,
    left: PyTree,
    right: PyTree,
) -> PyTree:
    return jax.tree_util.tree_map(
        fn,
        left,
        right,
    )


def tree_map3(
    fn,
    a: PyTree,
    b: PyTree,
    c: PyTree,
) -> PyTree:
    return jax.tree_util.tree_map(
        fn,
        a,
        b,
        c,
    )


@dataclass
class AdamState:
    step: int
    m: PyTree
    v: PyTree


def adam_init(
    params: PyTree,
) -> AdamState:
    zeros = zeros_like_tree(params)
    return AdamState(
        step=0,
        m=zeros,
        v=zeros,
    )


def adam_update(
    params: PyTree,
    grads: PyTree,
    state: AdamState,
    learning_rate: float = 1e-3,
    beta1: float = 0.9,
    beta2: float = 0.999,
    eps: float = 1e-8,
    weight_decay: float = 0.0,
) -> Tuple[PyTree, AdamState]:

    step = state.step + 1

    m = tree_map3(
        lambda m, g, _: beta1 * m + (1.0 - beta1) * g,
        state.m,
        grads,
        params,
    )

    v = tree_map3(
        lambda v, g, _: beta2 * v + (1.0 - beta2) * jnp.square(g),
        state.v,
        grads,
        params,
    )

    bias_correction_1 = 1.0 - beta1 ** step
    bias_correction_2 = 1.0 - beta2 ** step

    def update_leaf(p, mm, vv):
        m_hat = mm / bias_correction_1
        v_hat = vv / bias_correction_2
        update = m_hat / (
            jnp.sqrt(v_hat) + eps
        )
        if weight_decay != 0.0:
            update = update + weight_decay * p
        return p - learning_rate * update

    new_params = tree_map3(
        update_leaf,
        params,
        m,
        v,
    )

    return new_params, AdamState(
        step=step,
        m=m,
        v=v,
    )


# ---------------------------------------------------------------------------
# Gradient utilities
# ---------------------------------------------------------------------------

def global_grad_norm(
    grads: PyTree,
) -> Array:
    leaves = jax.tree_util.tree_leaves(
        grads,
    )

    squared = [
        jnp.sum(
            jnp.square(
                jnp.asarray(leaf),
            )
        )
        for leaf in leaves
    ]

    if not squared:
        return jnp.asarray(0.0)

    return jnp.sqrt(
        jnp.sum(
            jnp.stack(squared),
        )
    )


def clip_gradients(
    grads: PyTree,
    max_norm: float,
) -> PyTree:
    norm = global_grad_norm(
        grads,
    )

    scale = jnp.minimum(
        1.0,
        max_norm / (norm + 1e-6),
    )

    return jax.tree_util.tree_map(
        lambda x: x * scale,
        grads,
    )


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

def train_step(
    params: PyTree,
    optimizer_state: AdamState,
    token_ids: Array,
    config: TransformerConfig,
    learning_rate: float,
    grad_clip: Optional[float],
) -> Tuple[PyTree, AdamState, float, float]:

    loss, grads = loss_and_grad(
        params,
        token_ids,
        config,
    )

    if grad_clip is not None:
        grads = clip_gradients(
            grads,
            grad_clip,
        )

    grad_norm = global_grad_norm(
        grads,
    )

    params, optimizer_state = adam_update(
        params,
        grads,
        optimizer_state,
        learning_rate=learning_rate,
    )

    return (
        params,
        optimizer_state,
        float(loss),
        float(grad_norm),
    )


def synthetic_batch(
    key: Array,
    batch_size: int,
    sequence_length: int,
    vocab_size: int,
) -> Array:
    return jax.random.randint(
        key,
        shape=(
            batch_size,
            sequence_length,
        ),
        minval=0,
        maxval=vocab_size,
        dtype=jnp.int32,
    )


def train_synthetic(
    params: PyTree,
    config: TransformerConfig,
    steps: int,
    batch_size: int,
    learning_rate: float,
    grad_clip: Optional[float] = 1.0,
) -> Tuple[PyTree, AdamState, List[Dict[str, float]]]:

    optimizer_state = adam_init(
        params,
    )

    key = jax.random.PRNGKey(
        config.seed + 100,
    )

    history: List[Dict[str, float]] = []

    for step in range(steps):
        key, batch_key = jax.random.split(
            key,
        )

        batch = synthetic_batch(
            batch_key,
            batch_size,
            min(config.max_seq_len, 32),
            config.vocab_size,
        )

        params, optimizer_state, loss, grad_norm = train_step(
            params,
            optimizer_state,
            batch,
            config,
            learning_rate,
            grad_clip,
        )

        record = {
            "step": float(step + 1),
            "loss": loss,
            "grad_norm": grad_norm,
        }

        history.append(record)

    return params, optimizer_state, history


# ---------------------------------------------------------------------------
# Sampling and generation
# ---------------------------------------------------------------------------

def logits_at_last_position(
    params: PyTree,
    token_ids: Array,
    config: TransformerConfig,
) -> Array:
    logits = transformer(
        params,
        token_ids,
        config,
    )
    return logits[:, -1, :]


def sample_from_logits(
    key: Array,
    logits: Array,
    temperature: float = 1.0,
) -> Array:
    if temperature <= 0.0:
        return jnp.argmax(
            logits,
            axis=-1,
        )

    scaled = logits / temperature

    return jax.random.categorical(
        key,
        scaled,
        axis=-1,
    )


def greedy_from_logits(
    logits: Array,
) -> Array:
    return jnp.argmax(
        logits,
        axis=-1,
    )


def generate(
    params: PyTree,
    prompt: Array,
    config: TransformerConfig,
    max_new_tokens: int,
    key: Array,
    temperature: float = 1.0,
    greedy: bool = False,
) -> Array:

    tokens = prompt

    for _ in range(max_new_tokens):
        context = tokens[:, -config.max_seq_len:]

        logits = logits_at_last_position(
            params,
            context,
            config,
        )

        if greedy:
            next_token = greedy_from_logits(
                logits,
            )
        else:
            key, sample_key = jax.random.split(
                key,
            )
            next_token = sample_from_logits(
                sample_key,
                logits,
                temperature,
            )

        tokens = jnp.concatenate(
            [
                tokens,
                next_token[:, None],
            ],
            axis=1,
        )

    return tokens


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify_parameter_shapes(
    params: Mapping[str, Any],
    config: TransformerConfig,
) -> None:
    embedding = params["token_embedding"]

    assert embedding.shape == (
        config.vocab_size,
        config.d_model,
    )

    assert len(params["blocks"]) == config.n_layer

    for block in params["blocks"]:
        assert block["ln1"]["scale"].shape == (
            config.d_model,
        )

        assert block["attn"]["c_attn"]["weight"].shape == (
            config.d_model,
            3 * config.d_model,
        )

        assert block["attn"]["c_attn"]["bias"].shape == (
            3 * config.d_model,
        )

        assert block["attn"]["c_proj"]["weight"].shape == (
            config.d_model,
            config.d_model,
        )

        assert block["mlp"]["fc1"]["weight"].shape == (
            config.d_model,
            config.mlp_dim,
        )

        assert block["mlp"]["fc2"]["weight"].shape == (
            config.mlp_dim,
            config.d_model,
        )

    assert params["lm_head"]["weight"].shape == (
        config.d_model,
        config.vocab_size,
    )


def verify_causal_mask(
    sequence_length: int,
) -> bool:
    mask = causal_mask(
        sequence_length,
    )

    expected = jnp.triu(
        jnp.ones(
            (
                sequence_length,
                sequence_length,
            ),
            dtype=bool,
        ),
        k=1,
    )

    return bool(
        jnp.array_equal(
            mask,
            expected,
        )
    )


def verify_attention_normalization(
    weights: Array,
    atol: float = 1e-5,
) -> bool:
    row_sums = jnp.sum(
        weights,
        axis=-1,
    )

    return bool(
        jnp.allclose(
            row_sums,
            1.0,
            atol=atol,
        )
    )


def verify_no_future_attention(
    weights: Array,
    atol: float = 1e-7,
) -> bool:
    sequence_length = weights.shape[-1]

    mask = causal_mask(
        sequence_length,
    )

    future = jnp.where(
        mask[None, None, :, :],
        weights,
        0.0,
    )

    return bool(
        jnp.allclose(
            future,
            0.0,
            atol=atol,
        )
    )


def verify_forward_shapes(
    params: PyTree,
    config: TransformerConfig,
    batch_size: int = 2,
    sequence_length: int = 8,
) -> Dict[str, Tuple[int, ...]]:

    token_ids = jnp.arange(
        batch_size * sequence_length,
        dtype=jnp.int32,
    ).reshape(
        batch_size,
        sequence_length,
    ) % config.vocab_size

    logits = transformer(
        params,
        token_ids,
        config,
    )

    expected = (
        batch_size,
        sequence_length,
        config.vocab_size,
    )

    assert logits.shape == expected

    return {
        "input": tuple(token_ids.shape),
        "logits": tuple(logits.shape),
    }


def verify_gradients(
    params: PyTree,
    config: TransformerConfig,
    batch_size: int = 2,
    sequence_length: int = 8,
) -> Dict[str, Any]:

    key = jax.random.PRNGKey(
        config.seed + 200,
    )

    batch = synthetic_batch(
        key,
        batch_size,
        sequence_length,
        config.vocab_size,
    )

    loss, grads = loss_and_grad(
        params,
        batch,
        config,
    )

    assert bool(
        jnp.isfinite(loss)
    )

    assert tree_all_finite(
        grads,
    )

    return {
        "loss": float(loss),
        "gradient_norm": float(
            global_grad_norm(grads)
        ),
        "gradient_max_abs": tree_max_abs(
            grads
        ),
    }


def verify_jit_equivalence(
    params: PyTree,
    config: TransformerConfig,
) -> float:

    key = jax.random.PRNGKey(
        config.seed + 300,
    )

    tokens = synthetic_batch(
        key,
        2,
        8,
        config.vocab_size,
    )

    eager = transformer(
        params,
        tokens,
        config,
    )

    compiled = build_jitted_forward(
        config,
    )

    jitted = compiled(
        params,
        tokens,
    )

    difference = float(
        jnp.max(
            jnp.abs(
                eager - jitted
            )
        )
    )

    assert difference < 1e-5

    return difference


def verify_attention(
    params: PyTree,
    config: TransformerConfig,
) -> Dict[str, bool]:

    key = jax.random.PRNGKey(
        config.seed + 400,
    )

    tokens = synthetic_batch(
        key,
        2,
        8,
        config.vocab_size,
    )

    _, attention_history = transformer_hidden(
        params,
        tokens,
        config,
    )

    assert len(attention_history) == config.n_layer

    normalized = all(
        verify_attention_normalization(
            weights
        )
        for weights in attention_history
    )

    causal = all(
        verify_no_future_attention(
            weights
        )
        for weights in attention_history
    )

    return {
        "rows_normalized": normalized,
        "future_tokens_blocked": causal,
    }


def verify_all(
    params: PyTree,
    config: TransformerConfig,
) -> Dict[str, Any]:

    verify_parameter_shapes(
        params,
        config,
    )

    mask_ok = verify_causal_mask(
        16,
    )

    shape_info = verify_forward_shapes(
        params,
        config,
    )

    gradient_info = verify_gradients(
        params,
        config,
    )

    jit_difference = verify_jit_equivalence(
        params,
        config,
    )

    attention_info = verify_attention(
        params,
        config,
    )

    assert mask_ok
    assert attention_info["rows_normalized"]
    assert attention_info["future_tokens_blocked"]

    return {
        "parameter_count": parameter_count(
            params
        ),
        "mask_ok": mask_ok,
        "shapes": shape_info,
        "gradients": gradient_info,
        "jit_max_abs_difference": jit_difference,
        "attention": attention_info,
    }


# ---------------------------------------------------------------------------
# PyTree parameter counting
# ---------------------------------------------------------------------------

def parameter_count(
    params: PyTree,
) -> int:
    return flatten_tree_size(
        params,
    )


def parameter_report(
    params: Mapping[str, Any],
) -> Dict[str, int]:

    report: Dict[str, int] = {}

    report["token_embedding"] = int(
        params["token_embedding"].size
    )

    report["blocks"] = sum(
        flatten_tree_size(
            block
        )
        for block in params["blocks"]
    )

    report["final_ln"] = flatten_tree_size(
        params["final_ln"]
    )

    report["lm_head"] = flatten_tree_size(
        params["lm_head"]
    )

    report["total"] = sum(
        report.values()
    )

    return report


# ---------------------------------------------------------------------------
# Parameter serialization
# ---------------------------------------------------------------------------

def flatten_for_json(
    tree: PyTree,
) -> Dict[str, Any]:
    leaves, treedef = jax.tree_util.tree_flatten(
        tree,
    )

    payload = {
        "treedef": str(treedef),
        "leaf_shapes": [
            list(leaf.shape)
            for leaf in leaves
        ],
        "leaf_dtypes": [
            str(leaf.dtype)
            for leaf in leaves
        ],
    }

    return payload


def save_metadata(
    path: Path,
    config: TransformerConfig,
    params: PyTree,
) -> None:

    payload = {
        "config": {
            "vocab_size": config.vocab_size,
            "d_model": config.d_model,
            "n_head": config.n_head,
            "n_layer": config.n_layer,
            "mlp_ratio": config.mlp_ratio,
            "max_seq_len": config.max_seq_len,
            "dropout": config.dropout,
            "layer_norm_eps": config.layer_norm_eps,
            "seed": config.seed,
        },
        "parameters": parameter_report(
            params
        ),
        "tree": flatten_for_json(
            params
        ),
    }

    path.write_text(
        json.dumps(
            payload,
            indent=2,
        )
    )


def save_npz(
    path: Path,
    params: PyTree,
) -> None:

    leaves, _ = jax.tree_util.tree_flatten(
        params,
    )

    arrays = {
        f"leaf_{index:05d}": jnp.asarray(
            leaf
        )
        for index, leaf in enumerate(leaves)
    }

    jnp.savez(
        path,
        **arrays,
    )


# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

def benchmark_forward(
    params: PyTree,
    config: TransformerConfig,
    iterations: int = 10,
) -> Dict[str, float]:

    key = jax.random.PRNGKey(
        config.seed + 500,
    )

    tokens = synthetic_batch(
        key,
        2,
        min(config.max_seq_len, 32),
        config.vocab_size,
    )

    forward = build_jitted_forward(
        config,
    )

    warmup = forward(
        params,
        tokens,
    )

    warmup.block_until_ready()

    start = time.perf_counter()

    for _ in range(iterations):
        output = forward(
            params,
            tokens,
        )
        output.block_until_ready()

    elapsed = time.perf_counter() - start

    return {
        "iterations": float(iterations),
        "seconds_total": elapsed,
        "milliseconds_per_iteration": (
            elapsed * 1000.0 / iterations
        ),
    }


# ---------------------------------------------------------------------------
# Configuration and construction
# ---------------------------------------------------------------------------

def make_config(
    args: argparse.Namespace,
) -> TransformerConfig:

    return TransformerConfig(
        vocab_size=args.vocab_size,
        d_model=args.d_model,
        n_head=args.n_head,
        n_layer=args.n_layer,
        mlp_ratio=args.mlp_ratio,
        max_seq_len=args.max_seq_len,
        seed=args.seed,
    )


def build_model(
    config: TransformerConfig,
) -> PyTree:
    key = jax.random.PRNGKey(
        config.seed,
    )
    return init_transformer(
        key,
        config,
    )


# ---------------------------------------------------------------------------
# Demonstration
# ---------------------------------------------------------------------------

def demo(
    config: TransformerConfig,
) -> None:

    params = build_model(
        config,
    )

    print("JAX transformer initialized")
    print(
        "parameters:",
        parameter_count(params),
    )
    print(
        "parameter report:",
        parameter_report(params),
    )

    verification = verify_all(
        params,
        config,
    )

    print(
        json.dumps(
            verification,
            indent=2,
        )
    )

    key = jax.random.PRNGKey(
        config.seed + 600,
    )

    prompt = synthetic_batch(
        key,
        1,
        8,
        config.vocab_size,
    )

    generation_key = jax.random.PRNGKey(
        config.seed + 601,
    )

    generated = generate(
        params,
        prompt,
        config,
        max_new_tokens=8,
        key=generation_key,
        temperature=1.0,
    )

    print(
        "prompt:",
        prompt.tolist(),
    )

    print(
        "generated:",
        generated.tolist(),
    )

    benchmark = benchmark_forward(
        params,
        config,
        iterations=5,
    )

    print(
        json.dumps(
            benchmark,
            indent=2,
        )
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Pure JAX Transformer Harness",
    )

    parser.add_argument(
        "--vocab-size",
        type=int,
        default=256,
    )

    parser.add_argument(
        "--d-model",
        type=int,
        default=128,
    )

    parser.add_argument(
        "--n-head",
        type=int,
        default=4,
    )

    parser.add_argument(
        "--n-layer",
        type=int,
        default=4,
    )

    parser.add_argument(
        "--mlp-ratio",
        type=int,
        default=4,
    )

    parser.add_argument(
        "--max-seq-len",
        type=int,
        default=128,
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=0,
    )

    parser.add_argument(
        "--train",
        action="store_true",
    )

    parser.add_argument(
        "--steps",
        type=int,
        default=5,
    )

    parser.add_argument(
        "--batch-size",
        type=int,
        default=2,
    )

    parser.add_argument(
        "--learning-rate",
        type=float,
        default=1e-3,
    )

    parser.add_argument(
        "--save-metadata",
        type=Path,
        default=None,
    )

    parser.add_argument(
        "--save-npz",
        type=Path,
        default=None,
    )

    return parser


def main(
    argv: Optional[Sequence[str]] = None,
) -> None:

    parser = build_parser()
    args = parser.parse_args(
        argv,
    )

    config = make_config(
        args,
    )

    config.validate()

    params = build_model(
        config,
    )

    if args.save_metadata is not None:
        save_metadata(
            args.save_metadata,
            config,
            params,
        )

    if args.save_npz is not None:
        save_npz(
            args.save_npz,
            params,
        )

    if args.train:
        params, _, history = train_synthetic(
            params,
            config,
            steps=args.steps,
            batch_size=args.batch_size,
            learning_rate=args.learning_rate,
        )

        for record in history:
            print(
                "step={step:.0f} loss={loss:.6f} grad_norm={grad_norm:.6f}".format(
                    **record
                )
            )

    demo(
        config,
    )


if __name__ == "__main__":
    main()
