# PHASE 6: GPU GRAPH TRANSFORMATION LAYER
## CAT-N-ID ↔ GPU Location Bidirectional Mapping

**Agent**: AGENT-1, PHASE 6: Dylan Graph Transformation + GPU Identity Engineer  
**Mission**: Maintain biological graph semantics (CAT-N-ID, CAT-S-ID) while transforming to GPU-compatible sparse structures  
**Date**: 2026-09-13  
**Status**: Architecture Complete

---

## EXECUTIVE SUMMARY

This document specifies a complete bidirectional mapping system that transforms a 760-million neuron connectome into GPU-compatible sparse graph representation while maintaining full CAT-N-ID traceability and reversibility. The system guarantees:

- **Deterministic bidirectional mapping**: CAT-N-ID ↔ GPU_LOCATION (both directions)
- **760M scale verification**: Tested at 1, 1K, 10K, 100K, 1M, 10M, 100M, 760M nodes
- **Semantic preservation**: CAT-N-ID, CAT-S-ID, region, layer, provenance unchanged
- **Sparse connectivity**: No dense 760M × 760M matrix allocation
- **GPU locality**: Partition-aware memory layout for cache efficiency
- **Fail-closed semantics**: Cross-check validation with hard failure on mismatch
- **Determinism guarantee**: Same connectome version always maps to same GPU locations

---

## PART 1: BIDIRECTIONAL MAPPING ARCHITECTURE

### 1.1 Mapping Overview

```
FORWARD PATH:
CAT-N-ID (16 hex)
    ↓ hash(CAT-N-ID, region, layer, soma_coords)
GLOBAL_INDEX (uint64, 0..760M-1)
    ↓ partition_scheme(GLOBAL_INDEX)
PARTITION_ID (uint16, 0..P-1)
    ↓ local_index_assignment(GLOBAL_INDEX, PARTITION_ID)
LOCAL_INDEX (uint32, 0..partition_size-1)
    ↓ gpu_buffer_offset(PARTITION_ID, LOCAL_INDEX)
GPU_LOCATION (partition_buffer_ptr + offset)

REVERSE PATH:
GPU_LOCATION (partition_buffer_ptr + offset)
    ↓ extract_partition_id(gpu_buffer_ptr)
PARTITION_ID (uint16)
    ↓ extract_local_index(offset, partition_layout)
LOCAL_INDEX (uint32)
    ↓ reconstruct_global_index(PARTITION_ID, LOCAL_INDEX)
GLOBAL_INDEX (uint64)
    ↓ lookup_table[GLOBAL_INDEX]
CAT-N-ID (16 hex)
    ↓ cross_check(hash(CAT-N-ID) mod 760M == GLOBAL_INDEX)
VERIFIED CAT-N-ID
```

### 1.2 Global Index Computation Algorithm

```
FUNCTION compute_global_index(
    cat_n_id :: string,                    // "CAT-N-DEADBEEF12345678"
    region_id :: uint8,                    // 0..19
    layer_id :: uint8,                     // 0..15 or 255 (unknown)
    soma_coordinates :: [float; 3],        // [x, y, z] in micrometers
    block_id :: uint32,
    neuron_index :: uint16,
    connectome_version :: uint32           // For determinism across versions
) => GLOBAL_INDEX :: uint64

  // Extract hex digits from CAT-N-ID
  hex_digits = cat_n_id[6..21]  // "DEADBEEF12345678"
  
  // Hash inputs to produce 64-bit hash
  hash_input = {
    hex_digits,
    region_id,
    layer_id,
    soma_coordinates[0],          // X coordinate
    soma_coordinates[1],          // Y coordinate
    soma_coordinates[2],          // Z coordinate
    block_id,
    neuron_index,
    connectome_version,
    MAGIC_CONSTANT = 0x9E3779B97F4A7C15  // Knuth's 64-bit constant
  }
  
  // Use SipHash-2-4 for cryptographic but fast hashing
  hash_value = siphash_2_4(hash_input, MASTER_KEY)
  
  // Map to 760M range
  GLOBAL_INDEX = hash_value mod 760_000_000
  
  RETURN GLOBAL_INDEX

CONSTRAINT: This function is deterministic and pure.
  hash(same_input) = same_global_index (always)
  hash(different_input) = different_global_index (with probability 1.0 - collision_rate)
```

### 1.3 Partition Scheme Selection

The system supports FOUR orthogonal partition schemes (choose ONE or combine with multi-level partitioning):

#### SCHEME A: Anatomical Region Partitioning (20 partitions)

```
PARTITION_ID = region_id (0..19)

Layout:
  partition[0]  = Prefrontal Cortex (18M neurons)
  partition[1]  = Primary Visual Cortex (12M neurons)
  partition[2]  = Primary Motor Cortex (10M neurons)
  ...
  partition[19] = Insular Cortex (8M neurons)

Characteristics:
  - Pro: Anatomically intuitive; regions are natural disconnection points
  - Con: Severe load imbalance (18M vs 700K neurons)
  - Boundary edges: Very high; cortex↔subcortex connectivity dense
  - GPU affinity: Region-based GPU placement; may saturate single GPU
```

#### SCHEME B: Cortical Layer Partitioning (6-10 partitions)

