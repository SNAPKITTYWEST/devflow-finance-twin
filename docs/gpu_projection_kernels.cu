// gpu_projection_kernels.cu
// CUDA/HIP GPU Compute Kernels — 3D→2D Projection Pipeline
// Architecture: x86-64 + A100-40GB
// Extracted from PHASE_7_GPU_COMPUTE_KERNELS.md

#include <stdint.h>
#include <cuda_runtime.h>

// ============================================================
// Constant Memory Layout (96 KB total device limit)
// ============================================================

__constant__ double d_projection_matrix[16];      // 128 bytes
__constant__ double d_view_matrix[16];            // 128 bytes
__constant__ double d_isometric_matrix[16];       // 128 bytes
__constant__ double d_camera_eye[3];              // 24 bytes
__constant__ double d_camera_center[3];           // 24 bytes
__constant__ double d_camera_up[3];               // 24 bytes
__constant__ double d_orthogonal_scale[2];        // 16 bytes
__constant__ uint8_t d_colormap_lut[256 * 3];    // 768 bytes (256 RGB values)
__constant__ uint32_t d_circuit_neurons[1000000]; // Up to 1M circuit neurons (loaded via global mem)
__constant__ uint32_t d_layer_z_range[2];         // 8 bytes

// ============================================================
// Kernel 1: Orthogonal 2D Projection
// Input: 3D neuron positions (GPU buffer)
// Output: 2D screen positions + colors + sizes
// Determinism: 100% (no matrix ops, direct projection)
// ============================================================

__global__ void Kernel_Orthogonal2D_Projection(
  const float3* __restrict__ gpu_positions_3d,
  const uint32_t* __restrict__ gpu_firing_rates,
  const uint32_t neuron_count,
  const double scale_x,
  const double scale_y,
  float2* __restrict__ gpu_positions_2d_out,
  float4* __restrict__ gpu_colors_out,
  float* __restrict__ gpu_sizes_out,
  uint32_t* __restrict__ gpu_visibility_mask
) {
  uint32_t neuron_idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (neuron_idx >= neuron_count) return;

  float3 pos_3d = gpu_positions_3d[neuron_idx];

  double x_mm = (double)pos_3d.x / 1000.0;
  double y_mm = (double)pos_3d.y / 1000.0;

  double x_screen = x_mm / scale_x;
  double y_screen = y_mm / scale_y;

  uint32_t firing_rate_hz = gpu_firing_rates[neuron_idx];
  float rate_normalized = __fdividef((float)firing_rate_hz, 200.0f);
  rate_normalized = fminf(1.0f, rate_normalized);

  float4 color;
  if (rate_normalized < 0.5f) {
    float t = rate_normalized * 2.0f;
    color.x = 0.0f;
    color.y = t;
    color.z = 1.0f - t;
  } else {
    float t = (rate_normalized - 0.5f) * 2.0f;
    color.x = t;
    color.y = 1.0f - t;
    color.z = 0.0f;
  }
  color.w = 1.0f;

  float radius = 0.1f + sqrtf(rate_normalized) * 4.0f;
  uint32_t visible = 1;

  gpu_positions_2d_out[neuron_idx] = make_float2(x_screen, y_screen);
  gpu_colors_out[neuron_idx] = color;
  gpu_sizes_out[neuron_idx] = radius;
  gpu_visibility_mask[neuron_idx] = visible;
}

// Host invocation for Kernel_Orthogonal2D_Projection
void Launch_Orthogonal2D_Kernel(
  const GPU_Neuron_Buffer& gpu_neurons,
  const Orthogonal2D_Projection& proj,
  GPU_Projection_Output& gpu_output
) {
  uint32_t block_size = 256;
  uint32_t grid_size = (gpu_neurons.neuron_count + block_size - 1) / block_size;

  Kernel_Orthogonal2D_Projection<<<grid_size, block_size>>>(
    gpu_neurons.positions_3d,
    gpu_neurons.firing_rates,
    gpu_neurons.neuron_count,
    proj.scale_x,
    proj.scale_y,
    gpu_output.positions_2d,
    gpu_output.colors,
    gpu_output.sizes,
    gpu_output.visibility_mask
  );

  cudaDeviceSynchronize();
}

// ============================================================
// Kernel 2: Perspective Projection
// Full perspective projection with camera matrices
// ============================================================

