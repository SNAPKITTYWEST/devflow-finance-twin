#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

constant constexpr uint GROUP_SIZE = 64;
constant constexpr uint TILE_M = 64;
constant constexpr uint TILE_N = 64;
constant constexpr uint TILE_K = 32;

struct QKVParams {
    uint M;
    uint K;
    uint Nq, Nk, Nv;
    uint num_heads;
    uint num_kv_heads;
    uint head_dim;
    float alpha;
};

static inline float dequant_int4(uchar packed, uint lane) {
    int nib = (lane == 0) ? (int)(packed & 0x0F) : (int)(packed >> 4);
    nib = (nib >= 8) ? (nib - 16) : nib;
    return (float)nib;
}

kernel void fused_qkv_int4(
    device const uchar* Wq [[buffer(0)]],
    device const half* Sq [[buffer(1)]],
    device const uchar* Wk [[buffer(2)]],
    device const half* Sk [[buffer(3)]],
    device const uchar* Wv [[buffer(4)]],
    device const half* Sv [[buffer(5)]],
    device const half* X [[buffer(6)]],
    device half* Q [[buffer(7)]],
    device half* K [[buffer(8)]],
    device half* V [[buffer(9)]],
    constant QKVParams& p [[buffer(10)]],
    uint2 tgid [[threadgroup_position_in_grid]],
    uint tid [[thread_position_in_threadgroup]],
    uint simd_lane [[thread_index_in_simdgroup]])
{
    threadgroup half xs[TILE_M][TILE_K + 8];

    for (uint i = tid; i < TILE_M * TILE_K; i += TILE_M * TILE_K / 256) {
        uint row = i / TILE_K;
        uint col = i % TILE_K;
        uint gr = tgid.y * TILE_M + row;
        uint gc = tgid.x * TILE_K + col;
        xs[row][col] = (gr < p.M && gc < p.K) ? X[gr * p.K + gc] : (half)0;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    float accq = 0.f, acck = 0.f, accv = 0.f;

    for (uint k0 = 0; k0 < p.K; k0 += TILE_K) {
        uint row = tgid.y * TILE_M + (tid / (TILE_N / 4));
        uint colq = tgid.x * TILE_N + (tid % (TILE_N / 4));
        if (row >= p.M) continue;

        for (uint kk = 0; kk < TILE_K; ++kk) {
            uint gidx = (k0 + kk) / GROUP_SIZE;

            if (colq < p.Nq) {
                uchar pk = Wq[colq * (p.K / 2) + ((k0 + kk) >> 1)];
                float w = dequant_int4(pk, (k0 + kk) & 1u) * (float)Sq[colq * (p.K / GROUP_SIZE) + gidx];
                accq = fma(w, (float)xs[tid / (TILE_N / 4)][kk], accq);
            }
            uint colk = tgid.x * TILE_N + (tid % (TILE_N / 4));
            if (colk < p.Nk) {
                uchar pk = Wk[colk * (p.K / 2) + ((k0 + kk) >> 1)];
                float w = dequant_int4(pk, (k0 + kk) & 1u) * (float)Sk[colk * (p.K / GROUP_SIZE) + gidx];
                acck = fma(w, (float)xs[tid / (TILE_N / 4)][kk], acck);
            }
            uint colv = tgid.x * TILE_N + (tid % (TILE_N / 4));
            if (colv < p.Nv) {
                uchar pk = Wv[colv * (p.K / 2) + ((k0 + kk) >> 1)];
                float w = dequant_int4(pk, (k0 + kk) & 1u) * (float)Sv[colv * (p.K / GROUP_SIZE) + gidx];
                accv = fma(w, (float)xs[tid / (TILE_N / 4)][kk], accv);
            }
        }
    }

    uint row = tgid.y * TILE_M + (tid / (TILE_N / 4));
    if (row >= p.M) return;
    uint colq = tgid.x * TILE_N + (tid % (TILE_N / 4));
    if (colq < p.Nq) Q[row * p.Nq + colq] = (half)accq;
    if (colq < p.Nk) K[row * p.Nk + colq] = (half)acck;
    if (colq < p.Nv) V[row * p.Nv + colq] = (half)accv;
}
