/**
 * test_fib_braid_ledger.cpp
 * Unit tests for FNV-1a avalanche, deterministic entry construction,
 * hash-chain integrity, lock-free concurrent appends.
 *
 * Build: g++ -std=c++17 -O2 -pthread -o test_ledger test_fib_braid_ledger.cpp
 */

#include "fib_braid_ledger.hpp"

#include <iostream>
#include <thread>
#include <vector>
#include <atomic>
#include <random>
#include <cassert>
#include <cmath>
#include <iomanip>
#include <set>
#include <algorithm>

using namespace fib_braid;

static int g_failed = 0;
static int g_passed = 0;

#define CHECK(cond) do { \
    if (!(cond)) { \
        std::cerr << "FAIL: " << #cond << " (" << __FILE__ << ":" << __LINE__ << ")\n"; \
        ++g_failed; \
    } else { ++g_passed; } \
} while (0)

#define CHECK_EQ(a, b) do { \
    auto _a = (a); auto _b = (b); \
    if (_a != _b) { \
        std::cerr << "FAIL: " << #a << " == " << #b \
                  << " (" << _a << " != " << _b << ") " \
                  << __FILE__ << ":" << __LINE__ << "\n"; \
        ++g_failed; \
    } else { ++g_passed; } \
} while (0)

void test_fnv_basic() {
    CHECK_EQ(fnv1a_64(nullptr, 0), FNV_OFFSET);
    const char* s1 = "a";
    uint64_t h1 = fnv1a_64(s1, 1);
    CHECK(h1 != FNV_OFFSET);
    const char* s2 = "b";
    uint64_t h2 = fnv1a_64(s2, 1);
    CHECK(h1 != h2);
    CHECK_EQ(fnv1a_64(s1, 1), fnv1a_64(s1, 1));
}

void test_fnv_avalanche() {
    constexpr int TRIALS = 2048;
    constexpr int BITS = 64;
    std::vector<int> flipped(BITS, 0);
    std::mt19937_64 rng(0xC0FFEE);
    for (int t = 0; t < TRIALS; ++t) {
        uint64_t x = rng();
        uint64_t hx = fnv1a_u64(x);
        for (int b = 0; b < BITS; ++b) {
            uint64_t y = x ^ (1ull << b);
            uint64_t hy = fnv1a_u64(y);
            uint64_t diff = hx ^ hy;
            for (int ob = 0; ob < BITS; ++ob)
                if (diff & (1ull << ob)) ++flipped[ob];
        }
    }
    const double total = static_cast<double>(TRIALS) * BITS;
    double min_ratio = 1.0, max_ratio = 0.0;
    for (int b = 0; b < BITS; ++b) {
        double ratio = flipped[b] / total;
        min_ratio = std::min(min_ratio, ratio);
        max_ratio = std::max(max_ratio, ratio);
    }
    CHECK(min_ratio > 0.40);
    CHECK(max_ratio < 0.60);
    std::cout << " Avalanche bit-flip ratios: min=" << std::fixed << std::setprecision(3)
              << min_ratio << " max=" << max_ratio << "\n";
}

void test_braid_determinism() {
    BraidWord w0 = braid_from_fib(0, fib(0));
    CHECK_EQ(w0.len, 0u);

    BraidWord w1a = braid_from_fib(1, fib(1));
    BraidWord w1b = braid_from_fib(1, fib(1));
    CHECK_EQ(w1a.len, 1u);
    CHECK_EQ(w1a.gens[0], 1);
    CHECK(std::memcmp(w1a.gens, w1b.gens, w1a.len * sizeof(int32_t)) == 0);

    BraidWord w3 = braid_from_fib(3, fib(3));
    CHECK_EQ(w3.len, 2u);
    CHECK_EQ(w3.gens[0], 1);
    CHECK_EQ(w3.gens[1], -2);

    BraidWord w5 = braid_from_fib(5, fib(5));
    CHECK_EQ(w5.len, 5u);
    CHECK_EQ(w5.gens[0], 1);
    CHECK_EQ(w5.gens[1], -2);
    CHECK_EQ(w5.gens[2], 3);
    CHECK_EQ(w5.gens[3], -4);
    CHECK_EQ(w5.gens[4], 1);

    BraidWord cancel = {};
    cancel.gens[0] = 1; cancel.gens[1] = -1; cancel.gens[2] = 2; cancel.len = 3;
    BraidWord red = reduce(cancel);
    CHECK_EQ(red.len, 1u);
    CHECK_EQ(red.gens[0], 2);
}

