#pragma once
#include <cassert>
#include <cstddef>
#include <cstdint>

namespace afm::safety {

struct Tensor4Bit {
    const uint8_t* packed;
    const uint16_t* scales;
    size_t N;
    size_t K;
    size_t G;
};

inline void assert_shape(const Tensor4Bit& t) {
    assert(t.packed != nullptr && t.scales != nullptr);
    assert(t.K % 2 == 0);
    assert(t.K % t.G == 0);
    assert(t.N > 0 && t.K > 0);
}

inline float dequant(const Tensor4Bit& t, size_t n, size_t k) {
    assert(n < t.N);
    assert(k < t.K);
    size_t byte_idx = n * (t.K / 2) + (k >> 1);
    uint8_t b = t.packed[byte_idx];
    int nib = (k & 1u) ? (int)(b >> 4) : (int)(b & 0x0F);
    if (nib >= 8) nib -= 16;
    float s = (float)t.scales[n * (t.K / t.G) + (k / t.G)];
    return (float)nib * s;
}

}  // namespace afm::safety
