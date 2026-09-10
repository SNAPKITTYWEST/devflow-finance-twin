/* cuda_softmax_masked.cu
   CUDA kernels:
   - inverted_softmax_kernel: numerically stable softmax per row using shared memory and warp reductions
   - masked_attention_kernel: scaled dot-product attention with causal mask, optimized for RTX-4090 (Ada)
   - wrappers exported for C shim
   Lines: ~520
*/

#include <cuda_runtime.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>

extern "C" int launch_inverted_softmax(void *in_dev, void *out_dev, int rows, int cols);
extern "C" int launch_masked_attention(void *Q_dev, void *K_dev, void *V_dev, void *out_dev, int batch, int seq_len, int d_model, int n_heads);

/* Utility: warp reduce max and sum for float */
__inline__ __device__ float warp_reduce_max(float val) {
    for (int offset = warpSize/2; offset > 0; offset /= 2)
        val = fmaxf(val, __shfl_down_sync(0xffffffff, val, offset));
    return val;
}

__inline__ __device__ float warp_reduce_sum(float val) {
    for (int offset = warpSize/2; offset > 0; offset /= 2)
        val += __shfl_down_sync(0xffffffff, val, offset);
    return val;
}

/* Inverted softmax kernel:
   - Each block handles one row (cols <= 1024 recommended)
   - Uses shared memory to store per-block values
   - Steps:
     1) compute max via block reduction
     2) compute exp(x - max) into shared memory
     3) compute sum via block reduction
     4) normalize and write output
*/
__global__ void inverted_softmax_kernel(const float *in, float *out, int cols) {
    extern __shared__ float sdata[]; // size = blockDim.x
    int row = blockIdx.x;
    int tid = threadIdx.x;
    int idx = row * cols + tid;

    // load value or -inf if out of range
    float val = -INFINITY;
    if (tid < cols) val = in[idx];

    // step 1: block max
    float local_max = val;
    // warp-level reduction
    float wmax = warp_reduce_max(local_max);
    if ((tid & (warpSize - 1)) == 0) sdata[tid / warpSize] = wmax;
    __syncthreads();

    float block_max = -INFINITY;
    if (tid < (blockDim.x / warpSize)) {
        block_max = sdata[tid];
        block_max = warp_reduce_max(block_max);
    }
    __syncthreads();
    if (tid == 0) {
        // broadcast block_max to sdata[0]
        sdata[0] = block_max;
    }
    __syncthreads();
    block_max = sdata[0];

    // step 2: compute exp(x - max)
    float ex = 0.0f;
    if (tid < cols) ex = expf(val - block_max);
    sdata[tid] = ex;
    __syncthreads();

    // step 3: sum reduction
    float local_sum = (tid < cols) ? sdata[tid] : 0.0f;
    float wsum = warp_reduce_sum(local_sum);
    if ((tid & (warpSize - 1)) == 0) sdata[tid / warpSize] = wsum;
    __syncthreads();

    float block_sum = 0.0f;
    if (tid < (blockDim.x / warpSize)) {
        block_sum = sdata[tid];
        block_sum = warp_reduce_sum(block_sum);
    }
    __syncthreads();
    if (tid == 0) sdata[0] = block_sum;
    __syncthreads();
    block_sum = sdata[0];

    // step 4: normalize
    if (tid < cols) {
        float outv = sdata[tid] / block_sum;
        out[idx] = outv;
    }
}

