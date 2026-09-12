# docs/MEMORY.md
Word-addressable store with explicit bounds. A free-list heap sits above
a guard region; blocks carry a header word (allocated-bit + size).
Allocation is first-fit with splitting; release validates the header and
scans the free list to detect double frees. There is no tracing GC:
ALLOC/FREE are explicit and `mem_heap_used()` makes allocation behavior
observable. All runtime interfaces validate inputs; faults are sticky.
