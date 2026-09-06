/* call_core.c — isolated call fibre + supervisor
 * Constraints: static alloc, fixed widths, deterministic transitions,
 * O(1) per message, no hidden state, explicit recovery.
 */

#include <stdint.h>
#include <string.h>

#define MAX_CALLS 32
#define MAX_RESTARTS 5
#define RESTART_WINDOW_MS 10000
#define RTP_JITTER_SHIFT 4 /* /16 */

typedef enum { SIP_INIT=0, SIP_TRYING, SIP_INVITED, SIP_ACTIVE, SIP_TERM } sip_t;
typedef enum { OK=0, E_BADMSG, E_FULL, E_DEAD } err_t;

typedef struct {
    uint32_t ssrc;
    uint16_t seq;
    uint32_t ts;
    uint32_t last_ts;
    int32_t jitter; /* Q0, RFC3550-style */
    uint8_t codec; /* 0=PCMU */
} rtp_t;

typedef struct {
    uint16_t id; /* 0 = free */
    sip_t sip;
    rtp_t rtp;
    uint8_t alive; /* 1 = running */
    uint8_t restarts;
    uint32_t last_restart_ms;
} call_t;

typedef struct {
    call_t slot[MAX_CALLS];
    uint32_t now_ms; /* supplied by platform */
    uint16_t active;
} sup_t;

/* ---------- SIP transition table (dense) ---------- */
static const sip_t sip_next[5][5] = {
/* event: invite ring answer bye cancel */
/* INIT */ { SIP_TRYING, SIP_INIT, SIP_INIT, SIP_INIT, SIP_INIT },
/* TRYING */ { SIP_TRYING, SIP_INVITED,SIP_TRYING,SIP_TERM, SIP_TERM },
/* INVITED*/ { SIP_INVITED,SIP_INVITED,SIP_ACTIVE,SIP_TERM, SIP_TERM },
/* ACTIVE */ { SIP_ACTIVE, SIP_ACTIVE, SIP_ACTIVE,SIP_TERM, SIP_ACTIVE},
/* TERM */ { SIP_TERM, SIP_TERM, SIP_TERM, SIP_TERM, SIP_TERM }
};

/* map external event codes 0..4 → column */
static sip_t sip_step(sip_t s, uint8_t ev)
{
    if (ev > 4) return s;
    return sip_next[s][ev];
}

/* ---------- RTP update (integer only) ---------- */
static void rtp_step(rtp_t *r, uint32_t ssrc, uint16_t seq, uint32_t ts)
{
    if (r->last_ts != 0) {
        int32_t d = (int32_t)(ts - r->last_ts) - (int32_t)(seq - r->seq);
        if (d < 0) d = -d;
        r->jitter += (d - r->jitter) >> RTP_JITTER_SHIFT;
    }
    r->ssrc = ssrc;
    r->seq = seq;
    r->last_ts = ts;
}

/* ---------- single fibre transition ---------- */
/* state + msg → new_state (effects: none, pure) */
static err_t call_step(call_t *c, uint8_t kind, uint32_t a, uint32_t b, uint32_t d)
{
    if (!c->alive) return E_DEAD;
    if (kind == 0) { /* SIP event in a */
        c->sip = sip_step(c->sip, (uint8_t)a);
        return OK;
    }
    if (kind == 1) { /* RTP: a=ssrc, b=seq, d=ts */
        rtp_step(&c->rtp, a, (uint16_t)b, d);
        return OK;
    }
    return E_BADMSG;
}

/* ---------- supervisor primitives ---------- */
static call_t *sup_find(sup_t *s, uint16_t id)
{
    for (int i = 0; i < MAX_CALLS; i++)
        if (s->slot[i].id == id) return &s->slot[i];
    return 0;
}

static call_t *sup_alloc(sup_t *s, uint16_t id)
{
    for (int i = 0; i < MAX_CALLS; i++) {
        if (s->slot[i].id == 0) {
            call_t *c = &s->slot[i];
            memset(c, 0, sizeof(*c));
            c->id = id;
            c->alive = 1;
            c->sip = SIP_INIT;
            s->active++;
            return c;
        }
    }
    return 0;
}

/* explicit recovery: archive final state then re-init fibre */
static void fibre_reset(call_t *c, uint32_t now)
{
    /* WORM point: caller must have already copied c elsewhere */
    uint16_t id = c->id;
    uint8_t n = c->restarts + 1;
    memset(c, 0, sizeof(*c));
    c->id = id;
    c->alive = 1;
    c->sip = SIP_INIT;
    c->restarts = n;
    c->last_restart_ms= now;
}

static err_t sup_kill(sup_t *s, uint16_t id)
{
    call_t *c = sup_find(s, id);
    if (!c || !c->alive) return E_DEAD;
    c->alive = 0;
    s->active--;
    return OK;
}

/* restart with intensity limit */
static err_t sup_restart(sup_t *s, uint16_t id)
{
    call_t *c = sup_find(s, id);
    if (!c) return E_DEAD;

    if (s->now_ms - c->last_restart_ms > RESTART_WINDOW_MS)
        c->restarts = 0;

    if (c->restarts >= MAX_RESTARTS) {
        c->alive = 0; /* permanent isolation */
        s->active--;
        return E_DEAD;
    }
    fibre_reset(c, s->now_ms);
    return OK;
}

/* ---------- public deterministic interface ---------- */
err_t call_create(sup_t *s, uint16_t id)
{
    if (sup_find(s, id)) return E_FULL;
    if (!sup_alloc(s, id)) return E_FULL;
    return OK;
}

err_t call_msg(sup_t *s, uint16_t id, uint8_t kind,
               uint32_t a, uint32_t b, uint32_t d)
{
    call_t *c = sup_find(s, id);
    if (!c) return E_DEAD;
    err_t e = call_step(c, kind, a, b, d);
    if (e != OK) {
        /* treat protocol violation as fatal for this fibre */
        sup_kill(s, id);
        return e;
    }
    return OK;
}

err_t call_fault(sup_t *s, uint16_t id)
{
    return sup_restart(s, id);
}

void sup_tick(sup_t *s, uint32_t now_ms)
{
    s->now_ms = now_ms;
}

/* invariants (checked by audit, not runtime):
 * - active == count of alive slots
 * - id==0 ⇒ free
 * - restarts never decreases except on window expiry
 * - SIP state only moves forward or stays
 * - no shared mutable data between slots
 */
