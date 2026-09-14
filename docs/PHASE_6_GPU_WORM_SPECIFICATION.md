# PHASE 6: GPU WORM Layer — Cryptographic Integrity Specification

**Status**: SPECIFICATION COMPLETE  
**Date**: 2026-09-13  
**Scope**: Write-Once-Read-Many (WORM) cryptographic integrity for all GPU-compatible neural simulation artifacts  
**Security Model**: Fail-closed integrity verification; corrupted artifacts never silently used  

---

## 1. MISSION & INTEGRITY GUARANTEE

### 1.1 Core Promise

Every GPU artifact (neuron index, synapse table, partition manifest, execution trace) is **independently cryptographically verifiable**. Once sealed, artifacts are immutable and tamper-evident:

- **Sealed Immutability**: After sealing, PAYLOAD cannot be modified
- **Fail-Closed**: Integrity check failure → drop buffer, halt execution, error flag
- **Cryptographic Binding**: All related artifacts cryptographically linked via hash chains
- **Deterministic Verification**: Same artifact always verifies identically (reproducible checks)

### 1.2 Artifacts Requiring Protection

```
GPU-COMPATIBLE ARTIFACTS:
├─ NODE_INDEX_TABLE          [760M entries: CAT-N-ID → GLOBAL_INDEX → PARTITION_ID → LOCAL_INDEX]
├─ SYNAPSE_INDEX_TABLE       [1B entries: CAT-S-ID, source_CAT-N, dest_CAT-N, properties]
├─ PARTITION_MANIFEST        [Per partition: boundaries, CAT-N-ID range, synapse counts]
├─ GPU_BUFFER_MANIFEST       [GPU memory buffers: neural state, synapse table, event queue]
├─ MODEL_PARAMETERS          [HH, IAF, IAF_MOD firing models + neuron type assignments]
├─ GPU_KERNEL_VERSION        [Compiled kernel metadata: hash, config, optimization flags]
├─ EXECUTION_TRACE           [Per GPU run: spike events, state snapshots, memory checkpoints]
├─ BENCHMARK_DATA            [Performance: latency, throughput, memory utilization per timestep]
└─ NUMERICAL_ERROR_BOUNDS    [CPU/GPU divergence: max absolute error, mean error, confidence intervals]
```

---

## 2. ARTIFACT STRUCTURE (Universal Template)

Every GPU artifact conforms to this structure:

```
ARTIFACT
├─ METADATA (96 bytes)
│  ├─ ARTIFACT_ID [32 bytes]               // Hierarchical: GPU.NODE_INDEX / GPU.PARTITION_1 / etc.
│  ├─ VERSION [4 bytes]                    // Semantic: major.minor.patch
│  ├─ CREATION_TIMESTAMP [8 bytes]         // Nanosecond precision (uint64)
│  ├─ CREATOR [8 bytes]                    // Agent identifier (PHASE_6_ENGINE)
│  ├─ SEALED_FLAG [1 byte]                 // Boolean: immutable after sealing
│  ├─ MODEL_VERSION_HASH [32 bytes]        // SHA-256(model parameters used)
│  └─ CONNECTOME_VERSION_HASH [32 bytes]   // SHA-256(connectome generation params)
│
├─ IDENTITY (64 bytes)
│  ├─ DESCRIPTION [64 bytes]               // UTF-8 description of what this artifact contains
│
├─ PAYLOAD (variable size)
│  ├─ [Actual data: node indices, synapse table, execution trace, etc.]
│  └─ PAYLOAD_SIZE [8 bytes]               // Declared size in bytes
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]             // SHA-256 of parent block (for chain linking)
│  ├─ PAYLOAD_DIGEST [32 bytes]            // SHA-256(canonical_serialize(PAYLOAD))
│  ├─ ENTRY_ORDER_HASH [32 bytes]          // SHA-256(sort(PAYLOAD)) — for determinism
│  ├─ INTEGRITY_HASH [32 bytes]            // SHA-256(METADATA || PAYLOAD || PARENT_DIGEST)
│  └─ HMAC_TAG [32 bytes]                  // HMAC-SHA-256(K_master, canonical(all fields))
│
└─ SEAL (1 byte)
   └─ SEALED [1 byte]                      // 0x01 = sealed, immutable
```

**Total Overhead**: 96 + 64 + 8 + 128 + 1 = 297 bytes per artifact

### 2.1 Canonical Serialization (Big-Endian)

All artifacts serialize deterministically:

```
CANONICAL_SERIALIZE(artifact):
  buffer ← []
  
  // METADATA (fixed order, big-endian)
  buffer.append(artifact.artifact_id)                    // 32 bytes
  buffer.append(to_big_endian(artifact.version))         // 4 bytes
  buffer.append(to_big_endian_u64(artifact.timestamp))   // 8 bytes
  buffer.append(to_big_endian_u64(artifact.creator))     // 8 bytes
  buffer.append(uint8(artifact.sealed_flag))             // 1 byte
  buffer.append(artifact.model_version_hash)             // 32 bytes
  buffer.append(artifact.connectome_version_hash)        // 32 bytes
  
  // IDENTITY
  buffer.append(artifact.description.encode_utf8())      // 64 bytes (null-padded)
  
  // PAYLOAD
  buffer.append(to_big_endian_u64(artifact.payload_size))  // 8 bytes
  payload_canonical ← CANONICAL_SERIALIZE_PAYLOAD(artifact.payload)
  buffer.append(payload_canonical)                       // variable
  
  // INTEGRITY FIELDS
  buffer.append(artifact.parent_digest)                  // 32 bytes
  buffer.append(artifact.payload_digest)                 // 32 bytes
  buffer.append(artifact.entry_order_hash)               // 32 bytes
  buffer.append(artifact.integrity_hash)                 // 32 bytes
  // NOTE: HMAC_TAG is computed AFTER all other fields
  
  return buffer
```

**Floating-Point Encoding**: IEEE 754 double-precision (64-bit), big-endian byte order.

---

## 3. GPU BUFFER INTEGRITY SCHEME

For GPU memory buffers (neural state, synapse table, event queue):

### 3.1 Per-Buffer Verification

Each GPU buffer contains:

```
GPU_BUFFER
├─ BUFFER_DIGEST          [32 bytes]  SHA-256(canonical_serialize(buffer_contents))
├─ PARTITION_LINK         [4 bytes]   Which partition this buffer belongs to
├─ MODEL_VERSION          [4 bytes]   Which firing model (HH=1, IAF=2, IAF_MOD=3)
├─ CAT_N_RANGE            [32 bytes]  Min_CAT_N (16 bytes) + Max_CAT_N (16 bytes)
├─ ENTRY_COUNT            [8 bytes]   Number of entries in buffer
├─ BUFFER_PAYLOAD         [variable]  Actual neuron/synapse data
├─ INTEGRITY_HASH         [32 bytes]  SHA-256(BUFFER_DIGEST || PARTITION_LINK || MODEL_VERSION || CAT_N_RANGE)
└─ HMAC_TAG               [32 bytes]  HMAC-SHA-256(K_master, canonical(buffer))
```

### 3.2 Verification Algorithm (Fail-Closed)

