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

/* cuda_shim.c
   Small shim exposing C functions for Pascal host.
   Lines: ~140
*/
#include <stdio.h>
#include <stdlib.h>
#include <cuda.h>
#include <cuda_runtime.h>

extern int launch_vector_add_kernel(void *a, void *b, void *c, int n); /* implemented in vector_add.cu */

void cuda_init() {
    cudaError_t err = cudaSetDevice(0);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaSetDevice failed: %s\n", cudaGetErrorString(err));
        exit(1);
    }
}

void cuda_finalize() {
    cudaDeviceReset();
}

void* cuda_alloc(size_t size) {
    void *dptr = NULL;
    cudaError_t err = cudaMalloc(&dptr, size);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaMalloc failed: %s\n", cudaGetErrorString(err));
        return NULL;
    }
    return dptr;
}

void cuda_free(void *p) {
    if (p) cudaFree(p);
}

int cuda_launch_vector_add(void *a_dev, void *b_dev, void *c_dev, int n) {
    return launch_vector_add_kernel(a_dev, b_dev, c_dev, n);
}
