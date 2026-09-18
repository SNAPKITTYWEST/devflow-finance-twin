#include "../Common/types.h"

kernel void decode_step(
    device const half* x [[buffer(0)]],
    device const half* attn_norm_gain [[buffer(1)]],
    device const uchar* wq [[buffer(2)]],
    device const half* sq [[buffer(3)]],
    device const uchar* wk [[buffer(4)]],
    device const half* sk [[buffer(5)]],
    device const uchar* wv [[buffer(6)]],
    device const half* sv [[buffer(7)]],
    device const uchar* wo [[buffer(8)]],
    device const half* so [[buffer(9)]],
    device const half* ffn_norm_gain [[buffer(10)]],
    device const uchar* w_gate [[buffer(11)]],
    device const half* s_gate [[buffer(12)]],
    device const uchar* w_up [[buffer(13)]],
    device const half* s_up [[buffer(14)]],
    device const uchar* w_down [[buffer(15)]],
    device const half* s_down [[buffer(16)]],
    device half* k_cache [[buffer(17)]],
    device half* v_cache [[buffer(18)]],
    device half* output [[buffer(19)]],
    constant ModelConfig& config [[buffer(20)]],
    constant PosInfo& pos [[buffer(21)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid != 0u) {
        return;
    }

    uint hidden = config.hidden;
    uint q_heads = config.q_heads;
    uint kv_heads = config.kv_heads;
    uint head_dim = config.head_dim;
    uint intermediate = config.intermediate;
    uint position = pos.token_index;

    float norm_buf[3072];
    float q_buf[3072];
    float k_buf[1024];
    float v_buf[1024];

    float rms = 0.0f;
    for (uint i = 0u; i < hidden; ++i) {
        float v = float(x[i]);
        rms += v * v;
    }
    float inv = safe_rsqrt(rms / float(hidden) + config.epsilon);
    for (uint i = 0u; i < hidden; ++i) {
        norm_buf[i] = float(x[i]) * inv * float(attn_norm_gain[i]);
    }

    for (uint h = 0u; h < q_heads * head_dim; ++h) {
        float acc = 0.0f;
        for (uint c = 0u; c < hidden; ++c) {
            acc += dequant_i4(wq, sq, h, c, hidden) * norm_buf[c];
        }
        q_buf[h] = acc;
    }
    for (uint h = 0u; h < kv_heads * head_dim; ++h) {
        float acc = 0.0f;
        for (uint c = 0u; c < hidden; ++c) {
            acc += dequant_i4(wk, sk, h, c, hidden) * norm_buf[c];
        }
        k_buf[h] = acc;
    }
    for (uint h = 0u; h < kv_heads * head_dim; ++h) {
        float acc = 0.0f;
        for (uint c = 0u; c < hidden; ++c) {
            acc += dequant_i4(wv, sv, h, c, hidden) * norm_buf[c];
        }
        v_buf[h] = acc;
    }

    for (uint qh = 0u; qh < q_heads; ++qh) {
        for (uint pair = 0u; pair < head_dim / 2u; ++pair) {
            uint even = pair * 2u;
            uint odd = even + 1u;
            float angle = float(position) * pow(10000.0f, -float(2u * pair) / float(head_dim));
            float c = cos(angle);
            float s = sin(angle);
            float q0 = q_buf[qh * head_dim + even];
            float q1 = q_buf[qh * head_dim + odd];
            q_buf[qh * head_dim + even] = q0 * c - q1 * s;
            q_buf[qh * head_dim + odd] = q0 * s + q1 * c;
        }
    }
    for (uint kvh = 0u; kvh < kv_heads; ++kvh) {
        for (uint pair = 0u; pair < head_dim / 2u; ++pair) {
            uint even = pair * 2u;
            uint odd = even + 1u;
            float angle = float(position) * pow(10000.0f, -float(2u * pair) / float(head_dim));
            float c = cos(angle);
            float s = sin(angle);
            float k0 = k_buf[kvh * head_dim + even];
            float k1 = k_buf[kvh * head_dim + odd];
            k_buf[kvh * head_dim + even] = k0 * c - k1 * s;
            k_buf[kvh * head_dim + odd] = k0 * s + k1 * c;
        }
    }

    for (uint kvh = 0u; kvh < kv_heads; ++kvh) {
        for (uint d = 0u; d < head_dim; ++d) {
            uint off = kv_offset(position, kvh, head_dim, kv_heads) + d;
            k_cache[off] = half(k_buf[kvh * head_dim + d]);
            v_cache[off] = half(v_buf[kvh * head_dim + d]);
        }
    }

    float attn_out[3072];
    float scale = attention_scale(head_dim);
    uint len = position + 1u;

    for (uint qh = 0u; qh < q_heads; ++qh) {
        uint kvh = qh % kv_heads;

        float maxv = -1.0e30f;
        for (uint p = 0u; p < len; ++p) {
            float dot = 0.0f;
            for (uint d = 0u; d < head_dim; ++d) {
                dot += q_buf[qh * head_dim + d] * float(k_cache[kv_offset(p, kvh, head_dim, kv_heads) + d]);
            }
            maxv = max(maxv, dot * scale);
        }

        float sum = 0.0f;
        for (uint p = 0u; p < len; ++p) {
            float dot = 0.0f;
            for (uint d = 0u; d < head_dim; ++d) {
                dot += q_buf[qh * head_dim + d] * float(k_cache[kv_offset(p, kvh, head_dim, kv_heads) + d]);
            }
            sum += stable_exp(dot * scale, maxv);
        }
        float inv_sum = 1.0f / max(sum, 1.0e-8f);

        for (uint d = 0u; d < head_dim; ++d) {
            float acc = 0.0f;
            for (uint p = 0u; p < len; ++p) {
                float dot = 0.0f;
                for (uint dd = 0u; dd < head_dim; ++dd) {
                    dot += q_buf[qh * head_dim + dd] * float(k_cache[kv_offset(p, kvh, head_dim, kv_heads) + dd]);
                }
                float w = stable_exp(dot * scale, maxv) * inv_sum;
                acc += w * float(v_cache[kv_offset(p, kvh, head_dim, kv_heads) + d]);
            }
            attn_out[qh * head_dim + d] = acc;
        }
    }

    float proj[3072];
    for (uint r = 0u; r < hidden; ++r) {
        float acc = 0.0f;
        for (uint c = 0u; c < q_heads * head_dim; ++c) {
            acc += dequant_i4(wo, so, r, c, q_heads * head_dim) * attn_out[c];
        }
        proj[r] = acc;
    }

    float residual[3072];
    for (uint i = 0u; i < hidden; ++i) {
        residual[i] = float(x[i]) + proj[i];
    }

    rms = 0.0f;
    for (uint i = 0u; i < hidden; ++i) {
        rms += residual[i] * residual[i];
    }
    inv = safe_rsqrt(rms / float(hidden) + config.epsilon);
    for (uint i = 0u; i < hidden; ++i) {
        norm_buf[i] = residual[i] * inv * float(ffn_norm_gain[i]);
    }

    float mlp_buf[8192];
    for (uint r = 0u; r < intermediate; ++r) {
        float gate = 0.0f;
        float up = 0.0f;
        for (uint c = 0u; c < hidden; ++c) {
            gate += dequant_i4(w_gate, s_gate, r, c, hidden) * norm_buf[c];
            up += dequant_i4(w_up, s_up, r, c, hidden) * norm_buf[c];
        }
        mlp_buf[r] = silu(gate) * up;
    }

    for (uint r = 0u; r < hidden; ++r) {
        float acc = 0.0f;
        for (uint c = 0u; c < intermediate; ++c) {
            acc += dequant_i4(w_down, s_down, r, c, intermediate) * mlp_buf[c];
        }
        output[r] = half(residual[r] + acc);
    }
}