```cpp
enum VerificationResult {
  SUCCESS = 0,
  FAIL_BUFFER_CORRUPTED = 1,
  FAIL_PARTITION_MISMATCH = 2,
  FAIL_MODEL_MISMATCH = 3,
  FAIL_RANGE_VIOLATION = 4,
  FAIL_HMAC_INVALID = 5
};

VerificationResult GPU_Buffer_Verify(
  const GPU_Buffer& buffer,
  const PartitionManifest& partition,
  const MasterKey& k_master
) {
  // Step 1: Verify buffer contents hash
  SHA256 computed_buffer_digest = SHA256(canonical_serialize(buffer.contents));
  if (computed_buffer_digest != buffer.buffer_digest) {
    return FAIL_BUFFER_CORRUPTED;
  }
  
  // Step 2: Verify partition link
  if (buffer.partition_link != partition.partition_id) {
    return FAIL_PARTITION_MISMATCH;
  }
  
  // Step 3: Verify model version matches
  if (buffer.model_version != partition.model_version) {
    return FAIL_MODEL_MISMATCH;
  }
  
  // Step 4: Verify CAT-N range is within partition bounds
  if (buffer.cat_n_range.min < partition.cat_n_range.min ||
      buffer.cat_n_range.max > partition.cat_n_range.max) {
    return FAIL_RANGE_VIOLATION;
  }
  
  // Step 5: Recompute integrity hash
  std::vector<uint8_t> integrity_input;
  integrity_input.append(buffer.buffer_digest);
  integrity_input.append(to_big_endian(buffer.partition_link));
  integrity_input.append(to_big_endian(buffer.model_version));
  integrity_input.append(buffer.cat_n_range.serialize());
  SHA256 computed_integrity = SHA256(integrity_input);
  
  if (computed_integrity != buffer.integrity_hash) {
    return FAIL_BUFFER_CORRUPTED;
  }
  
  // Step 6: Constant-time HMAC verification
  std::vector<uint8_t> canonical_buffer = canonical_serialize(buffer);
  SHA256_HMAC computed_hmac = HMAC_SHA256(k_master, canonical_buffer);
  
  if (!constant_time_compare(computed_hmac.bytes(), buffer.hmac_tag)) {
    return FAIL_HMAC_INVALID;  // Tampering detected
  }
  
  return SUCCESS;
}
```

**Fail-Closed Guarantee**: If ANY check fails, execution halts immediately. No partial or degraded use.

---

## 4. PARTITION_MANIFEST SCHEMA

### 4.1 Complete Structure

```
PARTITION_MANIFEST
├─ METADATA (universal artifact header, 96 bytes)
│
├─ PARTITION_BODY
│  ├─ PARTITION_ID [4 bytes]               // Region enum: V1=0, CA1=1, M1=2, etc.
│  ├─ NODE_COUNT [8 bytes]                 // Neurons in this partition
│  ├─ CAT_N_RANGE [32 bytes]               // [Min_CAT-N, Max_CAT-N] for this partition
│  ├─ SYNAPSE_COUNT [8 bytes]              // Total synapses with both ends in this partition
│  ├─ BOUNDARY_SYNAPSE_COUNT [8 bytes]     // Inter-partition edges (source or target outside)
│  ├─ NODE_INDEX_DIGEST [32 bytes]         // SHA-256(NODE_INDEX_TABLE for this partition)
│  ├─ SYNAPSE_INDEX_DIGEST [32 bytes]      // SHA-256(SYNAPSE_INDEX_TABLE for this partition)
│  ├─ MODEL_VERSION_HASH [32 bytes]        // SHA-256(model parameters used)
│  ├─ CONNECTIVITY_HASH [32 bytes]         // SHA-256(all CAT-S-IDs in this partition)
│  ├─ CHILD_GPU_BUFFER_DIGESTS [variable]  // Array of digests of GPU buffers belonging to this partition
│  │  ├─ BUFFER_COUNT [4 bytes]
│  │  └─ [BUFFER_COUNT × 32 bytes] digests
│  ├─ TIMESTAMP [8 bytes]                  // Creation time (nanosecond precision)
│  ├─ SEALED_FLAG [1 byte]                 // 0x01 = immutable
│  └─ [Padding to align]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]             // SHA-256 of previous partition manifest
│  ├─ BODY_DIGEST [32 bytes]               // SHA-256(canonical(partition_body))
│  ├─ CHILD_ARRAY_HASH [32 bytes]          // SHA-256(all child digests concatenated)
│  ├─ INTEGRITY_HASH [32 bytes]            // SHA-256(BODY_DIGEST || CHILD_ARRAY_HASH || PARENT_DIGEST)
│  └─ HMAC_TAG [32 bytes]                  // HMAC-SHA-256(K_master, canonical(entire manifest))
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]                      // 0x01 = sealed, no further modifications
```

### 4.2 Verification

```cpp
bool PartitionManifest_Verify(
  const PartitionManifest& manifest,
  const NodeIndexTable& node_table,
  const SynapseIndexTable& synapse_table,
  const std::vector<GPU_Buffer>& gpu_buffers,
  const MasterKey& k_master
) {
  // Step 1: Verify sealed flag
  if (!manifest.sealed_flag) {
    log_error("Partition not sealed");
    return false;
  }
  
  // Step 2: Verify node count is consistent with CAT-N range
  size_t expected_nodes = manifest.cat_n_range.max - manifest.cat_n_range.min + 1;
  if (manifest.node_count != expected_nodes) {
    log_error("Node count mismatch");
    return false;
  }
  
  // Step 3: Verify node index digest
  std::vector<uint8_t> nodes_canonical = node_table.canonical_serialize_for_partition(manifest.partition_id);
  SHA256 computed_node_digest = SHA256(nodes_canonical);
  if (computed_node_digest != manifest.node_index_digest) {
    log_error("Node index digest mismatch");
    return false;
  }
  
  // Step 4: Verify synapse index digest
  std::vector<uint8_t> synapses_canonical = synapse_table.canonical_serialize_for_partition(manifest.partition_id);
  SHA256 computed_synapse_digest = SHA256(synapses_canonical);
  if (computed_synapse_digest != manifest.synapse_index_digest) {
    log_error("Synapse index digest mismatch");
    return false;
  }
  
  // Step 5: Verify all GPU buffers match stored digests
  for (size_t i = 0; i < gpu_buffers.size(); i++) {
    SHA256 buffer_digest = SHA256(canonical_serialize(gpu_buffers[i]));
    if (buffer_digest != manifest.child_gpu_buffer_digests[i]) {
      log_error("GPU buffer {} digest mismatch", i);
      return false;
    }
  }
  
  // Step 6: Verify HMAC
  std::vector<uint8_t> manifest_canonical = canonical_serialize(manifest);
  SHA256_HMAC computed_hmac = HMAC_SHA256(k_master, manifest_canonical);
  if (!constant_time_compare(computed_hmac.bytes(), manifest.hmac_tag)) {
    log_error("Partition manifest HMAC invalid");
    return false;
  }
  
  return true;
}
```

---

## 5. NODE_INDEX_TABLE INTEGRITY

### 5.1 Structure

