#include <assert.h>
#include <stdint.h>
#include <string.h>

#define MAX_CALLS    32
#define MAX_RESTARTS 5

typedef enum { SIP_INIT=0, SIP_TRYING, SIP_INVITED, SIP_ACTIVE, SIP_TERM } sip_t;
typedef enum { OK=0, E_BADMSG, E_FULL, E_DEAD } err_t;

typedef struct {
    uint32_t ssrc; uint16_t seq; uint32_t ts; uint32_t last_ts;
    int32_t jitter;
    uint8_t codec;
} rtp_t;

typedef struct {
    uint16_t id;
    sip_t sip;
    rtp_t rtp;
    uint8_t alive;
    uint8_t restarts;
    uint32_t last_restart_ms;
} call_t;

typedef struct {
    call_t slot[MAX_CALLS];
    uint32_t now_ms;
    uint16_t active;
} sup_t;

err_t call_create(sup_t *s, uint16_t id);
err_t call_msg(sup_t *s, uint16_t id, uint8_t kind, uint32_t a, uint32_t b, uint32_t d);
err_t call_fault(sup_t *s, uint16_t id);
void  sup_tick(sup_t *s, uint32_t now_ms);

void harness_slot_bounds(void) {
    sup_t s;
    memset(&s, 0, sizeof(s));

    for (uint16_t i = 1; i <= MAX_CALLS; i++) {
        err_t rc = call_create(&s, i);
        assert(rc == OK);
    }
    assert(s.active == MAX_CALLS);

    err_t rc = call_create(&s, MAX_CALLS + 1);
    assert(rc == E_FULL);
}

void harness_active_count(void) {
    sup_t s;
    memset(&s, 0, sizeof(s));

    call_create(&s, 100);
    call_create(&s, 200);
    assert(s.active == 2);

    uint16_t counted = 0;
    for (int i = 0; i < MAX_CALLS; i++) {
        if (s.slot[i].alive) counted++;
    }
    assert(counted == s.active);
}

void harness_restarts_capped(void) {
    sup_t s;
    memset(&s, 0, sizeof(s));
    s.now_ms = 0;

    call_create(&s, 42);

    for (int i = 0; i < MAX_RESTARTS + 2; i++) {
        call_fault(&s, 42);
    }

    for (int i = 0; i < MAX_CALLS; i++) {
        if (s.slot[i].id == 42) {
            assert(s.slot[i].restarts <= MAX_RESTARTS);
            break;
        }
    }
}

void harness_sip_starts_init(void) {
    sup_t s;
    memset(&s, 0, sizeof(s));
    call_create(&s, 1);

    for (int i = 0; i < MAX_CALLS; i++) {
        if (s.slot[i].id == 1) {
            assert(s.slot[i].sip == SIP_INIT);
            break;
        }
    }
}
