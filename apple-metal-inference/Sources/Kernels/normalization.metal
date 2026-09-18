#include "../Common/types.h"

kernel void rmsnorm(
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

kernel void rmsnorm_tiled(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    threadgroup float shared[128];
    float acc = 0.0f;
    for (uint i = tid; i < config.hidden; i += 128u) {
        float v = float(x[i]);
        acc += v * v;
    }
    shared[tid % 128u] = acc;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    float sum = 0.0f;
    for (uint i = 0u; i < 128u; ++i) {
        sum += shared[i];
    }
    float inv = safe_rsqrt(sum / float(config.hidden) + config.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(gain[tid]));
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
    float mean = 0.0f;
    float var = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        mean += v;
        var += v * v;
    }
    mean /= float(config.hidden);
    var = max(var / float(config.hidden) - mean * mean, 0.0f);
    float inv = safe_rsqrt(var + config.epsilon);
    y[tid] = half((float(x[tid]) - mean) * inv * float(gain[tid]) + float(bias[tid]));
}

kernel void layer_norm_no_bias(
    device const half* x [[buffer(0)]],
    device const half* gain [[buffer(1)]],
    device half* y [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float mean = 0.0f;
    float var = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        mean += v;
        var += v * v;
    }
    mean /= float(config.hidden);
    var = max(var / float(config.hidden) - mean * mean, 0.0f);
    float inv = safe_rsqrt(var + config.epsilon);
    y[tid] = half((float(x[tid]) - mean) * inv * float(gain[tid]));
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
    float sum = 0.0f;
    for (uint i = 0u; i < config.hidden; ++i) {
        float v = float(x[i]);
        sum += v * v;
    }
    float inv = safe_rsqrt(sum / float(config.hidden) + config.epsilon);
    y[tid] = half(float(x[tid]) * inv * float(gain[tid]));
}

kernel void residual_and_norm(
    device const half* x [[buffer(0)]],
    device const half* residual [[buffer(1)]],
    device const half* gain [[buffer(2)]],
    device half* y [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
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
    float val = float(x[tid]) * inv * float(gain[tid]);
    y[tid] = half(val + float(residual[tid]));
}
