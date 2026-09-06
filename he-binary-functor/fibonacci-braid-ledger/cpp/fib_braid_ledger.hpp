#pragma once
/**
 * fib_braid_ledger.hpp
 * Systems-level skeleton for the Fibonacci Braid Ledger.
 *
 * - Deterministic ledger entries (Fib-indexed braid words)
 * - 64-bit FNV-1a integrity chaining
 * - Lock-free multi-producer append-only buffer
 * - Read-only iterator for verification
 */

#include <atomic>
#include <cstdint>
#include <cstring>
#include <array>
#include <limits>
#include <type_traits>
#include <new>

namespace fib_braid {

constexpr uint32_t MAX_FIB_INDEX = 90;
constexpr uint32_t MAX_GEN = 4;
constexpr uint32_t MAX_WORD_LEN = 64;
constexpr uint32_t MAX_ENTRIES = 4096;
constexpr uint64_t SEAL_MOD = 1ull << 32;

constexpr uint64_t FNV_OFFSET = 0xcbf29ce484222325ull;
constexpr uint64_t FNV_PRIME = 0x100000001b3ull;

inline uint64_t fnv1a_64(const void* data, size_t len, uint64_t seed = FNV_OFFSET) noexcept {
    const uint8_t* p = static_cast<const uint8_t*>(data);
    uint64_t h = seed;
    for (size_t i = 0; i < len; ++i) { h ^= p[i]; h *= FNV_PRIME; }
    return h;
}

inline uint64_t fnv1a_u64(uint64_t v, uint64_t seed = FNV_OFFSET) noexcept {
    return fnv1a_64(&v, sizeof(v), seed);
}

struct BraidWord {
    int32_t gens[MAX_WORD_LEN];
    uint32_t len = 0;

    bool valid() const noexcept {
        if (len > MAX_WORD_LEN) return false;
        for (uint32_t i = 0; i < len; ++i) {
            int32_t a = gens[i] < 0 ? -gens[i] : gens[i];
            if (a < 1 || a > static_cast<int32_t>(MAX_GEN)) return false;
        }
        return true;
    }
    void clear() noexcept { len = 0; }
};

inline BraidWord reduce(const BraidWord& w) noexcept {
    BraidWord out;
    for (uint32_t i = 0; i < w.len; ++i) {
        if (out.len > 0 && out.gens[out.len - 1] == -w.gens[i]) --out.len;
        else out.gens[out.len++] = w.gens[i];
    }
    return out;
}

inline BraidWord braid_from_fib(uint32_t n, uint64_t fib_n) noexcept {
    BraidWord w;
    uint64_t L = fib_n < MAX_WORD_LEN ? fib_n : MAX_WORD_LEN;
    for (uint64_t k = 0; k < L; ++k) {
        int32_t g = 1 + static_cast<int32_t>(k % MAX_GEN);
        if (k & 1) g = -g;
        w.gens[w.len++] = g;
    }
    return w;
}

inline constexpr std::array<uint64_t, 91> make_fib_table() {
    std::array<uint64_t, 91> t{};
    t[0] = 0; t[1] = 1;
    for (int i = 2; i <= 90; ++i) t[i] = t[i-1] + t[i-2];
    return t;
}
inline constexpr auto FIB_TABLE = make_fib_table();

inline uint64_t fib(uint32_t n) noexcept {
    return n <= MAX_FIB_INDEX ? FIB_TABLE[n] : 0;
}

struct alignas(64) LedgerEntry {
    uint64_t sequence;
    uint64_t fib_value;
    BraidWord word;
    BraidWord reduced;
    uint64_t prev_hash;
    uint64_t entry_hash;
    uint64_t seal;
    uint32_t wlen;
    uint32_t rlen;
    uint8_t _pad[8];

    uint64_t compute_hash() const noexcept {
        uint64_t h = FNV_OFFSET;
        h = fnv1a_u64(sequence, h);
        h = fnv1a_u64(fib_value, h);
        h = fnv1a_64(word.gens, word.len * sizeof(int32_t), h);
        h = fnv1a_64(reduced.gens, reduced.len * sizeof(int32_t), h);
        h = fnv1a_u64(prev_hash, h);
        h = fnv1a_u64(seal, h);
        h = fnv1a_u64(wlen, h);
        h = fnv1a_u64(rlen, h);
        return h;
    }
};

static_assert(std::is_trivially_copyable_v<LedgerEntry>);
static_assert(sizeof(LedgerEntry) % 64 == 0);

class AppendOnlyLedger {
public:
    AppendOnlyLedger() noexcept {
        write_pos_.store(0, std::memory_order_relaxed);
        committed_.store(0, std::memory_order_relaxed);
        last_hash_.store(FNV_OFFSET, std::memory_order_relaxed);
    }

