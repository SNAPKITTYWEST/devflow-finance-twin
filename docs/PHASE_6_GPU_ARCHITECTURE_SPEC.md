# PHASE 6 GPU ARCHITECTURE SPECIFICATION
## GPU Memory Layout, Kernels, and CAT-N-ID Storage

**Specification ID**: PH6-GPU-ARCH-001  
**Date**: 2026-09-13  
**Status**: COMPLETE

---

## TABLE OF CONTENTS

1. [GPU Memory Architecture](#gpu-memory-architecture)
2. [Data Structure Layouts](#data-structure-layouts)
3. [CAT-N-ID Storage in GPU](#cat-n-id-storage-in-gpu)
4. [Reverse Lookup Kernels](#reverse-lookup-kernels)
5. [Cross-Check Validation Kernels](#cross-check-validation-kernels)
6. [GPU-Host Synchronization](#gpu-host-synchronization)
7. [Performance Optimization](#performance-optimization)

---

## GPU MEMORY ARCHITECTURE

### Memory Hierarchy

```
GPU MEMORY LAYOUT:

Total GPU VRAM per GPU: 64 GB (for 8-GPU setup)

GLOBAL MEMORY:
  ├── gpu_node_table (per partition) [194 GB total, ~24 GB per GPU]
  ├── gpu_synapse_table (per partition) [64 GB total, ~8 GB per GPU]
  ├── gpu_event_queue (global) [3.2 GB]
  ├── reverse_lookup_index (optional, per partition) [~12 GB total, ~1.5 GB per GPU]
  └── validation_logs (per partition) [variable]

SHARED MEMORY (per block, 96 KB per thread block):
  ├── synaptic_cache (incoming synapses) [48 KB]
  └── node_state_cache (preload node data) [48 KB]

CONSTANT MEMORY (per partition, 64 KB):
  ├── partition_metadata [512 bytes]
  ├── connectome_version [16 bytes]
  ├── hash_master_key [16 bytes]
  └── validation_parameters [512 bytes]

TEXTURE MEMORY (optional, for spatial localization):
  ├── soma_coordinates_texture [variable, for cache efficiency]
```

### Multi-GPU Distribution

```
8 GPUs distributed across 1600 partitions:

GPU 0: partitions[0..199]        (200 partitions × 475K neurons = 95M neurons)
GPU 1: partitions[200..399]      (200 partitions × 475K neurons = 95M neurons)
GPU 2: partitions[400..599]      (200 partitions × 475K neurons = 95M neurons)
GPU 3: partitions[600..799]      (200 partitions × 475K neurons = 95M neurons)
GPU 4: partitions[800..999]      (200 partitions × 475K neurons = 95M neurons)
GPU 5: partitions[1000..1199]    (200 partitions × 475K neurons = 95M neurons)
GPU 6: partitions[1200..1399]    (200 partitions × 475K neurons = 95M neurons)
GPU 7: partitions[1400..1599]    (200 partitions × 475K neurons = 95M neurons)

Total: 760M neurons, 8 × 95M = 760M

Each GPU buffer:
  - node_table: 95M × 256 bytes = 24.3 GB
  - synapse_table: ~125M × 64 bytes = 8 GB
  - metadata and overhead: ~1 GB
  - Total per GPU: ~33 GB (within 64 GB limit)
```

---

## DATA STRUCTURE LAYOUTS

### GPU Node Table (CUDA Memory Layout)

See [gpu_architecture_kernels.cu](../gpu/kernels/gpu_architecture_kernels.cu) for all data structures and kernel implementations. Excerpt:

```cuda
// CUDA kernel: one neuron record per node
// Located in GPU global memory

struct alignas(256) gpu_node {
  // === IDENTITY (48 bytes) ===
  uint64_t neuron_id_hash;           // SipHash of CAT-N-ID (8 bytes)
  uint32_t neuron_id_length;         // Always 22 ("CAT-N-" + 16 hex) (4 bytes)
  char     neuron_id[24];            // "CAT-N-DEADBEEF12345678\0" (24 bytes)
                                     // Extra 2 bytes for alignment
  uint16_t region_id;                // 0..19 (2 bytes)
  uint16_t layer_id;                 // 0..15 or 255 (2 bytes)
  
  // === SPATIAL LOCATION (16 bytes) ===
  float    soma_x;                   // X coordinate (micrometers) (4 bytes)
  float    soma_y;                   // Y coordinate (4 bytes)
  float    soma_z;                   // Z coordinate (4 bytes)
  
  // === MORPHOLOGY (12 bytes) ===
  uint16_t num_dendrite_compartments; // (2 bytes)
  uint16_t num_axon_segments;         // (2 bytes)
  uint16_t num_incoming_synapses;     // (2 bytes)
  uint16_t num_outgoing_synapses;     // (2 bytes)
  float    dendritic_extent;          // Maximum dendrite distance (μm) (4 bytes)
  
  // === SYNAPSE INDICES (8 bytes) ===
  uint32_t incoming_synapse_offset;   // Index in gpu_synapse_table (4 bytes)
  uint32_t outgoing_synapse_offset;   // Index in gpu_synapse_table (4 bytes)
  
  // === CONNECTIVITY (8 bytes) ===
  uint32_t num_partitions_with_inputs;  // For boundary edge tracking (4 bytes)
  uint32_t num_partitions_with_outputs; // (4 bytes)
  
  // === NEUROTRANSMITTER PROFILE (8 bytes) ===
  uint8_t  primary_neurotransmitter;  // Encoded: 0=GLU, 1=GABA, 2=DA, ... (1 byte)
  uint8_t  num_co_transmitters;       // (1 byte)
  uint8_t  co_transmitter_id[6];      // Encoded co-transmitter types (6 bytes)
  
  // === RECEPTOR PROFILE (12 bytes) ===
  struct {
    uint8_t receptor_type;            // 0=AMPA, 1=NMDA, 2=GABA-A, ...
    uint8_t expression_level;         // 0=absent, 1=low, 2=medium, 3=high
  } receptors[6];                     // Up to 6 receptor types (12 bytes)
  
  // === MEMBRANE PROPERTIES (16 bytes) ===
  float    resting_potential_mv;      // millivolts (4 bytes)
  float    spike_threshold_mv;        // millivolts (4 bytes)
  float    membrane_time_constant_ms; // tau_m (4 bytes)
  float    input_resistance_megaohms; // (4 bytes)
  
  // === FIRING PROPERTIES (12 bytes) ===
  float    max_firing_rate_hz;        // Spikes per second (4 bytes)
  float    refractory_period_ms;      // (4 bytes)
  uint16_t neuron_type_id;            // Encoded neuron type (2 bytes)
  uint16_t functional_role_id;        // Encoded functional role (2 bytes)
  
  // === VALIDATION (16 bytes) ===
  uint32_t global_index_expected;     // For reverse-lookup validation (4 bytes)
  uint32_t partition_id_check;        // Cross-check field (4 bytes)
  uint32_t local_index_check;         // Cross-check field (4 bytes)
  uint32_t validation_checksum;       // CRC32 of entire record (4 bytes)
};

// Total size: 48 + 16 + 12 + 8 + 8 + 8 + 12 + 16 + 12 + 16 = 156 bytes
// Padded to 256 bytes for cache-line alignment

__constant__ uint32_t GLOBAL_MEMORY_NODES_PER_PARTITION = 475_000_000;
__global__ gpu_node gpu_node_table[1600][475_000_000];
```

### GPU Synapse Table (CUDA Memory Layout)

```cuda
struct alignas(64) gpu_synapse {
  // === CONNECTIVITY (8 bytes) ===
  uint32_t source_local_index;        // Source neuron in partition (4 bytes)
  uint32_t dest_local_index;          // Dest neuron in partition (4 bytes)
  
  // === CROSS-PARTITION INFO (4 bytes) ===
  uint16_t source_partition_id;       // If boundary edge (2 bytes)
  uint16_t dest_partition_id;         // If boundary edge (2 bytes)
  
  // === SYNAPTIC PROPERTIES (16 bytes) ===
  float    weight;                    // Synaptic strength (µS or nS) (4 bytes)
  float    delay_ms;                  // Conduction delay (4 bytes)
  float    last_activation_time_ms;   // For event tracking (4 bytes)
  uint32_t num_activations;           // Statistics counter (4 bytes)
  
  // === NEUROTRANSMITTER & RECEPTOR (8 bytes) ===
  uint8_t  neurotransmitter_id;       // Encoded NT type (1 byte)
  uint8_t  receptor_type_id;          // Encoded receptor (1 byte)
  uint16_t synapse_id_hash_short;     // Short hash of CAT-S-ID for validation (2 bytes)
  uint32_t reserved;                  // For future use (4 bytes)
};

// Total size: 8 + 4 + 16 + 8 = 36 bytes
// Padded to 64 bytes for cache-line alignment

__global__ gpu_synapse gpu_synapse_table[1600][125_000_000];
```

### GPU Event Queue (Priority Heap)

```cuda
struct gpu_event {
  float    delivery_time_ms;           // Event time (key for heap ordering)
  uint16_t source_partition_id;
  uint16_t dest_partition_id;
  uint32_t source_local_index;
  uint32_t dest_local_index;
  float    event_value;                // Synaptic conductance or current
  uint32_t event_id;                   // For tracing
};

__global__ gpu_event gpu_event_queue[100_000_000];  // Priority min-heap
__device__ uint32_t gpu_event_queue_head = 0;
__device__ uint32_t gpu_event_queue_tail = 0;
```

---

## CAT-N-ID STORAGE IN GPU

### CAT-N-ID Storage Strategy

```
GOAL: Store CAT-N-ID in GPU memory for reverse lookup validation

STORAGE LOCATION:
  gpu_node[i].neuron_id[] = {neuron_id_field}
  
  Full storage: "CAT-N-DEADBEEF12345678" (22 characters)
  GPU allocation: 24 bytes per node (aligned)
  
VERIFICATION:
  GPU reverse-lookup extracts gpu_node[i].neuron_id
  Cross-check against host index_tables.global_index_to_cat_n[global_index]
  If mismatch → fail-closed (abort kernel)

EXAMPLE:

GPU memory layout:

gpu_node[0]:
  .neuron_id = "CAT-N-AAAA0000BBBB1111"
  .neuron_id_hash = 0x3c9e26a7d8f4b2c1  // SipHash output
  .neuron_id_length = 22

gpu_node[1]:
  .neuron_id = "CAT-N-CCCC2222DDDD3333"
  .neuron_id_hash = 0x7f5a1b9e3d2c4a08
  .neuron_id_length = 22

... (475K more nodes in partition[0])
```

### Hash Storage for Validation

```cuda
// Hash validation protocol:

__global__ void validate_neuron_id_hash(
    uint32_t partition_id,
    uint32_t local_index,
    gpu_node* node_table,
    uint8_t* hash_master_key
) {
  gpu_node node = node_table[local_index];
  
  // Reconstruct hash from CAT-N-ID
  uint64_t expected_hash = siphash_2_4(
    (uint8_t*)node.neuron_id,
    node.neuron_id_length,
    hash_master_key
  );
  
  // Check against stored hash
  if (node.neuron_id_hash != expected_hash) {
    // FAIL-CLOSED: Corruption detected
    atomicCAS(&device_validation_error, 0, NEURON_ID_HASH_MISMATCH);
    return;
  }
}
```

---

## REVERSE LOOKUP KERNELS

### Kernel 1: GPU Location → CAT-N-ID (Basic Reverse Lookup)

```cuda
// Kernel: Extract CAT-N-ID from GPU memory

__global__ void reverse_lookup_kernel(
    uint16_t* partition_ids,          // Input: partition IDs
    uint32_t* local_indices,          // Input: local indices
    uint32_t num_queries,             // Input: number of queries
    gpu_node** node_tables,           // Input: node tables (per partition)
    char** output_cat_n_ids,          // Output: recovered CAT-N-IDs
    uint32_t* output_global_indices   // Output: reconstructed global indices
) {
  
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;
  
  // STEP 1: Extract inputs
  uint16_t partition_id = partition_ids[idx];
  uint32_t local_index = local_indices[idx];
  
  // STEP 2: Load node from GPU memory
  gpu_node* partition_node_table = node_tables[partition_id];
  gpu_node node = partition_node_table[local_index];
  
  // STEP 3: Extract CAT-N-ID
  char* extracted_cat_n_id = node.neuron_id;
  
  // STEP 4: Store output
  char* output_ptr = output_cat_n_ids + (idx * 24);
  memcpy(output_ptr, extracted_cat_n_id, 22);
  output_ptr[22] = '\0';
  
  // STEP 5: Reconstruct and store GLOBAL_INDEX
  // (This will be cross-checked on host)
  uint32_t partition_base = partition_id * 475_000_000;
  uint32_t global_index = partition_base + local_index;
  output_global_indices[idx] = global_index;
}
```

### Kernel 2: Batch Reverse Lookup with Cross-Check

```cuda
__global__ void reverse_lookup_with_crosscheck_kernel(
    uint16_t* partition_ids,
    uint32_t* local_indices,
    uint32_t num_queries,
    gpu_node** node_tables,
    uint32_t* host_global_indices,    // From host, for cross-check
    uint64_t* node_id_hashes,         // Expected hashes from host
    char* output_cat_n_ids,
    uint32_t* validation_results      // 0=success, else error code
) {
  
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;
  
  uint16_t partition_id = partition_ids[idx];
  uint32_t local_index = local_indices[idx];
  
  gpu_node node = node_tables[partition_id][local_index];
  
  // CROSS-CHECK #1: Hash match
  if (node.neuron_id_hash != node_id_hashes[idx]) {
    validation_results[idx] = ERROR_HASH_MISMATCH;
    return;
  }
  
  // CROSS-CHECK #2: Global index consistency
  uint32_t computed_global = (partition_id * 475_000_000) + local_index;
  if (computed_global != host_global_indices[idx]) {
    validation_results[idx] = ERROR_GLOBAL_INDEX_MISMATCH;
    return;
  }
  
  // SUCCESS: Copy CAT-N-ID
  char* output_ptr = output_cat_n_ids + (idx * 24);
  memcpy(output_ptr, node.neuron_id, 22);
  output_ptr[22] = '\0';
  
  validation_results[idx] = 0;  // Success
}
```

### Kernel 3: Partition-Wide Reverse Index Build

```cuda
__global__ void build_reverse_lookup_index_kernel(
    uint32_t partition_id,
    uint32_t partition_size,
    gpu_node* node_table,
    uint32_t* reverse_index,          // Maps local_index → global_index
    char* partition_cat_n_ids         // Compact storage of all CAT-N-IDs
) {
  
  uint32_t local_index = blockIdx.x * blockDim.x + threadIdx.x;
  if (local_index >= partition_size) return;
  
  gpu_node node = node_table[local_index];
  
  // Compute global index
  uint32_t partition_base = partition_id * 475_000_000;
  uint32_t global_index = partition_base + local_index;
  
  // Store in reverse index
  reverse_index[local_index] = global_index;
  
  // Copy CAT-N-ID to compact storage (optional for faster access)
  char* output_ptr = partition_cat_n_ids + (local_index * 24);
  memcpy(output_ptr, node.neuron_id, 22);
}
```

---

## CROSS-CHECK VALIDATION KERNELS

### Kernel: Three-Check Validation

```cuda
__global__ void three_check_validation_kernel(
    uint32_t num_queries,
    uint16_t* partition_ids,
    uint32_t* local_indices,
    gpu_node** node_tables,
    uint8_t* hash_master_key,
    uint32_t* host_global_indices,
    char** host_cat_n_ids,
    uint32_t* validation_flags        // Output: 0=pass, else fail code
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
  uint32_t computed_global = (partition_id * 475_000_000) + local_index;
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
  
  // ALL CHECKS PASSED
  validation_flags[idx] = 0;
}
```

---

## GPU-HOST SYNCHRONIZATION

### Data Transfer Protocol

```cuda
// PHASE 1: Initialize GPU buffers (Host → GPU)

void upload_connectome_to_gpu(
    Connectome& connectome,
    uint32_t partition_id,
    uint32_t target_gpu
) {
  cudaSetDevice(target_gpu);
  
  // 1. Allocate GPU memory
  gpu_node* d_node_table;
  gpu_synapse* d_synapse_table;
  
  size_t node_bytes = connectome.partitions[partition_id].size * sizeof(gpu_node);
  size_t synapse_bytes = connectome.partitions[partition_id].num_synapses * sizeof(gpu_synapse);
  
  cudaMalloc(&d_node_table, node_bytes);
  cudaMalloc(&d_synapse_table, synapse_bytes);
  
  // 2. Copy host data to GPU
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
  
  // 3. Register in global GPU buffer map
  gpu_buffer_map[partition_id] = {d_node_table, d_synapse_table};
  
  cudaDeviceSynchronize();
}

// PHASE 2: Reverse lookup (GPU → Host)

void reverse_lookup_batch(
    const std::vector<uint16_t>& partition_ids,
    const std::vector<uint32_t>& local_indices,
    std::vector<std::string>& output_cat_n_ids,
    IndexTables& index_tables,
    uint32_t gpu_id
) {
  cudaSetDevice(gpu_id);
  
  size_t num_queries = partition_ids.size();
  
  // 1. Allocate device memory for inputs/outputs
  uint16_t* d_partition_ids;
  uint32_t* d_local_indices;
  char* d_output_cat_n_ids;
  uint32_t* d_validation_flags;
  
  cudaMalloc(&d_partition_ids, num_queries * sizeof(uint16_t));
  cudaMalloc(&d_local_indices, num_queries * sizeof(uint32_t));
  cudaMalloc(&d_output_cat_n_ids, num_queries * 24);
  cudaMalloc(&d_validation_flags, num_queries * sizeof(uint32_t));
  
  // 2. Copy inputs to GPU
  cudaMemcpy(d_partition_ids, partition_ids.data(), 
             num_queries * sizeof(uint16_t), cudaMemcpyHostToDevice);
  cudaMemcpy(d_local_indices, local_indices.data(),
             num_queries * sizeof(uint32_t), cudaMemcpyHostToDevice);
  
  // 3. Launch reverse lookup kernel
  uint32_t block_size = 256;
  uint32_t grid_size = (num_queries + block_size - 1) / block_size;
  
  reverse_lookup_with_crosscheck_kernel<<<grid_size, block_size>>>(
    d_partition_ids,
    d_local_indices,
    num_queries,
    gpu_node_tables,
    d_validation_flags
  );
  
  // 4. Copy results back to host
  char* h_output_cat_n_ids = new char[num_queries * 24];
  uint32_t* h_validation_flags = new uint32_t[num_queries];
  
  cudaMemcpy(h_output_cat_n_ids, d_output_cat_n_ids,
             num_queries * 24, cudaMemcpyDeviceToHost);
  cudaMemcpy(h_validation_flags, d_validation_flags,
             num_queries * sizeof(uint32_t), cudaMemcpyDeviceToHost);
  
  // 5. Parse results and check validation
  for (size_t i = 0; i < num_queries; i++) {
    if (h_validation_flags[i] != 0) {
      std::cerr << "Validation failed for query " << i 
                << " with error code " << h_validation_flags[i] << std::endl;
      throw MappingFailureException(...);
    }
    
    char* cat_n_id = h_output_cat_n_ids + (i * 24);
    output_cat_n_ids[i] = std::string(cat_n_id);
  }
  
  // 6. Cleanup
  cudaFree(d_partition_ids);
  cudaFree(d_local_indices);
  cudaFree(d_output_cat_n_ids);
  cudaFree(d_validation_flags);
  delete[] h_output_cat_n_ids;
  delete[] h_validation_flags;
}
```

---

## PERFORMANCE OPTIMIZATION

### Optimization 1: Shared Memory Cache for Node Data

```cuda
__global__ void reverse_lookup_cached_kernel(
    uint16_t* partition_ids,
    uint32_t* local_indices,
    uint32_t num_queries,
    gpu_node** node_tables
) {
  
  // Allocate shared memory (96 KB per block)
  extern __shared__ char shared_nodes[];
  
  uint32_t block_idx = blockIdx.x;
  uint32_t thread_idx = threadIdx.x;
  uint32_t threads_per_block = blockDim.x;
  
  // Each query processes one node
  uint32_t global_idx = block_idx * threads_per_block + thread_idx;
  if (global_idx >= num_queries) return;
  
  uint16_t partition_id = partition_ids[global_idx];
  uint32_t local_index = local_indices[global_idx];
  
  gpu_node* node_table = node_tables[partition_id];
  
  // Load node into shared memory (coalesced access)
  gpu_node node = node_table[local_index];
  
  // Write to shared memory for intra-block synchronization
  gpu_node* shared_node = (gpu_node*)(shared_nodes + thread_idx * sizeof(gpu_node));
  *shared_node = node;
  
  __syncthreads();
  
  // Process from shared memory (faster, lower latency)
  // ...
}
```

### Optimization 2: Texture Cache for Spatial Coordinates

```cuda
// For queries involving spatial locality, use texture cache

texture<float4, 1, cudaReadModeElementType> soma_coords_texture;

__global__ void reverse_lookup_texture_kernel(
    uint32_t partition_id,
    uint32_t* local_indices,
    uint32_t num_queries
) {
  
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;
  
  uint32_t local_index = local_indices[idx];
  
  // Fetch via texture cache (specialized for spatial access patterns)
  float4 soma_coords = tex1Dfetch(soma_coords_texture, local_index);
  
  // ... use soma_coords with high cache efficiency
}
```

### Optimization 3: Coalesced Global Memory Access

```cuda
// Ensure all threads in warp access contiguous memory

__global__ void coalesced_reverse_lookup_kernel(
    uint16_t* partition_ids,
    uint32_t* local_indices,
    uint32_t num_queries,
    gpu_node** node_tables
) {
  
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;
  
  // CORRECT: All threads in warp access contiguous memory addresses
  uint16_t partition_id = partition_ids[idx];
  uint32_t local_index = local_indices[idx];
  gpu_node node = node_tables[partition_id][local_index];
  
  // NOT: Random access pattern
  // uint32_t random_idx = some_function(idx);
  // gpu_node node = node_table[random_idx];  // POOR LOCALITY
}
```

### Optimization 4: Warp-Level Primitives for Validation

```cuda
// Use warp shuffle for intra-warp communication

__global__ void warp_optimized_validation_kernel(
    gpu_node* node_table,
    uint32_t num_queries
) {
  
  uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= num_queries) return;
  
  gpu_node node = node_table[idx];
  
  // Shuffle across warp for cross-check comparison
  uint64_t hash_from_neighbor = __shfl_sync(0xffffffff, node.neuron_id_hash, (threadIdx.x + 1) % 32);
  
  // Use for validation without shared memory overhead
  if (node.neuron_id_hash != hash_from_neighbor) {
    // Handle mismatch
  }
}
```

---

## SUMMARY TABLE

| Component | Size | Count | Total |
|---|---|---|---|
| gpu_node_table | 256 bytes | 760M | 194 GB |
| gpu_synapse_table | 64 bytes | 1B | 64 GB |
| gpu_event_queue | 32 bytes | 100M | 3.2 GB |
| reverse_lookup_index | 4 bytes | 760M | 3 GB |
| CAT-N-ID storage | 24 bytes | 760M | 18.2 GB |
| Partition metadata | 8 KB | 1600 | 12.8 MB |
| **Total GPU VRAM** | | | **~280 GB** (distributed across 8 GPUs) |

---

## NEXT STEPS

1. Implement CAT-N-ID field in gpu_node struct
2. Write SipHash-2-4 CUDA kernel
3. Implement reverse-lookup kernels with cross-check
4. Benchmark GPU throughput (CAT-N-IDs per second)
5. Optimize memory layout for cache efficiency
6. Test fail-closed semantics on corrupted data
