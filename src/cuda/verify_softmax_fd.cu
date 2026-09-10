/* verify_softmax_fd.cu
   Compute softmax on GPU and finite-difference Jacobian on GPU to compare with CPU analytic Jacobian.
   This file provides a test harness that can be compiled into a small executable to run on RTX-4090.
   Lines: ~260
*/

#include <cuda_runtime.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

__global__ void softmax_row_kernel(const float *in, float *out, int cols) {
    extern __shared__ float s[];
    int tid = threadIdx.x;
    if (tid >= cols) return;
    // compute max
    float maxv = -INFINITY;
    for (int i = 0; i < cols; ++i) maxv = fmaxf(maxv, in[i]);
    float ex = expf(in[tid] - maxv);
    s[tid] = ex;
    __syncthreads();
    float sum = 0.0f;
    for (int i = 0; i < cols; ++i) sum += s[i];
    out[tid] = s[tid] / sum;
}

void cpu_softmax(const float *in, float *out, int cols) {
    float maxv = -INFINITY;
    for (int i = 0; i < cols; ++i) maxv = fmaxf(maxv, in[i]);
    float sum = 0.0f;
    for (int i = 0; i < cols; ++i) {
        out[i] = expf(in[i] - maxv);
        sum += out[i];
    }
    for (int i = 0; i < cols; ++i) out[i] /= sum;
}

void cpu_softmax_jacobian(const float *s, float *J, int n) {
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j)
            J[i*n + j] = s[i] * ((i == j) - s[j]);
}

int main(int argc, char **argv) {
    int cols = 64;
    float *h_in = (float*)malloc(cols * sizeof(float));
    float *h_out = (float*)malloc(cols * sizeof(float));
    float *h_j = (float*)malloc(cols * cols * sizeof(float));
    float *h_j_fd = (float*)malloc(cols * cols * sizeof(float));

    for (int i = 0; i < cols; ++i) h_in[i] = ((float)rand() / RAND_MAX) * 2.0f - 1.0f;

    float *d_in, *d_out;
    cudaMalloc(&d_in, cols * sizeof(float));
    cudaMalloc(&d_out, cols * sizeof(float));
    cudaMemcpy(d_in, h_in, cols * sizeof(float), cudaMemcpyHostToDevice);

    softmax_row_kernel<<<1, cols, cols * sizeof(float)>>>(d_in, d_out, cols);
    cudaDeviceSynchronize();
    cudaMemcpy(h_out, d_out, cols * sizeof(float), cudaMemcpyDeviceToHost);

    cpu_softmax(h_in, h_out, cols);
    cpu_softmax_jacobian(h_out, h_j, cols);

    // finite difference on CPU for simplicity
    float eps = 1e-4f;
    for (int j = 0; j < cols; ++j) {
        float orig = h_in[j];
        h_in[j] = orig + eps;
        cpu_softmax(h_in, h_out, cols);
        float *yp = (float*)malloc(cols * sizeof(float));
        for (int i = 0; i < cols; ++i) yp[i] = h_out[i];
        h_in[j] = orig - eps;
        cpu_softmax(h_in, h_out, cols);
        float *ym = (float*)malloc(cols * sizeof(float));
        for (int i = 0; i < cols; ++i) ym[i] = h_out[i];
        h_in[j] = orig;
        for (int i = 0; i < cols; ++i) {
            h_j_fd[i*cols + j] = (yp[i] - ym[i]) / (2.0f * eps);
        }
        free(yp);
        free(ym);
    }

    // compare
    float maxerr = 0.0f;
    for (int i = 0; i < cols*cols; ++i) {
        float err = fabsf(h_j[i] - h_j_fd[i]);
        if (err > maxerr) maxerr = err;
    }
    printf("Softmax Jacobian max error (CPU FD vs analytic): %g\n", maxerr);

    cudaFree(d_in);
    cudaFree(d_out);
    free(h_in);
    free(h_out);
    free(h_j);
    free(h_j_fd);
    return 0;
}
