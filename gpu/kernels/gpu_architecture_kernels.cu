// gpu_architecture_kernels.cu
// GPU Memory Architecture, Data Structures, and Reverse-Lookup Kernels
// Specification: PHASE_6_GPU_ARCHITECTURE_SPEC.md
// Architecture: 8-GPU, 760M neuron connectome, A100-64GB

#include <stdint.h>
#include <cuda_runtime.h>

// ============================================================
// Data Structure: GPU Node Table (256-byte aligned)
// ============================================================

struct alignas(256) gpu_node {
  // === IDENTITY (48 bytes) ===
  uint64_t neuron_id_hash;           // SipHash of CAT-N-ID (8 bytes)
  uint32_t neuron_id_length;         // Always 22 ("CAT-N-" + 16 hex) (4 bytes)
  char     neuron_id[24];            // "CAT-N-DEADBEEF12345678\0" (24 bytes)
  uint16_t region_id;                // 0..19 (2 bytes)
  uint16_t layer_id;                 // 0..15 or 255 (2 bytes)

  // === SPATIAL LOCATION (16 bytes) ===
  float    soma_x;                   // X coordinate (micrometers) (4 bytes)
  float    soma_y;                   // Y coordinate (4 bytes)
  float    soma_z;                   // Z coordinate (4 bytes)

  // === MORPHOLOGY (12 bytes) ===
  uint16_t num_dendrite_compartments;
  uint16_t num_axon_segments;
  uint16_t num_incoming_synapses;
  uint16_t num_outgoing_synapses;
  float    dendritic_extent;

  // === SYNAPSE INDICES (8 bytes) ===
  uint32_t incoming_synapse_offset;
  uint32_t outgoing_synapse_offset;

  // === CONNECTIVITY (8 bytes) ===
  uint32_t num_partitions_with_inputs;
  uint32_t num_partitions_with_outputs;

  // === NEUROTRANSMITTER PROFILE (8 bytes) ===
  uint8_t  primary_neurotransmitter;
  uint8_t  num_co_transmitters;
  uint8_t  co_transmitter_id[6];

  // === RECEPTOR PROFILE (12 bytes) ===
  struct {
    uint8_t receptor_type;
    uint8_t expression_level;
  } receptors[6];

  // === MEMBRANE PROPERTIES (16 bytes) ===
  float    resting_potential_mv;
  float    spike_threshold_mv;
  float    membrane_time_constant_ms;
  float    input_resistance_megaohms;

  // === FIRING PROPERTIES (12 bytes) ===
  float    max_firing_rate_hz;
  float    refractory_period_ms;
  uint16_t neuron_type_id;
  uint16_t functional_role_id;

  // === VALIDATION (16 bytes) ===
  uint32_t global_index_expected;
  uint32_t partition_id_check;
  uint32_t local_index_check;
  uint32_t validation_checksum;       // CRC32 of entire record

  // Total declared: ~156 bytes; padded to 256 bytes for cache-line alignment
};

__constant__ uint32_t GLOBAL_MEMORY_NODES_PER_PARTITION = 475000000;

// ============================================================
// Data Structure: GPU Synapse Table (64-byte aligned)
// ============================================================

struct alignas(64) gpu_synapse {
  // === CONNECTIVITY (8 bytes) ===
  uint32_t source_local_index;
  uint32_t dest_local_index;

  // === CROSS-PARTITION INFO (4 bytes) ===
  uint16_t source_partition_id;
  uint16_t dest_partition_id;

  // === SYNAPTIC PROPERTIES (16 bytes) ===
  float    weight;
  float    delay_ms;
  float    last_activation_time_ms;
  uint32_t num_activations;

  // === NEUROTRANSMITTER & RECEPTOR (8 bytes) ===
  uint8_t  neurotransmitter_id;
  uint8_t  receptor_type_id;
  uint16_t synapse_id_hash_short;
  uint32_t reserved;

  // Total: 36 bytes; padded to 64 bytes
};

// ============================================================
// Data Structure: GPU Event Queue Entry
// ============================================================

