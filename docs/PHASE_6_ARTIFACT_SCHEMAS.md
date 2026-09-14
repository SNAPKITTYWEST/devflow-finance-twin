# PHASE 6: GPU WORM Artifact Schemas (Implementation Reference)

**Status**: SCHEMA DEFINITIONS  
**Date**: 2026-09-13  
**Purpose**: Precise byte-level artifact layouts for implementation and serialization  

---

## Schema Notation

```
Field_Name [size_bytes] : Description | Type

If field is compound:
Field_Name [size_bytes]
├─ Sub_Field_1 [size_bytes]
├─ Sub_Field_2 [size_bytes]
└─ Sub_Field_N [size_bytes]
```

All sizes in bytes. Byte order: **big-endian throughout** (network byte order).

---

## UNIVERSAL ARTIFACT HEADER (96 bytes)

Every GPU artifact begins with this header:

```
ARTIFACT_METADATA [96 bytes]
├─ artifact_id [32 bytes]                // Hierarchical ID, UTF-8 string, null-padded
├─ version_major [2 bytes]               // uint16_be
├─ version_minor [2 bytes]               // uint16_be
├─ version_patch [4 bytes]               // uint32_be (can include build number)
├─ creation_timestamp_ns [8 bytes]       // uint64_be (nanoseconds since UNIX epoch)
├─ creator_id [8 bytes]                  // uint64_be (agent identifier, e.g., 0x0600_0000_0000_0001 for PHASE_6)
├─ sealed_flag [1 byte]                  // 0x00=unsealed, 0x01=sealed
├─ model_version_hash [32 bytes]         // SHA-256 (binary)
└─ connectome_version_hash [32 bytes]    // SHA-256 (binary)
```

**Total**: 96 bytes exactly

---

## IDENTITY BLOCK (64 bytes)

Follows immediately after METADATA in all artifacts:

```
IDENTITY_BLOCK [64 bytes]
└─ description [64 bytes]                // UTF-8 string, null-padded (max 63 chars)
```

**Total**: 64 bytes exactly

---

## GPU_BUFFER SCHEMA

```
GPU_BUFFER
├─ BUFFER_METADATA [96 bytes]            // Universal header
├─ BUFFER_IDENTITY [64 bytes]            // "GPU_BUFFER for partition X, neurons [A, B]"
├─ BUFFER_BODY [variable, ≥ 128 bytes]
│  ├─ payload_size [8 bytes]             // uint64_be (size of buffer_contents below)
│  ├─ buffer_contents [payload_size]     // Actual neuron state or synapse data
│  ├─ partition_link [4 bytes]           // uint32_be (partition ID)
│  ├─ model_version [4 bytes]            // uint32_be (HH=1, IAF=2, IAF_MOD=3)
│  ├─ cat_n_range_min [16 bytes]         // CAT-N-ID (binary UUID)
│  └─ cat_n_range_max [16 bytes]         // CAT-N-ID (binary UUID)
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]           // SHA-256 (binary)
│  ├─ buffer_digest [32 bytes]           // SHA-256(buffer_contents)
│  ├─ range_hash [32 bytes]              // SHA-256(cat_n_range_min || cat_n_range_max)
│  ├─ integrity_hash [32 bytes]          // SHA-256(buffer_digest || range_hash || parent_digest)
│  └─ hmac_tag [32 bytes]                // HMAC-SHA-256
└─ SEAL [1 byte]
   └─ sealed [1 byte]                    // 0x01 = locked
```

**Minimum size**: 96 + 64 + 128 + 128 + 1 = 417 bytes

---

## NODE_INDEX_TABLE SCHEMA

