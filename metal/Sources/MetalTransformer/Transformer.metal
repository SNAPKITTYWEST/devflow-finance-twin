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
    float epsilon;
};

struct LinearShape {
    uint rows;
    uint cols;
};

struct PosInfo {
    uint token_index;
    uint seq_len;
};

struct KernelMetadata {
    uint id;
    uint lane;
    uint group;
    uint dim;
};

struct WeightLayout {
    uint row_stride;
    uint q_group_size;
    uint scale_stride;
    uint zero_stride;
    uint offset;
    uint flags;
};

struct AttentionTile {
    uint head;
    uint token;
    uint head_dim;
    uint kv_head;
    uint row_offset;
    uint col_offset;
};

constexpr uint kMaxBlock = 256u;
constexpr uint kMaxThreads = 1024u;
constexpr uint kRmsReduction = 32u;
constexpr uint kRoPEPairs = 128u;
constexpr uint kAttentionWindow = 4096u;

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

inline float dequant_i4(device const uchar* weight, device const half* scale, uint row, uint col, uint cols) {
    uint index = packed_index(row, col, cols);
    uchar packed = weight[index];
    uint nibble = (col & 1u) ? (packed >> 4u) : (packed & 0x0Fu);
    return float(signed_nibble(nibble)) * float(scale[row]);
}

inline float dequant_i8(device const uchar* weight, device const half* scale, uint row, uint col, uint cols) {
    uint index = row * cols + col;
    int8_t val = int8_t(weight[index]);
    return float(val) * float(scale[row]);
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

inline uint q_offset(uint head, uint head_dim) {
    return head * head_dim;
}

inline uint linear_index(uint row, uint col, uint stride) {
    return row * stride + col;
}

inline float reduce_sum(float x, float y) {
    return x + y;
}

inline float absmax(float x) {
    return abs(x);
}

inline float stable_softmax_exp(float x, float max_value) {
    return exp(x - max_value);
}

inline float weight_value_i4(device const uchar* weight, device const half* scale, uint row, uint col, uint cols) {
    return dequant_i4(weight, scale, row, col, cols);
}

kernel void embedding(
    device const half* table [[buffer(0)]],
    device const uint* token [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < config.hidden) {
        out[tid] = table[token[0] * config.hidden + tid];
    }
}

kernel void embedding_batch(
    device const half* table [[buffer(0)]],
    device const uint* tokens [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint batch = 1u;
    uint idx = tid / config.hidden;
    uint off = tid % config.hidden;
    if (idx < batch && off < config.hidden) {
        uint tok = tokens[idx];
        out[tid] = table[tok * config.hidden + off];
    }
}

kernel void rmsnorm(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]],
    uint lane [[thread_index_in_simdgroup]])
{
    threadgroup float accum[kRmsReduction];
    float local = 0.0f;
    for (uint j = tid; j < config.hidden; j += kRmsReduction) {
        float v = float(x[j]);
        local += v * v;
    }
    accum[lane] = local;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    float total = 0.0f;
    for (uint i = 0; i < kRmsReduction; ++i) {
        total += accum[i];
    }
    float inv = safe_rsqrt(total / float(config.hidden));
    if (tid < config.hidden) {
        y[tid] = half(float(x[tid]) * inv * float(gain[tid]));
    }
}

kernel void rmsnorm_safe(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid != 0u) {
        return;
    }
    float total = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        total += v * v;
    }
    float inv = safe_rsqrt(total / float(config.hidden) + config.epsilon);
    for (uint i = 0u; i < config.hidden; ++i) {
        y[i] = half(float(x[i]) * inv * float(gain[i]));
    }
}

kernel void rmsnorm_vec4(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float sum = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        sum += v * v;
    }
    float inv = safe_rsqrt(sum / float(config.hidden) + config.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(gain[tid]));
}

