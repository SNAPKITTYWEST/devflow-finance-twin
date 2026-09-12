/* tests/test_channels.c */
#include "channel.h"
#include "process.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

static Process *woken_pid;
static Process *wake_cb(ProcessID pid, void *ctx) {
    (void)pid; (void)ctx;
    return woken_pid; /* test stubs return the pre-set process */
}

int main(void) {
    ChannelTable *t = chtab_create(8, 2); /* cap-2 queues */
    int c = chan_create(t);
    CHECK(c >= 0);

    /* simple enqueue/dequeue without processes */
    CHECK(chan_send(t, c, 111, NULL, NULL, NULL) == CHAN_OK);
    CHECK(chan_send(t, c, 222, NULL, NULL, NULL) == CHAN_OK);
    Word v = 0;
    CHECK(chan_recv(t, c, &v, NULL, NULL, NULL) == CHAN_OK && v == 111);
    CHECK(chan_recv(t, c, &v, NULL, NULL, NULL) == CHAN_OK && v == 222);

    /* queue full -> sender blocks; staged value lives in R1 */
    Process *sender = proc_create(1, "s", 64);
    sender->regs[R1] = 333;
    CHECK(chan_send(t, c, 111, NULL, NULL, NULL) == CHAN_OK);
    CHECK(chan_send(t, c, 222, NULL, NULL, NULL) == CHAN_OK);
    CHECK(chan_send(t, c, 333, sender, wake_cb, NULL) == CHAN_BLOCKED);
    /* recv refills from blocked sender and wakes it */
    Process *r = proc_create(2, "r", 64);
    woken_pid = sender;
    CHECK(chan_recv(t, c, &v, NULL, wake_cb, NULL) == CHAN_OK && v == 111);
    CHECK(sender->status == PS_READY || sender->status == PS_RUNNING);
    CHECK(chan_recv(t, c, &v, NULL, NULL, NULL) == CHAN_OK && v == 222);
    CHECK(chan_recv(t, c, &v, NULL, NULL, NULL) == CHAN_OK && v == 333);

    /* closed channel: send fails, recv-on-empty fails */
    int c2 = chan_create(t);
    CHECK(chan_close(t, c2) == 0);
    CHECK(chan_send(t, c2, 1, NULL, NULL, NULL) == CHAN_ERROR);
    CHECK(chan_recv(t, c2, &v, NULL, NULL, NULL) == CHAN_ERROR);

    /* invalid channel */
    CHECK(chan_send(t, 77, 1, NULL, NULL, NULL) == CHAN_ERROR);
    CHECK(chan_ready(t, c) == false);

    proc_destroy(sender); proc_destroy(r);
    chtab_destroy(t);
    printf("test_channels: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
