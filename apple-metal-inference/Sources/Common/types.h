#ifndef SOVEREIGN_INFERENCE_TYPES_H
#define SOVEREIGN_INFERENCE_TYPES_H

#include <metal_stdlib>
using namespace metal;

struct ModelConfig {
    uint hidden;
    uint intermediate;
    uint q_heads;
    uint kv_heads;
    uint head_dim;
    uint vocab;
    uint context;
    uint layers;
    uint layer_index;
    uint position;
    uint token_count;
    float epsilon;
};

struct LinearShape {
    uint rows;
    uint cols;
    uint stride;
};

struct PosInfo {
    uint token_index;
    uint seq_len;
    uint layer_index;
};

struct AttentionSpec {
    uint heads;
    uint kv_heads;
    uint head_dim;
    uint length;
    uint offset;
    uint mask;
};

struct CacheSpec {
    uint layer;
    uint token;
    uint kv_head;
    uint position;
    uint head_dim;
};

struct QuantSpec {
    uint quant_bits;
    uint row_stride;
    uint scale_stride;
    uint zero_stride;
    uint has_bias;
};

inline uint packed_index(uint row, uint col, uint cols) {
    return row * ((cols + 1u) >> 1u) + (col >> 1u);
}

inline int signed_nibble(uint nibble) {
    int v = int(nibble);
    if (v >= 8) {
        v -= 16;
    }
    return v;
}

inline float clampf(float x, float lo, float hi) {
    return min(max(x, lo), hi);
}

inline float silu(float x) {
    return x / (1.0f + exp(-clampf(x, -80.0f, 80.0f)));
}

inline float safe_rsqrt(float x) {
    return rsqrt(max(x, 1.0e-6f));
}

inline uint kv_offset(uint token, uint kv_head, uint head_dim, uint kv_heads) {
    return ((token * kv_heads) + kv_head) * head_dim;
}

inline uint qkv_index(uint head, uint dim, uint head_dim) {
    return head * head_dim + dim;
}

inline float attention_scale(uint head_dim) {
    return 1.0f / sqrt(float(head_dim));
}

inline float stable_exp(float x, float maxv) {
    return exp(x - maxv);
}

inline float dequant_i4(device const uchar* w,
                        device const half* s,
                        uint row,
                        uint col,
                        uint cols) {
    uint idx = packed_index(row, col, cols);
    uchar packed = w[idx];
    uint nibble = ((col & 1u) == 0u) ? (packed & 0x0Fu) : (packed >> 4u);
    return float(signed_nibble(nibble)) * float(s[row]);
}

inline float dequant_i8(device const uchar* w,
                        device const half* s,
                        uint row,
                        uint col,
                        uint cols) {
    uint idx = row * cols + col;
    int8_t v = int8_t(w[idx]);
    return float(v) * float(s[row]);
}

#endif