    AppendOnlyLedger(const AppendOnlyLedger&) = delete;
    AppendOnlyLedger& operator=(const AppendOnlyLedger&) = delete;

    bool append(uint32_t logical_index) noexcept {
        if (logical_index > MAX_FIB_INDEX) return false;
        uint64_t pos = write_pos_.fetch_add(1, std::memory_order_acq_rel);
        if (pos >= MAX_ENTRIES) return false;

        LedgerEntry& e = slots_[pos];
        e.sequence = pos;
        e.fib_value = fib(logical_index);
        e.word = braid_from_fib(logical_index, e.fib_value);
        e.reduced = reduce(e.word);
        e.wlen = e.word.len;
        e.rlen = e.reduced.len;

        uint64_t ssum = 0;
        for (uint32_t i = 0; i < e.word.len; ++i) {
            int32_t g = e.word.gens[i];
            ssum += static_cast<uint64_t>(g < 0 ? -g : g);
        }
        uint64_t prev = last_hash_.load(std::memory_order_acquire);
        e.prev_hash = prev;
        e.seal = (prev + ssum * e.fib_value) % SEAL_MOD;

        e.entry_hash = e.compute_hash();
        last_hash_.store(e.entry_hash, std::memory_order_release);

        uint64_t expected = pos;
        while (!committed_.compare_exchange_weak(
                   expected, pos + 1,
                   std::memory_order_release,
                   std::memory_order_relaxed)) {
            expected = committed_.load(std::memory_order_relaxed);
            if (expected > pos) break;
            expected = pos;
        }
        return true;
    }

    uint64_t size() const noexcept {
        return committed_.load(std::memory_order_acquire);
    }

    bool full() const noexcept {
        return write_pos_.load(std::memory_order_relaxed) >= MAX_ENTRIES;
    }

    class const_iterator {
    public:
        using iterator_category = std::forward_iterator_tag;
        using value_type = const LedgerEntry;
        using difference_type = std::ptrdiff_t;
        using pointer = const LedgerEntry*;
        using reference = const LedgerEntry&;

        const_iterator() noexcept : ledger_(nullptr), idx_(0) {}
        const_iterator(const AppendOnlyLedger* l, uint64_t i) noexcept
            : ledger_(l), idx_(i) {}

        reference operator*() const noexcept { return ledger_->slots_[idx_]; }
        pointer operator->() const noexcept { return &ledger_->slots_[idx_]; }
        const_iterator& operator++() noexcept { ++idx_; return *this; }
        const_iterator operator++(int) noexcept {
            const_iterator tmp = *this; ++idx_; return tmp;
        }
        bool operator==(const const_iterator& o) const noexcept {
            return idx_ == o.idx_ && ledger_ == o.ledger_;
        }
        bool operator!=(const const_iterator& o) const noexcept { return !(*this == o); }

    private:
        const AppendOnlyLedger* ledger_;
        uint64_t idx_;
    };

    const_iterator begin() const noexcept { return const_iterator(this, 0); }
    const_iterator end() const noexcept { return const_iterator(this, size()); }
    const LedgerEntry& operator[](uint64_t i) const noexcept { return slots_[i]; }

    bool verify_chain() const noexcept {
        uint64_t expected_prev = FNV_OFFSET;
        const uint64_t n = size();
        for (uint64_t i = 0; i < n; ++i) {
            const LedgerEntry& e = slots_[i];
            if (e.prev_hash != expected_prev) return false;
            if (e.entry_hash != e.compute_hash()) return false;
            expected_prev = e.entry_hash;
        }
        return true;
    }

private:
    alignas(64) std::atomic<uint64_t> write_pos_;
    alignas(64) std::atomic<uint64_t> committed_;
    alignas(64) std::atomic<uint64_t> last_hash_;
    alignas(64) LedgerEntry slots_[MAX_ENTRIES];
};

} // namespace fib_braid