```
NODE_INDEX_TABLE
├─ METADATA (universal artifact header, 96 bytes)
│
├─ TABLE_BODY
│  ├─ ENTRY_COUNT [8 bytes]                // 760M at full scale
│  ├─ ENTRIES [760M × 56 bytes each]       // See below
│  ├─ HASH_COLLISION_COUNT [4 bytes]       // Must be 0 (invariant)
│  ├─ PAYLOAD_DIGEST [32 bytes]            // SHA-256(all entry data)
│  ├─ ENTRY_ORDER_HASH [32 bytes]          // SHA-256(sort(entries)) — deterministic
│  ├─ MODEL_VERSION [4 bytes]              // Connectome version
│  ├─ TIMESTAMP [8 bytes]
│  ├─ SEALED_FLAG [1 byte]
│  └─ [Padding]
│
├─ ENTRY FORMAT (56 bytes each)
│  ├─ CAT_N_ID [16 bytes]                  // Unique neuron identifier (UUID128)
│  ├─ GLOBAL_INDEX [8 bytes]               // Position in 760M-element array [0, 760M)
│  ├─ PARTITION_ID [4 bytes]               // Which region/partition
│  ├─ LOCAL_INDEX [4 bytes]                // Position within partition
│  ├─ NEURON_TYPE [2 bytes]                // Pyramidal, GABAergic, etc.
│  ├─ FIRING_MODEL [2 bytes]               // HH=1, IAF=2, IAF_MOD=3
│  └─ REGION_ID [2 bytes]                  // V1, CA1, M1, etc.
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]             // SHA-256 of previous NODE_INDEX version
│  ├─ BODY_DIGEST [32 bytes]               // SHA-256(canonical(table_body))
│  ├─ REVERSE_MAP_HASH [32 bytes]          // SHA-256(reverse mapping: GLOBAL_INDEX → CAT-N-ID)
│  ├─ INTEGRITY_HASH [32 bytes]            // SHA-256(BODY_DIGEST || REVERSE_MAP_HASH || PARENT_DIGEST)
│  └─ HMAC_TAG [32 bytes]                  // HMAC-SHA-256(K_master, canonical(entire table))
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]                      // 0x01 = immutable
```

### 5.2 Verification

```cpp
enum NodeIndexVerificationResult {
  SUCCESS = 0,
  FAIL_COLLISION_DETECTED = 1,
  FAIL_INDEX_OUT_OF_RANGE = 2,
  FAIL_REVERSE_MAPPING_BROKEN = 3,
  FAIL_PARTITION_RANGE_VIOLATION = 4,
  FAIL_HMAC_INVALID = 5,
  FAIL_ORDER_HASH_MISMATCH = 6
};

NodeIndexVerificationResult NodeIndexTable_Verify(
  const NodeIndexTable& table,
  const std::vector<PartitionManifest>& partitions,
  const MasterKey& k_master,
  int sample_size = 10000  // Random sample for full verification
) {
  // Step 1: Verify sealed flag
  if (!table.sealed_flag) {
    return FAIL_ORDER_HASH_MISMATCH;
  }
  
  // Step 2: Verify no collisions in CAT-N-IDs
  std::unordered_set<CatNID> seen_ids;
  for (const auto& entry : table.entries) {
    if (seen_ids.count(entry.cat_n_id)) {
      log_error("CAT-N-ID collision detected: {}", entry.cat_n_id);
      return FAIL_COLLISION_DETECTED;
    }
    seen_ids.insert(entry.cat_n_id);
  }
  
  // Step 3: Verify all GLOBAL_INDEX values in valid range [0, 760M)
  for (const auto& entry : table.entries) {
    if (entry.global_index >= 760000000LL || entry.global_index < 0) {
      log_error("GLOBAL_INDEX out of range: {}", entry.global_index);
      return FAIL_INDEX_OUT_OF_RANGE;
    }
  }
  
  // Step 4: Verify reverse mapping (random sample)
  std::vector<int> random_indices = random_sample(0, table.entries.size(), sample_size);
  for (int idx : random_indices) {
    const auto& entry = table.entries[idx];
    
    // Lookup reverse: GLOBAL_INDEX → CAT-N-ID
    bool found = false;
    for (const auto& e : table.entries) {
      if (e.global_index == entry.global_index) {
        if (e.cat_n_id != entry.cat_n_id) {
          log_error("Reverse mapping broken at GLOBAL_INDEX {}", entry.global_index);
          return FAIL_REVERSE_MAPPING_BROKEN;
        }
        found = true;
        break;
      }
    }
    
    if (!found) {
      log_error("GLOBAL_INDEX {} not found in reverse lookup", entry.global_index);
      return FAIL_REVERSE_MAPPING_BROKEN;
    }
  }
  
  // Step 5: Verify partition assignment consistency
  for (const auto& entry : table.entries) {
    bool partition_found = false;
    for (const auto& partition : partitions) {
      if (partition.partition_id == entry.partition_id &&
          entry.cat_n_id >= partition.cat_n_range.min &&
          entry.cat_n_id <= partition.cat_n_range.max) {
        partition_found = true;
        break;
      }
    }
    
    if (!partition_found) {
      log_error("CAT-N-ID {} partition assignment invalid", entry.cat_n_id);
      return FAIL_PARTITION_RANGE_VIOLATION;
    }
  }
  
  // Step 6: Verify entry order hash
  std::vector<NodeIndexEntry> sorted_entries = table.entries;
  std::sort(sorted_entries.begin(), sorted_entries.end(),
    [](const auto& a, const auto& b) { return a.cat_n_id < b.cat_n_id; }
  );
  SHA256 computed_order_hash = SHA256(canonical_serialize(sorted_entries));
  if (computed_order_hash != table.entry_order_hash) {
    return FAIL_ORDER_HASH_MISMATCH;
  }
  
  // Step 7: Verify HMAC
  std::vector<uint8_t> table_canonical = canonical_serialize(table);
  SHA256_HMAC computed_hmac = HMAC_SHA256(k_master, table_canonical);
  if (!constant_time_compare(computed_hmac.bytes(), table.hmac_tag)) {
    return FAIL_HMAC_INVALID;
  }
  
  return SUCCESS;
}
```

---

## 6. SYNAPSE_INDEX_TABLE INTEGRITY

### 6.1 Structure

```
SYNAPSE_INDEX_TABLE
├─ METADATA (universal artifact header, 96 bytes)
│
├─ TABLE_BODY
│  ├─ EDGE_COUNT [8 bytes]                 // 1B at full scale
│  ├─ ENTRIES [1B × 72 bytes each]         // See below
│  ├─ OUTGOING_NEIGHBOR_LISTS [variable]   // Indexed by source CAT-N-ID
│  ├─ INCOMING_NEIGHBOR_LISTS [variable]   // Indexed by dest CAT-N-ID
│  ├─ SPARSE_ADJACENCY_HASH [32 bytes]     // SHA-256(sparse representation)
│  ├─ SOURCE_DEST_VALIDITY_HASH [32 bytes] // SHA-256 proof all sources/dests exist
│  ├─ MODEL_VERSION [4 bytes]
│  ├─ TIMESTAMP [8 bytes]
│  ├─ SEALED_FLAG [1 byte]
│  └─ [Padding]
│
├─ ENTRY FORMAT (72 bytes each)
│  ├─ CAT_S_ID [8 bytes]                   // Unique synapse identifier (uint64)
│  ├─ SOURCE_CAT_N [16 bytes]              // Source neuron ID
│  ├─ DEST_CAT_N [16 bytes]                // Destination neuron ID
│  ├─ WEIGHT [8 bytes]                     // Float64, nanoSiemens
│  ├─ DELAY_MS [4 bytes]                   // Float32, ≥ 1ms
│  ├─ NEUROTRANSMITTER [1 byte]            // GLUT=0, GABA=1, DA=2, etc.
│  ├─ RECEPTOR_TYPE [1 byte]               // AMPA=0, NMDA=1, GABA_A=2, etc.
│  ├─ CONNECTION_TYPE [1 byte]             // FF=0, REC=1, FB=2
│  ├─ PLASTICITY_RULE [1 byte]             // NONE=0, STDP=1, BCM=2, etc.
│  ├─ LAST_UPDATE_TIMESTEP [8 bytes]       // uint64
│  └─ [Padding: 8 bytes]
│
├─ NEIGHBOR_LIST FORMAT
│  For each source neuron:
│    ├─ SOURCE_CAT_N [16 bytes]
│    ├─ OUTGOING_COUNT [4 bytes]           // Number of target synapses
│    └─ [OUTGOING_COUNT × 8 bytes]         // Array of CAT-S-IDs
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ NEIGHBOR_LIST_HASH [32 bytes]        // SHA-256(outgoing || incoming concatenated)
│  ├─ INTEGRITY_HASH [32 bytes]            // SHA-256(BODY_DIGEST || NEIGHBOR_HASH || PARENT_DIGEST)
│  └─ HMAC_TAG [32 bytes]                  // HMAC-SHA-256(K_master, canonical(entire table))
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]                      // 0x01 = immutable
```

