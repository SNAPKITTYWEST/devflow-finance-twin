#include "../Common/types.h"

kernel void kv_store(
    device const half* k [[buffer(0)]],
    device const half* v [[buffer(1)]],
    device half* k_cache [[buffer(2)]],
    device half* v_cache [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    constant PosInfo& pos [[buffer(5)]],
    uint tid [[thread_position_in_grid]])
{
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid >= kv_total) {
        return;
    }
    uint kv_head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint offset = kv_offset(pos.token_index, kv_head, config.head_dim, config.kv_heads) + dim;
    k_cache[offset] = k[tid];
    v_cache[offset] = v[tid];
}

kernel void kv_store_layer(
    device const half* k [[buffer(0)]],
    device const half* v [[buffer(1)]],
    device half* k_cache [[buffer(2)]],
    device half* v_cache [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    constant CacheSpec& spec [[buffer(5)]],
    uint tid [[thread_position_in_grid]])
{
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid >= kv_total) {
        return;
    }
    uint kv_head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint layer_stride = config.context * config.kv_heads * config.head_dim;
    uint base = spec.layer * layer_stride;
    uint offset = base + kv_offset(spec.position, kv_head, config.head_dim, config.kv_heads) + dim;
    k_cache[offset] = k[tid];
    v_cache[offset] = v[tid];
}

kernel void kv_fetch(
    device const half* k_cache [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* k_out [[buffer(2)]],
    device half* v_out [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    constant CacheSpec& spec [[buffer(5)]],
    uint tid [[thread_position_in_grid]])
{
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid >= kv_total) {
        return;
    }
    uint kv_head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint offset = kv_offset(spec.position, kv_head, config.head_dim, config.kv_heads) + dim;
    k_out[tid] = k_cache[offset];
    v_out[tid] = v_cache[offset];
}

kernel void kv_fetch_layer(
    device const half* k_cache [[buffer(0)]],
    device const half* v_cache [[buffer(1)]],
    device half* k_out [[buffer(2)]],
    device half* v_out [[buffer(3)]],
    constant ModelConfig& config [[buffer(4)]],
    constant CacheSpec& spec [[buffer(5)]],
    uint tid [[thread_position_in_grid]])
{
    uint kv_total = config.kv_heads * config.head_dim;
    if (tid >= kv_total) {
        return;
    }
    uint kv_head = tid / config.head_dim;
    uint dim = tid % config.head_dim;
    uint layer_stride = config.context * config.kv_heads * config.head_dim;
    uint base = spec.layer * layer_stride;
    uint offset = base + kv_offset(spec.position, kv_head, config.head_dim, config.kv_heads) + dim;
    k_out[tid] = k_cache[offset];
    v_out[tid] = v_cache[offset];
}