```
NODE_INDEX_TABLE
├─ ARTIFACT_METADATA [96 bytes]          // Universal header
├─ IDENTITY_BLOCK [64 bytes]             // "NODE_INDEX_TABLE with 760M entries"
├─ TABLE_HEADER [32 bytes]
│  ├─ entry_count [8 bytes]              // uint64_be (760,000,000 at full scale)
│  ├─ hash_collision_count [4 bytes]     // uint32_be (must be 0)
│  ├─ table_sealed [1 byte]              // 0x01 = sealed
│  └─ [19 bytes padding]
├─ ENTRIES [entry_count × 56 bytes each]
│  └─ For each entry (56 bytes total):
│     ├─ cat_n_id [16 bytes]             // Binary UUID
│     ├─ global_index [8 bytes]          // uint64_be, range [0, 760M)
│     ├─ partition_id [4 bytes]          // uint32_be
│     ├─ local_index [4 bytes]           // uint32_be (position within partition)
│     ├─ neuron_type [2 bytes]           // uint16_be (enum)
│     ├─ firing_model [2 bytes]          // uint16_be (1=HH, 2=IAF, 3=IAF_MOD)
│     └─ region_id [2 bytes]             // uint16_be (enum)
├─ HASHES_BLOCK [96 bytes]
│  ├─ payload_digest [32 bytes]          // SHA-256(all entries concatenated)
│  ├─ entry_order_hash [32 bytes]        // SHA-256(sorted entries)
│  └─ reverse_mapping_hash [32 bytes]    // SHA-256(GLOBAL_INDEX → CAT-N-ID)
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]
│  ├─ body_digest [32 bytes]             // SHA-256(table_header || entries)
│  ├─ hashes_digest [32 bytes]           // SHA-256(hashes_block)
│  ├─ integrity_hash [32 bytes]          // SHA-256(body_digest || hashes_digest || parent_digest)
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Total size at 760M scale**: 96 + 64 + 32 + (760,000,000 × 56) + 96 + 128 + 1 = **42.56 TB**

---

## SYNAPSE_INDEX_TABLE SCHEMA

```
SYNAPSE_INDEX_TABLE
├─ ARTIFACT_METADATA [96 bytes]
├─ IDENTITY_BLOCK [64 bytes]             // "SYNAPSE_INDEX_TABLE with 1B edges"
├─ TABLE_HEADER [32 bytes]
│  ├─ edge_count [8 bytes]               // uint64_be (1,000,000,000 at full scale)
│  ├─ duplicate_edge_count [4 bytes]     // uint32_be (should be 0)
│  ├─ table_sealed [1 byte]
│  └─ [19 bytes padding]
├─ ENTRIES [edge_count × 72 bytes each]
│  └─ For each entry (72 bytes total):
│     ├─ cat_s_id [8 bytes]              // uint64_be, globally unique
│     ├─ source_cat_n [16 bytes]         // Binary UUID
│     ├─ dest_cat_n [16 bytes]           // Binary UUID
│     ├─ weight [8 bytes]                // float64_ieee754_be (nanoSiemens)
│     ├─ delay_ms [4 bytes]              // float32_ieee754_be (≥ 1.0 ms)
│     ├─ neurotransmitter [1 byte]       // enum (GLUT=0, GABA=1, DA=2, etc.)
│     ├─ receptor_type [1 byte]          // enum (AMPA=0, NMDA=1, GABA_A=2, etc.)
│     ├─ connection_type [1 byte]        // enum (FF=0, REC=1, FB=2)
│     ├─ plasticity_rule [1 byte]        // enum (NONE=0, STDP=1, BCM=2, etc.)
│     ├─ last_update_timestep [8 bytes]  // uint64_be
│     └─ [8 bytes padding]
├─ NEIGHBOR_LISTS_BLOCK [variable]
│  ├─ lists_count [4 bytes]              // uint32_be (total unique source neurons)
│  └─ For each source neuron:
│     ├─ source_cat_n [16 bytes]         // Binary UUID
│     ├─ outgoing_synapse_count [4 bytes] // uint32_be
│     └─ outgoing_cat_s_ids [outgoing_synapse_count × 8 bytes]
├─ HASHES_BLOCK [96 bytes]
│  ├─ entries_digest [32 bytes]          // SHA-256(all entries)
│  ├─ neighbor_lists_hash [32 bytes]     // SHA-256(neighbor lists)
│  └─ source_dest_validity_hash [32 bytes] // SHA-256 proof of validity
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]
│  ├─ body_digest [32 bytes]
│  ├─ lists_digest [32 bytes]
│  ├─ integrity_hash [32 bytes]
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Total size at 1B scale**: 96 + 64 + 32 + (1,000,000,000 × 72) + variable + 96 + 128 + 1 = **~72 TB base** + neighbor lists

