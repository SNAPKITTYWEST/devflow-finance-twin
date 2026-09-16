/* examples/parallel.b */
worker(id) {
    out(id);
    out(id + 100);
}
main() {
    a = spawn worker(1);
    b = spawn worker(2);
    wait(a);
    wait(b);
}