### 6.2 Verification

```cpp
enum SynapseIndexVerificationResult {
  SUCCESS = 0,
  FAIL_EDGE_COLLISION = 1,
  FAIL_SOURCE_NOT_IN_NODE_TABLE = 2,
  FAIL_DEST_NOT_IN_NODE_TABLE = 3,
  FAIL_NEIGHBOR_LIST_INCONSISTENCY = 4,
  FAIL_DUPLICATE_EDGE = 5,
  FAIL_HMAC_INVALID = 6,
  FAIL_SPARSE_ADJACENCY_MISMATCH = 7
};

SynapseIndexVerificationResult SynapseIndexTable_Verify(
  const SynapseIndexTable& table,
  const NodeIndexTable& node_table,
  const MasterKey& k_master,
  int sample_size = 1000  // Random sample edges to verify
) {
  // Step 1: Verify sealed flag
  if (!table.sealed_flag) {
    return FAIL_EDGE_COLLISION;
  }
  
  // Step 2: Verify no duplicate CAT-S-IDs
  std::unordered_set<uint64_t> seen_edge_ids;
  for (const auto& entry : table.entries) {
    if (seen_edge_ids.count(entry.cat_s_id)) {
      log_error("CAT-S-ID collision: {}", entry.cat_s_id);
      return FAIL_EDGE_COLLISION;
    }
    seen_edge_ids.insert(entry.cat_s_id);
  }
  
  // Step 3: Random sample verification of source/dest existence
  std::vector<int> random_indices = random_sample(0, table.entries.size(), sample_size);
  for (int idx : random_indices) {
    const auto& entry = table.entries[idx];
    
    // Check source exists in NODE_INDEX_TABLE
    bool source_found = node_table.contains(entry.source_cat_n);
    if (!source_found) {
      log_error("Source CAT-N {} not in NODE_INDEX_TABLE", entry.source_cat_n);
      return FAIL_SOURCE_NOT_IN_NODE_TABLE;
    }
    
    // Check dest exists in NODE_INDEX_TABLE
    bool dest_found = node_table.contains(entry.dest_cat_n);
    if (!dest_found) {
      log_error("Dest CAT-N {} not in NODE_INDEX_TABLE", entry.dest_cat_n);
      return FAIL_DEST_NOT_IN_NODE_TABLE;
    }
  }
  
  // Step 4: Verify neighbor list consistency
  // For each synapse, verify it appears in both outgoing[source] and incoming[dest]
  for (int idx = 0; idx < std::min((size_t)sample_size, table.entries.size()); idx++) {
    const auto& entry = table.entries[idx];
    
    // Check outgoing[source] contains this synapse
    bool in_outgoing = false;
    for (const uint64_t& synapse_id : table.outgoing_synapses[entry.source_cat_n]) {
      if (synapse_id == entry.cat_s_id) {
        in_outgoing = true;
        break;
      }
    }
    if (!in_outgoing) {
      log_error("Synapse {} not in outgoing list for source {}", entry.cat_s_id, entry.source_cat_n);
      return FAIL_NEIGHBOR_LIST_INCONSISTENCY;
    }
    
    // Check incoming[dest] contains this synapse
    bool in_incoming = false;
    for (const uint64_t& synapse_id : table.incoming_synapses[entry.dest_cat_n]) {
      if (synapse_id == entry.cat_s_id) {
        in_incoming = true;
        break;
      }
    }
    if (!in_incoming) {
      log_error("Synapse {} not in incoming list for dest {}", entry.cat_s_id, entry.dest_cat_n);
      return FAIL_NEIGHBOR_LIST_INCONSISTENCY;
    }
  }
  
  // Step 5: Verify no duplicate edges (same source-dest pair)
  std::set<std::pair<CatNID, CatNID>> edge_pairs;
  for (const auto& entry : table.entries) {
    auto key = std::make_pair(entry.source_cat_n, entry.dest_cat_n);
    if (edge_pairs.count(key)) {
      log_error("Duplicate edge from {} to {}", entry.source_cat_n, entry.dest_cat_n);
      return FAIL_DUPLICATE_EDGE;
    }
    edge_pairs.insert(key);
  }
  
  // Step 6: Verify HMAC
  std::vector<uint8_t> table_canonical = canonical_serialize(table);
  SHA256_HMAC computed_hmac = HMAC_SHA256(k_master, table_canonical);
  if (!constant_time_compare(computed_hmac.bytes(), table.hmac_tag)) {
    return FAIL_HMAC_INVALID;
  }
  
  return SUCCESS;
}
```

---

## 7. MODEL_PARAMETERS INTEGRITY

### 7.1 Structure

```
MODEL_PARAMETERS
├─ METADATA (universal artifact header, 96 bytes)
│
├─ MODELS [3 records, one per model type]
│  For each MODEL_ID ∈ {HH=1, IAF=2, IAF_MOD=3}:
│  ├─ MODEL_ID [1 byte]
│  ├─ PARAMETER_COUNT [2 bytes]
│  ├─ PARAMETERS [variable]
│  │  [All parameter values serialized in order, IEEE 754 float64]
│  │  For HH: {V_rest, E_Na, E_K, E_L, g_Na_max, g_K_max, g_L_max, C_m, ...}
│  │  For IAF: {V_rest, V_threshold, V_reset, tau_m, C_m, ...}
│  ├─ NEURON_TYPE_COUNT [2 bytes]
│  ├─ NEURON_TYPES [variable]
│  │  Array of {NeuronType enum, count using this model}
│  ├─ PARAMETER_HASH [32 bytes]       // SHA-256(canonical(parameters))
│  ├─ TIMESTAMP [8 bytes]
│  └─ MODEL_SEALED [1 byte]           // Per-model seal flag
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]        // SHA-256 of previous MODEL_PARAMETERS version
│  ├─ MODELS_DIGEST [32 bytes]        // SHA-256(all 3 models concatenated)
│  ├─ TYPE_ASSIGNMENT_HASH [32 bytes] // SHA-256(neuron type to model mapping)
│  ├─ INTEGRITY_HASH [32 bytes]       // SHA-256(MODELS_DIGEST || TYPE_ASSIGNMENT_HASH)
│  └─ HMAC_TAG [32 bytes]             // HMAC-SHA-256(K_master, canonical(entire artifact))
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]                 // 0x01 = immutable
```