__global__ void Kernel_Perspective_Projection(
  const float3* __restrict__ gpu_positions_3d,
  const uint32_t* __restrict__ gpu_firing_rates,
  const uint32_t neuron_count,
  const double* __restrict__ gpu_view_matrix,
  const double* __restrict__ gpu_projection_matrix,
  float2* __restrict__ gpu_positions_2d_out,
  float4* __restrict__ gpu_colors_out,
  float* __restrict__ gpu_sizes_out,
  uint32_t* __restrict__ gpu_visibility_mask
) {
  uint32_t neuron_idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (neuron_idx >= neuron_count) return;

  float3 pos_3d = gpu_positions_3d[neuron_idx];
  double x = (double)pos_3d.x;
  double y = (double)pos_3d.y;
  double z = (double)pos_3d.z;
  double w = 1.0;

  double viewed_x = gpu_view_matrix[0] * x + gpu_view_matrix[1] * y +
                    gpu_view_matrix[2] * z + gpu_view_matrix[3] * w;
  double viewed_y = gpu_view_matrix[4] * x + gpu_view_matrix[5] * y +
                    gpu_view_matrix[6] * z + gpu_view_matrix[7] * w;
  double viewed_z = gpu_view_matrix[8] * x + gpu_view_matrix[9] * y +
                    gpu_view_matrix[10] * z + gpu_view_matrix[11] * w;
  double viewed_w = gpu_view_matrix[12] * x + gpu_view_matrix[13] * y +
                    gpu_view_matrix[14] * z + gpu_view_matrix[15] * w;

  double proj_x = gpu_projection_matrix[0] * viewed_x + gpu_projection_matrix[1] * viewed_y +
                  gpu_projection_matrix[2] * viewed_z + gpu_projection_matrix[3] * viewed_w;
  double proj_y = gpu_projection_matrix[4] * viewed_x + gpu_projection_matrix[5] * viewed_y +
                  gpu_projection_matrix[6] * viewed_z + gpu_projection_matrix[7] * viewed_w;
  double proj_z = gpu_projection_matrix[8] * viewed_x + gpu_projection_matrix[9] * viewed_y +
                  gpu_projection_matrix[10] * viewed_z + gpu_projection_matrix[11] * viewed_w;
  double proj_w = gpu_projection_matrix[12] * viewed_x + gpu_projection_matrix[13] * viewed_y +
                  gpu_projection_matrix[14] * viewed_z + gpu_projection_matrix[15] * viewed_w;

  double w_inv = 1.0 / proj_w;
  double ndc_x = proj_x * w_inv;
  double ndc_y = proj_y * w_inv;

  bool visible = (ndc_x >= -1.0 && ndc_x <= 1.0 &&
                  ndc_y >= -1.0 && ndc_y <= 1.0);

  uint32_t firing_rate_hz = gpu_firing_rates[neuron_idx];
  float rate_normalized = __fdividef((float)firing_rate_hz, 200.0f);
  rate_normalized = fminf(1.0f, rate_normalized);

  float4 color;
  if (rate_normalized < 0.5f) {
    float t = rate_normalized * 2.0f;
    color.x = 0.0f;
    color.y = t;
    color.z = 1.0f - t;
  } else {
    float t = (rate_normalized - 0.5f) * 2.0f;
    color.x = t;
    color.y = 1.0f - t;
    color.z = 0.0f;
  }
  color.w = visible ? 1.0f : 0.3f;

  float radius = 0.1f + sqrtf(rate_normalized) * 4.0f;

  gpu_positions_2d_out[neuron_idx] = make_float2((float)ndc_x, (float)ndc_y);
  gpu_colors_out[neuron_idx] = color;
  gpu_sizes_out[neuron_idx] = radius;
  gpu_visibility_mask[neuron_idx] = visible ? 1 : 0;
}

// ============================================================
// Kernel 3: Circuit Filter Projection
// Filter neurons by circuit membership (binary search)
// ============================================================

