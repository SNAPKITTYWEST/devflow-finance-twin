/* cuda_shim.c
   C shim that exposes a small API to Pascal and wraps CUDA runtime calls.
   Build: see build.sh
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <cuda.h>
#include <cuda_runtime.h>

/* Forward declaration for kernel wrapper implemented in vector_add.cu */
int launch_vector_add_kernel(void *a, void *b, void *c, int n);
int launch_micro_op_kernel(void *a, void *b, void *c, int n);

/* Initialize CUDA device 0 */
void cuda_init() {
    cudaError_t err = cudaSetDevice(0);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaSetDevice failed: %s\n", cudaGetErrorString(err));
        exit(1);
    }
}

/* Reset device */
void cuda_finalize() {
    cudaDeviceReset();
}

/* Allocate device memory */
void* cuda_alloc(size_t size) {
    void *dptr = NULL;
    cudaError_t err = cudaMalloc(&dptr, size);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaMalloc failed: %s\n", cudaGetErrorString(err));
        return NULL;
    }
    return dptr;
}

/* Free device memory */
void cuda_free(void *p) {
    if (p) cudaFree(p);
}

/* Host->Device copy */
int cuda_memcpy_h2d(void *dst, void *src, size_t size) {
    cudaError_t err = cudaMemcpy(dst, src, size, cudaMemcpyHostToDevice);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaMemcpy H2D failed: %s\n", cudaGetErrorString(err));
        return 1;
    }
    return 0;
}

/* Device->Host copy */
int cuda_memcpy_d2h(void *dst, void *src, size_t size) {
    cudaError_t err = cudaMemcpy(dst, src, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaMemcpy D2H failed: %s\n", cudaGetErrorString(err));
        return 1;
    }
    return 0;
}

/* Launch vector add kernel wrapper */
int cuda_launch_vector_add(void *a_dev, void *b_dev, void *c_dev, int n) {
    return launch_vector_add_kernel(a_dev, b_dev, c_dev, n);
}

/* Launch micro op kernel wrapper (PTX loaded by vector_add.cu or runtime) */
int cuda_launch_micro_op(void *a_dev, void *b_dev, void *c_dev, int n) {
    return launch_micro_op_kernel(a_dev, b_dev, c_dev, n);
}
