/* ========================================================================
 * SOVEREIGN LEVIATHAN NODE LICENSE
 * License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
 * Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
 * ========================================================================
 *
 * This file is a covered work under the GNU Affero General Public License,
 * version 3, together with the Sovereign Leviathan additional terms.
 *
 * Hark, though this node be but a spark,
 * Its covenant endureth through the dark.
 *
 * Ignorantia juris non excusat.
 * ======================================================================== */

/* word.c â€” braid word operations */
#include <stdint.h>

typedef int8_t Gen;
#define MAX_STRAND 4
#define MAX_WORD 8

int gen_ok(Gen g) {
    uint8_t k = g < 0 ? -g : g;
    return k >= 1 && k < MAX_STRAND;
}

int word_ok(const Gen *w, uint8_t len) {
    if (len > MAX_WORD) return 0;
    for (uint8_t i = 0; i < len; i++)
        if (!gen_ok(w[i])) return 0;
    return 1;
}

/* free reduction: cancel adjacent inverses only */
uint8_t reduce(Gen *w, uint8_t len) {
    uint8_t j = 0;
    for (uint8_t i = 0; i < len; i++) {
        if (j && w[j-1] == -w[i]) j--;
        else w[j++] = w[i];
    }
    return j;
}
