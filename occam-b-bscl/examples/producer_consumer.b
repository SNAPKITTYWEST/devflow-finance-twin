/* examples/producer_consumer.b */
producer(c) {
    i = 0;
    while (i < 5) { send(c, i * 10); i = i + 1; }
}
consumer(c) {
    i = 0;
    while (i < 5) { out(recv(c)); i = i + 1; }
}
main() {
    c = chan();
    p = spawn producer(c);
    consumer(c);
    wait(p);
}
