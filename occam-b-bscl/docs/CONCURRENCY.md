# docs/CONCURRENCY.md
Processes are independent contexts (own registers/stack/PC). Channels are
first-class objects with bounded FIFO queues: a sender meeting a waiting
receiver hands off directly; otherwise it enqueues, and a full queue
blocks the sender (back-pressure via staged value in R1). Receivers
block on empty channels. Sending on a closed channel is an error.
ALT tests guards left-to-right — the first ready guard wins, so ties are
impossible by construction. The scheduler is FIFO round-robin with a
fixed quantum: identical program + input + configuration yields an
identical schedule and identical output. The root process may exit while
children run; the program ends when all processes terminate, or with
exit code 3 on deadlock.
