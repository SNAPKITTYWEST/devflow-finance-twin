#include "../Common/types.h"

kernel void buffer_zero(
    device half* buf [[buffer(0)]],
    constant uint& count [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        buf[tid] = half(0.0f);
    }
}

kernel void buffer_zero_float(
    device float* buf [[buffer(0)]],
    constant uint& count [[buffer(1)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        buf[tid] = 0.0f;
    }
}

kernel void buffer_copy(
    device const half* src [[buffer(0)]],
    device half* dst [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < count) {
        dst[tid] = src[tid];
    }
}

kernel void vector_dot(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device float* result [[buffer(2)]],
    constant uint& length [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid != 0u) {
        return;
    }
    float acc = 0.0f;
    for (uint i = 0u; i < length; ++i) {
        acc += float(a[i]) * float(b[i]);
    }
    result[0] = acc;
}

kernel void tile_reduce(
    device const half* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant uint& length [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    threadgroup float shared[256];
    float acc = 0.0f;
    for (uint i = tid; i < length; i += 256u) {
        acc += float(input[i]);
    }
    shared[tid % 256u] = acc;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (tid == 0u) {
        float sum = 0.0f;
        for (uint i = 0u; i < 256u; ++i) {
            sum += shared[i];
        }
        output[0] = sum;
    }
}

kernel void tile_reduce_sq(
    device const half* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant uint& length [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    threadgroup float shared[256];
    float acc = 0.0f;
    for (uint i = tid; i < length; i += 256u) {
        float v = float(input[i]);
        acc += v * v;
    }
    shared[tid % 256u] = acc;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (tid == 0u) {
        float sum = 0.0f;
        for (uint i = 0u; i < 256u; ++i) {
            sum += shared[i];
        }
        output[0] = sum;
    }
}
