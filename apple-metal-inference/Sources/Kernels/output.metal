#include "../Common/types.h"

kernel void logits_i4(
    device const half* hidden [[buffer(0)]],
    device const uchar* lm_weight [[buffer(1)]],
    device const half* lm_scale [[buffer(2)]],
    device float* logits [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= config.vocab) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < config.hidden; ++col) {
        acc += dequant_i4(lm_weight, lm_scale, row, col, config.hidden) * float(hidden[col]);
    }
    logits[row] = acc;
}

kernel void logits_i8(
    device const half* hidden [[buffer(0)]],
    device const uchar* lm_weight [[buffer(1)]],
    device const half* lm_scale [[buffer(2)]],
    device float* logits [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= config.vocab) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < config.hidden; ++col) {
        acc += dequant_i8(lm_weight, lm_scale, row, col, config.hidden) * float(hidden[col]);
    }
    logits[row] = acc;
}

kernel void token_select(
    device const float* logits [[buffer(0)]],
    device uint* selected [[buffer(1)]],
    constant ModelConfig& config [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid != 0u) {
        return;
    }
    float best = -1.0e30f;
    uint best_idx = 0u;
    for (uint i = 0u; i < config.vocab; ++i) {
        if (logits[i] > best) {
            best = logits[i];
            best_idx = i;
        }
    }
    selected[0] = best_idx;
}

kernel void top_k_select(
    device const float* logits [[buffer(0)]],
    device float* top_vals [[buffer(1)]],
    device uint* top_ids [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    constant uint& k [[buffer(4)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid != 0u) {
        return;
    }
    for (uint ki = 0u; ki < k; ++ki) {
        top_vals[ki] = -1.0e30f;
        top_ids[ki] = 0u;
    }
    for (uint i = 0u; i < config.vocab; ++i) {
        float val = logits[i];
        uint slot = k;
        for (uint j = 0u; j < k; ++j) {
            if (val > top_vals[j]) {
                slot = j;
                break;
            }
        }
        if (slot < k) {
            for (uint j = k - 1u; j > slot; --j) {
                top_vals[j] = top_vals[j - 1u];
                top_ids[j] = top_ids[j - 1u];
            }
            top_vals[slot] = val;
            top_ids[slot] = i;
        }
    }
}

kernel void temperature_softmax(
    device float* logits [[buffer(0)]],
    constant ModelConfig& config [[buffer(1)]],
    constant float& temperature [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid != 0u) {
        return;
    }
    float inv_temp = 1.0f / max(temperature, 1.0e-6f);
    float maxv = -1.0e30f;
    for (uint i = 0u; i < config.vocab; ++i) {
        logits[i] *= inv_temp;
        maxv = max(maxv, logits[i]);
    }
    float sum = 0.0f;
    for (uint i = 0u; i < config.vocab; ++i) {
        float e = exp(logits[i] - maxv);
        logits[i] = e;
        sum += e;
    }
    float inv = 1.0f / max(sum, 1.0e-8f);
    for (uint i = 0u; i < config.vocab; ++i) {
        logits[i] *= inv;
    }
}
