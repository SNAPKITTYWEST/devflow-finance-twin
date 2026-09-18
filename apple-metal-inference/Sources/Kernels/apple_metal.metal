#include <metal_stdlib>
using namespace metal;

#define M_PI_F 3.14159265358979323846f
#define THREAD_GROUP_SIZE 256u
#define MAX_BATCH 8u
#define MAX_CONTEXT 4096u
#define MAX_VOCAB 32000u
#define MAX_LAYERS 32u
#define MAX_HEADS 32u
#define MAX_KV_HEADS 16u
#define MAX_HEAD_DIM 256u
#define MAX_MLP 8192u

struct ModelConfig {
    uint hidden;
    uint intermediate;
    uint q_heads;
    uint kv_heads;
    uint head_dim;
    uint vocab;
    uint context;
    uint layers;
    uint vocab_offset;
    float epsilon;
    float rope_base;
    float temperature;
};

struct LinearShape {
    uint rows;
    uint cols;
    uint batch;
};

struct AttentionInfo {
    uint q_heads;
    uint kv_heads;
    uint head_dim;
    uint seq_len;
    uint position;
    uint layer;
    uint batch;
};

struct KVLayout {
    uint layer;
    uint position;
    uint kv_head;
    uint head_dim;
    uint token_offset;
    uint stride;
};

struct MatmulJob {
    uint rows;
    uint cols;
    uint batch;
    uint out_offset;
    uint in_offset;
    uint w_offset;
};

struct TokenStep {
    uint token;
    uint position;
    uint layer;
    uint batch;
};

struct TokenState {
    uint token;
    uint pos;
    uint head;
    uint kv_index;
    uint slot;
};

inline uint packed_i4_index(uint row, uint col, uint cols) {
    return row * ((cols + 1u) >> 1u) + (col >> 1u);
}

inline int signed_nibble_value(uint nibble) {
    int v = int(nibble);
    if (v >= 8) {
        v -= 16;
    }
    return v;
}

inline uint packed_i8_index(uint row, uint col, uint cols) {
    return row * cols + col;
}

inline float dequant_i4_signed(device const uchar* w, device const half* scale, uint row, uint col, uint cols) {
    uint packed_index = packed_i4_index(row, col, cols);
    uchar packed = w[packed_index];
    uint nibble = ((col & 1u) == 0u) ? (packed & 0x0Fu) : (packed >> 4u);
    return float(signed_nibble_value(nibble)) * float(scale[row]);
}

inline float dequant_i8_signed(device const uchar* w, device const half* scale, uint row, uint col, uint cols) {
    uint idx = packed_i8_index(row, col, cols);
    int8_t v = int8_t(w[idx]);
    return float(v) * float(scale[row]);
}

inline float clampf(float x, float lo, float hi) {
    return min(max(x, lo), hi);
}

inline float safe_rsqrt(float x) {
    return rsqrt(max(x, 1.0e-6f));
}

inline float silu(float x) {
    return x / (1.0f + exp(-clampf(x, -80.0f, 80.0f)));
}

inline float gelu(float x) {
    float cdf = 0.5f * (1.0f + tanh(0.7978845608f * (x + 0.044715f * x * x * x)));
    return x * cdf;
}

inline float ropescale(uint dim, uint pos, float base) {
    return float(pos) * pow(base, -float(2u * (dim % (dim / 2u))) / float(dim));
}

inline float reduce_sum_float(float x, float y) {
    return x + y;
}

inline uint kv_offset(uint token, uint kv_head, uint head_dim, uint kv_heads) {
    return ((token * kv_heads) + kv_head) * head_dim;
}

inline uint qkv_offset(uint head, uint dim, uint head_dim) {
    return head * head_dim + dim;
}

inline float stable_exp(float x, float mx) {
    return exp(x - mx);
}

kernel void embedding_kernel(
    device const half* embedding_table [[buffer(0)]],
    device const uint* token_ids [[buffer(1)]],
    device half* hidden_state [[buffer(2)]],
    constant ModelConfig& cfg [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < cfg.hidden) {
        uint token = token_ids[0];
        hidden_state[tid] = embedding_table[token * cfg.hidden + tid];
    }
}