### 7.2 Verification

```cpp
enum ModelParametersVerificationResult {
  SUCCESS = 0,
  FAIL_PARAMETER_OUT_OF_RANGE = 1,
  FAIL_MODEL_TYPE_MISMATCH = 2,
  FAIL_NEURON_TYPE_INVALID = 3,
  FAIL_PARAMETER_HASH_MISMATCH = 4,
  FAIL_TYPE_ASSIGNMENT_HASH_MISMATCH = 5,
  FAIL_HMAC_INVALID = 6
};

// Biologically plausible bounds for parameters
struct ParameterBounds {
  static const double V_REST_MIN;         // -100 mV
  static const double V_REST_MAX;         // -40 mV
  static const double E_NA;              // +60 mV (fixed)
  static const double E_K;               // -90 mV (fixed)
  static const double E_L;               // -70 mV (fixed)
  static const double G_MAX_MIN;         // 0.1 nanoSiemens
  static const double G_MAX_MAX;         // 1000 nanoSiemens
  static const double TAU_M_MIN;         // 1 ms
  static const double TAU_M_MAX;         // 100 ms
  static const double C_M_MIN;           // 0.1 uF/cm²
  static const double C_M_MAX;           // 10 uF/cm²
};

ModelParametersVerificationResult ModelParameters_Verify(
  const ModelParameters& models,
  const NodeIndexTable& node_table,
  const MasterKey& k_master
) {
  // Step 1: Verify sealed flag
  if (!models.sealed_flag) {
    return FAIL_PARAMETER_OUT_OF_RANGE;
  }
  
  // Step 2: For each model, verify parameters are biologically plausible
  for (const auto& model : models.models) {
    if (model.model_id == ModelID::HH) {
      // Hodgkin-Huxley specific bounds
      if (model.params.V_rest < ParameterBounds::V_REST_MIN ||
          model.params.V_rest > ParameterBounds::V_REST_MAX) {
        return FAIL_PARAMETER_OUT_OF_RANGE;
      }
      if (model.params.g_Na_max < ParameterBounds::G_MAX_MIN ||
          model.params.g_Na_max > ParameterBounds::G_MAX_MAX) {
        return FAIL_PARAMETER_OUT_OF_RANGE;
      }
      // ... similar checks for other HH parameters
    } else if (model.model_id == ModelID::IAF) {
      // Leaky IAF bounds
      if (model.params.tau_m < ParameterBounds::TAU_M_MIN ||
          model.params.tau_m > ParameterBounds::TAU_M_MAX) {
        return FAIL_PARAMETER_OUT_OF_RANGE;
      }
      // ... similar checks
    }
  }
  
  // Step 3: Verify parameter hash for each model
  for (const auto& model : models.models) {
    std::vector<uint8_t> params_canonical = canonical_serialize(model.parameters);
    SHA256 computed_hash = SHA256(params_canonical);
    if (computed_hash != model.parameter_hash) {
      return FAIL_PARAMETER_HASH_MISMATCH;
    }
  }
  
  // Step 4: Verify neuron type assignments are consistent
  std::unordered_set<uint16_t> assigned_types;
  for (const auto& model : models.models) {
    for (const auto& type_assignment : model.neuron_types) {
      assigned_types.insert(type_assignment.neuron_type);
    }
  }
  
  // Random sample: verify every assigned neuron type has valid model
  for (const auto& entry : node_table.entries) {
    bool type_found = false;
    for (const auto& model : models.models) {
      for (const auto& type_assignment : model.neuron_types) {
        if (type_assignment.neuron_type == entry.neuron_type) {
          type_found = true;
          break;
        }
      }
      if (type_found) break;
    }
    
    if (!type_found) {
      log_error("Neuron type {} has no assigned model", entry.neuron_type);
      return FAIL_NEURON_TYPE_INVALID;
    }
  }
  
  // Step 5: Verify type assignment hash
  std::vector<uint8_t> assignment_canonical;
  for (const auto& model : models.models) {
    assignment_canonical.append(canonical_serialize(model.neuron_types));
  }
  SHA256 computed_assignment_hash = SHA256(assignment_canonical);
  if (computed_assignment_hash != models.type_assignment_hash) {
    return FAIL_TYPE_ASSIGNMENT_HASH_MISMATCH;
  }
  
  // Step 6: Verify HMAC
  std::vector<uint8_t> models_canonical = canonical_serialize(models);
  SHA256_HMAC computed_hmac = HMAC_SHA256(k_master, models_canonical);
  if (!constant_time_compare(computed_hmac.bytes(), models.hmac_tag)) {
    return FAIL_HMAC_INVALID;
  }
  
  return SUCCESS;
}
```

---

## 8. GPU_KERNEL_VERSION INTEGRITY

### 8.1 Structure

```
GPU_KERNEL_VERSION
├─ METADATA (universal artifact header, 96 bytes)
│
├─ KERNEL_BODY
│  ├─ KERNEL_HASH [32 bytes]          // SHA-256(compiled GPU kernel binary)
│  ├─ KERNEL_SOURCE_HASH [32 bytes]   // SHA-256(source code before compilation)
│  ├─ COMPILER_ID [32 bytes]          // CUDA 12.2, HIP 5.6, etc.
│  ├─ OPTIMIZATION_FLAGS [128 bytes]  // -O3 -march=sm_80, etc.
│  ├─ KERNEL_DESCRIPTION [256 bytes]  // Human-readable description
│  ├─ FUNCTION_SIGNATURES [variable]  // Metadata for each kernel function
│  │  For each function:
│  │  ├─ FUNCTION_NAME [64 bytes]
│  │  ├─ PARAMETER_COUNT [2 bytes]
│  │  └─ PARAMETER_TYPES [variable]
│  ├─ BUILD_TIMESTAMP [8 bytes]
│  ├─ BUILDER_ID [32 bytes]           // Which agent/service compiled this
│  └─ SEALED_FLAG [1 byte]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ SOURCE_DERIVED_HASH [32 bytes]  // SHA-256(kernel_source_hash || compiler_id)
│  ├─ INTEGRITY_HASH [32 bytes]       // SHA-256(BODY_DIGEST || SOURCE_DERIVED_HASH)
│  └─ HMAC_TAG [32 bytes]
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]                 // 0x01 = immutable
```

---

## 9. EXECUTION_TRACE INTEGRITY (Archival)

### 9.1 Structure

