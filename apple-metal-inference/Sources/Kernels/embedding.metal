#include "../Common/types.h"

kernel void embedding(
    device const half* embedding_table [[buffer(0)]],
    device const uint* token_ids [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid < config.hidden) {
        uint token = token_ids[0];
        output[tid] = embedding_table[token * config.hidden + tid];
    }
}

kernel void embedding_batch(
    device const half* embedding_table [[buffer(0)]],
    device const uint* token_ids [[buffer(1)]],
    device half* output [[buffer(2)]],
    constant ModelConfig& config [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    uint row = tid / config.hidden;
    uint col = tid % config.hidden;
    if (row < config.token_count && col < config.hidden) {
        uint token = token_ids[row];
        output[row * config.hidden + col] = embedding_table[token * config.hidden + col];
    }
}