kernel void rope_qk(
    device half* q [[buffer(0)]],
    device half* k [[buffer(1)]],
    constant ModelConfig& config [[buffer(2)]],
    constant PosInfo& pos [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    if (tid >= q_total || (tid & 1u)) {
        return;
    }
    uint pair = tid >> 1u;
    uint dim_pair = pair % (config.head_dim >> 1u);
    float angle = float(pos.token_index) * pow(10000.0f, -float(2u * dim_pair) / float(config.head_dim));
    float c = cos(angle);
    float s = sin(angle);

    uint q_head = tid / config.head_dim;
    uint q_offset_base = q_head * config.head_dim;
    uint q_e0 = q_offset_base + (dim_pair << 1u);
    float q0 = float(q[q_e0]);
    float q1 = float(q[q_e0 + 1u]);
    q[q_e0] = half(q0 * c - q1 * s);
    q[q_e0 + 1u] = half(q0 * s + q1 * c);

    uint kv_head = q_head % config.kv_heads;
    uint k_offset_base = kv_head * config.head_dim;
    uint k_e0 = k_offset_base + (dim_pair << 1u);
    float k0 = float(k[k_e0]);
    float k1 = float(k[k_e0 + 1u]);
    k[k_e0] = half(k0 * c - k1 * s);
    k[k_e0 + 1u] = half(k0 * s + k1 * c);
}

kernel void rope_qk_full(
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
    uint even_dim = pair << 1u;
    uint odd_dim = even_dim + 1u;
    if (dim >= config.head_dim || even_dim >= config.head_dim) {
        return;
    }
    float angle = float(pos.token_index) * pow(10000.0f, -float(2u * pair) / float(config.head_dim));
    float c = cos(angle);
    float s = sin(angle);

    if ((dim & 1u) == 0u) {
        float q0 = float(q[head * config.head_dim + even_dim]);
        float q1 = float(q[head * config.head_dim + odd_dim]);
        q[head * config.head_dim + even_dim] = half(q0 * c - q1 * s);
        q[head * config.head_dim + odd_dim] = half(q0 * s + q1 * c);
    }

    uint kv_head = head % config.kv_heads;
    uint k_base = kv_head * config.head_dim;
    float k0 = float(k[k_base + even_dim]);
    float k1 = float(k[k_base + odd_dim]);
    k[k_base + even_dim] = half(k0 * c - k1 * s);
    k[k_base + odd_dim] = half(k0 * s + k1 * c);
}

kernel void quantized_matvec(
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
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matvec_i8(
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
        acc += dequant_i8(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matvec_bias(
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
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matvec_bias_i8(
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
        acc += dequant_i8(weight, scale, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void qkv_projection(
    device const uchar* weight_q [[buffer(0)]],
    device const half* scale_q [[buffer(1)]],
    device const uchar* weight_k [[buffer(2)]],
    device const half* scale_k [[buffer(3)]],
    device const uchar* weight_v [[buffer(4)]],
    device const half* scale_v [[buffer(5)]],
    device const half* input [[buffer(6)]],
    device half* q_out [[buffer(7)]],
    device half* k_out [[buffer(8)]],
    device half* v_out [[buffer(9)]],
    constant LinearShape& q_shape [[buffer(10)]],
    constant LinearShape& k_shape [[buffer(11)]],
    constant LinearShape& v_shape [[buffer(12)]],
    uint row [[thread_position_in_grid]])
{
    if (row < q_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < q_shape.cols; ++col) {
            acc += dequant_i4(weight_q, scale_q, row, col, q_shape.cols) * float(input[col]);
        }
        q_out[row] = half(acc);
    }

    if (row < k_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < k_shape.cols; ++col) {
            acc += dequant_i4(weight_k, scale_k, row, col, k_shape.cols) * float(input[col]);
        }
        k_out[row] = half(acc);
    }

    if (row < v_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < v_shape.cols; ++col) {
            acc += dequant_i4(weight_v, scale_v, row, col, v_shape.cols) * float(input[col]);
        }
        v_out[row] = half(acc);
    }
}

kernel void qkv_projection_tiled(
    device const uchar* weight_q [[buffer(0)]],
    device const half* scale_q [[buffer(1)]],
    device const uchar* weight_k [[buffer(2)]],
    device const half* scale_k [[buffer(3)]],
    device const uchar* weight_v [[buffer(4)]],
    device const half* scale_v [[buffer(5)]],
    device const half* input [[buffer(6)]],
    device half* q_out [[buffer(7)]],
    device half* k_out [[buffer(8)]],
    device half* v_out [[buffer(9)]],
    constant LinearShape& q_shape [[buffer(10)]],
    constant LinearShape& k_shape [[buffer(11)]],
    constant LinearShape& v_shape [[buffer(12)]],
    uint tid [[thread_position_in_grid]])
{
    uint row = tid;
    if (row < q_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < q_shape.cols; ++col) {
            acc += dequant_i4(weight_q, scale_q, row, col, q_shape.cols) * float(input[col]);
        }
        q_out[row] = half(acc);
    }
    if (row < k_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < k_shape.cols; ++col) {
            acc += dequant_i4(weight_k, scale_k, row, col, k_shape.cols) * float(input[col]);
        }
        k_out[row] = half(acc);
    }
    if (row < v_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < v_shape.cols; ++col) {
            acc += dequant_i4(weight_v, scale_v, row, col, v_shape.cols) * float(input[col]);
        }
        v_out[row] = half(acc);
    }
}

kernel void attention_scores(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device half* scores [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.q_heads * pos.seq_len;
    if (tid >= total) {
        return;
    }
    uint head = tid / pos.seq_len;
    uint token = tid % pos.seq_len;
    uint kv_head = head % config.kv_heads;
    float dot = 0.0f;
    uint q_base = head * config.head_dim;
    uint k_base = kv_offset(token, kv_head, config.head_dim, config.kv_heads);
    for (uint d = 0u; d < config.head_dim; ++d) {
        dot += float(q[q_base + d]) * float(k_cache[k_base + d]);
    }
    scores[tid] = half(dot * safe_rsqrt(float(config.head_dim)));
}

kernel void attention_scores_full(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device half* scores [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / pos.seq_len;
    uint token = tid % pos.seq_len;
    if (head >= config.q_heads || token >= pos.seq_len) {
        return;
    }
    uint kv_head = head % config.kv_heads;
    float dot = 0.0f;
    uint q_base = head * config.head_dim;
    uint k_base = kv_offset(token, kv_head, config.head_dim, config.kv_heads);
    for (uint d = 0u; d < config.head_dim; ++d) {
        dot += float(q[q_base + d]) * float(k_cache[k_base + d]);
    }
    scores[tid] = half(dot * safe_rsqrt(float(config.head_dim)));
}

kernel void causal_mask(
    device half* scores [[buffer(0)]],
    constant ModelConfig& config [[buffer(1)]],
    constant PosInfo& pos [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.q_heads * pos.seq_len) {
        return;
    }
    uint head = tid / pos.seq_len;
    uint token = tid % pos.seq_len;
    if (token > pos.token_index) {
        scores[tid] = half(-INFINITY);
    }
}

kernel void causal_mask_ragged(
    device half* scores [[buffer(0)]],
    constant ModelConfig& config [[buffer(1)]],
    constant PosInfo& pos [[buffer(2)]],
    uint head [[thread_position_in_grid]],
    uint token [[thread_index_in_threadgroup]])
{
    if (head >= config.q_heads || token >= pos.seq_len) {
        return;
    }
    if (token > pos.token_index) {
        scores[head * pos.seq_len + token] = half(-INFINITY);
    }
}

kernel void softmax_stable(
    device half* scores [[buffer(0)]],
    constant ModelConfig& config [[buffer(1)]],
    constant PosInfo& pos [[buffer(2)]],
    uint head [[thread_position_in_grid]])
{
    if (head >= config.q_heads) {
        return;
    }
    float max_val = -INFINITY;
    for (uint t = 0u; t < pos.seq_len; ++t) {
        float v = float(scores[head * pos.seq_len + t]);
        max_val = max(max_val, v);
    }
    float denom = 0.0f;
    for (uint t = 0u; t < pos.seq_len; ++t) {
        float e = exp(float(scores[head * pos.seq_len + t]) - max_val);
        scores[head * pos.seq_len + t] = half(e);
        denom += e;
    }
    float inv = 1.0f / max(denom, 1.0e-20f);
    for (uint t = 0u; t < pos.seq_len; ++t) {
        scores[head * pos.seq_len + t] = half(float(scores[head * pos.seq_len + t]) * inv);
    }
}

kernel void softmax_stable_2d(
    device half* scores [[buffer(0)]],
    constant LinearShape& shape [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    uint rows = shape.rows;
    uint cols = shape.cols;
    if (tid >= rows) {
        return;
    }
    float max_val = -INFINITY;
    for (uint c = 0u; c < cols; ++c) {
        float v = float(scores[tid * cols + c]);
        max_val = max(max_val, v);
    }
    float denom = 0.0f;
    for (uint c = 0u; c < cols; ++c) {
        float e = exp(float(scores[tid * cols + c]) - max_val);
        scores[tid * cols + c] = half(e);
        denom += e;
    }
    float inv = 1.0f / max(denom, 1.0e-20f);
    for (uint c = 0u; c < cols; ++c) {
        scores[tid * cols + c] = half(float(scores[tid * cols + c]) * inv);
    }
}

kernel void attention_value(
    device const half* scores [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.q_heads * config.head_dim;
    if (tid >= total) {
        return;
    }
    uint head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint kv_head = head % config.kv_heads;
    float acc = 0.0f;
    for (uint token = 0u; token < pos.seq_len; ++token) {
        float w = float(scores[head * pos.seq_len + token]);
        uint v_base = kv_offset(token, kv_head, config.head_dim, config.kv_heads);
        acc += w * float(v_cache[v_base + dim]);
    }
    out[tid] = half(acc);
}

kernel void attention_value_tiled(
    device const half* scores [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    if (head >= config.q_heads || dim >= config.head_dim) {
        return;
    }
    uint kv_head = head % config.kv_heads;
    float acc = 0.0f;
    for (uint token = 0u; token < pos.seq_len; ++token) {
        float w = float(scores[head * pos.seq_len + token]);
        uint v_base = kv_offset(token, kv_head, config.head_dim, config.kv_heads);
        acc += w * float(v_cache[v_base + dim]);
    }
    out[tid] = half(acc);
}

kernel void weight_bias_add(
    device const half* in [[buffer(0)]],
    device const half* bias [[buffer(1)]],
    device half* out [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(in[tid]) + float(bias[tid]));
    }
}

kernel void add_residual(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(a[tid]) + float(b[tid]));
    }
}

kernel void add_residual_batch(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(a[tid]) + float(b[tid]));
    }
}

kernel void swiglu(
    device const half* gate [[buffer(0)]],
    device const half* up [[buffer(1)]],
    device half* out [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(silu(float(gate[tid])) * float(up[tid]));
    }
}

kernel void swiglu_gate(
    device const half* gate [[buffer(0)]],
    device const half* up [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant LinearShape& shape [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= shape.cols) {
        return;
    }
    out[tid] = half(silu(float(gate[tid])) * float(up[tid]));
}

kernel void kv_store(
    device const half* k [[buffer(0)]],
    device const half* v [[buffer(1)]],
    device half* k_cache [[buffer(2)]],
    device half* v_cache [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    constant PosInfo& pos [[buffer(5)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.kv_heads * config.head_dim;
    if (tid >= total) {
        return;
    }
    uint base = pos.token_index * total + tid;
    k_cache[base] = k[tid];
    v_cache[base] = v[tid];
}

kernel void kv_store_layer(
    device const half* k [[buffer(0)]],
    device const half* v [[buffer(1)]],
    device half* k_cache [[buffer(2)]],
    device half* v_cache [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    constant PosInfo& pos [[buffer(5)]],
    uint layer [[buffer(6)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.kv_heads * config.head_dim;
    if (tid >= total) {
        return;
    }
    uint base = (layer * config.context + pos.token_index) * total + tid;
    k_cache[base] = k[tid];
    v_cache[base] = v[tid];
}

kernel void final_norm(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float total = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        total += v * v;
    }
    float inv = safe_rsqrt(total / float(config.hidden) + config.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(gain[tid]));
}

kernel void final_norm_chunked(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float total = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        total += v * v;
    }
    float inv = safe_rsqrt(total / float(config.hidden) + config.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(gain[tid]));
}

kernel void logits(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* x [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void logits_i8(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* x [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void logits_bias(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device const half* x [[buffer(3)]],
    device half* out [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void prefix_cache_update(
    device const half* q [[buffer(0)]],
    device const half* k [[buffer(1)]],
    device const half* v [[buffer(2)]],
    device half* k_cache [[buffer(3)]],
    device half* v_cache [[buffer(4)]],
    constant ModelConfig& config [[buffer(5)]],
    constant PosInfo& pos [[buffer(6)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        q[tid] = q[tid];
    }
    if (tid < kv_total) {
        uint base = pos.token_index * kv_total + tid;
        k_cache[base] = k[tid];
        v_cache[base] = v[tid];
    }
}

kernel void segment_norm(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float sum = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        sum += v * v;
    }
    float inv = safe_rsqrt(sum / float(config.hidden) + config.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(gain[tid]));
}

kernel void scale_add(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant float& scale [[buffer(3)]],
    uint count [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(x[tid]) + scale * float(y[tid]));
    }
}

kernel void scale_mul(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant float& scale [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(scale * float(x[tid]));
    }
}

kernel void bias_activation(
    device const half* x [[buffer(0)]],
    device const half* bias [[buffer(1)]],
    device half* out [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(x[tid]) + float(bias[tid]));
    }
}

kernel void activation_relu(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    uint count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(max(float(x[tid]), 0.0f));
    }
}

kernel void activation_gelu(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    uint count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        float v = float(x[tid]);
        float x1 = v * 0.5f;
        float g = 0.5f * (1.0f + tanh(sqrt(2.0f / M_PI_F) * (x1 + 0.044715f * v * v * v)));
        out[tid] = half(v * g);
    }
}

kernel void activation_silu(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    uint count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        float v = float(x[tid]);
        out[tid] = half(v / (1.0f + exp(-clampf(v, -80.0f, 80.0f))));
    }
}

kernel void layer_norm(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device half* y [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float sum = 0.0f;
    float sq = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        sum += v;
        sq += v * v;
    }
    float mean = sum / float(config.hidden);
    float var = sq / float(config.hidden) - mean * mean;
    float inv = safe_rsqrt(var + config.epsilon);
    y[tid] = half((float(x[tid]) - mean) * inv * float(gain[tid]) + float(bias[tid]));
}

kernel void layer_norm_1d(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device half* y [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float sum = 0.0f;
    float sq = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        sum += v;
        sq += v * v;
    }
    float mean = sum / float(config.hidden);
    float var = sq / float(config.hidden) - mean * mean;
    float inv = safe_rsqrt(var + config.epsilon);
    y[tid] = half((float(x[tid]) - mean) * inv * float(gain[tid]) + float(bias[tid]));
}

kernel void ln_and_add(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device const half* gain [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* out [[buffer(4)]],
    constant ModelConfig& config [[buffer(5)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float sum = 0.0f;
    float sq = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        sum += v;
        sq += v * v;
    }
    float mean = sum / float(config.hidden);
    float var = sq / float(config.hidden) - mean * mean;
    float inv = safe_rsqrt(var + config.epsilon);
    float ln = (float(x[tid]) - mean) * inv;
    out[tid] = half(ln * float(gain[tid]) + float(bias[tid]) + float(y[tid]));
}

kernel void residual_projection(
    device const half* x [[buffer(0)]],
    device const half* proj [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    out[tid] = half(float(x[tid]) + float(proj[tid]));
}

kernel void residual_projection_scaled(
    device const half* x [[buffer(0)]],
    device const half* proj [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant float& scale [[buffer(3)]],
    uint count [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(x[tid]) + scale * float(proj[tid]));
    }
}

kernel void mixed_precision_reduce(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= count) {
        return;
    }
    float acc = 0.0f;
    for (uint i = 0u; i < count; ++i) {
        acc += float(x[i]);
    }
    out[tid] = half(acc / float(count));
}

kernel void dot_product(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 1u) {
        return;
    }
    float acc = 0.0f;
    for (uint i = 0u; i < n; ++i) {
        acc += float(a[i]) * float(b[i]);
    }
    out[0] = half(acc);
}

kernel void stream_copy(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    uint count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = in[tid];
    }
}

kernel void stream_fill(
    device half* out [[buffer(0)]],
    constant half& value [[buffer(1)]],
    uint count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = value;
    }
}

kernel void zero_buffer(
    device half* out [[buffer(0)]],
    uint count [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(0.0f);
    }
}

kernel void clamp_buffer(
    device half* out [[buffer(0)]],
    constant float& lo [[buffer(1)]],
    constant float& hi [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        float v = float(out[tid]);
        out[tid] = half(clampf(v, lo, hi));
    }
}

kernel void add_bias_kernel(
    device const half* x [[buffer(0)]],
    device const half* bias [[buffer(1)]],
    device half* y [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        y[tid] = half(float(x[tid]) + float(bias[tid % count]));
    }
}

kernel void masked_softmax(
    device half* scores [[buffer(0)]],
    constant ModelConfig& config [[buffer(1)]],
    constant PosInfo& pos [[buffer(2)]],
    uint head [[thread_position_in_grid]])
{
    if (head >= config.q_heads) {
        return;
    }
    float max_val = -INFINITY;
    for (uint t = 0u; t < pos.seq_len; ++t) {
        if (t <= pos.token_index) {
            float v = float(scores[head * pos.seq_len + t]);
            max_val = max(max_val, v);
        }
    }
    float denom = 0.0f;
    for (uint t = 0u; t < pos.seq_len; ++t) {
        if (t <= pos.token_index) {
            float e = exp(float(scores[head * pos.seq_len + t]) - max_val);
            scores[head * pos.seq_len + t] = half(e);
            denom += e;
        } else {
            scores[head * pos.seq_len + t] = half(0.0f);
        }
    }
    float inv = 1.0f / max(denom, 1.0e-20f);
    for (uint t = 0u; t < pos.seq_len; ++t) {
        if (t <= pos.token_index) {
            scores[head * pos.seq_len + t] = half(float(scores[head * pos.seq_len + t]) * inv);
        }
    }
}

kernel void masked_attention_value(
    device const half* scores [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.q_heads * config.head_dim;
    if (tid >= total) {
        return;
    }
    uint head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint kv_head = head % config.kv_heads;
    float acc = 0.0f;
    for (uint token = 0u; token <= pos.token_index; ++token) {
        float w = float(scores[head * pos.seq_len + token]);
        uint v_base = kv_offset(token, kv_head, config.head_dim, config.kv_heads);
        acc += w * float(v_cache[v_base + dim]);
    }
    out[tid] = half(acc);
}

kernel void qkv_split(
    device const half* qkv [[buffer(0)]],
    device half* q [[buffer(1)]],
    device half* k [[buffer(2)]],
    device half* v [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        q[tid] = qkv[tid];
    } else if (tid < q_total + kv_total) {
        k[tid - q_total] = qkv[tid];
    } else if (tid < q_total + 2u * kv_total) {
        v[tid - q_total - kv_total] = qkv[tid];
    }
}

kernel void qkv_concat(
    device const half* q [[buffer(0)]],
    device const half* k [[buffer(1)]],
    device const half* v [[buffer(2)]],
    device half* qkv [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        qkv[tid] = q[tid];
    } else if (tid < q_total + kv_total) {
        qkv[tid] = k[tid - q_total];
    } else if (tid < q_total + 2u * kv_total) {
        qkv[tid] = v[tid - q_total - kv_total];
    }
}

kernel void mixed_qkv(
    device const half* q_in [[buffer(0)]],
    device const half* k_in [[buffer(1)]],
    device const half* v_in [[buffer(2)]],
    device half* q_out [[buffer(3)]],
    device half* k_out [[buffer(4)]],
    device half* v_out [[buffer(5)]],
    constant ModelConfig& config [[buffer(6)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        q_out[tid] = q_in[tid];
        k_out[tid] = k_in[tid % kv_total];
        v_out[tid] = v_in[tid % kv_total];
    }
}

kernel void qkv_gqa(
    device const half* q_in [[buffer(0)]],
    device const half* k_in [[buffer(1)]],
    device const half* v_in [[buffer(2)]],
    device half* q_out [[buffer(3)]],
    device half* k_out [[buffer(4)]],
    device half* v_out [[buffer(5)]],
    constant ModelConfig& config [[buffer(6)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        q_out[tid] = q_in[tid];
    }
    if (tid < kv_total) {
        k_out[tid] = k_in[tid];
        v_out[tid] = v_in[tid];
    }
}

kernel void attention_projection(
    device const half* out [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* logits [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(out[col]);
    }
    logits[row] = half(acc);
}

kernel void output_projection(
    device const half* x [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* out [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void output_projection_i8(
    device const half* x [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* out [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void output_projection_no_bias(
    device const half* x [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void temp_reduce(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& n [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 1u) {
        return;
    }
    float acc = 0.0f;
    for (uint i = 0u; i < n; ++i) {
        acc += float(x[i]);
    }
    out[0] = half(acc);
}

kernel void reduce_max(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& n [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 1u) {
        return;
    }
    float mx = -INFINITY;
    for (uint i = 0u; i < n; ++i) {
        mx = max(mx, float(x[i]));
    }
    out[0] = half(mx);
}

kernel void reduce_sum_kernel(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& n [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 1u) {
        return;
    }
    float sum = 0.0f;
    for (uint i = 0u; i < n; ++i) {
        sum += float(x[i]);
    }
    out[0] = half(sum);
}

kernel void batch_token_copy(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& token_count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= token_count) {
        return;
    }
    out[tid] = in[tid];
}

kernel void batch_fill_zero(
    device half* out [[buffer(0)]],
    constant uint& count [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(0.0f);
    }
}

kernel void batch_fill_const(
    device half* out [[buffer(0)]],
    constant half& value [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = value;
    }
}

kernel void batch_scale_add(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant float& scale [[buffer(3)]],
    constant uint& count [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(x[tid]) + scale * float(y[tid]));
    }
}

kernel void additive_offset(
    device half* x [[buffer(0)]],
    constant float& offset [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        x[tid] = half(float(x[tid]) + offset);
    }
}

kernel void contrastive_scale(
    device half* x [[buffer(0)]],
    constant float& scale [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        x[tid] = half(scale * float(x[tid]));
    }
}

kernel void sum_rows(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint row [[thread_position_in_grid]])
{
    float acc = 0.0f;
    for (uint i = 0u; i < stride; ++i) {
        acc += float(x[row * stride + i]);
    }
    out[row] = half(acc);
}

kernel void max_rows(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint row [[thread_position_in_grid]])
{
    float mx = -INFINITY;
    for (uint i = 0u; i < stride; ++i) {
        mx = max(mx, float(x[row * stride + i]));
    }
    out[row] = half(mx);
}

kernel void elementwise_mul(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(a[tid]) * float(b[tid]));
    }
}

kernel void elementwise_div(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(a[tid]) / max(float(b[tid]), 1.0e-6f));
    }
}

kernel void abs_buffer(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    uint count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(abs(float(x[tid])));
    }
}

kernel void clamp_buffer_signed(
    device half* x [[buffer(0)]],
    constant float& lo [[buffer(1)]],
    constant float& hi [[buffer(2)]],
    uint count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        x[tid] = half(clampf(float(x[tid]), lo, hi));
    }
}

kernel void repeat_value(
    device half* out [[buffer(0)]],
    constant half& value [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = value;
    }
}

kernel void accumulation_block(
    device const half* x [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    float acc = 0.0f;
    for (uint i = 0u; i < stride; ++i) {
        acc += float(x[i]);
    }
    out[tid] = half(acc);
}

kernel void vector_bias_add(
    device const half* x [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(x[tid]) + float(b[tid]));
    }
}

kernel void vector_bias_mul(
    device const half* x [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(x[tid]) * float(b[tid]));
    }
}

kernel void buffer_add_const(
    device half* x [[buffer(0)]],
    constant float& c [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        x[tid] = half(float(x[tid]) + c);
    }
}

kernel void buffer_mul_const(
    device half* x [[buffer(0)]],
    constant float& c [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        x[tid] = half(float(x[tid]) * c);
    }
}

kernel void merge_buffers(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(a[tid]) + float(b[tid]));
    }
}

kernel void split_residual_state(
    device const half* x [[buffer(0)]],
    device half* residual [[buffer(1)]],
    device half* normalized [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        residual[tid] = x[tid];
        normalized[tid] = half(0.0f);
    }
}

kernel void reorder_qkv(
    device const half* q [[buffer(0)]],
    device const half* k [[buffer(1)]],
    device const half* v [[buffer(2)]],
    device half* qkv [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        qkv[tid] = q[tid];
    } else if (tid < q_total + kv_total) {
        qkv[tid] = k[tid - q_total];
    } else if (tid < q_total + 2u * kv_total) {
        qkv[tid] = v[tid - q_total - kv_total];
    }
}

kernel void reorder_qkv_headed(
    device const half* q [[buffer(0)]],
    device const half* k [[buffer(1)]],
    device const half* v [[buffer(2)]],
    device half* qkv [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        qkv[tid] = q[tid];
    } else if (tid < q_total + kv_total) {
        qkv[tid] = k[tid - q_total];
    } else if (tid < q_total + 2u * kv_total) {
        qkv[tid] = v[tid - q_total - kv_total];
    }
}

kernel void cache_lookup(
    device const half* k_cache [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.kv_heads * config.head_dim;
    if (tid >= total) {
        return;
    }
    uint base = pos.token_index * total + tid;
    out[tid] = k_cache[base] + v_cache[base];
}

kernel void cache_lookup_headed(
    device const half* k_cache [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.kv_heads * config.head_dim;
    if (tid >= total) {
        return;
    }
    uint base = pos.token_index * total + tid;
    out[tid] = k_cache[base] + v_cache[base];
}

kernel void stable_logits(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* x [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    constant float& temperature [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc / temperature);
}

kernel void classifier_logits(
    device const uchar* weight [[buffer(0)]],
    device const half* scale [[buffer(1)]],
    device const half* x [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void head_projection(
    device const half* x [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    out[row] = half(acc);
}

kernel void parallel_score_block(
    device const half* q [[buffer(0)]],
    device const half* k [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / pos.seq_len;
    uint token = tid % pos.seq_len;
    if (head >= config.q_heads || token >= pos.seq_len) {
        return;
    }
    uint kv_head = head % config.kv_heads;
    uint q_base = head * config.head_dim;
    uint k_base = kv_head * config.head_dim;
    float acc = 0.0f;
    for (uint d = 0u; d < config.head_dim; ++d) {
        acc += float(q[q_base + d]) * float(k[k_base + d]);
    }
    out[tid] = half(acc * safe_rsqrt(float(config.head_dim)));
}

kernel void attention_diag_mask(
    device half* scores [[buffer(0)]],
    constant ModelConfig& config [[buffer(1)]],
    constant PosInfo& pos [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    uint total = config.q_heads * pos.seq_len;
    if (tid >= total) {
        return;
    }
    uint head = tid / pos.seq_len;
    uint token = tid % pos.seq_len;
    if (token > pos.token_index) {
        scores[tid] = half(-INFINITY);
    }
}

kernel void attention_diag_mask_narrow(
    device half* scores [[buffer(0)]],
    constant ModelConfig& config [[buffer(1)]],
    constant PosInfo& pos [[buffer(2)]],
    uint head [[thread_position_in_grid]],
    uint token [[thread_index_in_threadgroup]])
{
    if (head >= config.q_heads || token >= pos.seq_len) {
        return;
    }
    if (token > pos.token_index) {
        scores[head * pos.seq_len + token] = half(-INFINITY);
    }
}

kernel void computed_score_invariants(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device half* scores [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / pos.seq_len;
    uint token = tid % pos.seq_len;
    if (head >= config.q_heads || token >= pos.seq_len) {
        return;
    }
    uint kv_head = head % config.kv_heads;
    float dot = 0.0f;
    uint q_base = head * config.head_dim;
    uint k_base = kv_offset(token, kv_head, config.head_dim, config.kv_heads);
    for (uint d = 0u; d < config.head_dim; ++d) {
        dot += float(q[q_base + d]) * float(k_cache[k_base + d]);
    }
    scores[tid] = half(dot * safe_rsqrt(float(config.head_dim)));
}

kernel void attention_update_values(
    device const half* scores [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    if (head >= config.q_heads || dim >= config.head_dim) {
        return;
    }
    uint kv_head = head % config.kv_heads;
    float acc = 0.0f;
    for (uint token = 0u; token <= pos.token_index; ++token) {
        float w = float(scores[head * pos.seq_len + token]);
        uint v_base = kv_offset(token, kv_head, config.head_dim, config.kv_heads);
        acc += w * float(v_cache[v_base + dim]);
    }
    out[tid] = half(acc);
}

kernel void attn_projection_grad(
    device const half* in [[buffer(0)]],
    device const uchar* w [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(w, scale, row, col, shape.cols) * float(in[col]);
    }
    out[row] = half(acc);
}

kernel void smoothed_output(
    device const half* x [[buffer(0)]],
    device const half* y [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant float& alpha [[buffer(3)]],
    uint count [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        out[tid] = half(float(x[tid]) * alpha + float(y[tid]));
    }
}

kernel void cross_attention_debug(
    device const half* q [[buffer(0)]],
    device const half* k_cache [[buffer(1)]],
    device half* out [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant PosInfo& pos [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.q_heads) {
        return;
    }
    float val = 0.0f;
    for (uint d = 0u; d < config.head_dim; ++d) {
        val += float(q[tid * config.head_dim + d]) * float(k_cache[(tid % config.kv_heads) * config.head_dim + d]);
    }
    out[tid] = half(val);
}

kernel void sequence_norm(
    device const half* x [[buffer(0)]],
    device half* y [[buffer(1)]],
    constant ModelConfig& config [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float sum = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        sum += float(x[i]);
    }
    float mean = sum / float(config.hidden);
    float sq = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]) - mean;
        sq += v * v;
    }
    float inv = safe_rsqrt(sq / float(config.hidden) + config.epsilon);
    y[tid] = half((float(x[tid]) - mean) * inv);
}

kernel void qkv_head_lift(
    device const half* q [[buffer(0)]],
    device const half* k [[buffer(1)]],
    device const half* v [[buffer(2)]],
    device half* out [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    if (tid < q_total) {
        out[tid] = q[tid];
    } else {
        uint n = tid - q_total;
        if (n < config.kv_heads * config.head_dim) {
            out[tid] = k[n];
        } else {
            out[tid] = v[n - config.kv_heads * config.head_dim];
        }
    }
}

kernel void head_split_qkv(
    device const half* qkv [[buffer(0)]],
    device half* q [[buffer(1)]],
    device half* k [[buffer(2)]],
    device half* v [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        q[tid] = qkv[tid];
    } else if (tid < q_total + kv_total) {
        k[tid - q_total] = qkv[tid];
    } else if (tid < q_total + 2u * kv_total) {
        v[tid - q_total - kv_total] = qkv[tid];
    }
}

kernel void qkv_stage_sanity(
    device const half* x [[buffer(0)]],
    device half* q [[buffer(1)]],
    device half* k [[buffer(2)]],
    device half* v [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    uint q_total = config.q_heads * config.head_dim;
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid < q_total) {
        q[tid] = x[tid];
    } else if (tid < q_total + kv_total) {
        k[tid - q_total] = x[tid];
    } else if (tid < q_total + 2u * kv_total) {
        v[tid - q_total - kv_total] = x[tid];
    }
}

kernel void memory_copy_stride(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_2(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_3(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_4(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_5(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_6(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_7(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_8(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_9(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_10(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_11(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_12(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_13(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_14(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_15(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_16(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_17(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_18(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_19(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_20(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_21(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_22(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_23(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_24(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_25(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_26(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_27(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_28(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_29(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}

kernel void memory_copy_stride_30(
    device const half* in [[buffer(0)]],
    device half* out [[buffer(1)]],
    constant uint& stride [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= stride) {
        return;
    }
    out[tid] = in[tid];
}
