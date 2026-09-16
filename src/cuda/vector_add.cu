/* vector_add.cu
   Simple vector add kernel and host wrapper.
   Lines: ~120
*/
#include <cuda_runtime.h>
#include <stdio.h>

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
        fprintf(stderr, "Kernel launch error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        fprintf(stderr, "cudaDeviceSynchronize error: %s\n", cudaGetErrorString(err));
        return 2;
    }
    return 0;
}