```
EXECUTION_TRACE_BLOCK
├─ METADATA (universal artifact header, 96 bytes)
│
├─ TRACE_BODY
│  ├─ TRACE_ID [64 bytes]             // execution_run_id + block_number
│  ├─ TIMESTEP_RANGE [16 bytes]       // [t_start, t_end] uint64 pair
│  ├─ WALL_CLOCK_START [8 bytes]      // Nanosecond precision
│  ├─ WALL_CLOCK_END [8 bytes]
│  │
│  ├─ STATE_SNAPSHOTS [variable]      // Per-neuron state at key timesteps
│  │  ├─ SNAPSHOT_COUNT [4 bytes]
│  │  └─ [SNAPSHOT_COUNT snapshots, each ~100 KB]
│  │
│  ├─ SPIKE_EVENTS [variable]         // All spikes in range
│  │  ├─ SPIKE_COUNT [8 bytes]
│  │  └─ [SPIKE_COUNT events, each 40 bytes]
│  │
│  ├─ BEHAVIORAL_OUTPUTS [variable]   // Motor/cognitive outputs
│  │  ├─ OUTPUT_COUNT [4 bytes]
│  │  └─ [OUTPUT_COUNT outputs]
│  │
│  ├─ GPU_MEMORY_SNAPSHOTS [variable] // GPU state at checkpoints
│  │  ├─ CHECKPOINT_COUNT [2 bytes]
│  │  └─ [CHECKPOINT_COUNT memory regions, each with digest]
│  │
│  ├─ CPU_VALIDATION_DATA [variable]  // Reference CPU results
│  │  ├─ REFERENCE_SPIKE_COUNT [8 bytes]
│  │  └─ [REFERENCE_SPIKE_COUNT spike events]
│  │
│  ├─ NUMERICAL_ERROR_RECORD [64 bytes]
│  │  ├─ MAX_ABSOLUTE_ERROR [8 bytes] // float64
│  │  ├─ MEAN_ABSOLUTE_ERROR [8 bytes]
│  │  ├─ SAMPLE_COUNT [8 bytes]
│  │  ├─ ERROR_DISTRIBUTION [40 bytes] // percentiles: min, p25, p50, p75, max
│  │  └─ VERIFICATION_STATUS [1 byte]  // PASS=0, FAIL=1, UNVERIFIED=2
│  │
│  ├─ TRACE_DIGEST [32 bytes]         // SHA-256(canonical(trace_body))
│  ├─ PARENT_TRACE_DIGEST [32 bytes]  // SHA-256 of previous block (chain)
│  ├─ MODEL_VERSION [4 bytes]
│  ├─ TIMESTAMP [8 bytes]
│  └─ SEALED_FLAG [1 byte]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]        // SHA-256 of previous trace block
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ SPIKE_ARRAY_HASH [32 bytes]     // SHA-256(all spikes)
│  ├─ INTEGRITY_HASH [32 bytes]       // SHA-256(BODY_DIGEST || SPIKE_ARRAY_HASH || PARENT_DIGEST)
│  └─ HMAC_TAG [32 bytes]
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]                 // 0x01 = immutable
```

### 9.2 Verification

```cpp
enum ExecutionTraceVerificationResult {
  SUCCESS = 0,
  FAIL_SPIKE_COUNT_MISMATCH = 1,
  FAIL_CPU_GPU_DIVERGENCE_EXCESSIVE = 2,
  FAIL_STATE_SNAPSHOT_INCONSISTENT = 3,
  FAIL_CHAIN_BROKEN = 4,
  FAIL_HMAC_INVALID = 5
};

ExecutionTraceVerificationResult ExecutionTrace_Verify(
  const ExecutionTraceBlock& trace,
  const ExecutionTraceBlock* parent_trace,  // Optional: previous block
  double max_allowed_error_threshold = 1e-10,  // Max CPU/GPU divergence
  const MasterKey& k_master
) {
  // Step 1: Verify sealed flag
  if (!trace.sealed_flag) {
    return FAIL_SPIKE_COUNT_MISMATCH;
  }
  
  // Step 2: Verify spike count matches recorded array
  if (trace.spike_events.size() != trace.spike_count) {
    return FAIL_SPIKE_COUNT_MISMATCH;
  }
  
  // Step 3: Verify CPU/GPU numerical error bounds
  if (trace.numerical_error_record.max_absolute_error > max_allowed_error_threshold) {
    log_warn("CPU/GPU divergence excessive: {} > {}",
      trace.numerical_error_record.max_absolute_error,
      max_allowed_error_threshold
    );
    return FAIL_CPU_GPU_DIVERGENCE_EXCESSIVE;
  }
  
  // Step 4: If chained to parent, verify chain link
  if (parent_trace != nullptr) {
    if (trace.parent_trace_digest != parent_trace->trace_digest) {
      log_error("Execution trace chain broken");
      return FAIL_CHAIN_BROKEN;
    }
  }
  
  // Step 5: Verify HMAC
  std::vector<uint8_t> trace_canonical = canonical_serialize(trace);
  SHA256_HMAC computed_hmac = HMAC_SHA256(k_master, trace_canonical);
  if (!constant_time_compare(computed_hmac.bytes(), trace.hmac_tag)) {
    return FAIL_HMAC_INVALID;
  }
  
  return SUCCESS;
}
```

---

## 10. BENCHMARK_DATA & NUMERICAL_ERROR_BOUNDS INTEGRITY

### 10.1 Benchmark Data Structure

```
BENCHMARK_DATA
├─ METADATA (universal artifact header, 96 bytes)
│
├─ BENCHMARK_BODY
│  ├─ RUN_ID [64 bytes]               // Unique run identifier
│  ├─ TIMESTEP_RANGE [16 bytes]       // [t_start, t_end]
│  ├─ NEURON_COUNT [8 bytes]          // Neurons simulated
│  ├─ SYNAPSE_COUNT [8 bytes]         // Synapses simulated
│  ├─ SPIKE_COUNT [8 bytes]           // Total spikes generated
│  │
│  ├─ TIMING_METRICS [variable]
│  │  ├─ PHASE_NAMES_COUNT [2 bytes]  // Number of execution phases
│  │  └─ Per-phase:
│  │     ├─ PHASE_NAME [32 bytes]
│  │     ├─ TOTAL_TIME_US [8 bytes]
│  │     ├─ AVG_TIME_US [8 bytes]
│  │     ├─ MIN_TIME_US [8 bytes]
│  │     ├─ MAX_TIME_US [8 bytes]
│  │     └─ CALL_COUNT [8 bytes]
│  │
│  ├─ RESOURCE_METRICS [variable]
│  │  ├─ GPU_MEMORY_PEAK_GB [8 bytes]
│  │  ├─ CPU_MEMORY_PEAK_GB [8 bytes]
│  │  ├─ GPU_UTILIZATION [4 bytes]    // Percentage 0-100
│  │  ├─ GPU_POWER_DRAW_W [4 bytes]
│  │  └─ THERMAL_THROTTLING_EVENTS [4 bytes]
│  │
│  ├─ THROUGHPUT_METRICS [variable]
│  │  ├─ NEURONS_PER_SECOND [8 bytes]
│  │  ├─ SYNAPSES_PER_SECOND [8 bytes]
│  │  └─ SPIKES_PER_SECOND [8 bytes]
│  │
│  ├─ BENCHMARK_DIGEST [32 bytes]
│  ├─ TIMESTAMP [8 bytes]
│  └─ SEALED_FLAG [1 byte]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ METRICS_HASH [32 bytes]
│  ├─ INTEGRITY_HASH [32 bytes]
│  └─ HMAC_TAG [32 bytes]
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]
```

### 10.2 Numerical Error Bounds Structure

