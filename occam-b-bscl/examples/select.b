/* examples/select.b */
main() {
    a = chan();
    b = chan();
    send(a, 11);
    send(b, 22);
    r = alt2(a, b); /* deterministic: left guard wins */
    out(r >> 32); /* 0 */
    out(r & 4294967295); /* 11 */
    /* timeout branch: neither channel ready */
    c = chan();
    d = chan();
    t = alt2(c, d);
    out(t >> 32); /* 2 = timeout index */
}
