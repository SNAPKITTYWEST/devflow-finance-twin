#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#define JXCL_NUM_REGS 16
#define STACK_SIZE    1024

typedef struct {
    uint8_t  *data;
    uint64_t  size;
    uint64_t  code_start;
    uint64_t  code_end;
} Memory;

typedef struct {
    uint64_t r[JXCL_NUM_REGS];
    uint64_t sp;
    uint64_t pc;
    uint64_t flags;
} Registers;

typedef struct {
    Registers regs;
    Memory    memory;
    int       halted;
    uint64_t  cycle_count;
} MachineState;

void     exec_push(MachineState *state, uint64_t value);
void     exec_pop (MachineState *state, uint64_t *out);
void     exec_call(MachineState *state, uint64_t target, uint64_t return_addr);
uint64_t addr_of  (uint64_t base, int64_t disp);

static MachineState make_state(uint8_t *buf) {
    MachineState s;
    memset(&s, 0, sizeof(s));
    s.memory.data = buf;
    s.memory.size = STACK_SIZE;
    s.memory.code_start = 0;
    s.memory.code_end = 0;
    s.regs.sp = STACK_SIZE;
    s.halted = 0;
    s.cycle_count = 0;
    return s;
}

void harness_push_pop_inverse(void) {
    uint8_t buf[STACK_SIZE];
    memset(buf, 0, STACK_SIZE);
    MachineState s = make_state(buf);

    uint64_t val = 0xDEADBEEFCAFEBABEULL;
    uint64_t sp_before = s.regs.sp;
    exec_push(&s, val);
    assert(s.regs.sp == sp_before - 8);

    uint64_t out;
    exec_pop(&s, &out);
    assert(out == val);
    assert(s.regs.sp == sp_before);
}

void harness_sp_alignment(void) {
    uint8_t buf[STACK_SIZE];
    memset(buf, 0, STACK_SIZE);
    MachineState s = make_state(buf);

    assert(s.regs.sp % 8 == 0);
    exec_push(&s, 42);
    assert(s.regs.sp % 8 == 0);

    uint64_t out;
    exec_pop(&s, &out);
    assert(s.regs.sp % 8 == 0);
}

void harness_multiple_push_pop(void) {
    uint8_t buf[STACK_SIZE];
    memset(buf, 0, STACK_SIZE);
    MachineState s = make_state(buf);

    exec_push(&s, 111);
    exec_push(&s, 222);
    exec_push(&s, 333);

    uint64_t a, b, c;
    exec_pop(&s, &a);
    exec_pop(&s, &b);
    exec_pop(&s, &c);

    assert(a == 333);
    assert(b == 222);
    assert(c == 111);
}

void harness_call_pushes_return(void) {
    uint8_t buf[STACK_SIZE];
    memset(buf, 0, STACK_SIZE);
    MachineState s = make_state(buf);

    uint64_t sp_before = s.regs.sp;
    exec_call(&s, 0x100, 0x50);
    assert(s.regs.sp == sp_before - 8);

    uint64_t ret;
    exec_pop(&s, &ret);
    assert(ret == 0x50);
}

void harness_addr_of_wrapping(void) {
    uint64_t a = addr_of(100, -50);
    assert(a == 50);

    uint64_t b = addr_of(0, -1);
    assert(b == UINT64_MAX);
}
