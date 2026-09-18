#include "../Common/types.h"

kernel void matmul_block(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* c [[buffer(2)]],
    constant LinearShape& shape [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint row = gid.y;
    uint col = gid.x;
    if (row >= shape.rows || col >= shape.stride) {
        return;
    }
    float acc = 0.0f;
    for (uint k = 0u; k < shape.cols; ++k) {
        acc += float(a[row * shape.cols + k]) * float(b[k * shape.stride + col]);
    }
    c[row * shape.stride + col] = half(acc);
}

kernel void matmul_block_tiled(
    device const half* a [[buffer(0)]],
    device const half* b [[buffer(1)]],
    device half* c [[buffer(2)]],
    constant LinearShape& shape [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]])
{
    const uint TILE = 16u;
    threadgroup float tileA[16][16];
    threadgroup float tileB[16][16];

    uint row = gid.y;
    uint col = gid.x;
    float acc = 0.0f;

    for (uint t = 0u; t < (shape.cols + TILE - 1u) / TILE; ++t) {
        uint aCol = t * TILE + lid.x;
        uint bRow = t * TILE + lid.y;
        tileA[lid.y][lid.x] = (row < shape.rows && aCol < shape.cols)
            ? float(a[row * shape.cols + aCol]) : 0.0f;
        tileB[lid.y][lid.x] = (bRow < shape.cols && col < shape.stride)
            ? float(b[bRow * shape.stride + col]) : 0.0f;
        threadgroup_barrier(mem_flags::mem_threadgroup);

        for (uint k = 0u; k < TILE; ++k) {
            acc += tileA[lid.y][k] * tileB[k][lid.x];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (row < shape.rows && col < shape.stride) {
        c[row * shape.stride + col] = half(acc);
    }
}

kernel void transposed_matmul(
    device const half* a [[buffer(0)]],
    device const half* b_transposed [[buffer(1)]],
    device half* c [[buffer(2)]],
    constant LinearShape& shape [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint row = gid.y;
    uint col = gid.x;
    if (row >= shape.rows || col >= shape.stride) {
        return;
    }
    float acc = 0.0f;
    for (uint k = 0u; k < shape.cols; ++k) {
        acc += float(a[row * shape.cols + k]) * float(b_transposed[col * shape.cols + k]);
    }
    c[row * shape.stride + col] = half(acc);
}
