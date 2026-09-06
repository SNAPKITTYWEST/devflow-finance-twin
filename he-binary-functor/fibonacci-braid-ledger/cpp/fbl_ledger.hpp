#ifndef FIB_BRAID_LEDGER_HPP
#define FIB_BRAID_LEDGER_HPP

#include <cstdint>
#include <atomic>
#include <array>
#include <cstring>
#include <cstddef>

namespace FBL {

constexpr uint64_t FNV_OFFSET_BASIS = 0xcbf29ce484222325ULL;
constexpr uint64_t FNV_PRIME = 0x100000001b3ULL;

inline uint64_t fnv1a_hash(const void* data, size_t len, uint64_t seed = FNV_OFFSET_BASIS) {
    const uint8_t* p = static_cast<const uint8_t*>(data);
    uint64_t hash = seed;
    for (size_t i = 0; i < len; ++i) {
        hash ^= p[i];
        hash *= FNV_PRIME;
    }
    return hash;
}

struct __attribute__((__packed__)) LedgerEntry {
    uint64_t fib_index;
    uint64_t seq_num;
    uint64_t state_in;
    uint64_t state_out;
    uint8_t braid_len;
    int8_t braid_word[16];
    uint64_t prev_seal;
    uint64_t self_seal;
};

template <size_t Capacity>
class ConcurrentLedgerBuffer {
public:
    enum class Status { OK, BUFFER_FULL, CHAIN_BROKEN, INVALID_WORD };

    ConcurrentLedgerBuffer() : tail_(0), committed_tail_(0) {
        for (size_t i = 0; i < Capacity; ++i) {
            slot_status_[i].store(0, std::memory_order_relaxed);
        }
    }

    Status append(uint64_t fib_index, uint64_t state_in, uint64_t state_out,
                  const int8_t* word, uint8_t braid_len, uint64_t& out_seal) {
        if (braid_len > 16) return Status::INVALID_WORD;

        size_t idx = tail_.fetch_add(1, std::memory_order_relaxed);
        if (idx >= Capacity) return Status::BUFFER_FULL;

        LedgerEntry& entry = buffer_[idx];
        entry.fib_index = fib_index;
        entry.seq_num = idx;
        entry.state_in = state_in;
        entry.state_out = state_out;
        entry.braid_len = braid_len;
        std::memset(entry.braid_word, 0, sizeof(entry.braid_word));
        if (braid_len > 0) std::memcpy(entry.braid_word, word, braid_len);

        if (idx == 0) {
            entry.prev_seal = FNV_OFFSET_BASIS;
        } else {
            while (committed_tail_.load(std::memory_order_acquire) < idx)
                __builtin_ia32_pause();
            entry.prev_seal = buffer_[idx - 1].self_seal;
        }

        size_t hash_len = offsetof(LedgerEntry, self_seal);
        uint64_t h = fnv1a_hash(&entry, hash_len);
        entry.self_seal = h;
        out_seal = h;

        slot_status_[idx].store(1, std::memory_order_release);

        size_t expected = idx;
        while (!committed_tail_.compare_exchange_weak(expected, expected + 1,
                                                     std::memory_order_release,
                                                     std::memory_order_relaxed)) {
            expected = committed_tail_.load(std::memory_order_relaxed);
            if (expected >= Capacity || slot_status_[expected].load(std::memory_order_acquire) == 0)
                break;
        }
        return Status::OK;
    }

    class ConstIterator {
    public:
        ConstIterator(const ConcurrentLedgerBuffer& ledger, size_t pos)
            : ledger_(ledger), pos_(pos) {}
        bool operator!=(const ConstIterator& other) const { return pos_ != other.pos_; }
        const LedgerEntry& operator*() const { return ledger_.buffer_[pos_]; }
        ConstIterator& operator++() { ++pos_; return *this; }
    private:
        const ConcurrentLedgerBuffer& ledger_;
        size_t pos_;
    };

    ConstIterator begin() const { return ConstIterator(*this, 0); }
    ConstIterator end() const { return ConstIterator(*this, committed_tail_.load(std::memory_order_acquire)); }

    bool verify_chain() const {
        size_t committed = committed_tail_.load(std::memory_order_acquire);
        if (committed == 0) return true;
        uint64_t expected_prev = FNV_OFFSET_BASIS;
        for (size_t i = 0; i < committed; ++i) {
            const auto& entry = buffer_[i];
            if (entry.prev_seal != expected_prev) return false;
            size_t hash_len = offsetof(LedgerEntry, self_seal);
            uint64_t computed_seal = fnv1a_hash(&entry, hash_len);
            if (computed_seal != entry.self_seal) return false;
            expected_prev = entry.self_seal;
        }
        return true;
    }

private:
    std::array<LedgerEntry, Capacity> buffer_;
    std::atomic<size_t> tail_;
    std::atomic<size_t> committed_tail_;
    std::array<std::atomic<uint32_t>, Capacity> slot_status_;
};

} // namespace FBL

#endif // FIB_BRAID_LEDGER_HPP
