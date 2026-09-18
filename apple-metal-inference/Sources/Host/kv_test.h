#pragma once
#include <atomic>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <random>
#include <vector>

namespace afm::test {

inline void secure_zero(void* p, size_t n) {
    volatile uint8_t* v = (volatile uint8_t*)p;
    while (n--) *v++ = 0;
    std::atomic_thread_fence(std::memory_order_seq_cst);
}

struct KVSlice {
    uint8_t* data;
    size_t bytes;
    uint64_t session_tag;
};

inline bool verify_session_isolation(const std::vector<KVSlice>& slices) {
    for (size_t i = 0; i < slices.size(); ++i) {
        for (size_t j = i + 1; j < slices.size(); ++j) {
            if (slices[i].data == slices[j].data) return false;
            if (slices[i].session_tag == slices[j].session_tag) return false;
        }
    }
    return true;
}

inline bool test_zeroize_after_release() {
    constexpr size_t N = 4096;
    std::vector<uint8_t> buf(N);
    std::mt19937 rng(0xC0FFEE);
    for (auto& b : buf) b = (uint8_t)rng();

    secure_zero(buf.data(), buf.size());
    for (auto b : buf) if (b != 0) return false;
    return true;
}

}  // namespace afm::test
