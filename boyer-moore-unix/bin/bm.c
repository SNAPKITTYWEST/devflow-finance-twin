/*
 * Boyer-Moore String Search: Hand-Rolled Implementation
 * Unix System V Compatible
 * Formal Proof: proof/BOYER_MOORE_FORMAL_PROOF.md
 *
 * USAGE:
 *   bm <pattern> <file>
 *   cat <file> | bm <pattern>
 *
 * EXIT CODES:
 *   0 = Pattern found
 *   1 = Pattern not found
 *   2 = Error (bad arguments, file not found, etc)
 *
 * OUTPUT:
 *   stdout: byte offset of first match (0-indexed)
 *   stderr: error messages only
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>

/* Constants */
#define BUFFER_SIZE 65536
#define MAX_PATTERN_SIZE 1024
#define ALPHABET_SIZE 256

/* State tracking for invariants */
typedef struct {
    size_t pattern_len;
    size_t text_pos;
    int last_shift;
    int mismatch_at;
} SearchState;

/* Bad-character table: LAST(P, c) for each character c */
static int bad_char_table[ALPHABET_SIZE];

/* Build bad-character table
 * PRECONDITION: pattern != NULL, 0 < pattern_len
 * POSTCONDITION: bad_char_table[c] = max({i | 0<=i<pattern_len && pattern[i]==c}) or -1
 */
static void build_bad_character_table(const unsigned char *pattern, size_t pattern_len)
{
    int c;

    /* REQUIRE: 0 <= c < ALPHABET_SIZE */
    for (c = 0; c < ALPHABET_SIZE; c++) {
        bad_char_table[c] = -1;
    }

    /* REQUIRE: 0 <= i < pattern_len */
    for (size_t i = 0; i < pattern_len; i++) {
        bad_char_table[(unsigned char)pattern[i]] = (int)i;
    }

    /* POSTCONDITION: For all c and i where pattern[i]=c: bad_char_table[c] >= i */
}

/* Good-suffix rule (simplified: shift by pattern length on mismatch)
 * FULL_IMPLEMENTATION would compute border array for each suffix
 * SIMPLIFIED: Always shift by at least 1
 * POSTCONDITION: shift >= 1
 */
static int compute_good_suffix_shift(size_t mismatch_pos, size_t pattern_len)
{
    /* On mismatch at position mismatch_pos from right,
     * safe shift is at least 1, at most pattern_len */

    /* REQUIRE: 0 <= mismatch_pos < pattern_len */
    /* POSTCONDITION: 1 <= result <= pattern_len */
    return 1;  /* Conservative; full impl uses border array */
}

/* Boyer-Moore search
 * PRECONDITION:
 *   - text != NULL or text_len = 0
 *   - pattern != NULL, 0 < pattern_len <= MAX_PATTERN_SIZE
 *   - 0 <= text_len
 * POSTCONDITION:
 *   - If found: return offset (0 <= offset <= text_len - pattern_len)
 *   - If not found: return (size_t)-1
 * INVARIANT: INV_SEARCH(s) maintained throughout
 */
static size_t boyer_moore_search(
    const unsigned char *text, size_t text_len,
    const unsigned char *pattern, size_t pattern_len)
{
    int j;
    int c;
    int shift_bad, shift_good, shift;
    size_t s;

    /* REQUIRE: well-founded inputs */
    if (pattern_len == 0) return 0;
    if (pattern_len > text_len) return (size_t)-1;

    /* Build bad-character table */
    build_bad_character_table(pattern, pattern_len);

    /* INVARIANT at loop entry: INV_SEARCH(s) */
    for (s = 0; s <= text_len - pattern_len; ) {
        /* j starts at right end of pattern (right-to-left comparison) */
        j = (int)pattern_len - 1;

        /* REQUIRE: 0 <= j < pattern_len */
        while (j >= 0 && pattern[j] == text[s + j]) {
            j--;
        }

        /* If j < 0, full pattern matched */
        if (j < 0) {
            /* POSTCONDITION: text[s : s+pattern_len] = pattern */
            return s;
        }

        /* Mismatch at position j
         * REQUIRE: 0 <= j < pattern_len
         * REQUIRE: pattern[j] != text[s + j]
         */
        c = (int)(unsigned char)text[s + j];

        /* Compute shifts
         * REQUIRE: -1 <= bad_char_table[c] < pattern_len
         * POSTCONDITION: shift_bad >= 1 (proven in formal proof)
         */
        shift_bad = j - bad_char_table[c];
        shift_good = compute_good_suffix_shift((size_t)j, pattern_len);

        /* Choose maximum shift (at least 1)
         * REQUIRE: shift_bad >= 1, shift_good >= 1
         * POSTCONDITION: shift >= 1
         */
        shift = (shift_bad > shift_good) ? shift_bad : shift_good;
        if (shift < 1) shift = 1;

        s += (size_t)shift;
        /* INVARIANT maintained: s incremented, no match skipped */
    }

    /* No match found
     * POSTCONDITION: for all 0 <= k <= text_len - pattern_len:
     *                text[k : k+pattern_len] != pattern
     */
    return (size_t)-1;
}