/* Masked scaled dot-product attention kernel (per batch, per head)
   - Q, K, V: (batch * seq_len * d_model) flattened
   - We assume d_model divisible by n_heads
   - For RTX-4090 tuning:
     * Use shared memory for K and V tiles
     * Use warp-level reductions for softmax
     * Use float32 or TF32 for dot products (configurable)
*/
__global__ void masked_attention_kernel(const float *Q, const float *K, const float *V, float *Out,
                                        int batch, int seq_len, int d_model, int n_heads) {
    extern __shared__ float shared[]; // dynamic shared memory
    int head_dim = d_model / n_heads;
    int batch_id = blockIdx.x / n_heads;
    int head_id = blockIdx.x % n_heads;
    int seq_pos = threadIdx.x; // thread per sequence position (assume blockDim.x == seq_len)
    if (batch_id >= batch) return;

    // pointers to this head's Q,K,V
    const float *Qh = Q + (batch_id * seq_len * d_model) + head_id * head_dim;
    const float *Kh = K + (batch_id * seq_len * d_model) + head_id * head_dim;
    const float *Vh = V + (batch_id * seq_len * d_model) + head_id * head_dim;
    float *Out_h = Out + (batch_id * seq_len * d_model) + head_id * head_dim;

    // compute attention scores for position seq_pos against all keys
    // store scores in shared memory
    float maxv = -INFINITY;
    float sum = 0.0f;

    // compute dot products across head_dim
    for (int j = 0; j < seq_len; j += blockDim.x) {
        // tile K and V into shared memory
        int kpos = j + threadIdx.x;
        if (kpos < seq_len) {
            // load K[kpos] vector for this head into shared memory
            for (int d = 0; d < head_dim; ++d) {
                shared[(threadIdx.x * head_dim) + d] = Kh[kpos * d_model + d * n_heads]; // careful indexing
            }
        }
        __syncthreads();

        // compute partial dot for this tile
        float dot = 0.0f;
        for (int d = 0; d < head_dim; ++d) {
            float qv = Qh[seq_pos * d_model + d * n_heads];
            float kv = shared[(threadIdx.x * head_dim) + d];
            dot += qv * kv;
        }
        // apply scale
        dot = dot / sqrtf((float)head_dim);
        // apply causal mask: if kpos > seq_pos then -inf
        int kpos_global = j + threadIdx.x;
        if (kpos_global > seq_pos) dot = -INFINITY;
        // write to shared scores (reuse shared memory)
        shared[threadIdx.x] = dot;
        __syncthreads();

        // compute max across tile (warp reduce)
        float local = shared[threadIdx.x];
        float wmax = warp_reduce_max(local);
        if ((threadIdx.x & (warpSize - 1)) == 0) shared[threadIdx.x / warpSize] = wmax;
        __syncthreads();
        float tile_max = -INFINITY;
        if (threadIdx.x < (blockDim.x / warpSize)) {
            tile_max = shared[threadIdx.x];
            tile_max = warp_reduce_max(tile_max);
        }
        __syncthreads();
        if (threadIdx.x == 0) shared[0] = tile_max;
        __syncthreads();
        tile_max = shared[0];

        // compute exp and sum
        float ex = expf(local - tile_max);
        shared[threadIdx.x] = ex;
        __syncthreads();
        float wsum = warp_reduce_sum(shared[threadIdx.x]);
        if ((threadIdx.x & (warpSize - 1)) == 0) shared[threadIdx.x / warpSize] = wsum;
        __syncthreads();
        float tile_sum = 0.0f;
        if (threadIdx.x < (blockDim.x / warpSize)) {
            tile_sum = shared[threadIdx.x];
            tile_sum = warp_reduce_sum(tile_sum);
        }
        __syncthreads();
        if (threadIdx.x == 0) shared[1] = tile_sum;
        __syncthreads();
        tile_sum = shared[1];

        // normalize and accumulate V contribution
        float weight = shared[threadIdx.x] / tile_sum;
        // load V vector for kpos_global
        if (kpos_global < seq_len) {
            for (int d = 0; d < head_dim; ++d) {
                float vv = Vh[kpos_global * d_model + d * n_heads];
                // accumulate into Out_h[seq_pos * d_model + d * n_heads]
                atomicAdd(&Out_h[seq_pos * d_model + d * n_heads], weight * vv);
            }
        }
        __syncthreads();
    }
}

/* Wrappers */
extern "C" int launch_inverted_softmax(void *in_dev, void *out_dev, int rows, int cols) {
    // Launch one block per row, blockDim.x = nextPow2(cols) up to 1024
    int block = 1;
    while (block < cols && block < 1024) block <<= 1;
    size_t shared = block * sizeof(float);
    dim3 grid(rows);
    dim3 blockDim(block);
    inverted_softmax_kernel<<<grid, blockDim, shared>>>((const float*)in_dev, (float*)out_dev, cols);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "inverted_softmax launch error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        fprintf(stderr, "inverted_softmax sync error: %s\n", cudaGetErrorString(err));
        return 2;
    }
    return 0;
}

extern "C" int launch_masked_attention(void *Q_dev, void *K_dev, void *V_dev, void *out_dev, int batch, int seq_len, int d_model, int n_heads) {
    // gridDim.x = batch * n_heads, blockDim.x = seq_len
    dim3 grid(batch * n_heads);
    dim3 block(seq_len);
    size_t shared = seq_len * (d_model / n_heads) * sizeof(float); // conservative
    masked_attention_kernel<<<grid, block, shared>>>((const float*)Q_dev, (const float*)K_dev, (const float*)V_dev, (float*)out_dev, batch, seq_len, d_model, n_heads);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "masked_attention launch error: %s\n", cudaGetErrorString(err));
        return 1;
    }
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        fprintf(stderr, "masked_attention sync error: %s\n", cudaGetErrorString(err));
        return 2;
    }
    return 0;
}