kernel void embedding_batch_kernel(
    device const half* embedding_table [[buffer(0)]],
    device const uint* token_ids [[buffer(1)]],
    device half* hidden_state [[buffer(2)]],
    constant ModelConfig& cfg [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = cfg.hidden * cfg.context;
    if (tid >= total) {
        return;
    }
    uint token_idx = tid / cfg.hidden;
    uint feature_idx = tid % cfg.hidden;
    uint token = token_ids[token_idx];
    hidden_state[feature_idx + token_idx * cfg.hidden] = embedding_table[token * cfg.hidden + feature_idx];
}

kernel void rmsnorm_kernel(
    device const half* x [[buffer(0)]],
    device const half* weight [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& cfg [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= cfg.hidden) {
        return;
    }
    float acc = 0.0f;
    for (uint i = 0u; i < cfg.hidden; ++i) {
        float v = float(x[i]);
        acc += v * v;
    }
    float inv = safe_rsqrt(acc / float(cfg.hidden) + cfg.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(weight[tid]));
}

kernel void rmsnorm_tiled_kernel(
    device const half* x [[buffer(0)]],
    device const half* weight [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& cfg [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= cfg.hidden) {
        return;
    }
    float sum = 0.0f;
    for (uint i = 0u; i < cfg.hidden; ++i) {
        sum += float(x[i]) * float(x[i]);
    }
    float inv = safe_rsqrt(sum / float(cfg.hidden) + cfg.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(weight[tid]));
}

kernel void layernorm_kernel(
    device const half* x [[buffer(0)]],
    device const half* weight [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device half* y [[buffer(3)]],
    constant ModelConfig& cfg [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= cfg.hidden) {
        return;
    }
    float mean = 0.0f;
    float var = 0.0f;
    for (uint i = 0u; i < cfg.hidden; ++i) {
        mean += float(x[i]);
    }
    mean /= float(cfg.hidden);
    for (uint i = 0u; i < cfg.hidden; ++i) {
        float dv = float(x[i]) - mean;
        var += dv * dv;
    }
    var /= float(cfg.hidden);
    float inv = safe_rsqrt(var + cfg.epsilon);
    y[tid] = half((float(x[tid]) - mean) * inv * float(weight[tid]) + float(bias[tid]));
}

kernel void rope_q_kernel(
    device half* q [[buffer(0)]],
    device half* k [[buffer(1)]],
    constant ModelConfig& cfg [[buffer(2)]],
    constant TokenStep& step [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = cfg.q_heads * cfg.head_dim;
    if (tid >= total) {
        return;
    }
    uint head = tid / cfg.head_dim;
    uint dim = tid % cfg.head_dim;
    uint pair = dim >> 1u;
    uint even = (pair << 1u);
    uint odd = even + 1u;

    float angle = float(step.position) * pow(cfg.rope_base, -float(2u * pair) / float(cfg.head_dim));
    float cs = cos(angle);
    float sn = sin(angle);

    if ((dim & 1u) == 0u) {
        float q0 = float(q[head * cfg.head_dim + even]);
        float q1 = float(q[head * cfg.head_dim + odd]);
        q[head * cfg.head_dim + even] = half(q0 * cs - q1 * sn);
        q[head * cfg.head_dim + odd] = half(q0 * sn + q1 * cs);
    }

    uint kv_head = head % cfg.kv_heads;
    uint k_base = kv_head * cfg.head_dim;
    float k0 = float(k[k_base + even]);
    float k1 = float(k[k_base + odd]);
    k[k_base + even] = half(k0 * cs - k1 * sn);
    k[k_base + odd] = half(k0 * sn + k1 * cs);
}

kernel void rope_qkv_kernel(
    device half* q [[buffer(0)]],
    device half* k [[buffer(1)]],
    device half* v [[buffer(2)]],
    constant ModelConfig& cfg [[buffer(3)]],
    constant TokenStep& step [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = cfg.q_heads * cfg.head_dim;
    if (tid >= q_total) {
        return;
    }
    uint head = tid / cfg.head_dim;
    uint dim = tid % cfg.head_dim;
    uint pair = dim >> 1u;
    uint even = (pair << 1u);
    uint odd = even + 1u;

    float angle = float(step.position) * pow(cfg.rope_base, -float(2u * pair) / float(cfg.head_dim));
    float cs = cos(angle);
    float sn = sin(angle);

    float q0 = float(q[head * cfg.head_dim + even]);
    float q1 = float(q[head * cfg.head_dim + odd]);
    q[head * cfg.head_dim + even] = half(q0 * cs - q1 * sn);
    q[head * cfg.head_dim + odd] = half(q0 * sn + q1 * cs);

    uint kv_head = head % cfg.kv_heads;
    uint kb = kv_head * cfg.head_dim;
    float k0 = float(k[kb + even]);
    float k1 = float(k[kb + odd]);
    k[kb + even] = half(k0 * cs - k1 * sn);
    k[kb + odd] = half(k0 * sn + k1 * cs);
    v[tid % cfg.head_dim] = v[tid % cfg.head_dim];
}

kernel void qkv_projection_kernel(
    device const uchar* wq [[buffer(0)]],
    device const half* sq [[buffer(1)]],
    device const uchar* wk [[buffer(2)]],
    device const half* sk [[buffer(3)]],
    device const uchar* wv [[buffer(4)]],
    device const half* sv [[buffer(5)]],
    device const half* input [[buffer(6)]],
    device half* q_out [[buffer(7)]],
    device half* k_out [[buffer(8)]],
    device half* v_out [[buffer(9)]],
    constant LinearShape& qshape [[buffer(10)]],
    constant LinearShape& kshape [[buffer(11)]],
    constant LinearShape& vshape [[buffer(12)]],
    uint row [[thread_position_in_grid]])
{
    if (row < qshape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < qshape.cols; ++col) {
            acc += dequant_i4_signed(wq, sq, row, col, qshape.cols) * float(input[col]);
        }
        q_out[row] = half(acc);
    }

    if (row < kshape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < kshape.cols; ++col) {
            acc += dequant_i4_signed(wk, sk, row, col, kshape.cols) * float(input[col]);
        }
        k_out[row] = half(acc);
    }

    if (row < vshape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < vshape.cols; ++col) {
            acc += dequant_i4_signed(wv, sv, row, col, vshape.cols) * float(input[col]);
        }
        v_out[row] = half(acc);
    }
}

kernel void qkv_projection_i8_kernel(
    device const uchar* wq [[buffer(0)]],
    device const half* sq [[buffer(1)]],
    device const uchar* wk [[buffer(2)]],
    device const half* sk [[buffer(3)]],
    device const uchar* wv [[buffer(4)]],
    device const half* sv [[buffer(5)]],
    device const half* input [[buffer(6)]],
    device half* q_out [[buffer(7)]],
    device half* k_out [[buffer(8)]],
    device half* v_out [[buffer(9)]],
    constant LinearShape& qshape [[buffer(10)]],
    constant LinearShape& kshape [[buffer(11)]],
    constant LinearShape& vshape [[buffer(12)]],
    uint row [[thread_position_in_grid]])
{
    if (row < qshape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < qshape.cols; ++col) {
            acc += dequant_i8_signed(wq, sq, row, col, qshape.cols) * float(input[col]);
        }
        q_out[row] = half(acc);
    }

    if (row < kshape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < kshape.cols; ++col) {
            acc += dequant_i8_signed(wk, sk, row, col, kshape.cols) * float(input[col]);
        }
        k_out[row] = half(acc);
    }

    if (row < vshape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < vshape.cols; ++col) {
            acc += dequant_i8_signed(wv, sv, row, col, vshape.cols) * float(input[col]);
        }
        v_out[row] = half(acc);
    }
}