struct gpu_event {
  float    delivery_time_ms;
  uint16_t source_partition_id;
  uint16_t dest_partition_id;
  uint32_t source_local_index;
  uint32_t dest_local_index;
  float    event_value;
  uint32_t event_id;
};

__device__ uint32_t gpu_event_queue_head = 0;
__device__ uint32_t gpu_event_queue_tail = 0;

// ============================================================
// Kernel: Validate Neuron ID Hash
// ============================================================

__global__ void validate_neuron_id_hash(
    uint32_t partition_id,
    uint32_t local_index,
    gpu_node* node_table,
    uint8_t* hash_master_key
) {
  gpu_node node = node_table[local_index];

  uint64_t expected_hash = siphash_2_4(
    (uint8_t*)node.neuron_id,
    node.neuron_id_length,
    hash_master_key
  );

  if (node.neuron_id_hash != expected_hash) {
    atomicCAS(&device_validation_error, 0, NEURON_ID_HASH_MISMATCH);
    return;
  }
}

// ============================================================
// Kernel 1: Basic Reverse Lookup (GPU Location → CAT-N-ID)
// ============================================================

__global__ void reverse_lookup_kernel(
    uint16_t* partition_ids,
    uint32_t* local_indices,
    uint32_t num_queries,
    gpu_node** node_tables,
    char** output_cat_n_ids,
    uint32_t* output_global_indices
) {
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;

  uint16_t partition_id = partition_ids[idx];
  uint32_t local_index = local_indices[idx];

  gpu_node* partition_node_table = node_tables[partition_id];
  gpu_node node = partition_node_table[local_index];

  char* extracted_cat_n_id = node.neuron_id;
  char* output_ptr = output_cat_n_ids + (idx * 24);
  memcpy(output_ptr, extracted_cat_n_id, 22);
  output_ptr[22] = '\0';

  uint32_t partition_base = partition_id * 475000000;
  uint32_t global_index = partition_base + local_index;
  output_global_indices[idx] = global_index;
}

// ============================================================
// Kernel 2: Batch Reverse Lookup with Cross-Check
// ============================================================

__global__ void reverse_lookup_with_crosscheck_kernel(
    uint16_t* partition_ids,
    uint32_t* local_indices,
    uint32_t num_queries,
    gpu_node** node_tables,
    uint32_t* host_global_indices,
    uint64_t* node_id_hashes,
    char* output_cat_n_ids,
    uint32_t* validation_results
) {
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;

  uint16_t partition_id = partition_ids[idx];
  uint32_t local_index = local_indices[idx];

  gpu_node node = node_tables[partition_id][local_index];

  if (node.neuron_id_hash != node_id_hashes[idx]) {
    validation_results[idx] = ERROR_HASH_MISMATCH;
    return;
  }

  uint32_t computed_global = (partition_id * 475000000) + local_index;
  if (computed_global != host_global_indices[idx]) {
    validation_results[idx] = ERROR_GLOBAL_INDEX_MISMATCH;
    return;
  }

  char* output_ptr = output_cat_n_ids + (idx * 24);
  memcpy(output_ptr, node.neuron_id, 22);
  output_ptr[22] = '\0';

  validation_results[idx] = 0;  // Success
}

// ============================================================
// Kernel 3: Partition-Wide Reverse Index Build
// ============================================================

__global__ void build_reverse_lookup_index_kernel(
    uint32_t partition_id,
    uint32_t partition_size,
    gpu_node* node_table,
    uint32_t* reverse_index,
    char* partition_cat_n_ids
) {
  uint32_t local_index = blockIdx.x * blockDim.x + threadIdx.x;
  if (local_index >= partition_size) return;

  gpu_node node = node_table[local_index];

  uint32_t partition_base = partition_id * 475000000;
  uint32_t global_index = partition_base + local_index;

  reverse_index[local_index] = global_index;

  char* output_ptr = partition_cat_n_ids + (local_index * 24);
  memcpy(output_ptr, node.neuron_id, 22);
}

