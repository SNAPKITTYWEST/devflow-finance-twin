/* examples/channel.b */
main() {
    c = chan();
    send(c, 123);
    out(recv(c)); /* 123 */
}