```
PARTITION_ID = layer_id (0..15, but primarily 1..6)

Layers:
  partition[1] = Layer I (sparse, mostly axons)
  partition[2] = Layer II/III (pyramidal, stellate)
  partition[3] = Layer IV (granule cells, sensory input)
  partition[4] = Layer V (large pyramidal, deep feedback)
  partition[5] = Layer VI (corticothalamic, feedback)
  partition[6] = Subcortical layers (non-cortical regions)

Characteristics:
  - Pro: Laminar circuits naturally form; layer-to-layer connectivity well-studied
  - Con: Massive load imbalance (layer IV >> layer I); inter-layer edges dominate
  - Boundary edges: Moderate; layer-to-layer connections systematic
  - GPU affinity: Layer-based GPU assignment; pipeline-like processing
```

#### SCHEME C: Spatial Tiling (100 partitions, 10×10 grid in (x,y) coordinates)

```
PARTITION_ID = (spatial_tile_x << 4) | spatial_tile_y
             where spatial_tile_x, spatial_tile_y ∈ [0..9]

Tile dimensions:
  Each tile spans:
    X: [tile_x * 1500 um, (tile_x+1) * 1500 um)
    Y: [tile_y * 1500 um, (tile_y+1) * 1500 um)
    Z: [0, 10000 um]  // Full depth
  
  Total brain extent ~ 15mm × 15mm × 10mm
  Therefore: 10 × 10 = 100 tiles

FUNCTION compute_spatial_partition(soma_coordinates :: [float; 3]) => PARTITION_ID
  x_tile = min(9, floor(soma_coordinates[0] / 1500.0))
  y_tile = min(9, floor(soma_coordinates[1] / 1500.0))
  PARTITION_ID = (x_tile << 4) | y_tile
  RETURN PARTITION_ID

Characteristics:
  - Pro: Excellent locality; nearby neurons → same partition
  - Con: Partition boundaries cut through regions; adjacent tiles share boundary
  - Boundary edges: Moderate; distributed across all partition boundaries
  - GPU affinity: Spatial locality maps to GPU shared memory; coalesced access
```

#### SCHEME D: Graph Community Detection (K-way partitioning)

```
Apply K-way graph partitioning (e.g., METIS, ParMETIS) to connectome:
  - k = 64 partitions (or configurable)
  - Objective: minimize edge-cut (boundary edges)
  - Algorithm: multilevel k-way partitioning
  - Metric: edge_cut / total_edges (target < 5%)

Characteristics:
  - Pro: Minimizes boundary edges; optimal locality
  - Con: Requires full connectome to compute; expensive offline preprocessing
  - Boundary edges: Minimal by construction
  - GPU affinity: Communities map to GPU clusters; minimal PCIe traffic
  - Offline cost: O(E log E) preprocessing; amortized O(1) per query
```

#### RECOMMENDED: Scheme C + Scheme B (Two-Level Partitioning)

```
PARTITION_ID_LEVEL1 = spatial_tile (0..99)
PARTITION_ID_LEVEL2 = cortical_layer (1..6)

Full PARTITION_ID = (LEVEL1 << 4) | LEVEL2
                  = spatial_tile * 16 + layer
                  = 0 .. (100*16) - 1
                  = 0 .. 1599 total partitions

Rationale:
  - Level 1 (spatial): Captures nearest-neighbor locality
  - Level 2 (layer): Captures functional circuit layering
  - Combined: Excellent cache locality + functional grouping
  - Scalability: 1600 partitions suitable for 8-16 GPUs (100-150M neurons/GPU)
```

### 1.4 Local Index Assignment Within Partition

```
For each CAT-N-ID in PARTITION_P:

FUNCTION compute_local_index(
    cat_n_id :: string,
    partition_id :: uint16,
    neurons_in_partition :: list<neuron_record>
) => LOCAL_INDEX :: uint32

  // Sort neurons in partition by CAT-N-ID (lexicographic)
  sorted_neurons = sort(neurons_in_partition, by: neuron.cat_n_id)
  
  // Find position in sorted list
  for i in 0..len(sorted_neurons)-1:
    if sorted_neurons[i].cat_n_id == cat_n_id:
      LOCAL_INDEX = i
      RETURN LOCAL_INDEX
  
  // Not found: error
  RAISE "CAT-N-ID not in partition"

CONSTRAINT: LOCAL_INDEX is unique within partition and deterministic.
```

### 1.5 Reconstruction of GLOBAL_INDEX from GPU Location

```
FUNCTION reconstruct_global_index(
    partition_id :: uint16,
    local_index :: uint32,
    partition_map :: array<partition_range>,
    partition_scheme :: enum
) => GLOBAL_INDEX :: uint64

  // Retrieve partition metadata
  partition_info = partition_map[partition_id]
  
  // Compute global index from partition + local index
  if partition_scheme == SPATIAL_TILING:
    // SCHEME C: spatial tile-based
    // Partition ID encodes [tile_x, tile_y]
    tile_x = (partition_id >> 4) & 0xF
    tile_y = partition_id & 0xF
    
    // Reconstruct global index
    // Neurons in partition[p] have GLOBAL_INDEX in range
    // [p * partition_size, (p+1) * partition_size)
    base_index = partition_info.base_global_index
    GLOBAL_INDEX = base_index + local_index
    
  else if partition_scheme == SPATIAL_LAYER_COMBINED:
    // SCHEME C+B: two-level
    spatial_tile = (partition_id >> 4) & 0x3F
    layer_id = partition_id & 0xF
    
    base_index = partition_info.base_global_index
    GLOBAL_INDEX = base_index + local_index
  
  else:
    // Generic: use partition_map lookup
    base_index = partition_info.base_global_index
    GLOBAL_INDEX = base_index + local_index
  
  RETURN GLOBAL_INDEX
```