__global__ void Kernel_Circuit_Filter_Projection(
  const float3* __restrict__ gpu_positions_3d,
  const uint32_t* __restrict__ gpu_neuron_indices,
  const uint32_t neuron_count,
  const uint32_t* __restrict__ gpu_circuit_neurons,
  const uint32_t circuit_neuron_count,
  const double* __restrict__ gpu_view_matrix,
  const double* __restrict__ gpu_projection_matrix,
  float2* __restrict__ gpu_positions_2d_out,
  float4* __restrict__ gpu_colors_out,
  float* __restrict__ gpu_sizes_out,
  uint32_t* __restrict__ gpu_visibility_mask,
  uint32_t* __restrict__ gpu_circuit_membership
) {
  uint32_t neuron_idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (neuron_idx >= neuron_count) return;

  uint32_t neuron_cat_n = gpu_neuron_indices[neuron_idx];

  // Binary search in circuit membership array
  bool in_circuit = false;
  // TODO: Implement binary search or use __binarySearch() intrinsic
  // For large circuits, consider pre-built hash table

  if (!in_circuit) {
    gpu_circuit_membership[neuron_idx] = 0;
    gpu_visibility_mask[neuron_idx] = 0;
    gpu_colors_out[neuron_idx] = make_float4(0.5f, 0.5f, 0.5f, 0.1f);
    return;
  }

  gpu_circuit_membership[neuron_idx] = 1;

  float3 pos_3d = gpu_positions_3d[neuron_idx];
  double x = (double)pos_3d.x;
  double y = (double)pos_3d.y;
  double z = (double)pos_3d.z;
  double w = 1.0;

  double viewed_x = gpu_view_matrix[0] * x + gpu_view_matrix[1] * y +
                    gpu_view_matrix[2] * z + gpu_view_matrix[3] * w;
  double viewed_y = gpu_view_matrix[4] * x + gpu_view_matrix[5] * y +
                    gpu_view_matrix[6] * z + gpu_view_matrix[7] * w;
  double viewed_z = gpu_view_matrix[8] * x + gpu_view_matrix[9] * y +
                    gpu_view_matrix[10] * z + gpu_view_matrix[11] * w;
  double viewed_w = gpu_view_matrix[12] * x + gpu_view_matrix[13] * y +
                    gpu_view_matrix[14] * z + gpu_view_matrix[15] * w;

  double proj_x = gpu_projection_matrix[0] * viewed_x + gpu_projection_matrix[1] * viewed_y +
                  gpu_projection_matrix[2] * viewed_z + gpu_projection_matrix[3] * viewed_w;
  double proj_y = gpu_projection_matrix[4] * viewed_x + gpu_projection_matrix[5] * viewed_y +
                  gpu_projection_matrix[6] * viewed_z + gpu_projection_matrix[7] * viewed_w;
  double proj_w = gpu_projection_matrix[12] * viewed_x + gpu_projection_matrix[13] * viewed_y +
                  gpu_projection_matrix[14] * viewed_z + gpu_projection_matrix[15] * viewed_w;

  double w_inv = 1.0 / proj_w;
  double ndc_x = proj_x * w_inv;
  double ndc_y = proj_y * w_inv;

  bool visible = (ndc_x >= -1.0 && ndc_x <= 1.0 &&
                  ndc_y >= -1.0 && ndc_y <= 1.0);

  float4 color = make_float4(1.0f, 0.0f, 0.0f, 1.0f);  // Red for circuit neurons

  gpu_positions_2d_out[neuron_idx] = make_float2((float)ndc_x, (float)ndc_y);
  gpu_colors_out[neuron_idx] = color;
  gpu_sizes_out[neuron_idx] = 1.0f;
  gpu_visibility_mask[neuron_idx] = visible ? 1 : 0;
}

// ============================================================
// Kernel 4: Synapse Projection
// Project synapse endpoints to 2D, color by activity
// ============================================================

__global__ void Kernel_Synapse_Projection(
  const uint32_t* __restrict__ gpu_synapse_source_idx,
  const uint32_t* __restrict__ gpu_synapse_dest_idx,
  const uint32_t synapse_count,
  const float2* __restrict__ gpu_neuron_positions_2d,
  const float* __restrict__ gpu_synaptic_activity,
  float2* __restrict__ gpu_edge_start,
  float2* __restrict__ gpu_edge_end,
  float4* __restrict__ gpu_edge_colors,
  uint32_t* __restrict__ gpu_edge_visibility
) {
  uint32_t synapse_idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (synapse_idx >= synapse_count) return;

  uint32_t src_idx = gpu_synapse_source_idx[synapse_idx];
  uint32_t dst_idx = gpu_synapse_dest_idx[synapse_idx];

  float2 src_pos = gpu_neuron_positions_2d[src_idx];
  float2 dst_pos = gpu_neuron_positions_2d[dst_idx];

  bool src_visible = (src_pos.x >= -1.0f && src_pos.x <= 1.0f &&
                      src_pos.y >= -1.0f && src_pos.y <= 1.0f);
  bool dst_visible = (dst_pos.x >= -1.0f && dst_pos.x <= 1.0f &&
                      dst_pos.y >= -1.0f && dst_pos.y <= 1.0f);
  bool visible = (src_visible && dst_visible);

  float activity = gpu_synaptic_activity[synapse_idx];

  float4 color;
  if (activity < 0.5f) {
    float t = activity * 2.0f;
    color.x = 0.5f * (1.0f - t);
    color.y = t;
    color.z = 0.5f * (1.0f - t);
  } else {
    float t = (activity - 0.5f) * 2.0f;
    color.x = t;
    color.y = 1.0f - t;
    color.z = 0.0f;
  }
  color.w = activity;

  gpu_edge_start[synapse_idx] = src_pos;
  gpu_edge_end[synapse_idx] = dst_pos;
  gpu_edge_colors[synapse_idx] = color;
  gpu_edge_visibility[synapse_idx] = visible ? 1 : 0;
}

// ============================================================
// Kernel 5: Activity Mapping
// Update neuron colors/sizes based on recent activity
// ============================================================