kernel void quantized_matmul_kernel(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* input [[buffer(2)]],
    device half* output [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4_signed(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matmul_i8_kernel(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* input [[buffer(2)]],
    device half* output [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8_signed(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matmul_bias_kernel(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device const half* input [[buffer(3)]],
    device half* output [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4_signed(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matmul_bias_i8_kernel(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device const half* input [[buffer(3)]],
    device half* output [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8_signed(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void attention_score_kernel(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device half* scores [[buffer(2)]],
    constant AttentionInfo& info [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / info.seq_len;
    uint token = tid % info.seq_len;
    if (head >= info.q_heads || token >= info.seq_len) {
        return;
    }
    uint kv_head = head % info.kv_heads;
    float scale = safe_rsqrt(float(info.head_dim));
    float acc = 0.0f;
    uint q_base = head * info.head_dim;
    uint k_base = kv_offset(token, kv_head, info.head_dim, info.kv_heads);
    for (uint d = 0u; d < info.head_dim; ++d) {
        acc += float(q[q_base + d]) * float(k_cache[k_base + d]);
    }
    scores[tid] = half(acc * scale);
}

kernel void attention_score_cache_kernel(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device half* scores [[buffer(2)]],
    constant AttentionInfo& info [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / info.seq_len;
    uint token = tid % info.seq_len;
    if (head >= info.q_heads || token >= info.seq_len) {
        return;
    }
    uint kv_head = head % info.kv_heads;
    uint q_base = head * info.head_dim;
    uint k_base = kv_offset(token, kv_head, info.head_dim, info.kv_heads);
    float acc = 0.0f;
    for (uint d = 0u; d < info.head_dim; ++d) {
        acc += float(q[q_base + d]) * float(k_cache[k_base + d]);
    }
    scores[tid] = half(acc * safe_rsqrt(float(info.head_dim)));
}

kernel void causal_mask_kernel(
    device half* scores [[buffer(0)]],
    constant AttentionInfo& info [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= info.q_heads * info.seq_len) {
        return;
    }
    uint head = tid / info.seq_len;
    uint token = tid % info.seq_len;
    if (token > info.position) {
        scores[tid] = half(-INFINITY);
    }
}

kernel void softmax_kernel(
    device half* scores [[buffer(0)]],
    constant AttentionInfo& info [[buffer(1)]],
    uint head [[thread_position_in_grid]])
{
    if (head >= info.q_heads) {
        return;
    }
    float max_v = -INFINITY;
    for (uint t = 0u; t < info.seq_len; ++t) {
        float v = float(scores[head * info.seq_len + t]);
        max_v = max(max_v, v);
    }
    float denom = 0.0f;
    for (uint t = 0u; t < info.seq_len; ++t) {
        float e = exp(float(scores[head * info.seq_len + t]) - max_v);
        scores[head * info.seq_len + t] = half(e);
        denom += e;
    }
    float inv = 1.0f / max(denom, 1.0e-20f);
    for (uint t = 0u; t < info.seq_len; ++t) {
        scores[head * info.seq_len + t] = half(float(scores[head * info.seq_len + t]) * inv);
    }
}

kernel void softmax_masked_kernel(
    device half* scores [[buffer(0)]],
    constant AttentionInfo& info [[buffer(1)]],
    uint head [[thread_position_in_grid]])
{
    if (head >= info.q_heads) {
        return;
    }
    float max_v = -INFINITY;
    for (uint t = 0u; t <= info.position; ++t) {
        float v = float(scores[head * info.seq_len + t]);
        max_v = max(max_v, v);
    }
    float denom = 0.0f;
    for (uint t = 0u; t <= info.position; ++t) {
        float e = exp(float(scores[head * info.seq_len + t]) - max_v);
        scores[head * info.seq_len + t] = half(e);
        denom += e;
    }
    float inv = 1.0f / max(denom, 1.0e-20f);
    for (uint t = 0u; t <= info.position; ++t) {
        scores[head * info.seq_len + t] = half(float(scores[head * info.seq_len + t]) * inv);
    }
}

kernel void attention_value_kernel(
    device const half* scores [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant AttentionInfo& info [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / info.head_dim;
    uint dim = tid % info.head_dim;
    if (head >= info.q_heads || dim >= info.head_dim) {
        return;
    }
    uint kv_head = head % info.kv_heads;
    float acc = 0.0f;
    for (uint t = 0u; t <= info.position; ++t) {
        float w = float(scores[head * info.seq_len + t]);
        uint v_base = kv_offset(t, kv_head, info.head_dim, info.kv_heads);
        acc += w * float(v_cache[v_base + dim]);
    }
    output[tid] = half(acc);
}

kernel void attention_value_ragged_kernel(
    device const half* scores [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant AttentionInfo& info [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / info.head_dim;
    uint dim = tid % info.head_dim;
    if (head >= info.q_heads || dim >= info.head_dim) {
        return;
    }
    uint kv_head = head % info.kv_heads;
    float acc = 0.0f;
    for (uint t = 0u; t <= info.position; ++t) {
        float w = float(scores[head * info.seq_len + t]);
        uint v_base = kv_offset(t, kv_head, info.head_dim, info.kv_heads);
        acc += w * float(v_cache[v_base + dim]);
    }
    output[tid] = half(acc);
}

kernel void output_projection_kernel(
    device const half* hidden [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* logits [[buffer(4)]],
    constant LinearShape& outshape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= outshape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < outshape.cols; ++col) {
        acc += dequant_i4_signed(weight, scale, row, col, outshape.cols) * float(hidden[col]);
    }
    logits[row] = half(acc);
}

kernel void output_projection_i8_kernel(
    device const half* hidden [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* logits [[buffer(4)]],
    constant LinearShape& outshape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= outshape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < outshape.cols; ++col) {
        acc += dequant_i8_signed(weight, scale, row, col, outshape.cols) * float(hidden[col]);
    }
    logits[row] = half(acc);
}

kernel void swiglu_kernel(
    device const half* gate [[buffer(0)]],
    device const half* up [[buffer(1)]],
    device half* output [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= count) {
        return;
    }
    output[tid] = half(silu(float(gate[tid])) * float(up[tid]));
}

kernel void swiglu_gate_kernel(
    device const half* gate [[buffer(0)]],
    device const half* up [[buffer(1)]],
    device half* hidden [[buffer(2)]],
    device half* output [[buffer(3)]],
    constant LinearShape& mlp [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= mlp.cols) {
        return;
    }
    hidden[tid] = half(silu(float(gate[tid])) * float(up[tid]));
    output[tid] = hidden[tid];
}

kernel void mlp_projection_kernel(
    device const half* input [[buffer(0)]],
    device const uchar* w1 [[buffer(1)]],
    device const half* s1 [[buffer(2)]],
    device const half* g1 [[buffer(3)]],
    device const uchar* w2 [[buffer(4)]],
    device const half* s2 [[buffer(5)]],
    device const half* g2 [[buffer(6)]],
    device half* h1 [[buffer(7)]],
    device half* h2 [[buffer(8)]],
    device half* out [[buffer(9)]],
    constant LinearShape& shape [[buffer(10)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= shape.cols) {
        return;
    }
    float acc1 = 0.0f;
    for (uint col = 0u; col < shape.rows; ++col) {
        acc1 += dequant_i4_signed(w1, s1, tid, col, shape.rows) * float(input[col]);
    }
    h1[tid] = half(acc1);

    float acc2 = 0.0f;
    for (uint col = 0u; col < shape.rows; ++col) {
        acc2 += dequant_i4_signed(w2, s2, tid, col, shape.rows) * float(input[col]);
    }
    h2[tid] = half(acc2);

    out[tid] = half(silu(float(g1[tid])) * float(h2[tid]));
}

kernel void residual_add_kernel(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* output [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        output[tid] = half(float(a[tid]) + float(b[tid]));
    }
}

kernel void residual_scale_kernel(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant float& scale [[buffer(3)]],
    uint count [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        output[tid] = half(float(a[tid]) + scale * float(b[tid]));
    }
}

kernel void kv_cache_store_kernel(
    device const half* k [[buffer(0)]],
    device const half* v [[buffer(1)]],
    device half* k_cache [[buffer(2)]],
    device half* v_cache [[buffer(3)]],
    constant KVLayout& layout [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = layout.kv_head * layout.head_dim;
    if (tid >= total) {
        return;
    }
    uint offset = ((layout.layer * 4096u + layout.position) * 8u + layout.kv_head) * layout.head_dim + tid;
    k_cache[offset] = k[tid];
    v_cache[offset] = v[tid];
}

kernel void kv_cache_store_head_kernel(
    device const half* k [[buffer(0)]],
    device const half* v [[buffer(1)]],
    device half* k_cache [[buffer(2)]],
    device half* v_cache [[buffer(3)]],
    constant KVLayout& layout [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = layout.kv_head * layout.head_dim;
    if (tid >= total) {
        return;
    }
    uint offset = ((layout.layer * 4096u + layout.position) * 8u + layout.kv_head) * layout.head_dim + tid;
    k_cache[offset] = k[tid];
    v_cache[offset] = v[tid];
}

kernel void kv_cache_load_kernel(
    device const half* k_cache [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant KVLayout& layout [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = layout.kv_head * layout.head_dim;
    if (tid >= total) {
        return;
    }
    uint offset = ((layout.layer * 4096u + layout.position) * 8u + layout.kv_head) * layout.head_dim + tid;
    output[tid] = k_cache[offset] + v_cache[offset];
}

kernel void final_norm_kernel(
    device const half* x [[buffer(0)]],
    device const half* weight [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& cfg [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= cfg.hidden) {
        return;
    }
    float sum = 0.0f;
    for (uint i = 0u; i < cfg.hidden; ++i) {
        sum += float(x[i]) * float(x[i]);
    }
    float inv = safe_rsqrt(sum / float(cfg.hidden) + cfg.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(weight[tid]));
}

kernel void logits_kernel(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* x [[buffer(2)]],
    device half* logits [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4_signed(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    logits[row] = half(acc);
}

kernel void logits_kernel_i8(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* x [[buffer(2)]],
    device half* logits [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8_signed(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    logits[row] = half(acc);
}

kernel void greedy_select_kernel(
    device const half* logits [[buffer(0)]],
    device const half* out_token [[buffer(1)]],
    constant uint& vocab_size [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 1u) {
        return;
    }
    float best = -INFINITY;
    uint best_index = 0u;
    for (uint i = 0u; i < vocab_size; ++i) {
        float v = float(logits[i]);
        if (v > best) {
            best = v;
            best_index = i;
        }
    }
    out_token[0] = half(best_index);
}

kernel void generate_step_kernel(
    device const half* hidden_state [[buffer(0)]],
    device const uchar* wq [[buffer(1)]],
    device const half* sq [[buffer(2)]],
    device const uchar* wk [[buffer(3)]],
    device const half* sk [[buffer(4)]],
    device const uchar* wv [[buffer(5)]],
    device const half* sv [[buffer(6)]],
    device const half* input [[buffer(7)]],
    device half* output [[buffer(8)]],
    constant LinearShape& shape [[buffer(9)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4_signed(wq, sq, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4_signed(wk, sk, row, col, shape.cols) * float(input[col]);
    }
}

kernel void kernel_000(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]));
    }
}

kernel void kernel_001(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * float(y[tid]));
    }
}

kernel void kernel_002(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + 0.5f * float(y[tid]));
    }
}

kernel void kernel_003(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 0.5f + float(y[tid]));
    }
}

kernel void kernel_004(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 0.5f);
    }
}

kernel void kernel_005(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) - float(y[tid]));
    }
}

kernel void kernel_006(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) / max(float(y[tid]), 1.0e-6f));
    }
}

kernel void kernel_007(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * float(y[tid]) * 0.5f);
    }
}

kernel void kernel_008(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) + 0.5f);
    }
}

kernel void kernel_009(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * float(y[tid]) + 0.5f);
    }
}

kernel void kernel_010(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 0.25f);
    }
}

kernel void kernel_011(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) - float(y[tid]) * 0.25f);
    }
}

