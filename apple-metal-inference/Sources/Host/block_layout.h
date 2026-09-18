#pragma once
#include <cstddef>

namespace afm {

struct BlockLayout {
    static constexpr int SUPERBLOCK_SIZE = 8;
    static constexpr int DEDICATED_BLOCKS = 5;
    static constexpr int SHARED_BLOCKS = 3;

    int num_blocks;
    size_t kv_bytes_per_block;

    size_t dedicated_kv_bytes() const { return DEDICATED_BLOCKS * kv_bytes_per_block; }
    size_t shared_kv_bytes() const { return kv_bytes_per_block; }

    size_t total_kv_bytes() const {
        int superblocks = (num_blocks + SUPERBLOCK_SIZE - 1) / SUPERBLOCK_SIZE;
        return (size_t)superblocks * (dedicated_kv_bytes() + shared_kv_bytes());
    }
};

}  // namespace afm
