#include <metal_stdlib>
using namespace metal;

struct LoRAParams {
    uint rank;
    uint K;
    uint N;
    float scale;
};

kernel void apply_lora_delta(
    device const half* A [[buffer(0)]],
    device const half* B [[buffer(1)]],
    device const half* X [[buffer(2)]],
    device half* Y [[buffer(3)]],
    constant LoRAParams& p [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint n = gid.x;
    uint m = gid.y;
    if (n >= p.N) return;

    float tmp[64];
    for (uint r = 0; r < p.rank; ++r) {
        float acc = 0.f;
        for (uint k = 0; k < p.K; ++k)
            acc += (float)A[r * p.K + k] * (float)X[m * p.K + k];
        tmp[r] = acc;
    }
    float delta = 0.f;
    for (uint r = 0; r < p.rank; ++r)
        delta += (float)B[n * p.rank + r] * tmp[r];

    Y[m * p.N + n] = (half)((float)Y[m * p.N + n] + delta * p.scale);
}