kernel void kernel_012(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * float(y[tid]) * 1.5f);
    }
}

kernel void kernel_013(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) + 1.0f);
    }
}

kernel void kernel_014(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * float(y[tid]) - 0.5f);
    }
}

kernel void kernel_015(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 2.0f);
    }
}

kernel void kernel_016(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 2.0f + float(y[tid]));
    }
}

kernel void kernel_017(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 2.0f + float(y[tid]) * 2.0f);
    }
}

kernel void kernel_018(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) - float(y[tid]) * 2.0f);
    }
}

kernel void kernel_019(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 0.25f + float(y[tid]));
    }
}

kernel void kernel_020(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 0.75f);
    }
}

kernel void kernel_021(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 0.75f + float(y[tid]));
    }
}

kernel void kernel_022(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 1.25f);
    }
}

kernel void kernel_023(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 1.25f + float(y[tid]));
    }
}

kernel void kernel_024(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 1.5f);
    }
}

kernel void kernel_025(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 1.5f + float(y[tid]));
    }
}

kernel void kernel_026(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 1.75f);
    }
}

kernel void kernel_027(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 1.75f + float(y[tid]));
    }
}

kernel void kernel_028(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 2.25f);
    }
}

kernel void kernel_029(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 2.25f + float(y[tid]));
    }
}

kernel void kernel_030(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 2.5f);
    }
}

kernel void kernel_031(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 2.5f + float(y[tid]));
    }
}

kernel void kernel_032(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 2.75f);
    }
}

kernel void kernel_033(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 2.75f + float(y[tid]));
    }
}

kernel void kernel_034(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 3.0f);
    }
}

kernel void kernel_035(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 3.0f + float(y[tid]));
    }
}

kernel void kernel_036(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 3.25f);
    }
}

kernel void kernel_037(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 3.25f + float(y[tid]));
    }
}

kernel void kernel_038(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 3.5f);
    }
}

kernel void kernel_039(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 3.5f + float(y[tid]));
    }
}

kernel void kernel_040(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 3.75f);
    }
}

kernel void kernel_041(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 3.75f + float(y[tid]));
    }
}

kernel void kernel_042(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 4.0f);
    }
}

kernel void kernel_043(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 4.0f + float(y[tid]));
    }
}

kernel void kernel_044(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 4.25f);
    }
}

kernel void kernel_045(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 4.25f + float(y[tid]));
    }
}

kernel void kernel_046(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 4.5f);
    }
}

kernel void kernel_047(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 4.5f + float(y[tid]));
    }
}

kernel void kernel_048(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 4.75f);
    }
}

kernel void kernel_049(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 4.75f + float(y[tid]));
    }
}

kernel void kernel_050(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 5.0f);
    }
}

kernel void kernel_051(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 5.0f + float(y[tid]));
    }
}

kernel void kernel_052(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 5.25f);
    }
}

kernel void kernel_053(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 5.25f + float(y[tid]));
    }
}

kernel void kernel_054(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 5.5f);
    }
}

kernel void kernel_055(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 5.5f + float(y[tid]));
    }
}

kernel void kernel_056(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 5.75f);
    }
}

kernel void kernel_057(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 5.75f + float(y[tid]));
    }
}

kernel void kernel_058(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 6.0f);
    }
}

kernel void kernel_059(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 6.0f + float(y[tid]));
    }
}

kernel void kernel_060(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 6.25f);
    }
}

kernel void kernel_061(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 6.25f + float(y[tid]));
    }
}

kernel void kernel_062(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 6.5f);
    }
}

kernel void kernel_063(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 6.5f + float(y[tid]));
    }
}

kernel void kernel_064(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 6.75f);
    }
}

kernel void kernel_065(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 6.75f + float(y[tid]));
    }
}

kernel void kernel_066(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 7.0f);
    }
}

kernel void kernel_067(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 7.0f + float(y[tid]));
    }
}

kernel void kernel_068(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 7.25f);
    }
}

kernel void kernel_069(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 7.25f + float(y[tid]));
    }
}

kernel void kernel_070(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 7.5f);
    }
}

kernel void kernel_071(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 7.5f + float(y[tid]));
    }
}

kernel void kernel_072(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 7.75f);
    }
}

kernel void kernel_073(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 7.75f + float(y[tid]));
    }
}

kernel void kernel_074(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 8.0f);
    }
}

kernel void kernel_075(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 8.0f + float(y[tid]));
    }
}

kernel void kernel_076(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 8.25f);
    }
}

kernel void kernel_077(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 8.25f + float(y[tid]));
    }
}

kernel void kernel_078(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 8.5f);
    }
}

kernel void kernel_079(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 8.5f + float(y[tid]));
    }
}

kernel void kernel_080(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 8.75f);
    }
}

kernel void kernel_081(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 8.75f + float(y[tid]));
    }
}

kernel void kernel_082(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 9.0f);
    }
}

kernel void kernel_083(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 9.0f + float(y[tid]));
    }
}

kernel void kernel_084(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 9.25f);
    }
}

kernel void kernel_085(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 9.25f + float(y[tid]));
    }
}

kernel void kernel_086(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 9.5f);
    }
}

kernel void kernel_087(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 9.5f + float(y[tid]));
    }
}

kernel void kernel_088(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 9.75f);
    }
}

kernel void kernel_089(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 9.75f + float(y[tid]));
    }
}

