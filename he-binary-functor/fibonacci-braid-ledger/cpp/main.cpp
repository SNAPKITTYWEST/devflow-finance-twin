/**
 * main.cpp — Unit test and concurrency harness for FBL ConcurrentLedgerBuffer
 * Build: g++ -std=c++17 -O2 -pthread -o test_fbl main.cpp
 */

#include "fbl_ledger.hpp"
#include <iostream>
#include <thread>
#include <vector>
#include <cassert>

void test_fnv_avalanche() {
    uint64_t val1 = 0x123456789ABCDEF0ULL;
    uint64_t val2 = val1 ^ (1ULL << 32);
    uint64_t h1 = FBL::fnv1a_hash(&val1, sizeof(val1));
    uint64_t h2 = FBL::fnv1a_hash(&val2, sizeof(val2));
    uint64_t diff = h1 ^ h2;
    int changed_bits = 0;
    for (int i = 0; i < 64; ++i)
        if ((diff >> i) & 1) changed_bits++;
    std::cout << "[TEST] FNV-1a Avalanche: Changed bits = " << changed_bits << "/64\n";
    assert(changed_bits >= 20 && changed_bits <= 44);
}

void test_concurrent_append() {
    constexpr size_t CAPACITY = 10000;
    FBL::ConcurrentLedgerBuffer<CAPACITY> ledger;
    constexpr int NUM_THREADS = 8;
    constexpr int OPS_PER_THREAD = 250;

    std::vector<std::thread> threads;
    threads.reserve(NUM_THREADS);

    for (int t = 0; t < NUM_THREADS; ++t) {
        threads.emplace_back([&ledger, t, OPS_PER_THREAD]() {
            for (int i = 0; i < OPS_PER_THREAD; ++i) {
                int8_t word[3] = {1, -2, 1};
                uint64_t seal = 0;
                uint64_t state_in = static_cast<uint64_t>(t * 1000 + i);
                uint64_t state_out = state_in ^ 0xDEADBEEFCAFEULL;
                auto status = ledger.append(i % 10, state_in, state_out, word, 3, seal);
                assert(status == decltype(ledger)::Status::OK);
            }
        });
    }
    for (auto& th : threads) th.join();

    bool chain_valid = ledger.verify_chain();
    std::cout << "[TEST] Concurrent Append Chain Verification: "
              << (chain_valid ? "PASSED" : "FAILED") << "\n";
    assert(chain_valid);
}

int main() {
    std::cout << "=== Running Fibonacci Braid Ledger System Tests ===\n";
    test_fnv_avalanche();
    test_concurrent_append();
    std::cout << "=== All Systems Tests Passed Successfully ===\n";
    return 0;
}
