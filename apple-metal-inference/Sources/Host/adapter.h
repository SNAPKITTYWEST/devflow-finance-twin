#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace afm {

constexpr size_t ALIGN_16K = 16384;

struct AdapterHeader {
    char magic[8];
    uint32_t version;
    uint32_t rank;
    uint32_t in_features;
    uint32_t out_features;
    float alpha;
    uint32_t dtype;
    uint32_t layer_count;
    uint64_t payload_bytes;
} __attribute__((packed));

struct LayerSlice {
    uint32_t layer_idx;
    uint32_t r;
    uint32_t k;
    uint32_t n;
    size_t a_offset;
    size_t b_offset;
};

class Adapter {
public:
    const uint8_t* base = nullptr;
    size_t size = 0;
    AdapterHeader hdr{};
    std::vector<LayerSlice> slices;

    const void* A(uint32_t layer) const {
        return base + slices[layer].a_offset;
    }
    const void* B(uint32_t layer) const {
        return base + slices[layer].b_offset;
    }
    float scale() const {
        return hdr.alpha / (float)hdr.rank;
    }
};

}  // namespace afm
