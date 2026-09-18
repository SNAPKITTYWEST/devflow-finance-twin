// Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// SPDX-License-Identifier: FSL-1.1

#include <cuda_runtime.h>
#include <cstdint>
#include <cstdio>

extern "C" void launch_malbolge_kernel(
    uint32_t* d_memory,
    uint32_t steps,
    uint32_t* d_entropy_out,
    size_t entropy_stride
) {
    dim3 grid(68);
    dim3 block(128);
    size_t shared_mem = 48 * 1024;

    malbolge_step_kernel<<<grid, block, shared_mem>>>(
        d_memory, steps, d_entropy_out, entropy_stride
    );

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(err));
        return;
    }

    cudaDeviceSynchronize();
}

extern "C" uint32_t* allocate_device_memory(size_t bytes) {
    uint32_t* ptr;
    cudaMalloc(&ptr, bytes);
    return ptr;
}

extern "C" void free_device_memory(uint32_t* ptr) {
    cudaFree(ptr);
}

extern "C" void copy_to_device(uint32_t* d_ptr, const uint32_t* h_ptr, size_t bytes) {
    cudaMemcpy(d_ptr, h_ptr, bytes, cudaMemcpyHostToDevice);
}

extern "C" void copy_from_device(uint32_t* h_ptr, const uint32_t* d_ptr, size_t bytes) {
    cudaMemcpy(h_ptr, d_ptr, bytes, cudaMemcpyDeviceToHost);
}