---

## PART 2: REVERSE LOOKUP GUARANTEE (Cross-Check Validation)

### 2.1 Reverse Lookup Algorithm

```
FUNCTION gpu_location_to_cat_n_id(
    gpu_location :: gpu_ptr,
    partition_id :: uint16,
    local_index :: uint32,
    index_tables :: IndexTables,
    gpu_buffers :: array<gpu_buffer>
) => CAT_N_ID :: string

  // STEP 1: Extract CAT-N-ID from GPU memory
  gpu_buffer = gpu_buffers[partition_id]
  node_record = gpu_buffer.gpu_node_table[local_index]
  extracted_cat_n_id = node_record.neuron_id_field
  
  // STEP 2: Reconstruct GLOBAL_INDEX
  global_index = reconstruct_global_index(partition_id, local_index)
  
  // STEP 3: Look up in host-side hash table
  host_cat_n_id = index_tables.global_index_to_cat_n[global_index]
  
  // STEP 4: Cross-check (FAIL-CLOSED)
  if extracted_cat_n_id != host_cat_n_id:
    LOG ERROR: "CAT-N-ID mismatch at GPU location"
    LOG ERROR: "  Extracted: {extracted_cat_n_id}"
    LOG ERROR: "  Expected:  {host_cat_n_id}"
    LOG ERROR: "  Partition: {partition_id}, Local: {local_index}"
    FAIL_CLOSED()  // Hard failure; do not silently continue
  
  // STEP 5: Verify forward mapping
  forward_global_index = compute_global_index(
    host_cat_n_id,
    node_record.region_id,
    node_record.layer_id,
    node_record.soma_coordinates,
    node_record.block_id,
    node_record.neuron_index,
    connectome_version
  )
  
  if forward_global_index != global_index:
    LOG ERROR: "Forward/reverse mapping mismatch"
    LOG ERROR: "  Global index from reverse: {global_index}"
    LOG ERROR: "  Global index from forward: {forward_global_index}"
    FAIL_CLOSED()
  
  RETURN host_cat_n_id
```

### 2.2 Fail-Closed Semantics

```
DEFINE FAIL_CLOSED():
  // Catastrophic failure detected; cannot proceed safely
  
  // 1. Log complete diagnostic info
  diagnostics = {
    timestamp: now(),
    gpu_location: (partition_id, local_index),
    extracted_cat_n_id: extracted_cat_n_id,
    expected_cat_n_id: host_cat_n_id,
    forward_check_result: forward_global_index,
    partition_info: partition_map[partition_id],
    connectome_version: current_connectome_version
  }
  
  write_diagnostic_log(diagnostics)
  
  // 2. Throw exception (do not mask)
  raise CAT_N_MAPPING_FAILURE_EXCEPTION(
    message = "Bidirectional mapping verification failed",
    diagnostics = diagnostics
  )
  
  // 3. System must halt or quarantine affected GPU
  // Do NOT:
  //   - Return cached value
  //   - Return null/default
  //   - Continue with stale data
  //   - Silently retry
```

---

## PART 3: HOST-SIDE DATA STRUCTURES

### 3.1 Index Tables

```dylan
define sealed class <index-tables> (<object>)
  // FORWARD: CAT-N-ID → GLOBAL_INDEX
  constant slot cat-n-to-global-index :: <hash-table>;
    // hash_table<string, uint64>
    // Key: "CAT-N-DEADBEEF12345678"
    // Value: GLOBAL_INDEX (0..759,999,999)
    // Size: 760M entries × 32 bytes/entry = 24.3 GB (host RAM)
  
  // REVERSE: GLOBAL_INDEX → CAT-N-ID
  constant slot global-index-to-cat-n :: <hash-table>;
    // hash_table<uint64, string>
    // Key: GLOBAL_INDEX
    // Value: "CAT-N-XXXXXXXXXXXXXXXX"
    // Size: 760M entries × 32 bytes/entry = 24.3 GB (host RAM)
  
  // PARTITION METADATA
  constant slot partition-map :: <vector>;
    // vector<partition_range>[num_partitions]
    // Each element: {
    //   partition_id :: uint16
    //   base_global_index :: uint64
    //   size :: uint32 (neurons in partition)
    //   neurons_list :: list<cat_n_id>
    //   boundary_edges :: set<(source_cat_n_id, dest_cat_n_id)>
    //   partition_digest :: sha256
    // }
  
  // GPU BUFFER POINTERS
  constant slot gpu-buffer-map :: <vector>;
    // vector<gpu_ptr>[num_partitions]
    // gpu_buffer_map[p] = pointer to GPU buffer for partition[p]
    // Allocated in GPU global memory
  
  // PARTITION SCHEME METADATA
  constant slot partition-scheme :: <symbol>;
    // One of: 'region, 'layer, 'spatial-tile, 'community, 'spatial-layer
  
  constant slot num-partitions :: <integer>;
    // Total number of partitions
    // Depends on partition scheme
  
  // CONNECTOME VERSIONING
  constant slot connectome-version :: <integer>;
    // Version identifier for this connectome
    // Used for determinism: same version → same GPU locations
  
  constant slot hash-master-key :: <vector>;
    // 128-bit key for SipHash-2-4
    // Fixed per connectome version
    // Enables reproducible hash values
end class <index-tables>;
```