---

## PARTITION_MANIFEST SCHEMA

```
PARTITION_MANIFEST
├─ ARTIFACT_METADATA [96 bytes]
├─ IDENTITY_BLOCK [64 bytes]             // "PARTITION_MANIFEST for V1 (partition 0)"
├─ PARTITION_BODY [256 bytes]
│  ├─ partition_id [4 bytes]             // uint32_be (V1=0, CA1=1, M1=2, etc.)
│  ├─ node_count [8 bytes]               // uint64_be
│  ├─ cat_n_range_min [16 bytes]         // Binary UUID
│  ├─ cat_n_range_max [16 bytes]         // Binary UUID
│  ├─ synapse_count [8 bytes]            // uint64_be (both ends in partition)
│  ├─ boundary_synapse_count [8 bytes]   // uint64_be (inter-partition edges)
│  ├─ node_index_digest [32 bytes]       // SHA-256
│  ├─ synapse_index_digest [32 bytes]    // SHA-256
│  ├─ model_version_hash [32 bytes]      // SHA-256
│  ├─ connectivity_hash [32 bytes]       // SHA-256(all CAT-S-IDs)
│  ├─ timestamp [8 bytes]                // uint64_be (nanoseconds)
│  ├─ partition_sealed [1 byte]
│  └─ [35 bytes padding]
├─ CHILD_BUFFERS_BLOCK [variable]
│  ├─ buffer_count [4 bytes]             // uint32_be
│  └─ buffer_digests [buffer_count × 32 bytes] // SHA-256 hashes
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]
│  ├─ body_digest [32 bytes]             // SHA-256(partition_body)
│  ├─ child_array_hash [32 bytes]        // SHA-256(child_buffers_block)
│  ├─ integrity_hash [32 bytes]
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Fixed overhead**: 96 + 64 + 256 + 128 + 1 = 545 bytes
**Variable**: 4 + (buffer_count × 32) bytes

---

## MODEL_PARAMETERS SCHEMA

```
MODEL_PARAMETERS
├─ ARTIFACT_METADATA [96 bytes]
├─ IDENTITY_BLOCK [64 bytes]
├─ MODELS_BLOCK [variable]
│  ├─ model_count [2 bytes]              // uint16_be (always 3: HH, IAF, IAF_MOD)
│  └─ For each model:
│     ├─ model_id [1 byte]               // enum (1=HH, 2=IAF, 3=IAF_MOD)
│     ├─ parameter_count [2 bytes]       // uint16_be
│     ├─ parameters [parameter_count × 8 bytes] // float64_ieee754_be each
│     ├─ parameter_hash [32 bytes]       // SHA-256(canonical parameters)
│     ├─ neuron_type_assignment_count [2 bytes] // uint16_be
│     └─ neuron_type_assignments [assignment_count × 4 bytes]
│        └─ Each assignment: neuron_type [2 bytes] + reserved [2 bytes]
├─ TYPE_ASSIGNMENT_HASH_BLOCK [32 bytes] // SHA-256 of all assignments
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]
│  ├─ models_digest [32 bytes]
│  ├─ type_assignment_hash [32 bytes]
│  ├─ integrity_hash [32 bytes]
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Approximate size**: 96 + 64 + (3 models × 200 bytes each) + 32 + 128 + 1 ≈ **~900 bytes**

---

## GPU_KERNEL_VERSION SCHEMA