kernel void kernel_090(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 10.0f);
    }
}

kernel void kernel_091(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 10.0f + float(y[tid]));
    }
}

kernel void kernel_092(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 10.25f);
    }
}

kernel void kernel_093(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 10.25f + float(y[tid]));
    }
}

kernel void kernel_094(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 10.5f);
    }
}

kernel void kernel_095(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 10.5f + float(y[tid]));
    }
}

kernel void kernel_096(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 10.75f);
    }
}

kernel void kernel_097(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 10.75f + float(y[tid]));
    }
}

kernel void kernel_098(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 11.0f);
    }
}

kernel void kernel_099(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 11.0f + float(y[tid]));
    }
}

kernel void kernel_100(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 11.25f);
    }
}

kernel void kernel_101(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 11.25f + float(y[tid]));
    }
}

kernel void kernel_102(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 11.5f);
    }
}

kernel void kernel_103(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 11.5f + float(y[tid]));
    }
}

kernel void kernel_104(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 11.75f);
    }
}

kernel void kernel_105(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 11.75f + float(y[tid]));
    }
}

kernel void kernel_106(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 12.0f);
    }
}

kernel void kernel_107(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 12.0f + float(y[tid]));
    }
}

kernel void kernel_108(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 12.25f);
    }
}

kernel void kernel_109(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 12.25f + float(y[tid]));
    }
}

kernel void kernel_110(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 12.5f);
    }
}

kernel void kernel_111(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 12.5f + float(y[tid]));
    }
}

kernel void kernel_112(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 12.75f);
    }
}

kernel void kernel_113(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 12.75f + float(y[tid]));
    }
}

kernel void kernel_114(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 13.0f);
    }
}

kernel void kernel_115(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 13.0f + float(y[tid]));
    }
}

kernel void kernel_116(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 13.25f);
    }
}

kernel void kernel_117(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 13.25f + float(y[tid]));
    }
}

kernel void kernel_118(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 13.5f);
    }
}

kernel void kernel_119(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 13.5f + float(y[tid]));
    }
}

kernel void kernel_120(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 13.75f);
    }
}

kernel void kernel_121(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 13.75f + float(y[tid]));
    }
}

kernel void kernel_122(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 14.0f);
    }
}

kernel void kernel_123(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 14.0f + float(y[tid]));
    }
}

kernel void kernel_124(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 14.25f);
    }
}

kernel void kernel_125(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 14.25f + float(y[tid]));
    }
}

kernel void kernel_126(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 14.5f);
    }
}

kernel void kernel_127(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 14.5f + float(y[tid]));
    }
}

kernel void kernel_128(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 14.75f);
    }
}

kernel void kernel_129(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 14.75f + float(y[tid]));
    }
}

kernel void kernel_130(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 15.0f);
    }
}

kernel void kernel_131(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 15.0f + float(y[tid]));
    }
}

kernel void kernel_132(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 15.25f);
    }
}

kernel void kernel_133(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 15.25f + float(y[tid]));
    }
}

kernel void kernel_134(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 15.5f);
    }
}

kernel void kernel_135(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 15.5f + float(y[tid]));
    }
}

kernel void kernel_136(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 15.75f);
    }
}

kernel void kernel_137(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 15.75f + float(y[tid]));
    }
}

kernel void kernel_138(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 16.0f);
    }
}

kernel void kernel_139(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 16.0f + float(y[tid]));
    }
}

kernel void kernel_140(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 16.25f);
    }
}

kernel void kernel_141(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 16.25f + float(y[tid]));
    }
}

kernel void kernel_142(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 16.5f);
    }
}

kernel void kernel_143(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 16.5f + float(y[tid]));
    }
}

kernel void kernel_144(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 16.75f);
    }
}

kernel void kernel_145(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 16.75f + float(y[tid]));
    }
}

kernel void kernel_146(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 17.0f);
    }
}

kernel void kernel_147(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 17.0f + float(y[tid]));
    }
}

kernel void kernel_148(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 17.25f);
    }
}

kernel void kernel_149(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 17.25f + float(y[tid]));
    }
}

kernel void kernel_150(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 17.5f);
    }
}

kernel void kernel_151(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 17.5f + float(y[tid]));
    }
}

kernel void kernel_152(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 17.75f);
    }
}

kernel void kernel_153(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 17.75f + float(y[tid]));
    }
}

kernel void kernel_154(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 18.0f);
    }
}

kernel void kernel_155(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 18.0f + float(y[tid]));
    }
}

kernel void kernel_156(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 18.25f);
    }
}

kernel void kernel_157(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 18.25f + float(y[tid]));
    }
}

kernel void kernel_158(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 18.5f);
    }
}

kernel void kernel_159(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 18.5f + float(y[tid]));
    }
}

kernel void kernel_160(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 18.75f);
    }
}

kernel void kernel_161(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 18.75f + float(y[tid]));
    }
}

kernel void kernel_162(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 19.0f);
    }
}

kernel void kernel_163(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 19.0f + float(y[tid]));
    }
}

kernel void kernel_164(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 19.25f);
    }
}

kernel void kernel_165(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 19.25f + float(y[tid]));
    }
}

kernel void kernel_166(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 19.5f);
    }
}

kernel void kernel_167(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 19.5f + float(y[tid]));
    }
}

kernel void kernel_168(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 19.75f);
    }
}

kernel void kernel_169(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 19.75f + float(y[tid]));
    }
}

kernel void kernel_170(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 20.0f);
    }
}

kernel void kernel_171(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 20.0f + float(y[tid]));
    }
}

kernel void kernel_172(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 20.25f);
    }
}

kernel void kernel_173(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 20.25f + float(y[tid]));
    }
}

kernel void kernel_174(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 20.5f);
    }
}

kernel void kernel_175(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 20.5f + float(y[tid]));
    }
}

kernel void kernel_176(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 20.75f);
    }
}

kernel void kernel_177(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 20.75f + float(y[tid]));
    }
}

kernel void kernel_178(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 21.0f);
    }
}

kernel void kernel_179(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 21.0f + float(y[tid]));
    }
}

kernel void kernel_180(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 21.25f);
    }
}

kernel void kernel_181(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 21.25f + float(y[tid]));
    }
}

kernel void kernel_182(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 21.5f);
    }
}

kernel void kernel_183(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 21.5f + float(y[tid]));
    }
}

kernel void kernel_184(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 21.75f);
    }
}

kernel void kernel_185(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 21.75f + float(y[tid]));
    }
}

kernel void kernel_186(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 22.0f);
    }
}

kernel void kernel_187(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 22.0f + float(y[tid]));
    }
}

kernel void kernel_188(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 22.25f);
    }
}

kernel void kernel_189(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 22.25f + float(y[tid]));
    }
}

kernel void kernel_190(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 22.5f);
    }
}

kernel void kernel_191(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 22.5f + float(y[tid]));
    }
}

kernel void kernel_192(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 22.75f);
    }
}

kernel void kernel_193(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 22.75f + float(y[tid]));
    }
}

kernel void kernel_194(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 23.0f);
    }
}

kernel void kernel_195(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 23.0f + float(y[tid]));
    }
}

kernel void kernel_196(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 23.25f);
    }
}

kernel void kernel_197(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 23.25f + float(y[tid]));
    }
}

kernel void kernel_198(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 23.5f);
    }
}

