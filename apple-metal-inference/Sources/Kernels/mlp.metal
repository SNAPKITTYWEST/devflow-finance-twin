#include "../Common/types.h"

kernel void swiglu(
    device const uchar* w_gate [[buffer(0)]],
    device const half* s_gate [[buffer(1)]],
    device const uchar* w_up [[buffer(2)]],
    device const half* s_up [[buffer(3)]],
    device const half* x [[buffer(4)]],
    device half* output [[buffer(5)]],
    constant ModelConfig& config [[buffer(6)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.intermediate) {
        return;
    }
    float gate = 0.0f;
    float up = 0.0f;
    for (uint col = 0u; col < config.hidden; ++col) {
        float xv = float(x[col]);
        gate += dequant_i4(w_gate, s_gate, tid, col, config.hidden) * xv;
        up += dequant_i4(w_up, s_up, tid, col, config.hidden) * xv;
    }
    output[tid] = half(silu(gate) * up);
}

kernel void swiglu_bias(
    device const uchar* w_gate [[buffer(0)]],
    device const half* s_gate [[buffer(1)]],
    device const half* b_gate [[buffer(2)]],
    device const uchar* w_up [[buffer(3)]],
    device const half* s_up [[buffer(4)]],
    device const half* b_up [[buffer(5)]],
    device const half* x [[buffer(6)]],
    device half* output [[buffer(7)]],
    constant ModelConfig& config [[buffer(8)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.intermediate) {
        return;
    }
    float gate = float(b_gate[tid]);
    float up = float(b_up[tid]);
    for (uint col = 0u; col < config.hidden; ++col) {
        float xv = float(x[col]);
        gate += dequant_i4(w_gate, s_gate, tid, col, config.hidden) * xv;
        up += dequant_i4(w_up, s_up, tid, col, config.hidden) * xv;
    }
    output[tid] = half(silu(gate) * up);
}

kernel void mlp_down(
    device const uchar* w_down [[buffer(0)]],
    device const half* s_down [[buffer(1)]],
    device const half* x [[buffer(2)]],
    device half* output [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < config.intermediate; ++col) {
        acc += dequant_i4(w_down, s_down, tid, col, config.intermediate) * float(x[col]);
    }
    output[tid] = half(acc);
}

kernel void mlp_down_bias(
    device const uchar* w_down [[buffer(0)]],
    device const half* s_down [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device const half* x [[buffer(3)]],
    device half* output [[buffer(4)]],
    constant ModelConfig& config [[buffer(5)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= config.hidden) {
        return;
    }
    float acc = float(bias[tid]);
    for (uint col = 0u; col < config.intermediate; ++col) {
        acc += dequant_i4(w_down, s_down, tid, col, config.intermediate) * float(x[col]);
    }
    output[tid] = half(acc);
}
