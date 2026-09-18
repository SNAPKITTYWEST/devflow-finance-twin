#include "../Common/types.h"

kernel void attention_scores(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device float* scores [[buffer(2)]],
    constant AttentionSpec& spec [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= spec.length) {
        return;
    }
    uint q_head = tid / spec.length;
    uint pos = tid % spec.length;
    if (q_head >= spec.heads) {
        return;
    }
    uint kv_head = q_head % spec.kv_heads;
    float scale = attention_scale(spec.head_dim);
    float dot = 0.0f;
    for (uint d = 0u; d < spec.head_dim; ++d) {
        float qv = float(q[qkv_index(q_head, d, spec.head_dim)]);
        float kv = float(k_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + d]);
        dot += qv * kv;
    }
    scores[q_head * spec.length + pos] = dot * scale;
}

kernel void causal_mask(
    device float* scores [[buffer(0)]],
    constant AttentionSpec& spec [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / spec.length;
    uint pos = tid % spec.length;
    if (head >= spec.heads || pos > spec.offset) {
        return;
    }
    if (pos > spec.offset) {
        scores[head * spec.length + pos] = -1.0e9f;
    }
}

kernel void stable_softmax(
    device float* scores [[buffer(0)]],
    constant AttentionSpec& spec [[buffer(1)]],
    uint head [[thread_position_in_grid]])
{
    if (head >= spec.heads) {
        return;
    }
    uint base = head * spec.length;
    uint len = spec.offset + 1u;

    float maxv = -1.0e30f;
    for (uint i = 0u; i < len; ++i) {
        maxv = max(maxv, scores[base + i]);
    }

    float sum = 0.0f;
    for (uint i = 0u; i < len; ++i) {
        float e = stable_exp(scores[base + i], maxv);
        scores[base + i] = e;
        sum += e;
    }

    float inv = 1.0f / max(sum, 1.0e-8f);
    for (uint i = 0u; i < len; ++i) {
        scores[base + i] *= inv;
    }
    for (uint i = len; i < spec.length; ++i) {
        scores[base + i] = 0.0f;
    }
}

kernel void attention_value(
    device const float* scores [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant AttentionSpec& spec [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / spec.head_dim;
    uint dim = tid % spec.head_dim;
    if (head >= spec.heads) {
        return;
    }
    uint kv_head = head % spec.kv_heads;
    uint len = spec.offset + 1u;

    float acc = 0.0f;
    for (uint pos = 0u; pos < len; ++pos) {
        float w = scores[head * spec.length + pos];
        float v = float(v_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + dim]);
        acc += w * v;
    }
    output[qkv_index(head, dim, spec.head_dim)] = half(acc);
}

kernel void fused_gqa_step(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device const half* v_cache [[buffer(2)]],
    device half* output [[buffer(3)]],
    constant AttentionSpec& spec [[buffer(4)]],
    uint q_head [[thread_position_in_grid]])
{
    if (q_head >= spec.heads) {
        return;
    }
    uint kv_head = q_head % spec.kv_heads;
    float scale = attention_scale(spec.head_dim);
    uint len = spec.offset + 1u;

    float maxv = -1.0e30f;
    for (uint pos = 0u; pos < len; ++pos) {
        float dot = 0.0f;
        for (uint d = 0u; d < spec.head_dim; ++d) {
            dot += float(q[qkv_index(q_head, d, spec.head_dim)]) *
                   float(k_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + d]);
        }
        maxv = max(maxv, dot * scale);
    }

    float sum = 0.0f;
    for (uint pos = 0u; pos < len; ++pos) {
        float dot = 0.0f;
        for (uint d = 0u; d < spec.head_dim; ++d) {
            dot += float(q[qkv_index(q_head, d, spec.head_dim)]) *
                   float(k_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + d]);
        }
        sum += stable_exp(dot * scale, maxv);
    }
    float inv = 1.0f / max(sum, 1.0e-8f);

    for (uint d = 0u; d < spec.head_dim; ++d) {
        float acc = 0.0f;
        for (uint pos = 0u; pos < len; ++pos) {
            float dot = 0.0f;
            for (uint dd = 0u; dd < spec.head_dim; ++dd) {
                dot += float(q[qkv_index(q_head, dd, spec.head_dim)]) *
                       float(k_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + dd]);
            }
            float w = stable_exp(dot * scale, maxv) * inv;
            acc += w * float(v_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + d]);
        }
        output[qkv_index(q_head, d, spec.head_dim)] = half(acc);
    }
}

kernel void fused_layer_attention(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device const half* v_cache [[buffer(2)]],
    device half* output [[buffer(3)]],
    device const uchar* wo_weight [[buffer(4)]],
    device const half* wo_scale [[buffer(5)]],
    device half* proj_out [[buffer(6)]],
    constant AttentionSpec& spec [[buffer(7)]],
    constant LinearShape& proj_shape [[buffer(8)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_head = tid;
    if (q_head >= spec.heads) {
        return;
    }
    uint kv_head = q_head % spec.kv_heads;
    float scale = attention_scale(spec.head_dim);
    uint len = spec.offset + 1u;

    float maxv = -1.0e30f;
    for (uint pos = 0u; pos < len; ++pos) {
        float dot = 0.0f;
        for (uint d = 0u; d < spec.head_dim; ++d) {
            dot += float(q[qkv_index(q_head, d, spec.head_dim)]) *
                   float(k_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + d]);
        }
        maxv = max(maxv, dot * scale);
    }

    float sum = 0.0f;
    for (uint pos = 0u; pos < len; ++pos) {
        float dot = 0.0f;
        for (uint d = 0u; d < spec.head_dim; ++d) {
            dot += float(q[qkv_index(q_head, d, spec.head_dim)]) *
                   float(k_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + d]);
        }
        sum += stable_exp(dot * scale, maxv);
    }
    float inv = 1.0f / max(sum, 1.0e-8f);

    for (uint d = 0u; d < spec.head_dim; ++d) {
        float acc = 0.0f;
        for (uint pos = 0u; pos < len; ++pos) {
            float dot = 0.0f;
            for (uint dd = 0u; dd < spec.head_dim; ++dd) {
                dot += float(q[qkv_index(q_head, dd, spec.head_dim)]) *
                       float(k_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + dd]);
            }
            float w = stable_exp(dot * scale, maxv) * inv;
            acc += w * float(v_cache[kv_offset(pos, kv_head, spec.head_dim, spec.kv_heads) + d]);
        }
        output[qkv_index(q_head, d, spec.head_dim)] = half(acc);
    }
}