kernel void kernel_199(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 23.5f + float(y[tid]));
    }
}

kernel void kernel_200(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 23.75f);
    }
}

kernel void kernel_201(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 23.75f + float(y[tid]));
    }
}

kernel void kernel_202(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 24.0f);
    }
}

kernel void kernel_203(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 24.0f + float(y[tid]));
    }
}

kernel void kernel_204(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 24.25f);
    }
}

kernel void kernel_205(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 24.25f + float(y[tid]));
    }
}

kernel void kernel_206(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 24.5f);
    }
}

kernel void kernel_207(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 24.5f + float(y[tid]));
    }
}

kernel void kernel_208(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 24.75f);
    }
}

kernel void kernel_209(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 24.75f + float(y[tid]));
    }
}

kernel void kernel_210(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 25.0f);
    }
}

kernel void kernel_211(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 25.0f + float(y[tid]));
    }
}

kernel void kernel_212(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 25.25f);
    }
}

kernel void kernel_213(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 25.25f + float(y[tid]));
    }
}

kernel void kernel_214(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 25.5f);
    }
}

kernel void kernel_215(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 25.5f + float(y[tid]));
    }
}

kernel void kernel_216(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 25.75f);
    }
}

kernel void kernel_217(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 25.75f + float(y[tid]));
    }
}

kernel void kernel_218(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 26.0f);
    }
}

kernel void kernel_219(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 26.0f + float(y[tid]));
    }
}

kernel void kernel_220(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 26.25f);
    }
}

kernel void kernel_221(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 26.25f + float(y[tid]));
    }
}

kernel void kernel_222(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 26.5f);
    }
}

kernel void kernel_223(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 26.5f + float(y[tid]));
    }
}

kernel void kernel_224(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 26.75f);
    }
}

kernel void kernel_225(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 26.75f + float(y[tid]));
    }
}

kernel void kernel_226(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 27.0f);
    }
}

kernel void kernel_227(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 27.0f + float(y[tid]));
    }
}

kernel void kernel_228(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 27.25f);
    }
}

kernel void kernel_229(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 27.25f + float(y[tid]));
    }
}

kernel void kernel_230(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 27.5f);
    }
}

kernel void kernel_231(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 27.5f + float(y[tid]));
    }
}

kernel void kernel_232(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 27.75f);
    }
}

kernel void kernel_233(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 27.75f + float(y[tid]));
    }
}

kernel void kernel_234(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 28.0f);
    }
}

kernel void kernel_235(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 28.0f + float(y[tid]));
    }
}

kernel void kernel_236(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 28.25f);
    }
}

kernel void kernel_237(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 28.25f + float(y[tid]));
    }
}

kernel void kernel_238(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[bid]) * 2.0f);
    }
}

kernel void kernel_239(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 2.0f + float(y[tid]));
    }
}

kernel void kernel_240(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 2.5f);
    }
}

kernel void kernel_241(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 2.5f + float(y[tid]));
    }
}

kernel void kernel_242(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 3.0f);
    }
}

kernel void kernel_243(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 3.0f + float(y[tid]));
    }
}

kernel void kernel_244(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 3.5f);
    }
}

kernel void kernel_245(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 3.5f + float(y[tid]));
    }
}

kernel void kernel_246(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 4.0f);
    }
}

kernel void kernel_247(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 4.0f + float(y[tid]));
    }
}

kernel void kernel_248(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 4.5f);
    }
}

kernel void kernel_249(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 4.5f + float(y[tid]));
    }
}

kernel void kernel_250(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 5.0f);
    }
}

kernel void kernel_251(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 5.0f + float(y[tid]));
    }
}

kernel void kernel_252(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 5.5f);
    }
}

kernel void kernel_253(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 5.5f + float(y[tid]));
    }
}

kernel void kernel_254(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 6.0f);
    }
}

kernel void kernel_255(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 6.0f + float(y[tid]));
    }
}

kernel void kernel_256(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 6.5f);
    }
}

kernel void kernel_257(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 6.5f + float(y[tid]));
    }
}

kernel void kernel_258(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 7.0f);
    }
}

kernel void kernel_259(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 7.0f + float(y[tid]));
    }
}

kernel void kernel_260(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 7.5f);
    }
}

kernel void kernel_261(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 7.5f + float(y[tid]));
    }
}

kernel void kernel_262(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 8.0f);
    }
}

kernel void kernel_263(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 8.0f + float(y[tid]));
    }
}

kernel void kernel_264(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 8.5f);
    }
}

kernel void kernel_265(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 8.5f + float(y[tid]));
    }
}

kernel void kernel_266(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 9.0f);
    }
}

kernel void kernel_267(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 9.0f + float(y[tid]));
    }
}

kernel void kernel_268(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 9.5f);
    }
}

kernel void kernel_269(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 9.5f + float(y[tid]));
    }
}

kernel void kernel_270(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 10.0f);
    }
}

kernel void kernel_271(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 10.0f + float(y[tid]));
    }
}

kernel void kernel_272(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 10.5f);
    }
}

kernel void kernel_273(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 10.5f + float(y[tid]));
    }
}

kernel void kernel_274(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 11.0f);
    }
}

kernel void kernel_275(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 11.0f + float(y[tid]));
    }
}

kernel void kernel_276(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 11.5f);
    }
}

kernel void kernel_277(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 11.5f + float(y[tid]));
    }
}

kernel void kernel_278(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 12.0f);
    }
}

kernel void kernel_279(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 12.0f + float(y[tid]));
    }
}

kernel void kernel_280(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 12.5f);
    }
}

kernel void kernel_281(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 12.5f + float(y[tid]));
    }
}

kernel void kernel_282(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 13.0f);
    }
}

kernel void kernel_283(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 13.0f + float(y[tid]));
    }
}

kernel void kernel_284(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 13.5f);
    }
}

kernel void kernel_285(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 13.5f + float(y[tid]));
    }
}

kernel void kernel_286(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 14.0f);
    }
}

kernel void kernel_287(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 14.0f + float(y[tid]));
    }
}

kernel void kernel_288(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 14.5f);
    }
}

kernel void kernel_289(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 14.5f + float(y[tid]));
    }
}

kernel void kernel_290(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 15.0f);
    }
}

kernel void kernel_291(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 15.0f + float(y[tid]));
    }
}

kernel void kernel_292(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 15.5f);
    }
}

kernel void kernel_293(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 15.5f + float(y[tid]));
    }
}

kernel void kernel_294(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 16.0f);
    }
}

kernel void kernel_295(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 16.0f + float(y[tid]));
    }
}

kernel void kernel_296(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 16.5f);
    }
}

kernel void kernel_297(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 16.5f + float(y[tid]));
    }
}

kernel void kernel_298(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 17.0f);
    }
}

kernel void kernel_299(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 17.0f + float(y[tid]));
    }
}

kernel void kernel_300(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 17.5f);
    }
}

kernel void kernel_301(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 17.5f + float(y[tid]));
    }
}

kernel void kernel_302(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 18.0f);
    }
}

kernel void kernel_303(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 18.0f + float(y[tid]));
    }
}

kernel void kernel_304(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 18.5f);
    }
}

kernel void kernel_305(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 18.5f + float(y[tid]));
    }
}

kernel void kernel_306(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 19.0f);
    }
}

kernel void kernel_307(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 19.0f + float(y[tid]));
    }
}

