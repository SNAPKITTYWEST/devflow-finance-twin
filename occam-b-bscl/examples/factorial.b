/* examples/factorial.b */
fact(n) {
    if (n < 2) { return 1; }
    return n * fact(n - 1);
}
main() {
    out(fact(10)); /* 3628800 */
}