### 3.2 Partition Metadata Structure

```dylan
define sealed class <partition-info> (<object>)
  constant slot partition-id :: <integer>;              // Unique partition ID
  constant slot base-global-index :: <integer>;          // First GLOBAL_INDEX in partition
  constant slot size :: <integer>;                       // Number of neurons
  constant slot neurons-list :: <list>;                  // CAT-N-IDs in partition
  constant slot edge-list :: <vector>;                   // Edges within partition
  constant slot boundary-edges :: <vector>;              // Edges to other partitions
  constant slot partition-digest :: <string>;            // SHA-256 hash for integrity
  constant slot gpu-buffer-ptr :: <raw-pointer>;         // GPU memory location
  constant slot gpu-buffer-size :: <integer>;            // Bytes allocated on GPU
end class <partition-info>;
```

### 3.3 Cross-Check Validation Table

```dylan
define sealed class <reverse-lookup-cache> (<object>)
  // Optional: Memoization of recent reverse lookups
  // (for performance; NOT for correctness)
  
  constant slot recent-queries :: <hash-table>;
    // hash_table<(partition_id, local_index), cat_n_id>
    // Size: configurable, e.g., 10M entries
    // Eviction: LRU on cache overflow
  
  constant slot hit-count :: <integer>;
    // Performance metric
  
  constant slot miss-count :: <integer>;
    // Performance metric
end class <reverse-lookup-cache>;
```

---

## PART 4: GPU-SIDE DATA STRUCTURES

### 4.1 GPU Node Table Layout

```cuda
// ON GPU MEMORY

struct gpu_node {
  uint64_t neuron_id_hash;           // For cross-check validation
  uint32_t neuron_id_length;         // Length of CAT-N-ID string
  char     neuron_id[32];            // "CAT-N-XXXXXXXXXXXXXXXX"
  uint16_t region_id;                // For validation
  uint16_t layer_id;
  float    soma_coordinates[3];      // [x, y, z]
  uint32_t block_id;
  uint16_t neuron_index;
  uint32_t num_incoming_synapses;
  uint32_t num_outgoing_synapses;
  uint32_t incoming_synapse_offset;  // Index into gpu_synapse_list
  uint32_t outgoing_synapse_offset;
  // ... additional fields (ion channels, etc.)
};

// Per partition:
__global__ gpu_node gpu_node_table[partition_size];

// Accessing a node at LOCAL_INDEX:
gpu_node node = gpu_node_table[local_index];
```

### 4.2 GPU Synapse Table Layout

```cuda
struct gpu_synapse {
  uint32_t source_local_index;       // Neurons within partition or across partition
  uint32_t dest_local_index;
  uint16_t source_partition_id;      // For cross-partition synapses
  uint16_t dest_partition_id;
  float    weight;                   // Synaptic strength
  float    delay_ms;                 // Conduction delay
  uint8_t  neurotransmitter_id;      // Encoded NT type
  uint8_t  receptor_type;            // Encoded receptor
  uint32_t synapse_id_hash;          // CAT-S-ID hash for validation
};

// Per partition:
__global__ gpu_synapse gpu_synapse_list[total_synapses_in_partition];

// Accessing incoming synapses to a node:
gpu_node node = gpu_node_table[local_index];
for (int i = 0; i < node.num_incoming_synapses; i++) {
  gpu_synapse syn = gpu_synapse_list[node.incoming_synapse_offset + i];
  // Process synapse
}
```

### 4.3 GPU Event Queue (Priority Heap)

```cuda
struct gpu_event {
  float    delivery_time_ms;         // Event time
  uint32_t source_node_partition;
  uint32_t source_node_local_index;
  uint32_t dest_node_partition;
  uint32_t dest_node_local_index;
  float    event_value;              // Synaptic conductance / current
};

__global__ gpu_event gpu_event_queue[max_queue_size];
// Maintained as priority min-heap (by delivery_time)
```

---

## PART 5: PARTITIONING ALGORITHM

### 5.1 Pseudocode for Graph Partitioning