```
GPU_KERNEL_VERSION
├─ ARTIFACT_METADATA [96 bytes]
├─ IDENTITY_BLOCK [64 bytes]
├─ KERNEL_METADATA [512 bytes]
│  ├─ kernel_hash [32 bytes]             // SHA-256 of compiled kernel
│  ├─ kernel_source_hash [32 bytes]      // SHA-256 of source code
│  ├─ compiler_id [32 bytes]             // UTF-8 string (e.g., "CUDA 12.2", null-padded)
│  ├─ optimization_flags [128 bytes]     // UTF-8 string (e.g., "-O3 -march=sm_80", null-padded)
│  ├─ kernel_description [256 bytes]     // UTF-8 string (human-readable description)
│  ├─ build_timestamp [8 bytes]          // uint64_be (nanoseconds)
│  ├─ builder_id [32 bytes]              // Agent identifier
│  └─ [??]
├─ FUNCTION_SIGNATURES_BLOCK [variable]
│  ├─ function_count [2 bytes]
│  └─ For each function:
│     ├─ function_name [64 bytes]        // UTF-8 string, null-padded
│     ├─ parameter_count [2 bytes]
│     └─ parameter_types [parameter_count × 1 bytes]
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]
│  ├─ metadata_digest [32 bytes]
│  ├─ source_derived_hash [32 bytes]
│  ├─ integrity_hash [32 bytes]
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Approximate size**: 96 + 64 + 512 + variable + 128 + 1 ≈ **~1 KB + function metadata**

---

## EXECUTION_TRACE_BLOCK SCHEMA

```
EXECUTION_TRACE_BLOCK
├─ ARTIFACT_METADATA [96 bytes]
├─ IDENTITY_BLOCK [64 bytes]
├─ TRACE_HEADER [128 bytes]
│  ├─ trace_id [64 bytes]                // UTF-8 string (run_id + block_num)
│  ├─ timestep_start [8 bytes]           // uint64_be
│  ├─ timestep_end [8 bytes]             // uint64_be
│  ├─ wall_clock_start_ns [8 bytes]      // uint64_be
│  ├─ wall_clock_end_ns [8 bytes]        // uint64_be
│  ├─ wall_clock_padding [24 bytes]      // Reserved
├─ STATE_SNAPSHOTS_BLOCK [variable]
│  ├─ snapshot_count [4 bytes]           // uint32_be
│  └─ For each snapshot (at key timesteps):
│     ├─ snapshot_timestamp [8 bytes]
│     ├─ neuron_count [8 bytes]
│     ├─ neuron_states [neuron_count × 88 bytes each]
│     │  └─ Per neuron: cat_n_id [16] + V [8] + I [8] + spike_count [8] + 
│     │                 last_spike [8] + refractory [8] + gates[3×8]
│     └─ snapshot_digest [32 bytes]      // SHA-256
├─ SPIKE_EVENTS_BLOCK [variable]
│  ├─ spike_count [8 bytes]              // uint64_be
│  └─ spike_events [spike_count × 40 bytes each]
│     └─ Per event: delivery_time [8] + source [16] + dest [16] + 
│                    weight [8] + neuro [1] + receptor [1] + padding [2]
├─ BEHAVIORAL_OUTPUTS_BLOCK [variable]
│  ├─ output_count [4 bytes]
│  └─ outputs [variable]
├─ GPU_MEMORY_SNAPSHOTS_BLOCK [variable]
│  ├─ checkpoint_count [2 bytes]
│  └─ For each checkpoint:
│     ├─ checkpoint_timestamp [8 bytes]
│     ├─ memory_region_count [4 bytes]
│     └─ memory_digests [memory_region_count × 32 bytes]
├─ CPU_VALIDATION_DATA_BLOCK [variable]
│  ├─ reference_spike_count [8 bytes]
│  └─ reference_spikes [reference_spike_count × 40 bytes]
├─ NUMERICAL_ERROR_RECORD [64 bytes]
│  ├─ max_absolute_error [8 bytes]       // float64_ieee754_be
│  ├─ mean_absolute_error [8 bytes]      // float64_ieee754_be
│  ├─ sample_count [8 bytes]             // uint64_be
│  ├─ error_min [8 bytes]                // float64_ieee754_be
│  ├─ error_p25 [8 bytes]
│  ├─ error_p50 [8 bytes]
│  ├─ error_p75 [8 bytes]
│  ├─ error_max [8 bytes]
│  └─ verification_status [1 byte]
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]           // SHA-256 of previous trace block
│  ├─ body_digest [32 bytes]
│  ├─ spike_array_hash [32 bytes]
│  ├─ integrity_hash [32 bytes]
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Variable size**: Depends on number of spikes, snapshots, and GPU checkpoints
**Typical for 100ms simulation**: 96 + 64 + 128 + variable (~1-100 GB)

