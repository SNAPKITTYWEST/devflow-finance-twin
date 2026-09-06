#ifndef BLOCKLACE_LEDGER_HPP
#define BLOCKLACE_LEDGER_HPP

#include <cstdint>
#include <atomic>
#include <array>
#include <cstring>

namespace FBL {

constexpr size_t MAX_PARENTS = 4;
constexpr size_t MAX_WORD_LEN = 16;

struct __attribute__((__packed__)) BlocklaceEntry {
    uint64_t block_height;
    uint64_t parent_count;
    uint64_t parent_seals[MAX_PARENTS];
    uint64_t state_transition_id;
    uint8_t braid_len;
    int8_t braid_word[MAX_WORD_LEN];
    uint64_t self_seal;
};

class BlocklaceLedgerNode {
public:
    static uint64_t hash_entry(const BlocklaceEntry& entry) {
        const uint8_t* ptr = reinterpret_cast<const uint8_t*>(&entry);
        uint64_t hash = 0xcbf29ce484222325ULL;
        size_t len = offsetof(BlocklaceEntry, self_seal);
        for (size_t i = 0; i < len; ++i) {
            hash ^= ptr[i];
            hash *= 0x100000001b3ULL;
        }
        return hash;
    }

    bool commit_block(BlocklaceEntry& entry, const uint64_t* parents, size_t p_count) {
        if (p_count > MAX_PARENTS) return false;
        entry.parent_count = p_count;
        std::memset(entry.parent_seals, 0, sizeof(entry.parent_seals));
        for (size_t i = 0; i < p_count; ++i) {
            entry.parent_seals[i] = parents[i];
        }
        entry.self_seal = hash_entry(entry);
        return true;
    }
};

} // namespace FBL

#endif // BLOCKLACE_LEDGER_HPP