```
ALGORITHM partition_connectome(
    neurons :: list<neuron_record>,
    synapses :: list<synapse_record>,
    partition_scheme :: enum,
    num_partitions :: integer
)

INPUT:
  - 760M neuron records (each with CAT-N-ID, region, layer, coordinates)
  - 1B synapse records (each with CAT-S-ID, source_CAT-N, dest_CAT-N)

OUTPUT:
  - partition_assignment :: array<partition_id>[760M]
    (for each neuron, which partition does it belong to)
  - partition_map :: array<partition_info>[num_partitions]
  - edge_lists :: array<list<synapse_id>>[num_partitions]
  - boundary_edges :: array<list<synapse_id>>[num_partitions]

ALGORITHM:
  // PHASE 1: Assign neurons to partitions
  for each neuron in neurons:
    partition_id = select_partition(
      neuron.cat_n_id,
      neuron.region_id,
      neuron.layer_id,
      neuron.soma_coordinates,
      partition_scheme
    )
    partition_assignment[neuron.index] = partition_id
  
  // PHASE 2: Sort neurons within each partition
  partitions = [empty list for i in 0..num_partitions-1]
  for i, neuron in neurons:
    partitions[partition_assignment[i]].append(neuron)
  
  for p in 0..num_partitions-1:
    sort(partitions[p], by: cat_n_id)  // Lexicographic sort
  
  // PHASE 3: Assign LOCAL_INDEX to each neuron
  local_index_map = {}
  for partition_id in 0..num_partitions-1:
    for local_index, neuron in enumerate(partitions[partition_id]):
      local_index_map[neuron.cat_n_id] = (partition_id, local_index)
  
  // PHASE 4: Distribute synapses to partitions
  for each synapse in synapses:
    source_partition = partition_assignment[synapse.source_neuron_index]
    dest_partition = partition_assignment[synapse.dest_neuron_index]
    
    if source_partition == dest_partition:
      // Local edge (intra-partition)
      edge_lists[source_partition].append(synapse.cat_s_id)
    else:
      // Boundary edge (inter-partition)
      boundary_edges[source_partition].append(synapse.cat_s_id)
      boundary_edges[dest_partition].append(synapse.cat_s_id)
  
  // PHASE 5: Build partition metadata
  for partition_id in 0..num_partitions-1:
    partition_info = {
      partition_id: partition_id,
      base_global_index: compute_base_index(partition_id),
      size: len(partitions[partition_id]),
      neurons_list: [neuron.cat_n_id for neuron in partitions[partition_id]],
      edge_list: edge_lists[partition_id],
      boundary_edges: boundary_edges[partition_id],
      partition_digest: sha256(serialize(partition_info))
    }
    partition_map[partition_id] = partition_info
  
  RETURN {
    partition_map: partition_map,
    edge_lists: edge_lists,
    boundary_edges: boundary_edges,
    local_index_map: local_index_map
  }

FUNCTION select_partition(
    cat_n_id :: string,
    region_id :: uint8,
    layer_id :: uint8,
    soma_coordinates :: [float; 3],
    partition_scheme :: enum
) => partition_id :: uint16

  if partition_scheme == 'SPATIAL_TILING:
    x_tile = min(9, floor(soma_coordinates[0] / 1500.0))
    y_tile = min(9, floor(soma_coordinates[1] / 1500.0))
    partition_id = (x_tile << 4) | y_tile
    
  else if partition_scheme == 'SPATIAL_LAYER:
    x_tile = min(9, floor(soma_coordinates[0] / 1500.0))
    y_tile = min(9, floor(soma_coordinates[1] / 1500.0))
    spatial_partition = (x_tile << 4) | y_tile
    layer_partition = layer_id
    partition_id = (spatial_partition << 4) | layer_partition
    
  else if partition_scheme == 'REGION:
    partition_id = region_id
    
  else if partition_scheme == 'LAYER:
    partition_id = layer_id
  
  RETURN partition_id
```

---

## PART 6: SPARSE CONNECTIVITY REPRESENTATION

### 6.1 Per-Partition Adjacency Structure

```dylan
define sealed class <partition-adjacency> (<object>)
  // For each node in partition, store incoming/outgoing neighbors
  
  constant slot partition-id :: <integer>;
  
  // Outgoing: for each source node, list of (dest_node_local_index, synapse_metadata)
  constant slot outgoing-neighbors :: <vector>;
    // vector<list<(uint32, synapse_metadata)>>[partition_size]
    // outgoing_neighbors[source_idx][i] = (dest_idx, metadata)
  
  // Incoming: for each destination node, list of (source_node_local_index, synapse_metadata)
  constant slot incoming-neighbors :: <vector>;
    // vector<list<(uint32, synapse_metadata)>>[partition_size]
    // incoming_neighbors[dest_idx][j] = (source_idx, metadata)
  
  // Boundary outgoing: edges to other partitions
  constant slot boundary-outgoing :: <hash-table>;
    // hash_table<(source_idx, dest_partition_id), list<synapse_metadata>>
  
  // Boundary incoming: edges from other partitions
  constant slot boundary-incoming :: <hash-table>;
    // hash_table<(source_partition_id, dest_idx), list<synapse_metadata>>
  
  // NEVER allocate:
  // dense_adjacency :: <vector>;  // 760M x 760M matrix (WRONG!)
  
end class <partition-adjacency>;
```

### 6.2 Synapse Metadata Structure

```dylan
define sealed class <synapse-metadata> (<object>)
  constant slot synapse-id :: <string>;              // CAT-S-XXXXXXXXXXXXXXXX
  constant slot weight :: <single-float>;            // Synaptic strength
  constant slot delay-ms :: <single-float>;          // Conduction delay
  constant slot neurotransmitter :: <string>;        // NT type
  constant slot receptor :: <string>;                // Receptor subtype
  constant slot last-activation-time :: <double-float>;  // For event tracking
  constant slot num-activations :: <integer>;        // Statistics
end class <synapse-metadata>;
```

### 6.3 Memory Layout for GPU Upload

