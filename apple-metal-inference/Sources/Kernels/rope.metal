#include "../Common/types.h"

kernel void rope_qk(
    device half* q [[buffer(0)]],
    device half* k [[buffer(1)]],
    constant ModelConfig& config [[buffer(2)]],
    constant PosInfo& pos [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    if (tid >= q_total) {
        return;
    }
    uint head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint pair = dim >> 1u;
    uint even = pair << 1u;
    uint odd = even + 1u;
    if (odd >= config.head_dim) {
        return;
    }

    float angle = float(pos.token_index) * pow(10000.0f, -float(2u * pair) / float(config.head_dim));
    float c = cos(angle);
    float s = sin(angle);

    if ((dim & 1u) == 0u) {
        float q0 = float(q[head * config.head_dim + even]);
        float q1 = float(q[head * config.head_dim + odd]);
        q[head * config.head_dim + even] = half(q0 * c - q1 * s);
        q[head * config.head_dim + odd] = half(q0 * s + q1 * c);

        uint kv_head = head % config.kv_heads;
        uint k_base = kv_head * config.head_dim;
        float k0 = float(k[k_base + even]);
        float k1 = float(k[k_base + odd]);
        k[k_base + even] = half(k0 * c - k1 * s);
        k[k_base + odd] = half(k0 * s + k1 * c);
    }
}

kernel void rope_kv_only(
    device half* k [[buffer(0)]],
    constant ModelConfig& config [[buffer(2)]],
    constant PosInfo& pos [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid >= kv_total) {
        return;
    }
    uint kv_head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint pair = dim >> 1u;
    uint even = pair << 1u;
    uint odd = even + 1u;
    if (odd >= config.head_dim) {
        return;
    }

    float angle = float(pos.token_index) * pow(10000.0f, -float(2u * pair) / float(config.head_dim));
    float c = cos(angle);
    float s = sin(angle);

    if ((dim & 1u) == 0u) {
        uint base = kv_head * config.head_dim;
        float k0 = float(k[base + even]);
        float k1 = float(k[base + odd]);
        k[base + even] = half(k0 * c - k1 * s);
        k[base + odd] = half(k0 * s + k1 * c);
    }
}