void test_single_thread_chain() {
    AppendOnlyLedger ledger;
    for (uint32_t i = 0; i < 20; ++i) CHECK(ledger.append(i));
    CHECK_EQ(ledger.size(), 20u);
    CHECK(ledger.verify_chain());

    const LedgerEntry& e0 = ledger[0];
    CHECK_EQ(e0.sequence, 0u);
    CHECK_EQ(e0.fib_value, 0u);
    CHECK_EQ(e0.word.len, 0u);
    CHECK_EQ(e0.prev_hash, FNV_OFFSET);

    const LedgerEntry& e1 = ledger[1];
    CHECK_EQ(e1.sequence, 1u);
    CHECK_EQ(e1.fib_value, 1u);
    CHECK_EQ(e1.word.len, 1u);
    CHECK_EQ(e1.word.gens[0], 1);
    CHECK_EQ(e1.prev_hash, e0.entry_hash);
}

void test_concurrent_appends() {
    constexpr int NUM_THREADS = 8;
    constexpr int OPS_PER_THREAD = 128;

    AppendOnlyLedger ledger;
    std::atomic<int> success{0};
    std::vector<std::thread> threads;

    auto worker = [&](int tid) {
        for (int i = 0; i < OPS_PER_THREAD; ++i) {
            uint32_t logical = static_cast<uint32_t>((tid * OPS_PER_THREAD + i) % (MAX_FIB_INDEX + 1));
            if (ledger.append(logical))
                success.fetch_add(1, std::memory_order_relaxed);
        }
    };

    for (int t = 0; t < NUM_THREADS; ++t)
        threads.emplace_back(worker, t);
    for (auto& th : threads) th.join();

    const uint64_t n = ledger.size();
    CHECK(n > 0);
    CHECK(success.load() == static_cast<int>(n));
    CHECK(ledger.verify_chain());

    std::vector<uint64_t> seqs;
    seqs.reserve(n);
    for (auto it = ledger.begin(); it != ledger.end(); ++it)
        seqs.push_back(it->sequence);
    std::sort(seqs.begin(), seqs.end());
    for (uint64_t i = 0; i < n; ++i) CHECK_EQ(seqs[i], i);

    std::set<uint64_t> seen_fib;
    for (auto it = ledger.begin(); it != ledger.end(); ++it) {
        const auto& e = *it;
        uint64_t expect_len = e.fib_value < MAX_WORD_LEN ? e.fib_value : MAX_WORD_LEN;
        CHECK_EQ(e.word.len, static_cast<uint32_t>(expect_len));
        CHECK(e.word.valid());
        seen_fib.insert(e.fib_value);
    }
    CHECK(!seen_fib.empty());
    std::cout << " Concurrent: " << n << " entries committed, chain OK\n";
}

void test_iterator() {
    AppendOnlyLedger ledger;
    for (uint32_t i = 0; i < 10; ++i) ledger.append(i);
    uint64_t count = 0, last_seq = 0;
    for (const auto& e : ledger) {
        if (count > 0) CHECK(e.sequence == last_seq + 1);
        last_seq = e.sequence;
        ++count;
    }
    CHECK_EQ(count, 10u);
    CHECK_EQ(count, ledger.size());
}

int main() {
    std::cout << "=== Fibonacci Braid Ledger — C++ unit tests ===\n\n";
    std::cout << "[1] FNV-1a basic\n";          test_fnv_basic();
    std::cout << "[2] FNV-1a avalanche\n";       test_fnv_avalanche();
    std::cout << "[3] Braid determinism\n";       test_braid_determinism();
    std::cout << "[4] Single-thread hash chain\n"; test_single_thread_chain();
    std::cout << "[5] Iterator\n";               test_iterator();
    std::cout << "[6] Concurrent appends\n";     test_concurrent_appends();
    std::cout << "\n----------------------------------------\n";
    std::cout << "Passed: " << g_passed << " Failed: " << g_failed << "\n";
    return g_failed ? 1 : 0;
}
