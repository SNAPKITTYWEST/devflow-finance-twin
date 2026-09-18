#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

constant constexpr uint kQuantGroup = 32;
constant constexpr float kInt4Offset = 7.5f;

struct ModelDims {
    uint16_t hidden;
    uint16_t qkvHidden;
    uint16_t headDim;
    uint16_t numHeads;
    uint16_t numKVHeads;
    uint16_t intermediate;
    uint16_t maxSeqLen;
    uint16_t vocabSize;
};

struct LayerWeights {
    device const uint8_t* wqkvPacked;
    device const half2*   wqkvScales;
    device const uint8_t* woPacked;
    device const half2*   woScales;
    device const uint8_t* w1Packed;
    device const half2*   w1Scales;
    device const uint8_t* w3Packed;
    device const half2*   w3Scales;
    device const uint8_t* w2Packed;
    device const half2*   w2Scales;
    device const float*   attnNormGamma;
    device const float*   ffnNormGamma;
};

struct KVCache {
    device float* k;
    device float* v;
};

METAL_FUNC void bassert(thread const bool& cond,
                        device atomic_uint* faultCounter) {
    if (!cond) { atomic_fetch_add_explicit(faultCounter, 1u, memory_order_relaxed); }
}

METAL_FUNC float dequantNibble(device const uint8_t* rowPacked,
                                device const half2*  rowScales,
                                uint inIdx) {
    uint byteIdx = inIdx >> 1;
    uint group   = inIdx / kQuantGroup;
    uint8_t byte = rowPacked[byteIdx];
    int nib = (inIdx & 1u) ? (byte >> 4) : (byte & 0x0Fu);
    float scale = float(rowScales[group].x);
    return (float(nib) - kInt4Offset) * scale;
}

kernel void qkvProjection(device const float*        x,
                          device const LayerWeights* w,
                          device const ModelDims*    dims,
                          device float*              y,
                          device atomic_uint*        faults,
                          uint2 gid [[thread_position_in_grid]]) {
    const uint seq = gid.y;
    const uint out = gid.x;
    const uint hidden = dims->hidden;

    if (out >= dims->qkvHidden) return;
    if (seq  >= dims->maxSeqLen) return;

    bassert((hidden & 1u) == 0u, faults);
    bassert(hidden % kQuantGroup == 0, faults);

    device const uint8_t* rowPacked = w->wqkvPacked + (size_t)out * (hidden >> 1);
    device const half2*  rowScales = w->wqkvScales + (size_t)out * (hidden / kQuantGroup);

    device const float* xrow = x + (size_t)seq * hidden;
    float acc = 0.0f;
    for (uint i = 0; i < hidden; ++i) {
        acc += xrow[i] * dequantNibble(rowPacked, rowScales, i);
    }
    y[(size_t)seq * dims->qkvHidden + out] = acc;
}

kernel void applyRoPE(device float*              qkv,
                      device const ModelDims*    dims,
                      device atomic_uint*        faults,
                      uint2 gid [[thread_position_in_grid]]) {
    const uint headDim = dims->headDim;
    const uint numHeads = dims->numHeads;
    const uint pairsPerHead = headDim >> 1;

    const uint head = gid.x / pairsPerHead;
    const uint pair = gid.x % pairsPerHead;
    const uint seq  = gid.y;

    if (head >= numHeads) return;
    bassert(pairsPerHead > 0, faults);

    const float invFreq = pow(10000.0f, -((float)(2u * pair)) / (float)headDim);
    const float angle = (float)seq * invFreq;
    const float cs = cos(angle);
    const float sn = sin(angle);

    const size_t idx = (size_t)seq * dims->qkvHidden
                     + (size_t)head * headDim + (2u * pair);
    const float x0 = qkv[idx];
    const float x1 = qkv[idx + 1];
    qkv[idx]     = x0 * cs - x1 * sn;
    qkv[idx + 1] = x0 * sn + x1 * cs;
}

kernel void gqaAttention(device const float*        qkv,
                         device KVCache*            cache,
                         device const ModelDims*    dims,
                         device float*              attnOut,
                         device atomic_uint*        faults,
                         uint2 gid [[thread_position_in_grid]]) {
    const uint head = gid.x;
    const uint qPos = gid.y;
    const uint H = dims->numHeads, G = dims->numKVHeads, dh = dims->headDim;

    if (head >= H || qPos >= dims->maxSeqLen) return;
    bassert(H % G == 0, faults);

    const uint rep = H / G;
    const uint kvHead = head / rep;
    const size_t kvStride = (size_t)G * dh;
    const uint kvLen = qPos + 1;

    device const float* q = qkv + (size_t)qPos * dims->qkvHidden
                                 + (size_t)head * dh;

    float m = -INFINITY;
    float l = 0.0f;
    float accV[128];
    for (uint i = 0; i < dh; ++i) accV[i] = 0.0f;

    const float scale = rsqrt((float)dh);

    for (uint p = 0; p < kvLen; ++p) {
        device const float* k = cache->k + (size_t)p * kvStride + (size_t)kvHead * dh;
        device const float* v = cache->v + (size_t)p * kvStride + (size_t)kvHead * dh;

        float score = 0.0f;
        for (uint i = 0; i < dh; ++i) score += q[i] * k[i];
        score *= scale;

        const float newM = max(m, score);
        const float correction = exp(m - newM);
        const float pExp = exp(score - newM);
        l = l * correction + pExp;
        for (uint i = 0; i < dh; ++i) {
            accV[i] = accV[i] * correction + pExp * v[i];
        }
        m = newM;
    }
    const float invL = 1.0f / l;
    device float* out = attnOut + (size_t)qPos * dims->hidden + (size_t)head * dh;
    for (uint i = 0; i < dh; ++i) out[i] = accV[i] * invL;
}