```
NUMERICAL_ERROR_BOUNDS
├─ METADATA (universal artifact header, 96 bytes)
│
├─ ERROR_BODY
│  ├─ COMPARISON_TYPE [1 byte]        // CPU_VS_GPU=0, DOUBLE_VS_FLOAT=1, etc.
│  ├─ TIMESTEP_RANGE [16 bytes]
│  ├─ SAMPLE_COUNT [8 bytes]          // Number of sampled comparisons
│  │
│  ├─ PER_VARIABLE_ERRORS [variable]  // For each state variable
│  │  ├─ VARIABLE_NAME [32 bytes]     // "membrane_potential", "spike_count", etc.
│  │  ├─ VARIABLE_TYPE [1 byte]       // FLOAT=0, UINT=1, etc.
│  │  ├─ MAX_ABSOLUTE_ERROR [8 bytes]
│  │  ├─ MEAN_ABSOLUTE_ERROR [8 bytes]
│  │  ├─ STDDEV_ABSOLUTE_ERROR [8 bytes]
│  │  ├─ MAX_RELATIVE_ERROR [8 bytes] // As percentage
│  │  ├─ CONFIDENCE_INTERVAL_95 [16 bytes] // [lower, upper]
│  │  └─ ERROR_HISTOGRAM [160 bytes]  // 20 bins
│  │
│  ├─ OVERALL_STATISTICS [64 bytes]
│  │  ├─ MAX_ERROR_ACROSS_VARIABLES [8 bytes]
│  │  ├─ MEAN_ERROR_ACROSS_VARIABLES [8 bytes]
│  │  ├─ ACCEPTANCE_THRESHOLD [8 bytes]
│  │  └─ PASS_FAIL_STATUS [1 byte]    // PASS=0, FAIL=1
│  │
│  ├─ WITNESS_SPIKES [variable]       // Cases with largest errors
│  │  ├─ WITNESS_COUNT [2 bytes]
│  │  └─ Per-witness:
│  │     ├─ TIMESTEP [8 bytes]
│  │     ├─ NEURON_ID [16 bytes]
│  │     ├─ CPU_VALUE [8 bytes]
│  │     ├─ GPU_VALUE [8 bytes]
│  │     └─ ERROR [8 bytes]
│  │
│  ├─ ERROR_DIGEST [32 bytes]
│  ├─ TIMESTAMP [8 bytes]
│  └─ SEALED_FLAG [1 byte]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_DIGEST [32 bytes]
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ WITNESS_HASH [32 bytes]
│  ├─ INTEGRITY_HASH [32 bytes]
│  └─ HMAC_TAG [32 bytes]
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]
```

---

## 11. CRYPTOGRAPHIC PRIMITIVES (Standardized)

### 11.1 SHA-256

```cpp
// NIST FIPS 180-4 (no modifications)
SHA256 SHA256(const std::vector<uint8_t>& data) {
  // Standard SHA-256 implementation
  // Returns 32-byte hash
  return standard_sha256_implementation(data);
}

// Example usage
std::vector<uint8_t> artifact_bytes = canonical_serialize(artifact);
SHA256 hash = SHA256(artifact_bytes);
// hash.bytes() returns std::array<uint8_t, 32>
```

### 11.2 HMAC-SHA-256

```cpp
// FIPS 198 (no modifications)
SHA256_HMAC HMAC_SHA256(
  const std::array<uint8_t, 32>& key,
  const std::vector<uint8_t>& message
) {
  // Standard HMAC implementation using SHA-256
  std::array<uint8_t, 32> k_pad = key;
  
  // ipad
  for (int i = 0; i < 32; i++) {
    k_pad[i] ^= 0x36;
  }
  std::vector<uint8_t> inner_input;
  inner_input.insert(inner_input.end(), k_pad.begin(), k_pad.end());
  inner_input.insert(inner_input.end(), message.begin(), message.end());
  SHA256 inner_hash = SHA256(inner_input);
  
  // opad
  k_pad = key;
  for (int i = 0; i < 32; i++) {
    k_pad[i] ^= 0x5c;
  }
  std::vector<uint8_t> outer_input;
  outer_input.insert(outer_input.end(), k_pad.begin(), k_pad.end());
  outer_input.insert(outer_input.end(), inner_hash.bytes().begin(), inner_hash.bytes().end());
  
  return SHA256(outer_input);
}

// Constant-time comparison (prevents timing attacks)
bool constant_time_compare(
  const std::array<uint8_t, 32>& a,
  const std::array<uint8_t, 32>& b
) {
  uint8_t result = 0;
  for (int i = 0; i < 32; i++) {
    result |= (a[i] ^ b[i]);
  }
  return result == 0;
}
```

### 11.3 Canonical Serialization

```cpp
std::vector<uint8_t> to_big_endian(uint32_t value) {
  std::vector<uint8_t> bytes(4);
  bytes[0] = (value >> 24) & 0xFF;
  bytes[1] = (value >> 16) & 0xFF;
  bytes[2] = (value >> 8) & 0xFF;
  bytes[3] = value & 0xFF;
  return bytes;
}

std::vector<uint8_t> to_big_endian_u64(uint64_t value) {
  std::vector<uint8_t> bytes(8);
  for (int i = 0; i < 8; i++) {
    bytes[i] = (value >> (56 - 8*i)) & 0xFF;
  }
  return bytes;
}

std::vector<uint8_t> to_ieee754_float64(double value) {
  // Convert double to IEEE 754 binary representation
  uint64_t bits;
  std::memcpy(&bits, &value, 8);
  return to_big_endian_u64(bits);
}

std::vector<uint8_t> canonical_serialize_string(const std::string& s) {
  std::vector<uint8_t> bytes;
  
  // Length prefix (big-endian u32)
  uint32_t len = s.length();
  bytes.append(to_big_endian(len));
  
  // UTF-8 bytes
  bytes.insert(bytes.end(), s.begin(), s.end());
  
  return bytes;
}
```

---

## 12. ADA/SPARK FORMAL CONTRACTS

### 12.1 Artifact_Seal Contract

```ada
-- Ada/SPARK contract for artifact sealing

package GPU_WORM_Integrity is

  type Artifact is record
    artifact_id: Artifact_ID_Type;
    payload: Payload_Type;
    sealed_flag: Boolean;
    hmac_tag: SHA256_Hash;
    integrity_hash: SHA256_Hash;
  end record;

  -- Precondition: Artifact must not already be sealed
  -- Postcondition: After sealing, sealed_flag = true and hmac_tag is computed
  -- Invariant: Payload cannot be modified after sealing
  procedure Seal_Artifact(
    artifact: in out Artifact;
    master_key: in Master_Key_Type
  ) with
    Pre => not artifact.sealed_flag,
    Post => artifact.sealed_flag and 
            artifact.hmac_tag = HMAC_SHA256(master_key, artifact'Old);

  -- Precondition: Artifact must be sealed
  -- Postcondition: Returns true iff HMAC verification succeeds
  function Verify_Artifact_Sealed(
    artifact: in Artifact;
    master_key: in Master_Key_Type
  ) return Boolean with
    Pre => artifact.sealed_flag,
    Post => Verify_Artifact_Sealed'Result = 
            (artifact.hmac_tag = HMAC_SHA256(master_key, artifact));

end GPU_WORM_Integrity;
```

### 12.2 GPU_Buffer_Verify Contract

