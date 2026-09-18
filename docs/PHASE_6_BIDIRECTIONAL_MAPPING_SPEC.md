# PHASE 6 DETAILED SPEC: BIDIRECTIONAL MAPPING ALGORITHM
## CAT-N-ID ↔ GPU Location with Scale Testing

**Specification ID**: PH6-BIDIR-001  
**Date**: 2026-09-13  
**Status**: ARCHITECTURE COMPLETE

---

## TABLE OF CONTENTS

1. [Bidirectional Mapping Overview](#bidirectional-mapping-overview)
2. [Forward Path: CAT-N-ID → GPU Location](#forward-path)
3. [Reverse Path: GPU Location → CAT-N-ID](#reverse-path)
4. [Cross-Check Validation](#cross-check-validation)
5. [Hash Function Specification](#hash-function-specification)
6. [Partition Scheme Details](#partition-scheme-details)
7. [Scale Ladder Test Specification](#scale-ladder-test-specification)
8. [GPU Location Determinism](#gpu-location-determinism)
9. [Implementation Pseudocode](#implementation-pseudocode)

---

## BIDIRECTIONAL MAPPING OVERVIEW

### Mapping Goals

1. **Deterministic**: Same input always produces same output
2. **Injective**: Different neurons → different GPU locations
3. **Reversible**: GPU location uniquely identifies neuron
4. **Traceable**: Every GPU location mappable back to CAT-N-ID
5. **Verifiable**: Cross-check at every step prevents silent errors

### Mapping Dimensions

```
760M neurons × 1600 partitions × (up to 760M/1600 = 475K neurons/partition)

Memory budget:
  Host RAM:
    - cat_n_to_global_index: 760M × 32 bytes = 24.3 GB
    - global_index_to_cat_n: 760M × 32 bytes = 24.3 GB
    - partition_map metadata: 1600 × 8 KB = 12.8 MB
    - Total: ~48.6 GB (typical host has 256+ GB)
  
  GPU VRAM:
    - gpu_node_table: 760M × 256 bytes = 194 GB
    - gpu_synapse_table: 1B × 64 bytes = 64 GB
    - gpu_event_queue: 100M × 32 bytes = 3.2 GB
    - Total: ~261 GB distributed across 8 GPUs = 32.6 GB/GPU
```

---

## FORWARD PATH: CAT-N-ID → GPU Location

### Path Specification

```
INPUT: CAT-N-ID (string, 16 hex digits)
       Example: "CAT-N-DEADBEEF12345678"

STEP 1: Validate Input
  assert(cat_n_id matches regex "CAT-N-[0-9A-F]{16}")
  assert(index_tables.cat_n_to_global_index.contains(cat_n_id))

STEP 2: Compute GLOBAL_INDEX
  global_index = compute_global_index(
    cat_n_id,
    neuron_record.region_id,
    neuron_record.layer_id,
    neuron_record.soma_coordinates,
    neuron_record.block_id,
    neuron_record.neuron_index,
    connectome_version
  )
  assert(0 <= global_index < 760_000_000)

STEP 3: Lookup Neuron Record
  neuron_record = index_tables.cat_n_to_global_index[cat_n_id]
  assert(neuron_record is not null)

STEP 4: Compute PARTITION_ID
  partition_id = select_partition(
    cat_n_id,
    neuron_record.region_id,
    neuron_record.layer_id,
    neuron_record.soma_coordinates,
    partition_scheme
  )
  assert(0 <= partition_id < num_partitions)

STEP 5: Compute LOCAL_INDEX
  partition_info = index_tables.partition_map[partition_id]
  sorted_neurons = partition_info.neurons_list (pre-sorted by CAT-N-ID)
  local_index = binary_search(sorted_neurons, cat_n_id)
  assert(local_index >= 0 and local_index < partition_info.size)

STEP 6: Get GPU Buffer Pointer
  gpu_buffer_ptr = index_tables.gpu_buffer_map[partition_id]
  assert(gpu_buffer_ptr is valid GPU memory address)

STEP 7: Compute GPU Offset
  node_size = sizeof(gpu_node) = 256 bytes
  gpu_offset = local_index * node_size
  gpu_location = gpu_buffer_ptr + gpu_offset
  assert(gpu_location is within gpu_buffer bounds)

STEP 8: Cache Result (optional)
  reverse_lookup_cache.insert((partition_id, local_index), cat_n_id)

OUTPUT: GPU_LOCATION (pointer to GPU node record)
        PARTITION_ID (uint16)
        LOCAL_INDEX (uint32)

RUNTIME: O(log n) for binary search (amortized O(1) with perfect hash)
```

### Implementation Pseudocode

```dylan
define function map-cat-n-id-to-gpu-location(
    cat-n-id :: <string>,
    index-tables :: <index-tables>
) => (gpu-location :: <gpu-ptr>, partition-id :: <integer>, local-index :: <integer>)
  
  // VALIDATION
  if (~valid-cat-n-id-format?(cat-n-id))
    error("Invalid CAT-N-ID format: %s", cat-n-id)
  end
  
  if (~index-tables.cat-n-to-global-index.key-exists?(cat-n-id))
    error("CAT-N-ID not found in index: %s", cat-n-id)
  end
  
  // LOOKUP
  neuron-record = index-tables.cat-n-to-global-index[cat-n-id]
  global-index = neuron-record.global-index
  
  assert(0 <= global-index & global-index < 760_000_000)
  
  // PARTITION SELECTION
  partition-id = compute-partition-id(
    neuron-record.region-id,
    neuron-record.layer-id,
    neuron-record.soma-coordinates,
    index-tables.partition-scheme
  )
  
  // LOCAL INDEX COMPUTATION
  partition-info = index-tables.partition-map[partition-id]
  sorted-neurons = partition-info.neurons-list
  local-index = binary-search-index(sorted-neurons, cat-n-id)
  
  if (local-index < 0)
    error("CAT-N-ID not in partition: %s", cat-n-id)
  end
  
  // GPU BUFFER LOOKUP
  gpu-buffer = index-tables.gpu-buffer-map[partition-id]
  if (gpu-buffer == null)
    error("GPU buffer not allocated for partition: %d", partition-id)
  end
  
  // GPU ADDRESS COMPUTATION
  gpu-location = gpu-buffer + (local-index * 256)  // 256 bytes per node
  
  RETURN values(gpu-location, partition-id, local-index)
end
```

---

## REVERSE PATH: GPU Location → CAT-N-ID

### Path Specification

```
INPUT: GPU_LOCATION (GPU memory pointer)
       PARTITION_ID (uint16)
       LOCAL_INDEX (uint32)

STEP 1: Validate GPU Location
  assert(partition_id < num_partitions)
  assert(local_index < partition_map[partition_id].size)
  assert(gpu_location == gpu_buffer_map[partition_id] + local_index * 256)

STEP 2: Read Node Record from GPU
  gpu_node = gpu_read_node(gpu_buffer_map[partition_id], local_index)
  extracted_cat_n_id = gpu_node.neuron_id_field
  extracted_neuron_id_hash = gpu_node.neuron_id_hash

STEP 3: Reconstruct GLOBAL_INDEX
  global_index = partition_map[partition_id].base_global_index + local_index
  assert(0 <= global_index < 760_000_000)

STEP 4: Lookup in Host Index Tables
  host_cat_n_id = index_tables.global_index_to_cat_n[global_index]
  assert(host_cat_n_id is not null)

STEP 5: Cross-Check #1: CAT-N-ID Consistency
  if (extracted_cat_n_id != host_cat_n_id):
    fail_closed(
      error = "CAT-N-ID mismatch",
      extracted = extracted_cat_n_id,
      expected = host_cat_n_id,
      location = (partition_id, local_index)
    )
  end

STEP 6: Cross-Check #2: Forward Verification
  host_neuron_record = index_tables.cat_n_to_global_index[host_cat_n_id]
  computed_global_index = compute_global_index(
    host_cat_n_id,
    host_neuron_record.region_id,
    host_neuron_record.layer_id,
    host_neuron_record.soma_coordinates,
    host_neuron_record.block_id,
    host_neuron_record.neuron_index,
    connectome_version
  )
  
  if (computed_global_index != global_index):
    fail_closed(
      error = "Forward/reverse mapping mismatch",
      computed = computed_global_index,
      expected = global_index
    )
  end

STEP 7: Cross-Check #3: Hash Verification
  expected_hash = siphash_2_4(
    extracted_cat_n_id,
    host_neuron_record.region_id,
    host_neuron_record.layer_id,
    host_neuron_record.soma_coordinates,
    host_neuron_record.block_id,
    host_neuron_record.neuron_index,
    connectome_version,
    MASTER_KEY
  )
  
  if (extracted_neuron_id_hash != expected_hash):
    fail_closed(
      error = "Neuron ID hash mismatch",
      extracted_hash = extracted_neuron_id_hash,
      computed_hash = expected_hash
    )
  end

STEP 8: Cache Result (optional)
  reverse_lookup_cache.insert((partition_id, local_index), host_cat_n_id)

OUTPUT: CAT-N-ID (string, verified)
        NEURON_RECORD (complete host-side record)

RUNTIME: O(1) GPU read + O(1) hash table lookup
```

### Implementation Pseudocode

```dylan
define function map-gpu-location-to-cat-n-id(
    gpu-location :: <gpu-ptr>,
    partition-id :: <integer>,
    local-index :: <integer>,
    index-tables :: <index-tables>
) => (cat-n-id :: <string>, neuron-record :: <neuron-record>)
  
  // STEP 1: GPU READ
  gpu-buffer = index-tables.gpu-buffer-map[partition-id]
  gpu-node = gpu-read-node(gpu-buffer, local-index)
  
  // STEP 2: RECONSTRUCT GLOBAL INDEX
  partition-info = index-tables.partition-map[partition-id]
  global-index = partition-info.base-global-index + local-index
  
  // STEP 3: HOST LOOKUP
  if (~index-tables.global-index-to-cat-n.key-exists?(global-index))
    fail-closed("Global index not in host table", global-index)
  end
  
  host-cat-n-id = index-tables.global-index-to-cat-n[global-index]
  
  // STEP 4: CROSS-CHECK #1
  if (gpu-node.neuron-id-field ~= host-cat-n-id)
    fail-closed(
      "CAT-N-ID mismatch",
      gpu-node.neuron-id-field,
      host-cat-n-id,
      partition-id,
      local-index
    )
  end
  
  // STEP 5: GET FULL RECORD
  host-neuron-record = index-tables.cat-n-to-global-index[host-cat-n-id]
  
  // STEP 6: CROSS-CHECK #2 (forward verification)
  computed-global-index = compute-global-index(
    host-cat-n-id,
    host-neuron-record.region-id,
    host-neuron-record.layer-id,
    host-neuron-record.soma-coordinates,
    host-neuron-record.block-id,
    host-neuron-record.neuron-index,
    index-tables.connectome-version
  )
  
  if (computed-global-index ~= global-index)
    fail-closed(
      "Forward/reverse mapping mismatch",
      computed-global-index,
      global-index
    )
  end
  
  // STEP 7: CACHE (optional)
  if (index-tables.has-reverse-lookup-cache?())
    index-tables.reverse-lookup-cache.insert(
      pair(partition-id, local-index),
      host-cat-n-id
    )
  end
  
  RETURN values(host-cat-n-id, host-neuron-record)
end
```

---

## CROSS-CHECK VALIDATION

### Validation Strategy

```
Every reverse lookup performs THREE cross-checks:

CHECK 1: Direct CAT-N-ID comparison
  GPU extracted_id vs Host stored_id
  Must match exactly

CHECK 2: Forward path verification
  Recompute global_index from host data
  Must equal reconstructed global_index

CHECK 3: Hash verification
  Recompute SipHash of neuron properties
  Must match hash stored in GPU node

If ANY check fails → FAIL_CLOSED (hard error)
```

### Fail-Closed Implementation

```dylan
define sealed class <mapping-failure-exception> (<error>)
  constant slot error-code :: <integer>;
  constant slot diagnostics :: <vector>;
  constant slot timestamp :: <date>;
  constant slot gpu-location :: <pair>;  // (partition_id, local_index)
  constant slot affected-cat-n-id :: <string>;
end class <mapping-failure-exception>;

define function fail-closed(
    error-message :: <string>,
    #rest diagnostic-values
) => (nothing)
  
  // 1. LOG DIAGNOSTICS
  write-diagnostic-entry(
    timestamp: current-time(),
    error-message: error-message,
    diagnostics: diagnostic-values
  )
  
  // 2. ALERT
  send-alert("CRITICAL: CAT-N-ID mapping verification failed")
  
  // 3. RAISE EXCEPTION
  exception = make(<mapping-failure-exception>,
    error-code: compute-error-code(error-message),
    diagnostics: diagnostic-values,
    timestamp: current-time()
  )
  throw(exception)
  
  // 4. UNREACHABLE (prevents silent failure)
  signal("FAIL-CLOSED triggered; system halted")
  never-return()
end
```

---

## HASH FUNCTION SPECIFICATION

### SipHash-2-4 Configuration

```
Algorithm: SipHash-2-4 (Simon & Jean-Philippe Aumasson)

ROUNDS: c=2, d=4
  c = initialization rounds (2)
  d = finalization rounds (4)

KEY SIZE: 128 bits (16 bytes)

OUTPUT: 64 bits

DESIGN RATIONALE:
  - Fast: 2-4 cycles per byte (competitive with MurmurHash)
  - Secure: Resistant to collision attacks and cryptanalysis
  - Deterministic: Identical output for identical input (within same version)
  - Collision-resistant: Probability of collision ~ 2^-64

CONFIGURATION FOR CAT-N-ID:

define function siphash-2-4-cat-n(
    cat-n-id :: <string>,
    region-id :: <integer>,
    layer-id :: <integer>,
    soma-coordinates :: <vector>,  // [x, y, z]
    block-id :: <integer>,
    neuron-index :: <integer>,
    connectome-version :: <integer>,
    master-key :: <vector>          // 128-bit key
) => (hash-value :: <integer>)
  
  // Serialize input to byte stream
  buffer = make(<byte-vector>, size: 256)
  offset = 0
  
  // Write CAT-N-ID (16 hex characters = 8 bytes)
  hex-bytes = parse-hex(cat-n-id[6..21])  // Extract 16 hex digits
  copy-bytes(buffer, offset, hex-bytes, 0, 8)
  offset += 8
  
  // Write region_id (4 bytes)
  write-u32-le(buffer, offset, region-id)
  offset += 4
  
  // Write layer_id (4 bytes)
  write-u32-le(buffer, offset, layer-id)
  offset += 4
  
  // Write soma coordinates [x, y, z] (12 bytes)
  write-float32-le(buffer, offset, soma-coordinates[0])
  offset += 4
  write-float32-le(buffer, offset, soma-coordinates[1])
  offset += 4
  write-float32-le(buffer, offset, soma-coordinates[2])
  offset += 4
  
  // Write block_id (4 bytes)
  write-u32-le(buffer, offset, block-id)
  offset += 4
  
  // Write neuron_index (4 bytes)
  write-u32-le(buffer, offset, neuron-index)
  offset += 4
  
  // Write connectome_version (4 bytes)
  write-u32-le(buffer, offset, connectome-version)
  offset += 4
  
  // Write MAGIC_CONSTANT (8 bytes, Knuth's golden ratio)
  write-u64-le(buffer, offset, 0x9E3779B97F4A7C15)
  offset += 8
  
  // Total: 8+4+4+12+4+4+4+8 = 48 bytes
  
  // Compute SipHash-2-4
  hash-value = siphash(
    buffer[0..48),
    master-key
  )
  
  RETURN hash-value
end
```

### MASTER_KEY Selection

```
The MASTER_KEY must be:
  1. Fixed per connectome_version
  2. Stored securely (not hardcoded)
  3. Reproducible across runs (determinism)
  4. Unique per connectome (to prevent mapping collisions across versions)

GENERATION:

define function generate-master-key(connectome-version :: <integer>)
    => (key :: <vector>)
  
  // Use deterministic KDF (PBKDF2-SHA256)
  // Input: connectome version identifier
  
  version-string = format("%d", connectome-version)
  salt = "CAT-N-MAPPING-MASTER-KEY-v1"  // Fixed salt
  
  derived-key = pbkdf2-sha256(
    password: version-string,
    salt: salt,
    iterations: 100_000,
    output-length: 16 bytes
  )
  
  RETURN derived-key
end

STORAGE:

Store in version lock:
  connectome_version_lock {
    major: 1,
    minor: 0,
    patch: 0,
    connectome_hash: sha256(...),
    partition_scheme: 'spatial-layer,
    num_partitions: 1600,
    hash_master_key: derived_key
  }
```

---

## PARTITION SCHEME DETAILS

### Spatial Tiling (Recommended Scheme C)

```
Tile dimensions:
  X-tiles: 0..9 (10 tiles, 1500 μm each = 15000 μm total width)
  Y-tiles: 0..9 (10 tiles, 1500 μm each = 15000 μm total height)
  Z: [0, 10000 μm] (full depth, no tiling)

Partition ID encoding:
  PARTITION_ID = (x_tile << 4) | y_tile
  
  Example:
    x_tile = 3, y_tile = 5
    PARTITION_ID = (3 << 4) | 5 = 0x35 = 53

FUNCTION compute-spatial-partition(soma-coordinates :: [float; 3])
  x = soma-coordinates[0]
  y = soma-coordinates[1]
  z = soma-coordinates[2]  // Unused for partitioning
  
  x-tile = min(9, max(0, floor(x / 1500.0)))
  y-tile = min(9, max(0, floor(y / 1500.0)))
  
  PARTITION_ID = (x-tile << 4) | y-tile
  
  RETURN PARTITION_ID
```

### Layer + Spatial (Recommended Scheme C+B)

```
Two-level partition ID:
  PARTITION_ID = (spatial_tile << 4) | layer_id
  
  spatial_tile: 0..99 (10x10 grid)
  layer_id: 0..15 (cortical layers + non-cortical)
  
  Total partitions: 100 * 16 = 1600

FUNCTION compute-spatial-layer-partition(
    soma-coordinates :: [float; 3],
    layer-id :: <integer>
) => partition-id

  x = soma-coordinates[0]
  y = soma-coordinates[1]
  
  x-tile = min(9, max(0, floor(x / 1500.0)))
  y-tile = min(9, max(0, floor(y / 1500.0)))
  spatial-tile = x-tile * 10 + y-tile
  
  PARTITION_ID = (spatial-tile << 4) | layer-id
  
  RETURN PARTITION_ID
```

---

## SCALE LADDER TEST SPECIFICATION

### Test Scales and Metrics

```
SCALE_LADDER = [1, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 760_000_000]

For each scale S:
  Generate S random neurons
  Measure 8 metrics
  Verify all PASS criteria
```

### Metric 1: Bidirectional Mapping Accuracy

```
DEFINITION:
  For N neurons, perform N forward + N reverse mappings
  Count successes and failures

PASS CRITERIA:
  forward_success_rate >= 99.999%
  reverse_success_rate >= 99.999%
  
  (Allow at most 1 failure per 100,000 neurons)

MEASUREMENT CODE:

define function measure-bidirectional-accuracy(
    scale :: <integer>,
    connectome :: <connectome-data>
) => (forward-success :: <single-float>, reverse-success :: <single-float>)
  
  neurons = connectome.neurons[0..scale-1]
  
  forward-successes = 0
  forward-failures = 0
  
  for each neuron in neurons:
    try:
      gpu-location = map-cat-n-id-to-gpu-location(neuron.cat-n-id)
      forward-successes += 1
    catch error:
      forward-failures += 1
      log-error("Forward mapping failed", neuron.cat-n-id, error)
  end
  
  reverse-successes = 0
  reverse-failures = 0
  
  for each neuron in neurons:
    try:
      gpu-location = map-cat-n-id-to-gpu-location(neuron.cat-n-id)
      recovered-cat-n-id = map-gpu-location-to-cat-n-id(gpu-location.partition, gpu-location.index)
      
      if (recovered-cat-n-id == neuron.cat-n-id):
        reverse-successes += 1
      else:
        reverse-failures += 1
        log-error("CAT-N-ID mismatch", neuron.cat-n-id, recovered-cat-n-id)
    catch error:
      reverse-failures += 1
      log-error("Reverse mapping failed", gpu-location, error)
  end
  
  forward-rate = (forward-successes / scale) * 100.0
  reverse-rate = (reverse-successes / scale) * 100.0
  
  RETURN values(forward-rate, reverse-rate)
end
```

### Metric 2: Hash Collision Rate

```
DEFINITION:
  Count how many distinct GLOBAL_INDEXes are produced for S neurons
  Collision = two different CAT-N-IDs map to same GLOBAL_INDEX

PASS CRITERIA:
  collision_count == 0 (zero collisions across all scales)

MEASUREMENT CODE:

define function measure-hash-collisions(
    scale :: <integer>,
    connectome :: <connectome-data>
) => (collision-count :: <integer>, uniqueness :: <single-float>)
  
  neurons = connectome.neurons[0..scale-1]
  global-indices = make(<hash-set>)
  collisions = 0
  
  for each neuron in neurons:
    global-index = compute-global-index(
      neuron.cat-n-id,
      neuron.region-id,
      neuron.layer-id,
      neuron.soma-coordinates,
      neuron.block-id,
      neuron.neuron-index,
      connectome.version
    )
    
    if (global-indices.contains?(global-index)):
      collisions += 1
      log-warning("Hash collision detected", global-index)
    else:
      global-indices.add(global-index)
    end
  end
  
  uniqueness = (global-indices.size / scale) * 100.0
  
  RETURN values(collisions, uniqueness)
end
```

### Metric 3: Partition Load Balance

```
DEFINITION:
  max_partition_size = largest partition
  min_partition_size = smallest partition
  load_balance_ratio = max / min

PASS CRITERIA:
  load_balance_ratio <= 2.0 (no partition more than 2x largest)

MEASUREMENT CODE:

define function measure-partition-load-balance(
    partition-map :: <vector>
) => (ratio :: <single-float>, max-size :: <integer>, min-size :: <integer>)
  
  sizes = map(partition => partition.size, partition-map)
  max-size = max(sizes)
  min-size = min(sizes)
  
  if (min-size == 0):
    ratio = infinity()
  else:
    ratio = max-size / min-size
  end
  
  RETURN values(ratio, max-size, min-size)
end
```

### Metric 4: Lookup Performance

```
DEFINITION:
  Measure time for forward and reverse lookups
  
PASS CRITERIA:
  forward_lookup_time < 1 microsecond (host-side operation)
  reverse_lookup_time < 1 microsecond (host-side operation)

MEASUREMENT CODE:

define function measure-lookup-performance(
    scale :: <integer>,
    connectome :: <connectome-data>,
    index-tables :: <index-tables>
) => (forward-time :: <integer>, reverse-time :: <integer>)
  // Measure in nanoseconds
  
  neurons = connectome.neurons[0..scale-1]
  
  // FORWARD LOOKUP TIMING
  samples = min(1000, scale)  // Sample subset for large scales
  forward-times = make(<vector>, size: samples)
  
  for i in 0..samples-1:
    neuron = neurons[i]
    
    start-ns = current-time-nanoseconds()
    gpu-location = map-cat-n-id-to-gpu-location(neuron.cat-n-id, index-tables)
    end-ns = current-time-nanoseconds()
    
    forward-times[i] = end-ns - start-ns
  end
  
  forward-avg = average(forward-times)
  
  // REVERSE LOOKUP TIMING
  reverse-times = make(<vector>, size: samples)
  
  for i in 0..samples-1:
    neuron = neurons[i]
    gpu-location = map-cat-n-id-to-gpu-location(neuron.cat-n-id, index-tables)
    
    start-ns = current-time-nanoseconds()
    recovered-cat-n-id = map-gpu-location-to-cat-n-id(
      gpu-location.partition,
      gpu-location.index,
      index-tables
    )
    end-ns = current-time-nanoseconds()
    
    reverse-times[i] = end-ns - start-ns
  end
  
  reverse-avg = average(reverse-times)
  
  RETURN values(forward-avg, reverse-avg)
end
```

### Metric 5: Cross-Check Failure Rate

```
DEFINITION:
  Count how many reverse lookups fail cross-check validation

PASS CRITERIA:
  failure_count == 0 (no validation failures)

MEASUREMENT CODE:

define function measure-cross-check-failures(
    scale :: <integer>,
    connectome :: <connectome-data>,
    index-tables :: <index-tables>
) => (failure-count :: <integer>)
  
  neurons = connectome.neurons[0..scale-1]
  failures = 0
  
  for each neuron in neurons:
    try:
      gpu-location = map-cat-n-id-to-gpu-location(neuron.cat-n-id, index-tables)
      recovered = map-gpu-location-to-cat-n-id(
        gpu-location.partition,
        gpu-location.index,
        index-tables
      )
      
      // If we reach here without exception, cross-checks passed
    catch <mapping-failure-exception> as e:
      failures += 1
      log-error("Cross-check failure", e)
    end
  end
  
  RETURN failures
end
```

### Metric 6: Determinism Guarantee

```
DEFINITION:
  Run mapping twice on same connectome
  Compare GPU locations for each CAT-N-ID
  
PASS CRITERIA:
  All (CAT-N-ID, location) pairs identical across runs

MEASUREMENT CODE:

define function measure-determinism(
    connectome :: <connectome-data>,
    index-tables :: <index-tables>
) => (determinism-violations :: <integer>)
  
  neurons = connectome.neurons
  violations = 0
  
  // RUN 1: Map all neurons
  mapping1 = make(<hash-table>)
  for each neuron in neurons:
    gpu-location1 = map-cat-n-id-to-gpu-location(neuron.cat-n-id, index-tables)
    mapping1[neuron.cat-n-id] = gpu-location1
  end
  
  // RUN 2: Map all neurons again (same connectome, same version)
  mapping2 = make(<hash-table>)
  for each neuron in neurons:
    gpu-location2 = map-cat-n-id-to-gpu-location(neuron.cat-n-id, index-tables)
    mapping2[neuron.cat-n-id] = gpu-location2
  end
  
  // COMPARE
  for each neuron in neurons:
    if (mapping1[neuron.cat-n-id] ~= mapping2[neuron.cat-n-id]):
      violations += 1
      log-error("Determinism violation", neuron.cat-n-id)
    end
  end
  
  RETURN violations
end
```

### Metric 7: Memory Usage

```
DEFINITION:
  Report host RAM and GPU VRAM usage

PASS CRITERIA:
  host_ram_used <= 256 GB
  gpu_vram_used <= 8 * 64 GB = 512 GB (for 8 GPUs)

MEASUREMENT CODE:

define function measure-memory-usage(
    index-tables :: <index-tables>,
    gpu-buffers :: <vector>
) => (host-ram :: <integer>, gpu-vram :: <integer>)
  
  // HOST RAM
  cat-n-to-global = size-of-hash-table(index-tables.cat-n-to-global-index)
  global-to-cat-n = size-of-hash-table(index-tables.global-index-to-cat-n)
  partition-metadata = 1600 * 8192  // ~8 KB per partition
  
  host-ram = cat-n-to-global + global-to-cat-n + partition-metadata
  
  // GPU VRAM
  gpu-vram = 0
  for each gpu-buffer in gpu-buffers:
    gpu-vram += gpu-buffer.allocated-size
  end
  
  RETURN values(host-ram, gpu-vram)
end
```

### Metric 8: Edge Preservation

```
DEFINITION:
  Verify that all edges are stored (no edges lost during partitioning)

PASS CRITERIA:
  total_input_edges == total_partitioned_edges + total_boundary_edges

MEASUREMENT CODE:

define function measure-edge-preservation(
    original-synapses :: <vector>,
    partition-map :: <vector>
) => (input-edges :: <integer>, stored-edges :: <integer>, preserved :: <boolean>)
  
  input-edges = original-synapses.size
  
  stored-edges = 0
  for each partition in partition-map:
    stored-edges += partition.edge-list.size
    stored-edges += partition.boundary-edges.size
  end
  
  preserved = (input-edges == stored-edges)
  
  if (~preserved):
    log-error("Edge loss detected",
      input: input-edges,
      stored: stored-edges,
      missing: input-edges - stored-edges
    )
  end
  
  RETURN values(input-edges, stored-edges, preserved)
end
```

---

## GPU LOCATION DETERMINISM

### Determinism Proof

```
THEOREM: GPU locations are deterministic given connectome version

PROOF:
  1. CAT-N-ID is immutable (property of neuron record)
  2. hash(CAT-N-ID, neuron_properties) is deterministic (SipHash-2-4)
  3. GLOBAL_INDEX = hash(...) mod 760M is deterministic
  4. PARTITION_ID = f(region, layer, coordinates, scheme) is deterministic
  5. LOCAL_INDEX = position in sorted list is deterministic
  6. GPU_LOCATION = (partition_id, local_index) is deterministic
  
  Therefore: GPU_LOCATION is fully determined by:
    - connectome_version
    - partition_scheme
    - (CAT-N-ID and all neuron properties)
  
  Same inputs → Same GPU locations

VERSIONING STRATEGY:
  connectome_version_lock {
    connectome_hash: SHA-256(all neuron+synapse data)
    partition_scheme: 'spatial-layer
    hash_master_key: derived from version
  }
  
  Two connectomes are identical iff:
    - connectome_hash matches
    - partition_scheme matches
    - (implied: hash_master_key matches)
  
  Therefore: Identical connectomes produce identical GPU mappings
```

### Version Locking Mechanism

```dylan
define sealed class <connectome-version-lock> (<object>)
  // FROZEN ATTRIBUTES (never change after creation)
  constant slot major :: <integer>;
  constant slot minor :: <integer>;
  constant slot patch :: <integer>;
  constant slot connectome-hash :: <string>;        // SHA-256 of all neurons+synapses
  constant slot partition-scheme :: <symbol>;       // 'spatial-layer, etc.
  constant slot num-partitions :: <integer>;
  constant slot hash-master-key :: <vector>;       // 128-bit SipHash key
  constant slot timestamp-created :: <date>;
  constant slot created-by :: <string>;
end class <connectome-version-lock>;

define function create-version-lock(
    connectome :: <connectome-data>,
    partition-scheme :: <symbol>
) => (lock :: <connectome-version-lock>)
  
  // COMPUTE CONNECTOME HASH
  connectome-hash = compute-connectome-hash(connectome)
  
  // DERIVE MASTER KEY FROM VERSION
  version-string = format("CAT-N-MAPPING-%s-%s",
    connectome-hash,
    symbol-to-string(partition-scheme)
  )
  
  master-key = pbkdf2-sha256(
    password: version-string,
    salt: "CAT-N-MASTER-KEY-v1",
    iterations: 100000,
    output-length: 16
  )
  
  // CREATE LOCK
  lock = make(<connectome-version-lock>,
    major: 1,
    minor: 0,
    patch: 0,
    connectome-hash: connectome-hash,
    partition-scheme: partition-scheme,
    num-partitions: 1600,
    hash-master-key: master-key,
    timestamp-created: now(),
    created-by: user-name()
  )
  
  // PERSIST
  write-version-lock-to-disk(lock)
  
  RETURN lock
end
```

---

## IMPLEMENTATION PSEUDOCODE

### Complete Forward + Reverse Cycle

```dylan
define function test-bidirectional-cycle(
    cat-n-id :: <string>,
    neuron-record :: <neuron-record>,
    index-tables :: <index-tables>
) => (success :: <boolean>)
  
  // FORWARD: CAT-N-ID → GPU_LOCATION
  gpu-location = map-cat-n-id-to-gpu-location(cat-n-id, index-tables)
  partition-id = gpu-location.partition-id
  local-index = gpu-location.local-index
  
  // REVERSE: GPU_LOCATION → CAT-N-ID
  recovered-cat-n-id = map-gpu-location-to-cat-n-id(
    partition-id,
    local-index,
    index-tables
  )
  
  // VERIFY: CAT-N-ID in == CAT-N-ID out
  if (cat-n-id == recovered-cat-n-id):
    log-info("Bidirectional cycle successful", cat-n-id)
    RETURN #t
  else:
    log-error("Bidirectional cycle FAILED",
      input: cat-n-id,
      output: recovered-cat-n-id
    )
    RETURN #f
  end
end

// TEST ALL SCALES
define function test-all-scales(connectome :: <connectome-data>)
  scale-ladder = #[1, 1000, 10000, 100000, 1000000, 10000000, 100000000, 760000000]
  
  for each scale in scale-ladder:
    format("Testing scale: %d neurons...\n", scale)
    
    neurons = connectome.neurons[0..scale-1]
    successes = 0
    failures = 0
    
    for each neuron in neurons:
      if (test-bidirectional-cycle(neuron.cat-n-id, neuron, connectome.index-tables)):
        successes += 1
      else:
        failures += 1
      end
    end
    
    success-rate = (successes / scale) * 100.0
    format("  Successes: %d / %d (%.4f%%)\n", successes, scale, success-rate)
    format("  Failures: %d\n", failures)
    
    if (failures > 0):
      format("  WARNING: Failures detected at scale %d\n", scale)
    end
  end
end
```

---

## SUMMARY

| Component | Specification | Implementation Status |
|---|---|---|
| Forward path | CAT-N-ID → GPU location | SPECIFIED |
| Reverse path | GPU location → CAT-N-ID | SPECIFIED |
| Cross-check #1 | Direct CAT-N-ID comparison | SPECIFIED |
| Cross-check #2 | Forward/reverse consistency | SPECIFIED |
| Cross-check #3 | Hash verification | SPECIFIED |
| Hash function | SipHash-2-4 configuration | SPECIFIED |
| Partition scheme | Spatial + layer (1600 partitions) | SPECIFIED |
| Scale ladder | 8 scales × 8 metrics = 64 measurements | SPECIFIED |
| Determinism guarantee | Version locking mechanism | SPECIFIED |
| Fail-closed semantics | Hard error on any validation failure | SPECIFIED |

---

## NEXT STEPS

1. Implement host-side index tables in Dylan
2. Implement GPU-side node/synapse structures in CUDA
3. Run scale ladder tests at all 8 scales
4. Validate determinism across connectome versions
5. Measure performance (lookup times, memory usage)
6. Formal verification of mapping correctness
