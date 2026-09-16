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

import math
from typing import Any, Dict, Tuple

import jax
import jax.numpy as jnp
import jax.nn as jnn


Array = jax.Array
Params = Dict[str, Any]


def linear(
    x: Array,
    weight: Array,
    bias: Array,
) -> Array:
    return x @ weight + bias


def layer_norm(
    x: Array,
    scale: Array,
    bias: Array,
    eps: float = 1e-5,
) -> Array:
    mean = jnp.mean(x, axis=-1, keepdims=True)
    variance = jnp.mean(
        jnp.square(x - mean),
        axis=-1,
        keepdims=True,
    )

    normalized = (
        x - mean
    ) / jnp.sqrt(variance + eps)

    return normalized * scale + bias


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


def split_qkv(
    qkv: Array,
    d_model: int,
) -> Tuple[Array, Array, Array]:
    return jnp.split(
        qkv,
        3,
        axis=-1,
    )


def reshape_heads(
    x: Array,
    n_head: int,
) -> Array:
    batch, sequence, channels = x.shape

    head_dim = channels // n_head

    x = x.reshape(
        batch,
        sequence,
        n_head,
        head_dim,
    )

    return x.transpose(
        0,
        2,
        1,
        3,
    )


def merge_heads(
    x: Array,
) -> Array:
    batch, heads, sequence, head_dim = x.shape

    x = x.transpose(
        0,
        2,
        1,
        3,
    )

    return x.reshape(
        batch,
        sequence,
        heads * head_dim,
    )


