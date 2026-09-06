#include <stdint.h>
#include <stdbool.h>

#define MAX_ERRORS 0x05
#define OP_NOP     0x00
#define OP_EXEC    0x01
#define OP_RESET   0x02

typedef enum {
    PHASE_RUN    = 0x0,
    PHASE_FAULT  = 0x1,
    PHASE_RECOVER= 0x2
} worker_phase_t;

typedef struct __attribute__((__packed__)) {
    uint32_t payload : 24;
    uint32_t opcode  : 8;
} cmd_word_t;

typedef struct {
    uint32_t epoch;
    uint8_t  err_count;
    worker_phase_t phase;
    uint16_t seq_parity;
} worker_state_t;

static inline bool validate_cmd(cmd_word_t cmd) {
    return (cmd.opcode == OP_NOP || cmd.opcode == OP_EXEC || cmd.opcode == OP_RESET)
        && (cmd.payload <= 0xFFFF);
}

static inline worker_state_t transition(worker_state_t s, cmd_word_t m) {
    if (!validate_cmd(m)) {
        s.err_count = (s.err_count < MAX_ERRORS) ? s.err_count + 1 : MAX_ERRORS;
        s.phase = (s.err_count >= MAX_ERRORS) ? PHASE_FAULT : PHASE_RECOVER;
        return s;
    }

    switch (s.phase) {
        case PHASE_RUN:
            if (m.opcode == OP_RESET) {
                s.phase = PHASE_RECOVER;
            } else {
                s.epoch++;
                s.seq_parity ^= (uint16_t)(m.payload & 0x1);
            }
            break;
        case PHASE_FAULT:
            if (m.opcode == OP_RESET) {
                s.err_count = 0;
                s.phase = PHASE_RECOVER;
            }
            break;
        case PHASE_RECOVER:
            s.epoch = 0;
            s.phase = PHASE_RUN;
            break;
    }
    return s;
}

int dispatch_worker(worker_state_t *s, cmd_word_t m) {
    worker_state_t next = transition(*s, m);
    if (next.phase == PHASE_FAULT && s->phase != PHASE_FAULT) {
        *s = next;
        return -1;  // Fault containment boundary tripped
    }
    *s = next;
    return 0;
}
