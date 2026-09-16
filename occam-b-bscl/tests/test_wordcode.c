/* tests/test_wordcode.c */
#include "wordcode.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); fails++; } } while (0)

int main(void) {
    /* encode/decode round trip over every opcode */
    for (int op = OP_NOP; op < OP_COUNT; op++) {
        Instruction ins = wc_encode((uint8_t)op, 7, 123456, 654321);
        uint8_t o; uint32_t a, b, c;
        CHECK(wc_decode(ins, &o, &a, &b, &c));
        CHECK(o == (uint8_t)op && a == 7 && b == 123456 && c == 654321);
    }
    /* invalid opcode rejected */
    uint8_t o; uint32_t a, b, c;
    CHECK(!wc_decode(0xFF00000000000000ULL, &o, &a, &b, &c));

    /* serialize/deserialize round trip */
    WcImage img; wc_image_init(&img);
    Word code[4] = { wc_encode(OP_CONST, R0, 0, 10),
                     wc_encode(OP_CONST, R1, 0, 20),
                     wc_encode(OP_ADD, R0, R1, 0),
                     wc_encode(OP_HALT, 0, 0, 0) };
    CHECK(wc_image_set_code(&img, code, 4));
    img.entry = 0; img.entry_frame_size = 1;
    FILE *f = tmpfile();
    char err[128];
    CHECK(wc_serialize(&img, f, err, sizeof(err)));
    rewind(f);
    WcImage img2; wc_image_init(&img2);
    CHECK(wc_deserialize(&img2, f, err, sizeof(err)));
    CHECK(img2.code_size == 4 && img2.entry == 0);
    fclose(f);

    /* malformed images rejected */
    FILE *bad = tmpfile();
    Word junk[7] = { 0xDEADBEEF, 1, 8, 1, 0, 0, 0 };
    fwrite(junk, sizeof(Word), 7, bad);
    rewind(bad);
    WcImage img3; wc_image_init(&img3);
    CHECK(!wc_deserialize(&img3, bad, err, sizeof(err)));
    fclose(bad);
    /* entry out of range */
    FILE *bad2 = tmpfile();
    Word hdr2[7] = { WC_MAGIC, WC_VERSION, 8, 4, 0, 99, 1 };
    fwrite(hdr2, sizeof(Word), 7, bad2);
    fwrite(code, sizeof(Word), 4, bad2);
    rewind(bad2);
    CHECK(!wc_deserialize(&img3, bad2, err, sizeof(err)));
    fclose(bad2);

    /* disassembler produces readable assembly */
    FILE *d = tmpfile();
    wc_disassemble(d, &img);
    rewind(d);
    char line[128];
    CHECK(fgets(line, sizeof(line), d) != NULL); /* header comment */
    CHECK(fgets(line, sizeof(line), d) != NULL);
    CHECK(strstr(line, "CONST") && strstr(line, "R0") && strstr(line, "10"));
    fclose(d);
    wc_image_free(&img); wc_image_free(&img2); wc_image_free(&img3);
    printf("test_wordcode: %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