def causal_self_attention(
    params: Params,
    x: Array,
    n_head: int,
) -> Array:

    batch, sequence, d_model = x.shape

    qkv = linear(
        x,
        params["c_attn"]["weight"],
        params["c_attn"]["bias"],
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

    head_dim = d_model // n_head

    scale = 1.0 / math.sqrt(
        head_dim
    )

    scores = jnp.matmul(
        q,
        jnp.swapaxes(
            k,
            -1,
            -2,
        ),
    )

    scores = scores * scale

    mask = causal_mask(
        sequence,
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

    y = jnp.matmul(
        weights,
        v,
    )

    y = merge_heads(
        y,
    )

    return linear(
        y,
        params["c_proj"]["weight"],
        params["c_proj"]["bias"],
    )


def mlp(
    params: Params,
    x: Array,
) -> Array:

    x = linear(
        x,
        params["fc1"]["weight"],
        params["fc1"]["bias"],
    )

    x = jnn.gelu(
        x,
    )

    x = linear(
        x,
        params["fc2"]["weight"],
        params["fc2"]["bias"],
    )

    return x


def transformer_block(
    params: Params,
    x: Array,
    n_head: int,
    eps: float = 1e-5,
) -> Array:

    normalized = layer_norm(
        x,
        params["ln1"]["scale"],
        params["ln1"]["bias"],
        eps,
    )

    attention_output = causal_self_attention(
        params["attn"],
        normalized,
        n_head,
    )

    x = x + attention_output

    normalized = layer_norm(
        x,
        params["ln2"]["scale"],
        params["ln2"]["bias"],
        eps,
    )

    mlp_output = mlp(
        params["mlp"],
        normalized,
    )

    x = x + mlp_output

    return x


def transformer(
    params: Params,
    token_ids: Array,
    n_head: int,
    eps: float = 1e-5,
) -> Array:

    x = params["token_embedding"][
        token_ids
    ]

    for block in params["blocks"]:
        x = transformer_block(
            block,
            x,
            n_head,
            eps,
        )

    x = layer_norm(
        x,
        params["final_ln"]["scale"],
        params["final_ln"]["bias"],
        eps,
    )

    logits = linear(
        x,
        params["lm_head"]["weight"],
        params["lm_head"]["bias"],
    )

    return logits


def init_linear(
    key: Array,
    input_dim: int,
    output_dim: int,
) -> Tuple[Array, Array]:

    weight_key, _ = jax.random.split(
        key,
    )

    scale = 1.0 / math.sqrt(
        input_dim,
    )

    weight = (
        jax.random.normal(
            weight_key,
            (
                input_dim,
                output_dim,
            ),
        )
        * scale
    )

    bias = jnp.zeros(
        (
            output_dim,
        ),
    )

    return weight, bias


def init_layer_norm(
    d_model: int,
) -> Dict[str, Array]:

    return {
        "scale": jnp.ones(
            (d_model,),
        ),
        "bias": jnp.zeros(
            (d_model,),
        ),
    }


def init_attention(
    key: Array,
    d_model: int,
) -> Params:

    k1, k2 = jax.random.split(
        key,
    )

    w_qkv, b_qkv = init_linear(
        k1,
        d_model,
        3 * d_model,
    )

    w_proj, b_proj = init_linear(
        k2,
        d_model,
        d_model,
    )

    return {
        "c_attn": {
            "weight": w_qkv,
            "bias": b_qkv,
        },
        "c_proj": {
            "weight": w_proj,
            "bias": b_proj,
        },
    }


def init_mlp(
    key: Array,
    d_model: int,
) -> Params:

    k1, k2 = jax.random.split(
        key,
    )

    w1, b1 = init_linear(
        k1,
        d_model,
        4 * d_model,
    )

    w2, b2 = init_linear(
        k2,
        4 * d_model,
        d_model,
    )

    return {
        "fc1": {
            "weight": w1,
            "bias": b1,
        },
        "fc2": {
            "weight": w2,
            "bias": b2,
        },
    }


def init_block(
    key: Array,
    d_model: int,
) -> Params:

    k_attn, k_mlp = jax.random.split(
        key,
    )

    return {
        "ln1": init_layer_norm(
            d_model,
        ),
        "attn": init_attention(
            k_attn,
            d_model,
        ),
        "ln2": init_layer_norm(
            d_model,
        ),
        "mlp": init_mlp(
            k_mlp,
            d_model,
        ),
    }


def init_transformer(
    key: Array,
    vocab_size: int,
    d_model: int,
    n_head: int,
    n_layer: int,
) -> Params:

    keys = jax.random.split(
        key,
        n_layer + 2,
    )

    embedding_key = keys[0]

    embedding_scale = 1.0 / math.sqrt(
        d_model,
    )

    token_embedding = (
        jax.random.normal(
            embedding_key,
            (
                vocab_size,
                d_model,
            ),
        )
        * embedding_scale
    )

    blocks = tuple(
        init_block(
            keys[i + 1],
            d_model,
        )
        for i in range(n_layer)
    )

    lm_key = keys[-1]

    lm_weight, lm_bias = init_linear(
        lm_key,
        d_model,
        vocab_size,
    )

    return {
        "token_embedding": token_embedding,
        "blocks": blocks,
        "final_ln": init_layer_norm(
            d_model,
        ),
        "lm_head": {
            "weight": lm_weight,
            "bias": lm_bias,
        },
    }


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


def language_model_loss(
    params: Params,
    token_ids: Array,
    targets: Array,
    n_head: int,
) -> Array:

    logits = transformer(
        params,
        token_ids,
        n_head,
    )

    return cross_entropy(
        logits,
        targets,
    )


@jax.jit
def forward_jit(
    params: Params,
    token_ids: Array,
    n_head: int,
) -> Array:

    return transformer(
        params,
        token_ids,
        n_head,
    )


@jax.jit
def loss_jit(
    params: Params,
    token_ids: Array,
    targets: Array,
    n_head: int,
) -> Array:

    return language_model_loss(
        params,
        token_ids,
        targets,
        n_head,
    )


@jax.jit
def gradients(
    params: Params,
    token_ids: Array,
    targets: Array,
    n_head: int,
):

    return jax.grad(
        language_model_loss,
    )(
        params,
        token_ids,
        targets,
        n_head,
    )


def parameter_count(
    params: Params,
) -> int:

    leaves = jax.tree_util.tree_leaves(
        params,
    )

    return sum(
        int(x.size)
        for x in leaves
    )


def causal_attention_weights(
    params: Params,
    x: Array,
    n_head: int,
) -> Array:

    batch, sequence, d_model = x.shape

    qkv = linear(
        x,
        params["c_attn"]["weight"],
        params["c_attn"]["bias"],
    )

    q, k, _ = split_qkv(
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

    head_dim = d_model // n_head

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
            dtype=x.dtype,
        ),
    )

    mask = causal_mask(
        sequence,
    )

    scores = jnp.where(
        mask[None, None, :, :],
        -jnp.inf,
        scores,
    )

    return jnn.softmax(
        scores,
        axis=-1,
    )


def verify_shapes(
    params: Params,
    token_ids: Array,
    n_head: int,
) -> Dict[str, Tuple[int, ...]]:

    logits = transformer(
        params,
        token_ids,
        n_head,
    )

    return {
        "tokens": tuple(
            token_ids.shape
        ),
        "logits": tuple(
            logits.shape
        ),
        "embedding": tuple(
            params["token_embedding"].shape
        ),
    }


def verify_causal_mask(
    sequence_length: int,
) -> bool:

    mask = causal_mask(
        sequence_length,
    )

    for i in range(
        sequence_length,
    ):
        for j in range(
            sequence_length,
        ):
            if j > i:
                if not bool(
                    mask[i, j]
                ):
                    return False
            else:
                if bool(
                    mask[i, j]
                ):
                    return False

    return True


def verify_attention_normalization(
    weights: Array,
) -> bool:

    sums = jnp.sum(
        weights,
        axis=-1,
    )

    return bool(
        jnp.allclose(
            sums,
            1.0,
            atol=1e-5,
        )
    )


def verify_no_future_attention(
    weights: Array,
) -> bool:

    sequence_length = weights.shape[-1]

    mask = causal_mask(
        sequence_length,
    )

    future_weights = jnp.where(
        mask[None, None, :, :],
        weights,
        0.0,
    )

    return bool(
        jnp.allclose(
            future_weights,
            0.0,
            atol=1e-7,
        )
    )
