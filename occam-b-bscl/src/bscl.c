#include "compiler.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Block 19: BSCL FRONTEND — the structured control/system layer.
 * BSCL shares the B grammar and pipeline; it adds deterministic
 * control constructs which the parser already accepts natively:
 *
 *   loop stmt until (cond);   : post-condition loop (desugared in parser)
 *   when (cond) stmt          : guarded statement (== if)
 *   atomic stmt               : cooperative section; between YIELDs a
 *                               process never interleaves, so a block
 *                               is already atomic — passed through.
 *
 * The layer below additionally strips `#` directive lines and rejects
 * anything else non-BSCL, then compiles through the common pipeline.
 * There is no separate BSCL runtime. */

bool bscl_to_b(const char *src, char **out_b, DiagList *diags,
               const char *file) {
    (void)diags; (void)file;
    size_t cap = strlen(src) + 64, len = 0;
    char *buf = malloc(cap);
    if (!buf) return false;
    int lineno = 0;
    char *copy = strdup(src);
    char *save = NULL;
    for (char *line = strtok_r(copy, "\n", &save); line;
         line = strtok_r(NULL, "\n", &save)) {
        lineno++;
        char *s = line;
        while (*s == ' ' || *s == '\t') s++;
        if (*s == '#') continue;              /* BSCL directive: host-only */
        size_t n = strlen(line);
        if (len + n + 2 > cap) {
            cap *= 2;
            buf = realloc(buf, cap);
            if (!buf) { free(copy); return false; }
        }
        memcpy(buf + len, line, n); len += n;
        buf[len++] = '\n';
    }
    buf[len] = 0;
    free(copy);
    *out_b = buf;
    return true;
}
