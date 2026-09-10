/* vector_add.cu
   - vector add kernel
   - micro op kernel (compiled from PTX or as CUDA)
   - wrappers exported with C linkage for the C shim
   Build with nvcc and link into shared lib (see build.sh)
*/

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdint.h>

extern "C" int launch_vector_add_kernel(void *a_dev, void *b_dev, void *c_dev, int n);
extern "C" int launch_micro_op_kernel(void *a_dev, void *b_dev, void *c_dev, int n);

/* Simple vector add kernel (float) */
__global__ void vec_add_kernel(const float *a, const float *b, float *c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) c[idx] = a[idx] + b[idx];
}

extern "C" int launch_vector_add_kernel(void *a_dev, void *b_dev, void *c_dev, int n) {
    const float *a = (const float*)a_dev;
    const float *b = (const float*)b_dev;
    float *c = (float*)c_dev;
    int block = 256;
    int grid = (n + block - 1) / block;
    vec_add_kernel<<<grid, block>>>(a, b, c, n);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "vec_add_kernel launch error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        fprintf(stderr, "vec_add sync error: %s\n", cudaGetErrorString(err));
        return 2;
    }
    return 0;
}

/* Micro-op kernel implemented in CUDA for portability (same semantics as PTX micro_kernel.ptx)
   This kernel computes: c[idx] = (a[idx] ^ b[idx]) + (a[idx] & b[idx]) for 32-bit words
*/
__global__ void micro_op_kernel(const uint32_t *a, const uint32_t *b, uint32_t *c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        uint32_t av = a[idx];
        uint32_t bv = b[idx];
        uint32_t x = av ^ bv;
        uint32_t y = av & bv;
        c[idx] = x + y;
    }
}

extern "C" int launch_micro_op_kernel(void *a_dev, void *b_dev, void *c_dev, int n) {
    const uint32_t *a = (const uint32_t*)a_dev;
    const uint32_t *b = (const uint32_t*)b_dev;
    uint32_t *c = (uint32_t*)c_dev;
    int block = 256;
    int grid = (n + block - 1) / block;
    micro_op_kernel<<<grid, block>>>(a, b, c, n);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "micro_op_kernel launch error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        fprintf(stderr, "micro_op sync error: %s\n", cudaGetErrorString(err));
        return 2;
    }
    return 0;
}