// ============================================================
// Kernel: Three-Check Validation
// ============================================================

__global__ void three_check_validation_kernel(
    uint32_t num_queries,
    uint16_t* partition_ids,
    uint32_t* local_indices,
    gpu_node** node_tables,
    uint8_t* hash_master_key,
    uint32_t* host_global_indices,
    char** host_cat_n_ids,
    uint32_t* validation_flags
) {
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;

  uint16_t partition_id = partition_ids[idx];
  uint32_t local_index = local_indices[idx];
  gpu_node node = node_tables[partition_id][local_index];

  // CHECK 1: Direct CAT-N-ID comparison
  if (strcmp(node.neuron_id, host_cat_n_ids[idx]) != 0) {
    validation_flags[idx] = CHECK1_CAT_N_ID_MISMATCH;
    return;
  }

  // CHECK 2: Global index reconstruction
  uint32_t computed_global = (partition_id * 475000000) + local_index;
  if (computed_global != host_global_indices[idx]) {
    validation_flags[idx] = CHECK2_GLOBAL_INDEX_MISMATCH;
    return;
  }

  // CHECK 3: Hash verification
  uint64_t expected_hash = siphash_2_4(
    (uint8_t*)node.neuron_id,
    22,
    hash_master_key
  );
  if (node.neuron_id_hash != expected_hash) {
    validation_flags[idx] = CHECK3_HASH_MISMATCH;
    return;
  }

  validation_flags[idx] = 0;  // ALL CHECKS PASSED
}

// ============================================================
// Host: Upload Connectome to GPU (Host → GPU Phase 1)
// ============================================================

void upload_connectome_to_gpu(
    Connectome& connectome,
    uint32_t partition_id,
    uint32_t target_gpu
) {
  cudaSetDevice(target_gpu);

  gpu_node* d_node_table;
  gpu_synapse* d_synapse_table;

  size_t node_bytes = connectome.partitions[partition_id].size * sizeof(gpu_node);
  size_t synapse_bytes = connectome.partitions[partition_id].num_synapses * sizeof(gpu_synapse);

  cudaMalloc(&d_node_table, node_bytes);
  cudaMalloc(&d_synapse_table, synapse_bytes);

  cudaMemcpy(
    d_node_table,
    connectome.partitions[partition_id].host_node_data,
    node_bytes,
    cudaMemcpyHostToDevice
  );

  cudaMemcpy(
    d_synapse_table,
    connectome.partitions[partition_id].host_synapse_data,
    synapse_bytes,
    cudaMemcpyHostToDevice
  );

  gpu_buffer_map[partition_id] = {d_node_table, d_synapse_table};

  cudaDeviceSynchronize();
}

// ============================================================
// Host: Batch Reverse Lookup (GPU → Host Phase 2)
// ============================================================

