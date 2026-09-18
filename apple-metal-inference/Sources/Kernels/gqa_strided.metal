#include <metal_stdlib>
using namespace metal;

struct AttnParams {
    uint seq_len;
    uint kv_len;
    uint num_heads;
    uint num_kv_heads;
    uint head_dim;
    uint kv_stride;
    float scale;
};

kernel void gqa_attention(
    device const half* Q [[buffer(0)]],
    device const half* Kc [[buffer(1)]],
    device const half* Vc [[buffer(2)]],
    device half* O [[buffer(3)]],
    constant AttnParams& p [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint q_pos = gid.y;
    uint h = gid.x;
    if (q_pos >= p.seq_len || h >= p.num_heads) return;

    uint kv_h = h / (p.num_heads / p.num_kv_heads);
    uint d = p.head_dim;

    uint q_off = q_pos * p.num_heads * d + h * d;
    uint kv_off = kv_h * d;

    float m = -INFINITY;
    for (uint t = 0; t < p.kv_len; ++t) {
        float s = 0.f;
        uint k_off = t * p.kv_stride + kv_off;
        for (uint i = 0; i < d; ++i)
            s += (float)Q[q_off + i] * (float)Kc[k_off + i];
        s *= p.scale;
        m = max(m, s);
    }

    float l = 0.f;
    for (uint t = 0; t < p.kv_len; ++t) {
        float s = 0.f;
        uint k_off = t * p.kv_stride + kv_off;
        for (uint i = 0; i < d; ++i)
            s += (float)Q[q_off + i] * (float)Kc[k_off + i];
        l += exp(s * p.scale - m);
    }

    for (uint i = 0; i < d; ++i) {
        float acc = 0.f;
        for (uint t = 0; t < p.kv_len; ++t) {
            uint k_off = t * p.kv_stride + kv_off;
            uint v_off = t * p.kv_stride + kv_off;
            float s = 0.f;
            for (uint j = 0; j < d; ++j)
                s += (float)Q[q_off + j] * (float)Kc[k_off + j];
            float w = exp(s * p.scale - m) / l;
            acc += w * (float)Vc[v_off + i];
        }
        O[q_off + i] = (half)acc;
    }
}

struct RoPEParams {
    uint head_dim;
    uint num_heads;
    uint num_kv_heads;
    uint seq_len;
    uint pos_offset;
    float theta_base;
};

kernel void rope_apply(
    device half* Q [[buffer(0)]],
    device half* K [[buffer(1)]],
    constant RoPEParams& p [[buffer(2)]],
    uint3 gid [[thread_position_in_grid]])
{
    uint d = gid.x;
    uint h = gid.y;
    if (d >= p.head_dim) return;

    uint pos = gid.z + p.pos_offset;
    uint half_d = p.head_dim / 2;
    if (d >= half_d) return;

    float freq = pow(p.theta_base, -2.0f * (float)d / (float)p.head_dim);
    float ang = (float)pos * freq;
    float c = cos(ang), s = sin(ang);

    uint q_base = pos * p.num_heads * p.head_dim + h * p.head_dim;
    float q0 = (float)Q[q_base + d];
    float q1 = (float)Q[q_base + d + half_d];
    Q[q_base + d] = (half)(q0 * c - q1 * s);
    Q[q_base + d + half_d] = (half)(q0 * s + q1 * c);

    if (h < p.num_kv_heads) {
        uint k_base = pos * p.num_kv_heads * p.head_dim + h * p.head_dim;
        float k0 = (float)K[k_base + d];
        float k1 = (float)K[k_base + d + half_d];
        K[k_base + d] = (half)(k0 * c - k1 * s);
        K[k_base + d + half_d] = (half)(k0 * s + k1 * c);
    }
}