__global__ void Kernel_Activity_Mapping(
  const uint32_t* __restrict__ gpu_membrane_voltage_quantized,
  const uint32_t* __restrict__ gpu_spike_times,
  const uint32_t neuron_count,
  const uint64_t current_timestep,
  float4* __restrict__ gpu_colors_out,
  float* __restrict__ gpu_sizes_out,
  float* __restrict__ gpu_opacity_out
) {
  uint32_t neuron_idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (neuron_idx >= neuron_count) return;

  uint32_t v_quantized = gpu_membrane_voltage_quantized[neuron_idx];
  double voltage_mv = -70.0 + (double)v_quantized * (100.0 / 255.0);

  uint8_t color_idx = v_quantized;
  float3 color_rgb = colormap_lut[color_idx];  // Precomputed colormap in constant memory

  uint64_t last_spike = gpu_spike_times[neuron_idx];
  uint64_t ms_since_spike = (current_timestep - last_spike) / 10000;

  float alpha = expf(-(float)ms_since_spike / 100.0f);
  alpha = fmaxf(0.3f, alpha);

  float size = 1.0f;

  gpu_colors_out[neuron_idx] = make_float4(color_rgb.x, color_rgb.y, color_rgb.z, alpha);
  gpu_sizes_out[neuron_idx] = size;
  gpu_opacity_out[neuron_idx] = alpha;
}

// ============================================================
// Kernel 6: Determinism Hash
// Compute hash of projection output for determinism verification
// Uses Murmur3 for lightweight per-block hashing
// ============================================================

__global__ void Kernel_Determinism_Hash(
  const float2* __restrict__ gpu_positions_2d,
  const float4* __restrict__ gpu_colors,
  const float* __restrict__ gpu_sizes,
  const uint32_t neuron_count,
  uint32_t* __restrict__ gpu_block_hashes
) {
  __shared__ uint32_t shared_hash[256];

  uint32_t neuron_idx = blockIdx.x * blockDim.x + threadIdx.x;
  uint32_t local_thread_idx = threadIdx.x;

  uint32_t neuron_hash = 0;

  if (neuron_idx < neuron_count) {
    float2 pos = gpu_positions_2d[neuron_idx];
    float4 col = gpu_colors[neuron_idx];
    float size = gpu_sizes[neuron_idx];

    neuron_hash = Murmur3_Hash_32(
      reinterpret_cast<const uint8_t*>(&pos),
      sizeof(float2) + sizeof(float4) + sizeof(float)
    );
  }

  shared_hash[local_thread_idx] = neuron_hash;
  __syncthreads();

  for (int s = 128; s > 0; s >>= 1) {
    if (local_thread_idx < s) {
      shared_hash[local_thread_idx] ^= shared_hash[local_thread_idx + s];
    }
    __syncthreads();
  }

  if (local_thread_idx == 0) {
    gpu_block_hashes[blockIdx.x] = shared_hash[0];
  }
}

// ============================================================
// Host: Dispatch All Projection Kernels
// ============================================================

void Launch_Projection_Kernels(
  const GPU_Neuron_Buffer& gpu_neurons,
  const Perspective_Projection& camera,
  GPU_Projection_Output& gpu_output,
  uint32_t projection_type
) {
  uint32_t block_size = 256;
  uint32_t grid_size = (gpu_neurons.neuron_count + block_size - 1) / block_size;

  cudaEvent_t kernel_start, kernel_end;
  cudaEventCreate(&kernel_start);
  cudaEventCreate(&kernel_end);

  cudaEventRecord(kernel_start);

  switch (projection_type) {
    case PROJ_ORTHOGONAL_2D:
      Kernel_Orthogonal2D_Projection<<<grid_size, block_size>>>(
        gpu_neurons.positions_3d,
        gpu_neurons.firing_rates,
        gpu_neurons.neuron_count,
        camera.scale_x,
        camera.scale_y,
        gpu_output.positions_2d,
        gpu_output.colors,
        gpu_output.sizes,
        gpu_output.visibility_mask
      );
      break;

    case PROJ_PERSPECTIVE:
      Kernel_Perspective_Projection<<<grid_size, block_size>>>(
        gpu_neurons.positions_3d,
        gpu_neurons.firing_rates,
        gpu_neurons.neuron_count,
        gpu_camera_matrices.view_matrix,
        gpu_camera_matrices.projection_matrix,
        gpu_output.positions_2d,
        gpu_output.colors,
        gpu_output.sizes,
        gpu_output.visibility_mask
      );
      break;
  }

  cudaEventRecord(kernel_end);
  cudaEventSynchronize(kernel_end);

  float elapsed_ms;
  cudaEventElapsedTime(&elapsed_ms, kernel_start, kernel_end);

  // log_info("Projection kernel execution: {:.2f} ms", elapsed_ms);
}
