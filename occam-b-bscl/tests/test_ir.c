/* tests/test_ir.c */
#include "ir.h"
#include <stdio.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

int main(void) {
    IRModule m;
    ir_module_init(&m);
    ir_emit(&m, IR_CONST, R0, 42, 0, NULL);
    ir_emit_label(&m, 0);
    ir_emit(&m, IR_OUT, R0, 0, 0, NULL);
    ir_emit(&m, IR_HALT, 0, 0, 0, NULL);
    CHECK(ir_count(&m) == 4);
    /* growth beyond initial capacity */
    for (int i = 0; i < 1000; i++) ir_emit(&m, IR_NOP, 0, 0, 0, NULL);
    CHECK(ir_count(&m) == 1004);
    /* labels are recorded as IR items */
    bool saw_label = false;
    for (size_t i = 0; i < m.count; i++)
        if (m.items[i].op == IR_LABEL) saw_label = true;
    CHECK(saw_label);
    /* dump does not crash */
    FILE *f = tmpfile();
    ir_dump(f, &m);
    fclose(f);
    ir_module_free(&m);
    CHECK(m.items == NULL);
    printf("test_ir: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