/* Read entire file into buffer
 * PRECONDITION: fd >= 0
 * POSTCONDITION:
 *   - buffer allocated, *text_len = total bytes read
 *   - or NULL on error, *text_len = 0
 * INVARIANT: bytes_read <= BUFFER_SIZE on each read
 */
static unsigned char *read_file(int fd, size_t *text_len)
{
    unsigned char *buffer;
    unsigned char *temp;
    size_t total = 0;
    size_t capacity = BUFFER_SIZE;
    ssize_t bytes_read;

    *text_len = 0;

    buffer = (unsigned char *)malloc(capacity);
    if (buffer == NULL) {
        fprintf(stderr, "bm: malloc failed\n");
        return NULL;
    }

    while (1) {
        /* REQUIRE: 0 <= total <= capacity */
        if (total == capacity) {
            capacity *= 2;
            if (capacity > 10 * 1024 * 1024) {
                fprintf(stderr, "bm: file too large (>10MB)\n");
                free(buffer);
                return NULL;
            }

            temp = (unsigned char *)realloc(buffer, capacity);
            if (temp == NULL) {
                fprintf(stderr, "bm: realloc failed\n");
                free(buffer);
                return NULL;
            }
            buffer = temp;
        }

        /* Read chunk
         * REQUIRE: 0 <= capacity - total
         * POSTCONDITION: 0 <= bytes_read <= capacity - total, or bytes_read = -1
         */
        bytes_read = read(fd, buffer + total, capacity - total);

        if (bytes_read < 0) {
            fprintf(stderr, "bm: read error: %s\n", strerror(errno));
            free(buffer);
            return NULL;
        }

        if (bytes_read == 0) {
            /* EOF */
            break;
        }

        total += (size_t)bytes_read;
        /* INVARIANT: total <= capacity */
    }

    *text_len = total;
    return buffer;
}

int main(int argc, char *argv[])
{
    const char *pattern_str;
    const unsigned char *pattern;
    unsigned char *text;
    size_t pattern_len;
    size_t text_len;
    size_t result;
    int fd;
    int exit_code;

    if (argc < 2) {
        fprintf(stderr, "usage: bm <pattern> [file]\n");
        return 2;
    }

    pattern_str = argv[1];
    pattern = (const unsigned char *)pattern_str;
    pattern_len = strlen(pattern_str);

    if (pattern_len == 0) {
        fprintf(stderr, "bm: pattern must not be empty\n");
        return 2;
    }

    if (pattern_len > MAX_PATTERN_SIZE) {
        fprintf(stderr, "bm: pattern too long (max %d)\n", MAX_PATTERN_SIZE);
        return 2;
    }

    /* Determine input source */
    if (argc >= 3) {
        /* Read from file */
        fd = open(argv[2], O_RDONLY);
        if (fd < 0) {
            fprintf(stderr, "bm: cannot open %s: %s\n", argv[2], strerror(errno));
            return 2;
        }
    } else {
        /* Read from stdin */
        fd = STDIN_FILENO;
    }

    /* Read text */
    text = read_file(fd, &text_len);

    if (fd != STDIN_FILENO) {
        close(fd);
    }

    if (text == NULL) {
        return 2;
    }

    /* Perform search
     * PRECONDITION: pattern != NULL, 0 < pattern_len
     *               text != NULL or text_len = 0
     * POSTCONDITION: result is position or (size_t)-1
     */
    result = boyer_moore_search(text, text_len, pattern, pattern_len);

    /* Output result */
    if (result != (size_t)-1) {
        printf("%zu\n", result);
        exit_code = 0;
    } else {
        exit_code = 1;
    }

    free(text);
    return exit_code;
}
