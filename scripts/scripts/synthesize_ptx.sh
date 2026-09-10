#!/bin/sh
# synthesize_ptx.sh
# Compile CUDA kernels and generate PTX for target architectures (RTX-4090: sm_89, H100: sm_90)
# Usage: ./synthesize_ptx.sh
set -e

echo "Compiling vector_add and softmax kernels to object files..."
nvcc -c -o vector_add.o vector_add.cu -Xcompiler -fPIC
nvcc -c -o cuda_softmax_masked.o cuda_softmax_masked.cu -Xcompiler -fPIC

echo "Generating PTX for RTX-4090 (sm_89)..."
nvcc -ptx -arch=sm_89 cuda_softmax_masked.cu -o ptx_sm_89.ptx

echo "Generating PTX for H100 (sm_90)..."
nvcc -ptx -arch=sm_90 cuda_softmax_masked.cu -o ptx_sm_90.ptx

echo "Linking shared library libcuda_shim.so..."
gcc -c -fPIC cuda_shim.c -o cuda_shim.o -I/usr/local/cuda/include
gcc -shared -o libcuda_shim.so cuda_shim.o vector_add.o cuda_softmax_masked.o -L/usr/local/cuda/lib64 -lcudart -lcuda

echo "Build complete. PTX files: ptx_sm_89.ptx, ptx_sm_90.ptx"