---

## BENCHMARK_DATA SCHEMA

```
BENCHMARK_DATA
├─ ARTIFACT_METADATA [96 bytes]
├─ IDENTITY_BLOCK [64 bytes]
├─ BENCHMARK_HEADER [64 bytes]
│  ├─ run_id [64 bytes]                  // UTF-8 string
├─ NEURON_STATS_BLOCK [48 bytes]
│  ├─ neuron_count [8 bytes]             // uint64_be
│  ├─ synapse_count [8 bytes]            // uint64_be
│  ├─ spike_count [8 bytes]              // uint64_be
│  ├─ active_neuron_percent [4 bytes]    // float32_ieee754_be (0-100)
│  ├─ timestep_range_start [8 bytes]
│  └─ timestep_range_end [8 bytes]
├─ TIMING_METRICS_BLOCK [variable]
│  ├─ phase_count [2 bytes]
│  └─ For each phase:
│     ├─ phase_name [32 bytes]           // UTF-8 string, null-padded
│     ├─ total_time_us [8 bytes]         // uint64_be
│     ├─ avg_time_us [8 bytes]           // float64_ieee754_be
│     ├─ min_time_us [8 bytes]           // float64_ieee754_be
│     ├─ max_time_us [8 bytes]           // float64_ieee754_be
│     ├─ call_count [8 bytes]            // uint64_be
│     └─ percent_of_total [4 bytes]      // float32_ieee754_be
├─ RESOURCE_METRICS_BLOCK [32 bytes]
│  ├─ gpu_memory_peak_gb [8 bytes]       // float64_ieee754_be
│  ├─ cpu_memory_peak_gb [8 bytes]       // float64_ieee754_be
│  ├─ gpu_utilization_percent [4 bytes]  // float32_ieee754_be
│  ├─ gpu_power_draw_w [4 bytes]         // float32_ieee754_be
│  └─ thermal_throttle_events [4 bytes]  // uint32_be
├─ THROUGHPUT_BLOCK [24 bytes]
│  ├─ neurons_per_second [8 bytes]       // float64_ieee754_be
│  ├─ synapses_per_second [8 bytes]      // float64_ieee754_be
│  └─ spikes_per_second [8 bytes]        // float64_ieee754_be
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]
│  ├─ body_digest [32 bytes]
│  ├─ metrics_hash [32 bytes]
│  ├─ integrity_hash [32 bytes]
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Fixed size**: 96 + 64 + 64 + 48 + 32 + 24 + 128 + 1 = **~460 bytes** (excluding variable phase metrics)

---

## NUMERICAL_ERROR_BOUNDS SCHEMA

```
NUMERICAL_ERROR_BOUNDS
├─ ARTIFACT_METADATA [96 bytes]
├─ IDENTITY_BLOCK [64 bytes]
├─ ERROR_HEADER [64 bytes]
│  ├─ comparison_type [1 byte]           // 0=CPU_VS_GPU, 1=DOUBLE_VS_FLOAT, etc.
│  ├─ timestep_range_start [8 bytes]
│  ├─ timestep_range_end [8 bytes]
│  ├─ sample_count [8 bytes]             // uint64_be (how many comparisons made)
│  └─ [39 bytes padding]
├─ VARIABLE_ERRORS_BLOCK [variable]
│  ├─ variable_count [2 bytes]           // uint16_be (number of state variables)
│  └─ For each variable:
│     ├─ variable_name [32 bytes]        // UTF-8 string, null-padded
│     ├─ variable_type [1 byte]          // 0=float64, 1=uint64, 2=int32, etc.
│     ├─ max_absolute_error [8 bytes]    // float64_ieee754_be
│     ├─ mean_absolute_error [8 bytes]
│     ├─ stddev_absolute_error [8 bytes]
│     ├─ max_relative_error_percent [8 bytes] // float64_ieee754_be
│     ├─ confidence_lower_95 [8 bytes]
│     ├─ confidence_upper_95 [8 bytes]
│     └─ error_histogram [160 bytes]     // 20 bins × 8 bytes each (uint64_be counts)
├─ OVERALL_STATISTICS_BLOCK [32 bytes]
│  ├─ max_error_across_variables [8 bytes]
│  ├─ mean_error_across_variables [8 bytes]
│  ├─ acceptance_threshold [8 bytes]
│  └─ pass_fail_status [1 byte]          // 0=PASS, 1=FAIL
├─ WITNESS_SPIKES_BLOCK [variable]
│  ├─ witness_count [2 bytes]            // uint16_be (up to 100 worst cases)
│  └─ For each witness:
│     ├─ timestep [8 bytes]              // uint64_be
│     ├─ neuron_id [16 bytes]            // Binary UUID
│     ├─ cpu_value [8 bytes]             // float64_ieee754_be
│     ├─ gpu_value [8 bytes]             // float64_ieee754_be
│     └─ error_magnitude [8 bytes]       // float64_ieee754_be
├─ INTEGRITY_BLOCK [128 bytes]
│  ├─ parent_digest [32 bytes]
│  ├─ body_digest [32 bytes]
│  ├─ witness_hash [32 bytes]
│  ├─ integrity_hash [32 bytes]
│  └─ hmac_tag [32 bytes]
└─ SEAL [1 byte]
   └─ sealed [1 byte]