kernel void rmsNorm(device const float*        x,
                    device const float*        gamma,
                    device float*              y,
                    device const ModelDims*    dims,
                    device atomic_uint*        faults,
                    uint2 gid [[thread_position_in_grid]]) {
    const uint seq = gid.y;
    const uint hidden = dims->hidden;
    if (seq >= dims->maxSeqLen) return;

    device const float* xr = x + (size_t)seq * hidden;

    float partial = 0.0f;
    for (uint i = gid.x; i < hidden; i += 128u) { partial += xr[i] * xr[i]; }
    partial = quad_sum(partial);

    threadgroup float tgSum[32];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const uint quadID = gid.x / 4u;
    if ((gid.x & 3u) == 0u && quadID < 32u) { tgSum[quadID] = partial; }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    float total = 0.0f;
    const uint nQuads = min(32u, (hidden + 3u) / 4u);
    for (uint i = 0; i < nQuads; ++i) total += tgSum[i];

    const float rms = rsqrt(total / (float)hidden + 1e-6f);
    for (uint i = gid.x; i < hidden; i += 128u) {
        y[(size_t)seq * hidden + i] = xr[i] * rms * gamma[i];
    }
}

kernel void swigluFFN(device const float*     gate,
                      device const float*     up,
                      device float*           act,
                      device const ModelDims* dims,
                      uint2 gid [[thread_position_in_grid]]) {
    const uint seq = gid.y;
    const uint i   = gid.x;
    if (i >= dims->intermediate) return;
    const size_t idx = (size_t)seq * dims->intermediate + i;
    const float g = gate[idx];
    const float u = up[idx];
    const float silu = g / (1.0f + exp(-g));
    act[idx] = silu * u;
}

kernel void int4Matvec(device const float*        x,
                       device const uint8_t*      wPacked,
                       device const half2*       wScales,
                       device float*             y,
                       constant uint& inDim,
                       constant uint& outDim,
                       device atomic_uint*       faults,
                       uint2 gid [[thread_position_in_grid]]) {
    const uint seq = gid.y;
    const uint out = gid.x;
    if (out >= outDim) return;
    bassert((inDim & 1u) == 0u, faults);
    bassert(inDim % kQuantGroup == 0, faults);

    device const uint8_t* rowPacked = wPacked + (size_t)out * (inDim >> 1);
    device const half2*  rowScales = wScales + (size_t)out * (inDim / kQuantGroup);
    device const float*  xr = x + (size_t)seq * inDim;

    float acc = 0.0f;
    for (uint i = 0; i < inDim; ++i) {
        acc += xr[i] * dequantNibble(rowPacked, rowScales, i);
    }
    y[(size_t)seq * outDim + out] = acc;
}

kernel void loraDown(device const float*  x,
                     device const half*   A,
                     device float*        z,
                     constant uint& inDim,
                     constant uint& r,
                     uint2 gid [[thread_position_in_grid]]) {
    const uint seq = gid.y, ri = gid.x;
    if (ri >= r) return;
    device const half* arow = A + (size_t)ri * inDim;
    device const float* xr  = x + (size_t)seq * inDim;
    float acc = 0.0f;
    for (uint i = 0; i < inDim; ++i) acc += xr[i] * (float)arow[i];
    z[(size_t)seq * r + ri] = acc;
}

kernel void loraUp(device const float*  z,
                   device const half*   B,
                   device float*        y,
                   constant uint& outDim,
                   constant uint& r,
                   constant float& alphaOverRank,
                   uint2 gid [[thread_position_in_grid]]) {
    const uint seq = gid.y, out = gid.x;
    if (out >= outDim) return;
    device const half* brow = B + (size_t)out * r;
    device const float* zr  = z + (size_t)seq * r;
    float acc = 0.0f;
    for (uint i = 0; i < r; ++i) acc += zr[i] * (float)brow[i];
    y[(size_t)seq * outDim + out] += alphaOverRank * acc;
}

kernel void secureClearKV(device float*             cache,
                          constant uint&            elemCount,
                          device atomic_uint*       faults,
                          uint gid [[thread_position_in_grid]]) {
    if (gid >= elemCount) return;
    volatile device float* vc = cache + gid;
    *vc = 0.0f;
    bassert(*vc == 0.0f, faults);
}
