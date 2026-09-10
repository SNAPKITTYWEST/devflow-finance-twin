import math
import jax
import jax.numpy as jnp


# ============================================================
# Configuration
# ============================================================

class TransformerConfig:
    def __init__(
        self,
        vocab_size,
        d_model,
        n_head,
        n_layer,
        max_seq_len,
        dropout=0.0,
        eps=1e-5,
    ):
        if d_model % n_head != 0:
            raise ValueError("d_model must be divisible by n_head")

        self.vocab_size = vocab_size
        self.d_model = d_model
        self.n_head = n_head
        self.n_layer = n_layer
        self.max_seq_len = max_seq_len
        self.dropout = dropout
        self.eps = eps
        self.head_dim = d_model // n_head


# ============================================================
# Initialization
# ============================================================

def normal(key, shape, scale=0.02, dtype=jnp.float32):
    return scale * jax.random.normal(key, shape, dtype=dtype)


def zeros(shape, dtype=jnp.float32):
    return jnp.zeros(shape, dtype=dtype)


def ones(shape, dtype=jnp.float32):
    return jnp.ones(shape, dtype=dtype)


def split_key(key, count):
    return jax.random.split(key, count)


def init_linear(key, in_features, out_features):
    wk, bk = jax.random.split(key)

    return {
        "weight": normal(
            wk,
            (in_features, out_features),
        ),
        "bias": zeros((out_features,)),
    }


def init_layer_norm(d_model):
    return {
        "scale": ones((d_model,)),
        "bias": zeros((d_model,)),
    }


def init_attention(key, config):
    k1, k2 = jax.random.split(key)

    return {
        "c_attn": init_linear(
            k1,
            config.d_model,
            3 * config.d_model,
        ),
        "c_proj": init_linear(
            k2,
            config.d_model,
            config.d_model,
        ),
        "n_head": config.n_head,
        "head_dim": config.head_dim,
    }


def init_mlp(key, config):
    k1, k2 = jax.random.split(key)

    return {
        "fc1": init_linear(
            k1,
            config.d_model,
            4 * config.d_model,
        ),
        "fc2": init_linear(
            k2,
            4 * config.d_model,
            config.d_model,
        ),
    }


def init_block(key, config):
    k1, k2 = jax.random.split(key)

    return {
        "ln1": init_layer_norm(config.d_model),
        "attn": init_attention(k1, config),
        "ln2": init_layer_norm(config.d_model),
        "mlp": init_mlp(k2, config),
    }


def init_transformer(key, config):
    keys = split_key(
        key,
        2 + config.n_layer,
    )

    embedding_key = keys[0]
    head_key = keys[1]
    block_keys = keys[2:]

    blocks = tuple(
        init_block(k, config)
        for k in block_keys
    )

    return {
        "embedding": normal(
            embedding_key,
            (
                config.vocab_size,
                config.d_model,
            ),
        ),
        "blocks": blocks,
        "final_ln": init_layer_norm(
            config.d_model
        ),
        "lm_head": init_linear(
            head_key,
            config.d_model,
            config.vocab_size,
        ),
    }


# ============================================================
# Linear
# ============================================================

def linear(params, x):
    return (
        jnp.matmul(
            x,
            params["weight"],
        )
        + params["bias"]
    )


# ============================================================
# LayerNorm
# ============================================================

def layer_norm(params, x, eps=1e-5):
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
        variance + eps
    )

    return (
        normalized * params["scale"]
        + params["bias"]
    )


# ============================================================
# Embedding
# ============================================================

def token_embedding(params, token_ids):
    return params["embedding"][token_ids]


# ============================================================
# GELU
# ============================================================

def gelu(x):
    return jax.nn.gelu(x)


# ============================================================
# Causal Mask
# ============================================================

def causal_mask(sequence_length):
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


# ============================================================
# Causal Self Attention
# ============================================================

def causal_self_attention(
    params,
    x,
):
    batch_size, sequence_length, channels = x.shape

    n_head = params["n_head"]
    head_dim = params["head_dim"]

    qkv = linear(
        params["c_attn"],
        x,
    )

    q, k, v = jnp.split(
        qkv,
        3,
        axis=-1,
    )

    q = q.reshape(
        batch_size,
        sequence_length,
        n_head,
        head_dim,
    )

    k = k.reshape(
        batch_size,
        sequence_length,
        n_head,
        head_dim,
    )

    v = v.reshape(
        batch_size,
        sequence_length,
        n_head,
        head_dim,
    )

    q = jnp.transpose(
        q,
        (0, 2, 1, 3),
    )

    k = jnp.transpose(
        k,
        (0, 2, 1, 3),
    )

    v = jnp.transpose(
        v,
        (0, 2, 1, 3),
    )

    scale = 1.0 / math.sqrt(head_dim)

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
        sequence_length
    )

    scores = jnp.where(
        mask[None, None, :, :],
        -jnp.inf,
        scores,
    )

    attention = jax.nn.softmax(
        scores,
        axis=-1,
    )

    y = jnp.matmul(
        attention,
        v,
    )

    y = jnp.transpose(
        y,
        (0, 2, 1, 3),
    )

    y = y.reshape(
        batch_size,
        sequence_length,
        channels,
    )

    return linear(
        params["c_proj"],
        y,
    )


# ============================================================
# MLP
# ============================================================

def mlp(params, x):
    x = linear(
        params["fc1"],
        x,
    )

    x = gelu(x)

    x = linear(
        params["fc2"],
        x,
    )

    return x


# ============================================================
# Transformer Block
# ============================================================

