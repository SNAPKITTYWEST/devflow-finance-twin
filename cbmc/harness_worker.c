#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#define MAX_ERRORS 0x05
#define OP_NOP     0x00
#define OP_EXEC    0x01
#define OP_RESET   0x02

typedef enum { PHASE_RUN=0x0, PHASE_FAULT=0x1, PHASE_RECOVER=0x2 } worker_phase_t;

typedef struct __attribute__((__packed__)) {
    uint32_t payload : 24;
    uint32_t opcode  : 8;
} cmd_word_t;

typedef struct {
    uint32_t epoch;
    uint8_t err_count;
    worker_phase_t phase;
    uint16_t seq_parity;
} worker_state_t;

static inline bool validate_cmd(cmd_word_t cmd);
static inline worker_state_t transition(worker_state_t s, cmd_word_t m);
int dispatch_worker(worker_state_t *s, cmd_word_t m);

void harness_err_count_bounded(void) {
    worker_state_t s = { .epoch = 0, .err_count = 0, .phase = PHASE_RUN, .seq_parity = 0 };
    cmd_word_t bad = { .payload = 0xFFFFFF, .opcode = 0xFF };

    for (int i = 0; i < MAX_ERRORS + 5; i++) {
        dispatch_worker(&s, bad);
    }
    assert(s.err_count <= MAX_ERRORS);
}

void harness_fault_phase(void) {
    worker_state_t s = { .epoch = 0, .err_count = 0, .phase = PHASE_RUN, .seq_parity = 0 };
    cmd_word_t bad = { .payload = 0, .opcode = 0xFF };

    for (int i = 0; i < MAX_ERRORS; i++) {
        dispatch_worker(&s, bad);
    }
    assert(s.phase == PHASE_FAULT);
}

void harness_epoch_monotonic(void) {
    worker_state_t s = { .epoch = 0, .err_count = 0, .phase = PHASE_RUN, .seq_parity = 0 };
    cmd_word_t exec = { .payload = 0x01, .opcode = OP_EXEC };

    uint32_t prev_epoch = s.epoch;
    for (int i = 0; i < 10; i++) {
        dispatch_worker(&s, exec);
        assert(s.epoch >= prev_epoch);
        prev_epoch = s.epoch;
    }
}

void harness_reset_recovers(void) {
    worker_state_t s = { .epoch = 0, .err_count = MAX_ERRORS, .phase = PHASE_FAULT, .seq_parity = 0 };
    cmd_word_t reset = { .payload = 0, .opcode = OP_RESET };

    dispatch_worker(&s, reset);
    assert(s.phase == PHASE_RECOVER || s.phase == PHASE_RUN);
}

void harness_nop_idempotent(void) {
    worker_state_t s = { .epoch = 5, .err_count = 0, .phase = PHASE_RUN, .seq_parity = 0 };
    cmd_word_t nop = { .payload = 0, .opcode = OP_NOP };

    worker_state_t before = s;
    dispatch_worker(&s, nop);
    assert(s.err_count == before.err_count);
    assert(s.phase == before.phase);
}
