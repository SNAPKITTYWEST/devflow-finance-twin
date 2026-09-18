#include "../Common/types.h"

kernel void residual_add(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    output[tid] = half(float(a[tid]) + float(b[tid]));
}

kernel void residual_add_scaled(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant float& scale [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    output[tid] = half(float(a[tid]) + float(b[tid]) * scale);
}

kernel void residual_add_inplace(
    device half* x [[buffer(0)]],
    device const half* delta [[buffer(1)]],
    constant ModelConfig& config [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    x[tid] = half(float(x[tid]) + float(delta[tid]));
}
