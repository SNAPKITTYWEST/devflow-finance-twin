#pragma once
#include "adapter.h"
#include <atomic>
#include <cstring>

#ifdef __APPLE__
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#endif

namespace afm {

class AdapterSlot {
public:
    std::atomic<const Adapter*> active{nullptr};
    Adapter a_slot;
    Adapter b_slot;
    std::atomic<int> which{0};

#ifdef __APPLE__
    bool load(const char* path) {
        int fd = open(path, O_RDONLY);
        if (fd < 0) return false;
        off_t sz = lseek(fd, 0, SEEK_END);
        lseek(fd, 0, SEEK_SET);

        void* p = mmap(nullptr, (size_t)sz, PROT_READ, MAP_PRIVATE, fd, 0);
        close(fd);
        if (p == MAP_FAILED) return false;

        Adapter* target = &a_slot;
        if (which.load() == 0) target = &b_slot;
        target->base = (const uint8_t*)p;
        target->size = (size_t)sz;
        std::memcpy(&target->hdr, p, sizeof(AdapterHeader));

        int prev = which.exchange(which.load() == 0 ? 1 : 0);
        active.store(target, std::memory_order_release);
        (void)prev;
        return true;
    }
#endif
};

}  // namespace afm