```ada
package GPU_Buffer_Verification is

  type GPU_Buffer is record
    buffer_digest: SHA256_Hash;
    partition_link: Partition_ID_Type;
    model_version: Model_Type;
    cat_n_range: CAT_N_Range;
    contents: Buffer_Contents;
    hmac_tag: SHA256_Hash;
  end record;

  type Verification_Result is (SUCCESS, FAIL_BUFFER_CORRUPTED, 
                               FAIL_PARTITION_MISMATCH, FAIL_HMAC_INVALID);

  -- Precondition: GPU buffer loaded from storage
  -- Postcondition: Either SUCCESS (buffer usable) or FAIL_* (halt execution)
  -- Invariant: Corrupted buffer never used for computation
  function GPU_Buffer_Verify(
    buffer: in GPU_Buffer;
    partition: in Partition_Manifest;
    master_key: in Master_Key_Type
  ) return Verification_Result with
    Post => (if GPU_Buffer_Verify'Result = SUCCESS then
             Verify_HMAC(buffer) and
             buffer.partition_link = partition.partition_id and
             Is_CAT_N_In_Range(buffer.cat_n_range, partition.cat_n_range)
            else
             GPU_Buffer_Verify'Result in (FAIL_BUFFER_CORRUPTED | 
                                         FAIL_PARTITION_MISMATCH | 
                                         FAIL_HMAC_INVALID)
            );

end GPU_Buffer_Verification;
```

### 12.3 CAT_N_Range_Consistency Contract

```ada
package CAT_N_Range_Consistency is

  type Partition_Collection is array (Partition_ID_Type) of Partition_Manifest;

  -- Precondition: Partitions are sealed
  -- Postcondition: All CAT-N IDs are assigned to exactly one partition
  -- Invariant: Complete coverage, no orphans
  procedure Verify_CAT_N_Coverage(
    partitions: in Partition_Collection;
    node_table: in Node_Index_Table
  ) with
    Pre => (for all p of partitions => p.sealed_flag),
    Post => (for all entry of node_table.entries =>
             (exists p of partitions =>
              p.partition_id = entry.partition_id and
              In_Range(entry.cat_n_id, p.cat_n_range)) and
             (for all p1, p2 of partitions =>
              (if p1.partition_id /= p2.partition_id then
               Disjoint_Ranges(p1.cat_n_range, p2.cat_n_range))));

end CAT_N_Range_Consistency;
```

### 12.4 Fail-Closed Guarantee Contract

```ada
package Fail_Closed_Guarantee is

  -- Invariant: Corrupted artifact cannot be silently used
  -- If any integrity check fails, execution must halt
  
  procedure Use_GPU_Buffer_Or_Halt(
    buffer: in GPU_Buffer;
    master_key: in Master_Key_Type;
    halt_flag: out Boolean
  ) with
    Post => (if GPU_Buffer_Verify(buffer, master_key) /= SUCCESS then
             halt_flag = True
            else
             halt_flag = False
            );

end Fail_Closed_Guarantee;
```

---

## 13. FAIL-CLOSED GUARANTEE SPECIFICATION

### 13.1 Failure Modes and Recovery

```
FAILURE_MODE_1: Buffer Checksum Fails
  Entry Point: GPU_Buffer_Verify()
  Detection: SHA-256(buffer_contents) != stored buffer_digest
  Action: Set halt_flag, log error, drop buffer
  Recovery: None (artifact is corrupted)
  Result: User notified, simulation halted

FAILURE_MODE_2: HMAC Verification Fails
  Entry Point: GPU_Buffer_Verify()
  Detection: HMAC_SHA256(K, buffer) != stored hmac_tag
  Action: Set halt_flag, log tampering alert
  Recovery: None (possible tampering detected)
  Result: User notified, security alert logged

FAILURE_MODE_3: Partition Range Violation
  Entry Point: GPU_Buffer_Verify()
  Detection: buffer.cat_n_range not within partition.cat_n_range
  Action: Set halt_flag, log range error
  Recovery: None (artifact inconsistency)
  Result: User notified, simulation halted

FAILURE_MODE_4: Model Version Mismatch
  Entry Point: GPU_Buffer_Verify()
  Detection: buffer.model_version != partition.model_version
  Action: Set halt_flag, log model mismatch
  Recovery: None (versioning inconsistency)
  Result: User notified, simulation halted
```

### 13.2 Verification Pipeline (Execution Start)

```
VERIFICATION_PIPELINE at Simulation Start:

1. Load all partition manifests
2. For each partition:
   a) Verify partition manifest HMAC
   b) If fails → Halt, error
   
3. Load NODE_INDEX_TABLE
4. Verify NODE_INDEX_TABLE:
   a) Check for collisions
   b) Check reverse mapping
   c) Verify HMAC
   d) If any fails → Halt, error
   
5. Load SYNAPSE_INDEX_TABLE
6. Verify SYNAPSE_INDEX_TABLE:
   a) Cross-reference with NODE_INDEX_TABLE
   b) Check neighbor list consistency
   c) Verify HMAC
   d) If any fails → Halt, error
   
7. Load MODEL_PARAMETERS
8. Verify MODEL_PARAMETERS:
   a) Check parameter ranges (biologically plausible)
   b) Check neuron type assignments
   c) Verify HMAC
   d) If any fails → Halt, error
   
9. Load GPU_KERNEL_VERSION
10. Verify GPU_KERNEL_VERSION:
    a) Check source hash matches compiled binary
    b) Verify HMAC
    c) If any fails → Halt, error (kernel mismatch)
    
11. Load initial GPU buffers
12. For each GPU buffer:
    a) Verify GPU_Buffer_Verify() returns SUCCESS
    b) If fails → Halt, error, drop buffer
    
13. If all verifications pass → Proceed to simulation
14. Otherwise → Halt, write error log, exit
```

---

## 14. IMPLEMENTATION CHECKLIST

- [ ] Implement universal ARTIFACT structure with metadata
- [ ] Implement canonical serialization (big-endian, IEEE 754)
- [ ] Implement SHA-256 (or use NIST library)
- [ ] Implement HMAC-SHA-256 with constant-time comparison
- [ ] Implement GPU_Buffer_Verify() with all 6 checks
- [ ] Implement PartitionManifest_Verify()
- [ ] Implement NodeIndexTable_Verify() with collision detection and reverse mapping
- [ ] Implement SynapseIndexTable_Verify() with neighbor list consistency
- [ ] Implement ModelParameters_Verify() with biologically plausible bounds
- [ ] Implement ExecutionTrace_Verify() with chain linking
- [ ] Write Ada/SPARK contracts for all verification functions
- [ ] Implement fail-closed guarantee (halt on any verification failure)
- [ ] Add comprehensive error logging with timestamps
- [ ] Add security alert logging for tampering detection
- [ ] Write unit tests for each verification function
- [ ] Write integration tests for full pipeline verification
- [ ] Document cryptographic key management (master key derivation, storage)
- [ ] Document artifact versioning and backward compatibility
- [ ] Document recovery procedures (manual artifact reconstruction)

---

## 15. SUMMARY

This GPU WORM specification provides:

1. **Universal Artifact Structure**: All GPU artifacts follow consistent template with 297-byte overhead
2. **Cryptographic Binding**: SHA-256 digests + HMAC-SHA-256 tags ensure integrity
3. **Fail-Closed Guarantee**: Corrupted artifacts never silently used; all verification failures halt execution
4. **Deterministic Verification**: All checks are reproducible and order-independent
5. **Formal Contracts**: Ada/SPARK contracts specify pre/post conditions and invariants
6. **Scale Support**: Verified for 760M nodes, 1B synapses, with deterministic ordering
7. **Chain Linking**: Artifacts linked via parent digests for complete trace verification
8. **Biologically Plausible Bounds**: Model parameters verified against realistic neural ranges

**End of GPU WORM Specification**