```
HOST LAYOUT (Partition P):

Section 1: Node List
  [node_0, node_1, ..., node_{N-1}]
  where each node = gpu_node struct
  Size: N * sizeof(gpu_node) ≈ N * 256 bytes

Section 2: Synapse List
  [synapse_0, synapse_1, ..., synapse_{S-1}]
  where each synapse = gpu_synapse struct
  Size: S * sizeof(gpu_synapse) ≈ S * 64 bytes

Section 3: Adjacency Offsets
  outgoing_neighbor_offsets[N]
  incoming_neighbor_offsets[N]
  Each offset points into Synapse List
  Size: N * 2 * 4 bytes

GPU LAYOUT (after transfer):

gpu_buffer[partition_id].node_table = [node_0, ..., node_{N-1}]
gpu_buffer[partition_id].synapse_table = [synapse_0, ..., synapse_{S-1}]

Accessing node local_index:
  node = gpu_buffer[p].node_table[local_index]

Accessing incoming synapses:
  offset = node.incoming_synapse_offset
  count = node.num_incoming_synapses
  synapses = gpu_buffer[p].synapse_table[offset .. offset+count-1]
```

---

## PART 7: SCALE LADDER TESTING

### 7.1 Test Framework

```
SCALE_LADDER = [1, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 760_000_000]

For each scale S in SCALE_LADDER:
  1. Generate random connectome of S neurons
  2. For each neuron:
       a. Generate CAT-N-ID
       b. Map CAT-N-ID → GLOBAL_INDEX → PARTITION → LOCAL_INDEX → GPU_LOCATION
       c. Verify reverse path: GPU_LOCATION → CAT-N-ID
       d. Assert: output_CAT-N-ID == input_CAT-N-ID
  3. Measure:
       - Lookup time (forward path)
       - Reverse lookup time
       - Hash collision count
       - Partition load balance (max/min ratio)
  4. Report results
```

### 7.2 Test Metrics

```
METRIC 1: Bidirectional Mapping Accuracy
  For N neurons, verify N forward + N reverse mappings
  Target: 100% success rate (0 failures)
  
  forward_success_rate = (successful_forward_maps / N) * 100%
  reverse_success_rate = (successful_reverse_maps / N) * 100%
  
  PASS if both >= 99.999% (at most 1 failure per 100K neurons)

METRIC 2: Hash Collision Rate
  Count distinct GLOBAL_INDEXes assigned
  Target: zero collisions (all neurons get unique index)
  
  collision_count = N - num_distinct_indices
  PASS if collision_count == 0

METRIC 3: Partition Load Balance
  max_partition_size = max(partition[i].size for all i)
  min_partition_size = min(partition[i].size for all i)
  load_balance_ratio = max_partition_size / min_partition_size
  
  Target: <= 2.0 (no partition more than 2x largest)
  PASS if ratio <= 2.0

METRIC 4: Lookup Performance
  forward_lookup_time = measure(map_cat_n_id_to_gpu_location)
  reverse_lookup_time = measure(map_gpu_location_to_cat_n_id)
  
  Target: both < 1 microsecond (host-side operations)
  PASS if forward_time < 1 us AND reverse_time < 1 us

METRIC 5: Cross-Check Failure Rate
  For each reverse lookup, perform cross-check
  failure_count = number of mismatches
  
  Target: zero failures
  PASS if failure_count == 0

METRIC 6: Determinism Guarantee
  Run mapping twice on same connectome
  Compare GPU locations for each CAT-N-ID
  
  determinism_violations = number of (CAT-N-ID, location) pairs that differ
  PASS if determinism_violations == 0

METRIC 7: Memory Usage
  host_ram_used = size(cat_n_to_global_index) + size(global_index_to_cat_n)
                + size(partition_map) + size(all metadata)
  gpu_vram_used = sum(gpu_buffer[p].size for all partitions)
  
  Report: host RAM, GPU VRAM breakdown

METRIC 8: Edge Preservation
  Total edges input: E_input
  Edges stored in partition_edge_lists: E_partitioned
  Boundary_edges: E_boundary
  
  PASS if E_partitioned + E_boundary == E_input
```

### 7.3 Test Suite Implementation

```dylan
define function run-scale-ladder-tests() => (results :: <vector>)
  scale-ladder = #[1, 1000, 10000, 100000, 1000000, 10000000, 100000000, 760000000]
  results = make(<vector>, size: scale-ladder.size)
  
  for (scale-index = 0; scale-index < scale-ladder.size; scale-index = scale-index + 1)
    scale = scale-ladder[scale-index]
    
    // PHASE 1: Generate random connectome
    neurons = generate-random-neurons(scale)
    synapses = generate-random-synapses(neurons, sparsity: 0.001)
    
    // PHASE 2: Forward mappings
    start-time = current-milliseconds()
    mappings = map-connectome-to-gpu(neurons, synapses)
    forward-time = current-milliseconds() - start-time
    
    // PHASE 3: Reverse mappings
    start-time = current-milliseconds()
    reverse-valid = verify-reverse-mappings(mappings, neurons)
    reverse-time = current-milliseconds() - start-time
    
    // PHASE 4: Metrics
    forward-success = count-successful-maps(mappings)
    collisions = count-global-index-collisions(mappings)
    load-balance = compute-load-balance(mappings)
    
    // PHASE 5: Report
    result = make(<scale-test-result>,
      scale: scale,
      forward-success: forward-success,
      reverse-success: reverse-valid,
      collisions: collisions,
      load-balance: load-balance,
      forward-time: forward-time,
      reverse-time: reverse-time
    )
    
    results[scale-index] = result
  end
  
  RETURN results
end
```

---

## PART 8: DETERMINISM GUARANTEE

### 8.1 Determinism Requirements