void reverse_lookup_batch(
    const std::vector<uint16_t>& partition_ids,
    const std::vector<uint32_t>& local_indices,
    std::vector<std::string>& output_cat_n_ids,
    IndexTables& index_tables,
    uint32_t gpu_id
) {
  cudaSetDevice(gpu_id);

  size_t num_queries = partition_ids.size();

  uint16_t* d_partition_ids;
  uint32_t* d_local_indices;
  char* d_output_cat_n_ids;
  uint32_t* d_validation_flags;

  cudaMalloc(&d_partition_ids, num_queries * sizeof(uint16_t));
  cudaMalloc(&d_local_indices, num_queries * sizeof(uint32_t));
  cudaMalloc(&d_output_cat_n_ids, num_queries * 24);
  cudaMalloc(&d_validation_flags, num_queries * sizeof(uint32_t));

  cudaMemcpy(d_partition_ids, partition_ids.data(),
             num_queries * sizeof(uint16_t), cudaMemcpyHostToDevice);
  cudaMemcpy(d_local_indices, local_indices.data(),
             num_queries * sizeof(uint32_t), cudaMemcpyHostToDevice);

  uint32_t block_size = 256;
  uint32_t grid_size = (num_queries + block_size - 1) / block_size;

  reverse_lookup_with_crosscheck_kernel<<<grid_size, block_size>>>(
    d_partition_ids,
    d_local_indices,
    num_queries,
    gpu_node_tables,
    d_validation_flags
  );

  char* h_output_cat_n_ids = new char[num_queries * 24];
  uint32_t* h_validation_flags = new uint32_t[num_queries];

  cudaMemcpy(h_output_cat_n_ids, d_output_cat_n_ids,
             num_queries * 24, cudaMemcpyDeviceToHost);
  cudaMemcpy(h_validation_flags, d_validation_flags,
             num_queries * sizeof(uint32_t), cudaMemcpyDeviceToHost);

  for (size_t i = 0; i < num_queries; i++) {
    if (h_validation_flags[i] != 0) {
      // Validation failed — throw or handle
      throw MappingFailureException();
    }
    char* cat_n_id = h_output_cat_n_ids + (i * 24);
    output_cat_n_ids[i] = std::string(cat_n_id);
  }

  cudaFree(d_partition_ids);
  cudaFree(d_local_indices);
  cudaFree(d_output_cat_n_ids);
  cudaFree(d_validation_flags);
  delete[] h_output_cat_n_ids;
  delete[] h_validation_flags;
}

// ============================================================
// Optimization 1: Shared Memory Cache for Node Data
// ============================================================

__global__ void reverse_lookup_cached_kernel(
    uint16_t* partition_ids,
    uint32_t* local_indices,
    uint32_t num_queries,
    gpu_node** node_tables
) {
  extern __shared__ char shared_nodes[];

  uint32_t block_idx = blockIdx.x;
  uint32_t thread_idx = threadIdx.x;
  uint32_t threads_per_block = blockDim.x;

  uint32_t global_idx = block_idx * threads_per_block + thread_idx;
  if (global_idx >= num_queries) return;

  uint16_t partition_id = partition_ids[global_idx];
  uint32_t local_index = local_indices[global_idx];

  gpu_node* node_table = node_tables[partition_id];
  gpu_node node = node_table[local_index];

  gpu_node* shared_node = (gpu_node*)(shared_nodes + thread_idx * sizeof(gpu_node));
  *shared_node = node;

  __syncthreads();

  // Process from shared memory (faster, lower latency)
  // ... (implementation-specific processing here)
}

// ============================================================
// Optimization 2: Texture Cache for Spatial Coordinates
// ============================================================

texture<float4, 1, cudaReadModeElementType> soma_coords_texture;

__global__ void reverse_lookup_texture_kernel(
    uint32_t partition_id,
    uint32_t* local_indices,
    uint32_t num_queries
) {
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;

  uint32_t local_index = local_indices[idx];

  float4 soma_coords = tex1Dfetch(soma_coords_texture, local_index);
  // ... use soma_coords with high cache efficiency
}

// ============================================================
// Optimization 3: Coalesced Global Memory Access
// ============================================================

__global__ void coalesced_reverse_lookup_kernel(
    uint16_t* partition_ids,
    uint32_t* local_indices,
    uint32_t num_queries,
    gpu_node** node_tables
) {
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;

  uint16_t partition_id = partition_ids[idx];
  uint32_t local_index = local_indices[idx];
  gpu_node node = node_tables[partition_id][local_index];

  // All threads in warp access contiguous memory — coalesced access pattern
  (void)node;
}

// ============================================================
// Optimization 4: Warp-Level Primitives for Validation
// ============================================================

__global__ void warp_optimized_validation_kernel(
    gpu_node* node_table,
    uint32_t num_queries
) {
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;

  gpu_node node = node_table[idx];

  // Warp shuffle for intra-warp cross-check comparison
  uint64_t hash_from_neighbor = __shfl_sync(0xffffffff, node.neuron_id_hash, (threadIdx.x + 1) % 32);

  if (node.neuron_id_hash != hash_from_neighbor) {
    // Handle mismatch — log or flag
  }
}