def transformer_block(
    params,
    x,
    eps=1e-5,
):
    normalized = layer_norm(
        params["ln1"],
        x,
        eps,
    )

    attention_output = causal_self_attention(
        params["attn"],
        normalized,
    )

    x = x + attention_output

    normalized = layer_norm(
        params["ln2"],
        x,
        eps,
    )

    mlp_output = mlp(
        params["mlp"],
        normalized,
    )

    x = x + mlp_output

    return x


# ============================================================
# Transformer
# ============================================================

def transformer(
    params,
    token_ids,
    eps=1e-5,
):
    x = token_embedding(
        params,
        token_ids,
    )

    for block in params["blocks"]:
        x = transformer_block(
            block,
            x,
            eps,
        )

    x = layer_norm(
        params["final_ln"],
        x,
        eps,
    )

    return x


# ============================================================
# Language Model Head
# ============================================================

def logits(
    params,
    token_ids,
    eps=1e-5,
):
    x = transformer(
        params,
        token_ids,
        eps,
    )

    return linear(
        params["lm_head"],
        x,
    )


# ============================================================
# JIT Forward
# ============================================================

@jax.jit
def forward(
    params,
    token_ids,
):
    return logits(
        params,
        token_ids,
    )


# ============================================================
# Cross Entropy
# ============================================================

def cross_entropy(
    params,
    token_ids,
    targets,
):
    output = logits(
        params,
        token_ids,
    )

    log_probs = jax.nn.log_softmax(
        output,
        axis=-1,
    )

    target_log_probs = jnp.take_along_axis(
        log_probs,
        targets[..., None],
        axis=-1,
    )

    return -jnp.mean(
        target_log_probs[..., 0]
    )


# ============================================================
# Gradient
# ============================================================

def loss_and_grad(
    params,
    token_ids,
    targets,
):
    loss, grads = jax.value_and_grad(
        cross_entropy
    )(
        params,
        token_ids,
        targets,
    )

    return loss, grads


# ============================================================
# Parameter Counting
# ============================================================

def parameter_count(params):
    leaves = jax.tree_util.tree_leaves(
        params
    )

    return sum(
        x.size
        for x in leaves
        if hasattr(x, "size")
    )


# ============================================================
# Shape Inspection
# ============================================================

def parameter_shapes(params):
    return jax.tree_util.tree_map(
        lambda x: x.shape
        if hasattr(x, "shape")
        else x,
        params,
    )


# ============================================================
# Attention Extraction
# ============================================================

def attention_weights(
    params,
    x,
):
    batch_size, sequence_length, channels = x.shape

    n_head = params["n_head"]
    head_dim = params["head_dim"]

    qkv = linear(
        params["c_attn"],
        x,
    )

    q, k, _ = jnp.split(
        qkv,
        3,
        axis=-1,
    )

    q = q.reshape(
        batch_size,
        sequence_length,
        n_head,
        head_dim,
    )

    k = k.reshape(
        batch_size,
        sequence_length,
        n_head,
        head_dim,
    )

    q = q.transpose(
        0,
        2,
        1,
        3,
    )

    k = k.transpose(
        0,
        2,
        1,
        3,
    )

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
        )
    )

    mask = causal_mask(
        sequence_length
    )

    scores = jnp.where(
        mask[None, None, :, :],
        -jnp.inf,
        scores,
    )

    return jax.nn.softmax(
        scores,
        axis=-1,
    )


# ============================================================
# Autoregressive Next Token
# ============================================================

def next_token_logits(
    params,
    token_ids,
):
    output = forward(
        params,
        token_ids,
    )

    return output[:, -1, :]


def greedy_next_token(
    params,
    token_ids,
):
    next_logits = next_token_logits(
        params,
        token_ids,
    )

    return jnp.argmax(
        next_logits,
        axis=-1,
    )


# ============================================================
# Sequence Generation
# ============================================================

def generate(
    params,
    token_ids,
    steps,
):
    current = token_ids

    for _ in range(steps):
        token = greedy_next_token(
            params,
            current,
        )

        current = jnp.concatenate(
            [
                current,
                token[:, None],
            ],
            axis=1,
        )

    return current


# ============================================================
# Batch Mapping
# ============================================================

batched_forward = jax.jit(
    jax.vmap(
        lambda params, token_ids:
            logits(
                params,
                token_ids,
            ),
        in_axes=(None, 0),
    )
)


# ============================================================
# Causal Verification
# ============================================================

def verify_causal_mask(
    params,
    x,
):
    weights = attention_weights(
        params["attn"],
        x,
    )

    sequence_length = x.shape[1]

    mask = causal_mask(
        sequence_length
    )

    future = jnp.where(
        mask[None, None, :, :],
        weights,
        0.0,
    )

    return jnp.max(
        jnp.abs(future)
    )


# ============================================================
# Attention Row Verification
# ============================================================

def verify_attention_rows(
    params,
    x,
):
    weights = attention_weights(
        params["attn"],
        x,
    )

    row_sums = jnp.sum(
        weights,
        axis=-1,
    )

    return jnp.max(
        jnp.abs(
            row_sums - 1.0
        )
    )


# ============================================================
# Factory
# ============================================================

def create_model(
    seed,
    vocab_size=50257,
    d_model=768,
    n_head=12,
    n_layer=12,
    max_seq_len=1024,
):
    config = TransformerConfig(
        vocab_size=vocab_size,
        d_model=d_model,
        n_head=n_head,
        n_layer=n_layer,
        max_seq_len=max_seq_len,
    )

    key = jax.random.PRNGKey(
        seed
    )

    params = init_transformer(
        key,
        config,
    )

    return config, params


# ============================================================
# Example Construction
# ============================================================

config, params = create_model(
    seed=42,
    vocab_size=50257,
    d_model=768,
    n_head=12,
    n_layer=12,
    max_seq_len=1024,
)