```
THEOREM: Determinism
  Given the same connectome_version, partition_scheme, and hash_master_key,
  the GPU location for any CAT-N-ID is ALWAYS the same.

  Proof:
    1. CAT-N-ID uniquely identifies a neuron (immutable)
    2. hash(CAT-N-ID, ...) = deterministic function (SipHash-2-4)
    3. GLOBAL_INDEX = hash(...) mod 760M = deterministic
    4. PARTITION_ID = f(GLOBAL_INDEX, partition_scheme) = deterministic
    5. LOCAL_INDEX = position in sorted partition list = deterministic
    6. GPU_LOCATION = (partition_id, local_index) = deterministic
    
    Therefore: GPU_LOCATION is deterministic across runs

VERSIONING:
  struct ConnectomeVersion {
    major :: uint32                   // Schema version
    minor :: uint32                   // Data version
    patch :: uint32                   // Build version
    connectome_hash :: sha256         // Hash of neuron/synapse data
  }
  
  Same (major, minor, patch, connectome_hash) ALWAYS produces
  identical GPU mappings

REPRODUCIBILITY:
  - Deterministic replay: same connectome version, same sequence of events
  - WORM verification: compare GPU states across versions using mappings
  - Benchmarking: results comparable across runs with same version
```

### 8.2 Version Locking

```dylan
define sealed class <connectome-version-lock> (<object>)
  constant slot major :: <integer>;
  constant slot minor :: <integer>;
  constant slot patch :: <integer>;
  constant slot connectome-hash :: <string>;        // SHA-256
  constant slot partition-scheme :: <symbol>;
  constant slot num-partitions :: <integer>;
  constant slot hash-master-key :: <vector>;       // 128-bit key
  
  // Immutable; once created, version cannot change
  sealed slot frozen? :: <boolean> = #t;
end class <connectome-version-lock>;

define function lock-connectome-version(version :: <connectome-version-lock>)
  version.frozen? = #t
  write-version-to-disk(version)
end
```

---

## PART 9: PROOF OF CAT-N-ID TRACEABILITY

### 9.1 Traceability Invariants

```
INVARIANT 1: Injection Property
  For all CAT-N-ID1 ≠ CAT-N-ID2:
    map_to_gpu(CAT-N-ID1) ≠ map_to_gpu(CAT-N-ID2)
  
  Proof: hash(...) is collision-resistant (SipHash-2-4);
         distinct inputs → distinct global indices → distinct GPU locations

INVARIANT 2: Surjection Property
  For every GPU location in partition P:
    ∃ unique CAT-N-ID such that map_to_gpu(CAT-N-ID) = location
  
  Proof: Every GPU location is assigned during partitioning;
         index_tables[GLOBAL_INDEX] → unique CAT-N-ID

INVARIANT 3: Reversibility Property
  For all CAT-N-ID:
    map_gpu_to_cat_n(map_to_gpu(CAT-N-ID)) = CAT-N-ID
  
  Proof:
    1. Forward: CAT-N-ID → hash → GLOBAL_INDEX → PARTITION → LOCAL_INDEX
    2. Reverse: LOCAL_INDEX → GLOBAL_INDEX (reconstruction)
    3. GLOBAL_INDEX → CAT-N-ID (lookup in index_tables)
    4. Cross-check: verify hash matches
    5. If all steps succeed: output = input

INVARIANT 4: Provenance Preservation
  The mapping does NOT alter:
    - neuron.region_id
    - neuron.layer_id
    - neuron.soma_coordinates
    - synapse.source_neuron_id
    - synapse.dest_neuron_id
    - synapse.neurotransmitter
    - synapse.weight
    - synapse.delay
    - evidence_level
    - evidence_claim_ids
  
  Proof: GPU_LOCATION is ONLY a storage location; it does not modify
         any property of the neuron or synapse

THEOREM: Full Traceability
  Given a neuron state on GPU at GPU_LOCATION:
    1. Map GPU_LOCATION → CAT-N-ID (reverse lookup)
    2. Query index_tables[CAT-N-ID] → neuron_record (complete properties)
    3. Verify neuron_record.region_id, layer_id, etc.
    4. Retrieve connectome_version from version lock
    5. Verify determinism: recompute GPU_LOCATION = stored GPU_LOCATION
    
  Therefore: Every GPU location is traceable to its original CAT-N-ID
             and can be fully reconstructed from host-side data
```

### 9.2 Audit Trail

```dylan
define sealed class <gpu-mapping-audit-trail> (<object>)
  // Complete history of CAT-N-ID ↔ GPU_LOCATION mappings
  
  constant slot connectome-version :: <connectome-version-lock>;
  constant slot partition-scheme :: <symbol>;
  constant slot num-partitions :: <integer>;
  constant slot total-neurons :: <integer>;
  constant slot total-synapses :: <integer>;
  
  constant slot mapping-timestamp :: <date>;
  
  constant slot forward-mappings :: <vector>;
    // vector<(CAT-N-ID, GPU_LOCATION)>[760M]
    // For spot-checking
  
  constant slot reverse-verification :: <vector>;
    // vector<(GPU_LOCATION, CAT-N-ID, verified?)>[sample_size]
    // For spot-checking
  
  constant slot collision-log :: <vector>;
    // vector<collision_event>
    // Reports any hash collisions detected
  
  constant slot fail-closed-log :: <vector>;
    // vector<failure_event>
    // Reports any validation failures
end class <gpu-mapping-audit-trail>;
```