kernel void kernel_308(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 19.5f);
    }
}

kernel void kernel_309(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 19.5f + float(y[tid]));
    }
}

kernel void kernel_310(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 20.0f);
    }
}

kernel void kernel_311(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 20.0f + float(y[tid]));
    }
}

kernel void kernel_312(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 20.5f);
    }
}

kernel void kernel_313(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 20.5f + float(y[tid]));
    }
}

kernel void kernel_314(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 21.0f);
    }
}

kernel void kernel_315(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 21.0f + float(y[tid]));
    }
}

kernel void kernel_316(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 21.5f);
    }
}

kernel void kernel_317(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 21.5f + float(y[tid]));
    }
}

kernel void kernel_318(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 22.0f);
    }
}

kernel void kernel_319(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 22.0f + float(y[tid]));
    }
}

kernel void kernel_320(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 22.5f);
    }
}

kernel void kernel_321(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 22.5f + float(y[tid]));
    }
}

kernel void kernel_322(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 23.0f);
    }
}

kernel void kernel_323(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 23.0f + float(y[tid]));
    }
}

kernel void kernel_324(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 23.5f);
    }
}

kernel void kernel_325(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 23.5f + float(y[tid]));
    }
}

kernel void kernel_326(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 24.0f);
    }
}

kernel void kernel_327(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 24.0f + float(y[tid]));
    }
}

kernel void kernel_328(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 24.5f);
    }
}

kernel void kernel_329(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 24.5f + float(y[tid]));
    }
}

kernel void kernel_330(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 25.0f);
    }
}

kernel void kernel_331(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 25.0f + float(y[tid]));
    }
}

kernel void kernel_332(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 25.5f);
    }
}

kernel void kernel_333(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 25.5f + float(y[tid]));
    }
}

kernel void kernel_334(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 26.0f);
    }
}

kernel void kernel_335(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 26.0f + float(y[tid]));
    }
}

kernel void kernel_336(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 26.5f);
    }
}

kernel void kernel_337(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 26.5f + float(y[tid]));
    }
}

kernel void kernel_338(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 27.0f);
    }
}

kernel void kernel_339(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 27.0f + float(y[tid]));
    }
}

kernel void kernel_340(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 27.5f);
    }
}

kernel void kernel_341(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 27.5f + float(y[tid]));
    }
}

kernel void kernel_342(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 28.0f);
    }
}

kernel void kernel_343(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 28.0f + float(y[tid]));
    }
}

kernel void kernel_344(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 28.5f);
    }
}

kernel void kernel_345(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 28.5f + float(y[tid]));
    }
}

kernel void kernel_346(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 29.0f);
    }
}

kernel void kernel_347(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 29.0f + float(y[tid]));
    }
}

kernel void kernel_348(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 29.5f);
    }
}

kernel void kernel_349(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 29.5f + float(y[tid]));
    }
}

kernel void kernel_350(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 30.0f);
    }
}

kernel void kernel_351(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 30.0f + float(y[tid]));
    }
}

kernel void kernel_352(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 30.5f);
    }
}

kernel void kernel_353(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 30.5f + float(y[tid]));
    }
}

kernel void kernel_354(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 31.0f);
    }
}

kernel void kernel_355(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 31.0f + float(y[tid]));
    }
}

kernel void kernel_356(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 31.5f);
    }
}

kernel void kernel_357(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 31.5f + float(y[tid]));
    }
}

kernel void kernel_358(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 32.0f);
    }
}

kernel void kernel_359(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 32.0f + float(y[tid]));
    }
}

kernel void kernel_360(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 32.5f);
    }
}

kernel void kernel_361(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 32.5f + float(y[tid]));
    }
}

kernel void kernel_362(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 33.0f);
    }
}

kernel void kernel_363(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 33.0f + float(y[tid]));
    }
}

kernel void kernel_364(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 33.5f);
    }
}

kernel void kernel_365(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 33.5f + float(y[tid]));
    }
}

kernel void kernel_366(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 34.0f);
    }
}

kernel void kernel_367(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 34.0f + float(y[tid]));
    }
}

kernel void kernel_368(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 34.5f);
    }
}

kernel void kernel_369(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 34.5f + float(y[tid]));
    }
}

kernel void kernel_370(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 35.0f);
    }
}

kernel void kernel_371(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 35.0f + float(y[tid]));
    }
}

kernel void kernel_372(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 35.5f);
    }
}

kernel void kernel_373(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 35.5f + float(y[tid]));
    }
}

kernel void kernel_374(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 36.0f);
    }
}

kernel void kernel_375(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 36.0f + float(y[tid]));
    }
}

kernel void kernel_376(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 36.5f);
    }
}

kernel void kernel_377(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 36.5f + float(y[tid]));
    }
}

kernel void kernel_378(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 37.0f);
    }
}

kernel void kernel_379(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 37.0f + float(y[tid]));
    }
}

kernel void kernel_380(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 37.5f);
    }
}

kernel void kernel_381(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 37.5f + float(y[tid]));
    }
}

kernel void kernel_382(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 38.0f);
    }
}

kernel void kernel_383(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 38.0f + float(y[tid]));
    }
}

kernel void kernel_384(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 38.5f);
    }
}

kernel void kernel_385(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 38.5f + float(y[tid]));
    }
}

kernel void kernel_386(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 39.0f);
    }
}

kernel void kernel_387(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 39.0f + float(y[tid]));
    }
}

kernel void kernel_388(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 39.5f);
    }
}

kernel void kernel_389(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 39.5f + float(y[tid]));
    }
}

kernel void kernel_390(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 40.0f);
    }
}

kernel void kernel_391(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 40.0f + float(y[tid]));
    }
}

kernel void kernel_392(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 40.5f);
    }
}

kernel void kernel_393(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 40.5f + float(y[tid]));
    }
}

kernel void kernel_394(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 41.0f);
    }
}

kernel void kernel_395(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 41.0f + float(y[tid]));
    }
}

kernel void kernel_396(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 41.5f);
    }
}

kernel void kernel_397(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 41.5f + float(y[tid]));
    }
}

kernel void kernel_398(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 42.0f);
    }
}

kernel void kernel_399(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 42.0f + float(y[tid]));
    }
}

kernel void kernel_400(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 42.5f);
    }
}

kernel void kernel_401(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 42.5f + float(y[tid]));
    }
}

kernel void kernel_402(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 43.0f);
    }
}

kernel void kernel_403(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 43.0f + float(y[tid]));
    }
}

kernel void kernel_404(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 43.5f);
    }
}

kernel void kernel_405(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 43.5f + float(y[tid]));
    }
}

kernel void kernel_406(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 44.0f);
    }
}

kernel void kernel_407(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 44.0f + float(y[tid]));
    }
}

kernel void kernel_408(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 44.5f);
    }
}

kernel void kernel_409(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 44.5f + float(y[tid]));
    }
}

kernel void kernel_410(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 45.0f);
    }
}

kernel void kernel_411(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 45.0f + float(y[tid]));
    }
}

kernel void kernel_412(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 45.5f);
    }
}

kernel void kernel_413(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 45.5f + float(y[tid]));
    }
}

kernel void kernel_414(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 46.0f);
    }
}

kernel void kernel_415(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 46.0f + float(y[tid]));
    }
}

kernel void kernel_416(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 46.5f);
    }
}

