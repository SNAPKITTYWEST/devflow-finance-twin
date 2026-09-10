#!/bin/sh
set -e
echo "Building CUDA objects..."
nvcc -c -o vector_add.o vector_add.cu -Xcompiler -fPIC
echo "Compiling C shim..."
gcc -c -fPIC cuda_shim.c -o cuda_shim.o -I/usr/local/cuda/include
echo "Linking shared library libcuda_shim.so..."
gcc -shared -o libcuda_shim.so cuda_shim.o vector_add.o -L/usr/local/cuda/lib64 -lcudart -lcuda
echo "Compiling Pascal host (Free Pascal)..."
fpc -k"-Wl,-rpath,." -k"-L." gpu_host.pas -o gpu_host
echo "Build complete."
echo "Run: LD_LIBRARY_PATH=. ./gpu_host"