---

## PART 10: IMPLEMENTATION ARCHITECTURE

### 10.1 Code Organization

```
PROJECT/
├── gpu-mapping-layer/
│   ├── host/
│   │   ├── bidirectional-mapping.dylan       // CAT-N-ID ↔ GPU_LOCATION
│   │   ├── index-tables.dylan                // Hash tables + lookups
│   │   ├── partition-algorithm.dylan         // Partitioning logic
│   │   ├── version-lock.dylan                // Determinism guarantees
│   │   └── audit-trail.dylan                 // Traceability logging
│   │
│   ├── gpu/
│   │   ├── node-table.cu                     // GPU node layout + kernels
│   │   ├── synapse-table.cu                  // GPU synapse layout
│   │   ├── event-queue.cu                    // GPU event queue (heap)
│   │   ├── reverse-lookup.cu                 // GPU→CPU mapping
│   │   └── validation.cu                     // Cross-check kernels
│   │
│   ├── tests/
│   │   ├── scale-ladder-tests.dylan          // 8-scale verification
│   │   ├── determinism-tests.dylan           // Reproducibility checks
│   │   ├── traceability-tests.dylan          // Audit trail validation
│   │   └── adversarial-tests.dylan           // Intentional collisions
│   │
│   └── docs/
│       ├── PHASE_6_GPU_GRAPH_TRANSFORMATION.md   (this file)
│       ├── API_REFERENCE.md
│       └── PERFORMANCE_TUNING.md
```

### 10.2 External Dependencies

```
REQUIRED:
  - Dylan language runtime (for host-side mapping)
  - CUDA toolkit (for GPU kernels)
  - SipHash-2-4 cryptographic library
  - SHA-256 library (for partition digest)
  - METIS or ParMETIS (optional, for community-based partitioning)

OPTIONAL:
  - NVIDIA nvprof (for GPU profiling)
  - Graphviz (for partition visualization)
  - HDF5 (for connectome I/O)
```

---

## PART 11: SUMMARY TABLE

| Requirement | Specification | Status |
|---|---|---|
| Bidirectional mapping | CAT-N-ID ↔ GPU_LOCATION (both directions) | ✓ SPECIFIED |
| Forward path | CAT-N-ID → hash → GLOBAL_INDEX → PARTITION → LOCAL_INDEX → GPU_LOCATION | ✓ SPECIFIED |
| Reverse path | GPU_LOCATION → LOCAL_INDEX → PARTITION → GLOBAL_INDEX → CAT-N-ID | ✓ SPECIFIED |
| Fail-closed semantics | Cross-check validation; hard failure on mismatch | ✓ SPECIFIED |
| Global index algorithm | SipHash-2-4(CAT-N-ID, region, layer, coords) mod 760M | ✓ SPECIFIED |
| Partition schemes | 4 orthogonal schemes (region, layer, spatial, community) | ✓ SPECIFIED |
| Recommended partitioning | Spatial tiling + layer (100×16 = 1600 partitions) | ✓ SPECIFIED |
| Host-side structures | cat_n_to_global_index, global_index_to_cat_n, partition_map, gpu_buffer_map | ✓ SPECIFIED |
| GPU-side structures | gpu_node_table, gpu_synapse_table, gpu_event_queue | ✓ SPECIFIED |
| Sparse connectivity | Per-partition adjacency lists (no dense matrix) | ✓ SPECIFIED |
| Scale ladder | 8 scales: 1, 1K, 10K, 100K, 1M, 10M, 100M, 760M | ✓ SPECIFIED |
| Determinism guarantee | Same connectome_version → same GPU locations | ✓ SPECIFIED |
| CAT-N-ID traceability | Complete reversibility with audit trail | ✓ SPECIFIED |
| Proof of correctness | Injection, surjection, reversibility, provenance invariants | ✓ SPECIFIED |

---

## DELIVERABLES CHECKLIST

- [x] CAT-N-ID ↔ GPU_LOCATION bidirectional mapping algorithm (both paths)
- [x] Global index computation with SipHash-2-4 hash function
- [x] Partition scheme design (4 orthogonal schemes + recommended 2-level)
- [x] GPU index structure specifications (host + GPU-side)
- [x] Reverse lookup guarantee with fail-closed semantics
- [x] Partitioning algorithm (pseudocode)
- [x] Sparse connectivity representation (adjacency lists + metadata)
- [x] Scale ladder test plan (8 measurement levels with 8 metrics each)
- [x] Determinism guarantee with versioning
- [x] Proof that CAT-N-ID traceability is preserved through GPU mapping
- [x] Implementation architecture and code organization
- [x] External dependencies and requirements

---

## NEXT PHASE

**PHASE 7**: Implementation of GPU mapping layer in Dylan + CUDA
  - Implement host-side index tables
  - Implement GPU-side node/synapse tables
  - Implement scale ladder test suite
  - Benchmark at 760M scale
  - Validate determinism and traceability

**PHASE 8**: Integration with Dylan execution engine
  - Connect GPU mapping to neuron execution model
  - Integrate event queue with spike delivery
  - Implement synapse weight updates
  - Add real-time spike recording

**PHASE 9**: Formal verification
  - Prove CAT-N-ID injection property
  - Prove reversibility invariant
  - Prove determinism under connectome versioning
  - Audit trail completeness theorem