kernel void kernel_417(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 46.5f + float(y[tid]));
    }
}

kernel void kernel_418(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 47.0f);
    }
}

kernel void kernel_419(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 47.0f + float(y[tid]));
    }
}

kernel void kernel_420(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 47.5f);
    }
}

kernel void kernel_421(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 47.5f + float(y[tid]));
    }
}

kernel void kernel_422(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 48.0f);
    }
}

kernel void kernel_423(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 48.0f + float(y[tid]));
    }
}

kernel void kernel_424(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 48.5f);
    }
}

kernel void kernel_425(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 48.5f + float(y[tid]));
    }
}

kernel void kernel_426(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 49.0f);
    }
}

kernel void kernel_427(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 49.0f + float(y[tid]));
    }
}

kernel void kernel_428(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 49.5f);
    }
}

kernel void kernel_429(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 49.5f + float(y[tid]));
    }
}

kernel void kernel_430(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 50.0f);
    }
}

kernel void kernel_431(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 50.0f + float(y[tid]));
    }
}

kernel void kernel_432(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 50.5f);
    }
}

kernel void kernel_433(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 50.5f + float(y[tid]));
    }
}

kernel void kernel_434(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 51.0f);
    }
}

kernel void kernel_435(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 51.0f + float(y[tid]));
    }
}

kernel void kernel_436(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 51.5f);
    }
}

kernel void kernel_437(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 51.5f + float(y[tid]));
    }
}

kernel void kernel_438(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 52.0f);
    }
}

kernel void kernel_439(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 52.0f + float(y[tid]));
    }
}

kernel void kernel_440(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 52.5f);
    }
}

kernel void kernel_441(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 52.5f + float(y[tid]));
    }
}

kernel void kernel_442(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 53.0f);
    }
}

kernel void kernel_443(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 53.0f + float(y[tid]));
    }
}

kernel void kernel_444(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 53.5f);
    }
}

kernel void kernel_445(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 53.5f + float(y[tid]));
    }
}

kernel void kernel_446(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 54.0f);
    }
}

kernel void kernel_447(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 54.0f + float(y[tid]));
    }
}

kernel void kernel_448(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 54.5f);
    }
}

kernel void kernel_449(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 54.5f + float(y[tid]));
    }
}

kernel void kernel_450(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 55.0f);
    }
}

kernel void kernel_451(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 55.0f + float(y[tid]));
    }
}

kernel void kernel_452(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 55.5f);
    }
}

kernel void kernel_453(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 55.5f + float(y[tid]));
    }
}

kernel void kernel_454(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 56.0f);
    }
}

kernel void kernel_455(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 56.0f + float(y[tid]));
    }
}

kernel void kernel_456(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 56.5f);
    }
}

kernel void kernel_457(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 56.5f + float(y[tid]));
    }
}

kernel void kernel_458(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 57.0f);
    }
}

kernel void kernel_459(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 57.0f + float(y[tid]));
    }
}

kernel void kernel_460(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 57.5f);
    }
}

kernel void kernel_461(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 57.5f + float(y[tid]));
    }
}

kernel void kernel_462(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 58.0f);
    }
}

kernel void kernel_463(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 58.0f + float(y[tid]));
    }
}

kernel void kernel_464(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 58.5f);
    }
}

kernel void kernel_465(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 58.5f + float(y[tid]));
    }
}

kernel void kernel_466(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 59.0f);
    }
}

kernel void kernel_467(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 59.0f + float(y[tid]));
    }
}

kernel void kernel_468(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 59.5f);
    }
}

kernel void kernel_469(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 59.5f + float(y[tid]));
    }
}

kernel void kernel_470(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 60.0f);
    }
}

kernel void kernel_471(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 60.0f + float(y[tid]));
    }
}

kernel void kernel_472(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 60.5f);
    }
}

kernel void kernel_473(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 60.5f + float(y[tid]));
    }
}

kernel void kernel_474(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 61.0f);
    }
}

kernel void kernel_475(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 61.0f + float(y[tid]));
    }
}

kernel void kernel_476(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 61.5f);
    }
}

kernel void kernel_477(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 61.5f + float(y[tid]));
    }
}

kernel void kernel_478(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 62.0f);
    }
}

kernel void kernel_479(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 62.0f + float(y[tid]));
    }
}

kernel void kernel_480(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 62.5f);
    }
}

kernel void kernel_481(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 62.5f + float(y[tid]));
    }
}

kernel void kernel_482(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 63.0f);
    }
}

kernel void kernel_483(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 63.0f + float(y[tid]));
    }
}

kernel void kernel_484(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 63.5f);
    }
}

kernel void kernel_485(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 63.5f + float(y[tid]));
    }
}

kernel void kernel_486(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 64.0f);
    }
}

kernel void kernel_487(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 64.0f + float(y[tid]));
    }
}

kernel void kernel_488(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 64.5f);
    }
}

kernel void kernel_489(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 64.5f + float(y[tid]));
    }
}

kernel void kernel_490(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 65.0f);
    }
}

kernel void kernel_491(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 65.0f + float(y[tid]));
    }
}

kernel void kernel_492(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 65.5f);
    }
}

kernel void kernel_493(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 65.5f + float(y[tid]));
    }
}

kernel void kernel_494(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 66.0f);
    }
}

kernel void kernel_495(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 66.0f + float(y[tid]));
    }
}

kernel void kernel_496(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 66.5f);
    }
}

kernel void kernel_497(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 66.5f + float(y[tid]));
    }
}

kernel void kernel_498(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 67.0f);
    }
}

kernel void kernel_499(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 67.0f + float(y[tid]));
    }
}

kernel void kernel_500(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 67.5f);
    }
}

kernel void kernel_501(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 67.5f + float(y[tid]));
    }
}

kernel void kernel_502(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 68.0f);
    }
}

kernel void kernel_503(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 68.0f + float(y[tid]));
    }
}

kernel void kernel_504(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 68.5f);
    }
}

kernel void kernel_505(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 68.5f + float(y[tid]));
    }
}

kernel void kernel_506(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 69.0f);
    }
}

kernel void kernel_507(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 69.0f + float(y[tid]));
    }
}

kernel void kernel_508(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 69.5f);
    }
}

kernel void kernel_509(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 69.5f + float(y[tid]));
    }
}

kernel void kernel_510(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 70.0f);
    }
}

kernel void kernel_511(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 70.0f + float(y[tid]));
    }
}

kernel void kernel_512(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 70.5f);
    }
}

kernel void kernel_513(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 70.5f + float(y[tid]));
    }
}

kernel void kernel_514(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 71.0f);
    }
}

kernel void kernel_515(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 71.0f + float(y[tid]));
    }
}

kernel void kernel_516(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 71.5f);
    }
}

kernel void kernel_517(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 71.5f + float(y[tid]));
    }
}

kernel void kernel_518(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 72.0f);
    }
}

kernel void kernel_519(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 72.0f + float(y[tid]));
    }
}

kernel void kernel_520(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 72.5f);
    }
}

kernel void kernel_521(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 72.5f + float(y[tid]));
    }
}

kernel void kernel_522(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 73.0f);
    }
}

kernel void kernel_523(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 73.0f + float(y[tid]));
    }
}

kernel void kernel_524(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) + float(y[tid]) * 73.5f);
    }
}

kernel void kernel_525(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < n) {
        out[tid] = half(float(x[tid]) * 73