```

**Approximate size**: 96 + 64 + 64 + (N_vars × 304) + 32 + variable + 128 + 1 ≈ **~1-5 KB**

---

## SERIALIZATION EXAMPLES

### Example 1: Big-Endian Uint64

```
Value: 0x0123456789ABCDEF (uint64)
Serialized: [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF] (8 bytes, MSB first)
```

### Example 2: IEEE 754 Float64

```
Value: 3.14159265358979 (double)
IEEE 754 bits: 0x400921FB54442D18
Serialized: [0x40, 0x09, 0x21, 0xFB, 0x54, 0x44, 0x2D, 0x18] (8 bytes, big-endian)
```

### Example 3: Canonical CAT-N-ID (UUID)

```
CAT-N-ID: "CAT-N-00000001-0000-0000-0000-000000000001" → Binary representation
Serialized: [16 bytes of UUID bits] (big-endian encoding of UUID fields)
```

### Example 4: Canonical String (UTF-8 with Length Prefix)

```
String: "GPU_BUFFER for partition 0"
Length: 26 (uint32_be)
Serialized: [0x00, 0x00, 0x00, 0x1A] + [UTF-8 bytes: 0x47, 0x50, 0x55, ...]
```

---

## ENCODING RULES (Final)

1. **All multi-byte integers**: Big-endian (network byte order)
2. **All floating-point values**: IEEE 754-2008, big-endian byte order
3. **All strings**: UTF-8 encoded, null-terminated within fixed-size fields, null-padded
4. **All UUIDs**: 16-byte binary representation, big-endian byte order
5. **All enums**: Store as uint8_t or uint16_t (as specified), big-endian
6. **No padding unless specified**: Fields are byte-aligned as listed
7. **Hash digests**: Raw 32-byte SHA-256 output (binary, not hex)
8. **HMAC tags**: Raw 32-byte HMAC-SHA-256 output (binary, not hex)

---

## End of Artifact Schemas
