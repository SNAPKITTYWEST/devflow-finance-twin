# PHASE 7: Visualization WORM Provenance Layer
## Ada/SPARK + WORM Provenance Engineer (Visualization Artifacts)

**Status**: SPECIFICATION COMPLETE  
**Date**: 2026-09-13  
**Scope**: Write-Once-Read-Many (WORM) cryptographic provenance for all visualization artifacts  
**Security Model**: Bidirectional traceability; every 2D element → 3D node/edge → GPU representation → evidence

---

## EXECUTIVE SUMMARY

Phase 7 establishes cryptographic provenance for visualization artifacts, making every 2D visualization element traceable to:
1. Its source 3D graph node/edge
2. The Phase 6 GPU validated representation
3. The CAT-N/CAT-S evidence (behavioral trace)

**Bidirectional Traceability**:
- Forward: 2D projection → 3D snapshot → GPU artifact
- Reverse: GPU artifact → 3D snapshot → 2D visualization

**Invariants**:
- Every 2D pixel element maps to exactly one 3D node or edge
- Every projection parameter is immutable after sealing
- All projections cryptographically linked to source 3D graph
- Behavioral data integrated at activity frame and trace levels

---

## 1. ARTIFACTS REQUIRING PROTECTION

```
VISUALIZATION_LAYER_ARTIFACTS:
├─ 3D_GRAPH_SNAPSHOT              [One per timestep: full node/edge set with 3D coords]
├─ 2D_PROJECTION                  [One per viewport/camera: screen-space rendering]
├─ PROJECTION_PARAMETERS          [One per algorithm: transformation matrices, camera]
├─ CAMERA_PARAMETERS              [Per view: eye position, frustum, aspect ratio]
├─ TRANSFORMATION_MATRICES        [Per projection: model-view-projection chain]
├─ ACTIVITY_FRAME                 [Per timestep: neuron/synapse state snapshot]
├─ BEHAVIORAL_TRACE               [Per episode: sequence of activity frames + actions]
├─ VIEWPORT_SNAPSHOT              [Per user interaction: captured 2D render + metadata]
└─ RENDERING_STATE                [Per frame: GPU texture bindings, shader state]
```

---

## 2. 3D_GRAPH_SNAPSHOT STRUCTURE

Complete immutable snapshot of 3D neural graph with cryptographic binding to Phase 6.

```
3D_GRAPH_SNAPSHOT
├─ METADATA (96 bytes)
│  ├─ SNAPSHOT_ID [32 bytes]          // UUID: graph_version + timestamp
│  ├─ VERSION [4 bytes]               // Semantic versioning
│  ├─ CREATION_TIMESTAMP [8 bytes]    // Nanosecond precision (uint64)
│  ├─ CREATOR [8 bytes]               // PHASE_7_VISUALIZATION_ENGINE
│  ├─ SEALED_FLAG [1 byte]            // 0x01 = immutable
│  ├─ MODEL_VERSION_HASH [32 bytes]   // SHA-256(model parameters from Phase 6)
│  └─ CONNECTOME_VERSION_HASH [32 bytes] // SHA-256(connectome from Phase 6)
│
├─ SNAPSHOT_BODY
│  ├─ GRAPH_VERSION_ID [16 bytes]     // Link to Phase 6 GPU artifact version
│  ├─ NODE_COUNT [8 bytes]            // 760M neurons
│  ├─ EDGE_COUNT [8 bytes]            // 1B synapses
│  ├─ TIMESTAMP [8 bytes]             // Aligned with timestep
│  ├─ BOUNDING_BOX [48 bytes]
│  │  ├─ MIN_X [8 bytes] (float64)
│  │  ├─ MIN_Y [8 bytes] (float64)
│  │  ├─ MIN_Z [8 bytes] (float64)
│  │  ├─ MAX_X [8 bytes] (float64)
│  │  ├─ MAX_Y [8 bytes] (float64)
│  │  └─ MAX_Z [8 bytes] (float64)
│  │
│  ├─ NODE_COORDINATE_TABLE [variable]
│  │  ├─ NODE_TABLE_SIZE [8 bytes]    // Total bytes
│  │  └─ [NODE_COUNT × 40 bytes]
│  │     ├─ CAT_N_ID [16 bytes]       // UUID of neuron
│  │     ├─ X [8 bytes]               // IEEE 754 float64
│  │     ├─ Y [8 bytes]               // IEEE 754 float64
│  │     └─ Z [8 bytes]               // IEEE 754 float64
│  │
│  ├─ EDGE_TOPOLOGY_TABLE [variable]
│  │  ├─ EDGE_TABLE_SIZE [8 bytes]
│  │  └─ [EDGE_COUNT × 40 bytes]
│  │     ├─ CAT_S_ID [8 bytes]        // uint64 edge identifier
│  │     ├─ SOURCE_CAT_N [16 bytes]
│  │     ├─ DEST_CAT_N [16 bytes]
│  │     └─ SYNAPSE_TYPE [1 byte]     // Excitatory, Inhibitory, etc.
│  │
│  ├─ ANATOMICAL_HIERARCHY [variable]
│  │  ├─ HIERARCHY_SIZE [8 bytes]
│  │  └─ [NODE_COUNT × 16 bytes]
│  │     ├─ CAT_N_ID [16 bytes]
│  │     ├─ REGION_ID [4 bytes]       // V1, CA1, M1, etc.
│  │     ├─ LAYER_ID [4 bytes]        // Layer 1, 2/3, etc.
│  │     └─ [Padding: 8 bytes]
│  │
│  ├─ NODE_TABLE_DIGEST [32 bytes]    // SHA-256(canonical(node_coordinate_table))
│  ├─ EDGE_TABLE_DIGEST [32 bytes]    // SHA-256(canonical(edge_topology_table))
│  ├─ COORDINATE_DIGEST [32 bytes]    // SHA-256(all (x,y,z) tuples sorted)
│  ├─ ANATOMICAL_DIGEST [32 bytes]    // SHA-256(region/layer assignments sorted)
│  ├─ SEALED_FLAG [1 byte]
│  └─ [Padding]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_SNAPSHOT_DIGEST [32 bytes] // SHA-256(previous 3D snapshot)
│  ├─ BODY_DIGEST [32 bytes]            // SHA-256(canonical(snapshot_body))
│  ├─ GPU_PHASE6_LINK_DIGEST [32 bytes] // SHA-256(GPU artifact this came from)
│  ├─ INTEGRITY_HASH [32 bytes]         // SHA-256(BODY_DIGEST || GPU_LINK || PARENT)
│  └─ HMAC_TAG [32 bytes]               // HMAC-SHA-256(K_master, canonical(all))
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]                 // 0x01 = sealed, immutable
```

**Total Overhead**: 96 + 128 + 8 + 1 = 233 bytes + coordinate/topology tables

---

## 3. 2D_PROJECTION ARTIFACT

Screen-space projection with complete mapping to source 3D nodes/edges and CAT-N/CAT-S references.

```
2D_PROJECTION
├─ METADATA (96 bytes)
│  ├─ PROJECTION_ID [32 bytes]        // UUID: 2d_version + projection_type + timestamp
│  ├─ VERSION [4 bytes]
│  ├─ CREATION_TIMESTAMP [8 bytes]
│  ├─ CREATOR [8 bytes]               // PHASE_7_PROJECTION_ENGINE
│  ├─ SEALED_FLAG [1 byte]
│  ├─ MODEL_VERSION_HASH [32 bytes]
│  └─ CONNECTOME_VERSION_HASH [32 bytes]
│
├─ PROJECTION_HEADER
│  ├─ SOURCE_3D_SNAPSHOT_ID [32 bytes] // Immutable link to source 3D graph
│  ├─ PROJECTION_VERSION [4 bytes]
│  ├─ PROJECTION_TYPE [1 byte]        // 0=Orthogonal, 1=Perspective, 2=Circuit-Specific
│  ├─ RESOLUTION_WIDTH [4 bytes]      // Pixel width
│  ├─ RESOLUTION_HEIGHT [4 bytes]     // Pixel height
│  ├─ PIXEL_ASPECT_RATIO [8 bytes]    // float64
│  ├─ TIMESTAMP [8 bytes]
│  └─ [Padding]
│
├─ PROJECTION_DATA
│  ├─ NODE_MAPPING [variable]
│  │  ├─ MAPPED_NODE_COUNT [4 bytes]  // How many 3D nodes visible in 2D
│  │  └─ [MAPPED_NODE_COUNT × 44 bytes]
│  │     ├─ SOURCE_3D_NODE_INDEX [8 bytes]  // Index into 3D snapshot
│  │     ├─ CAT_N_ID [16 bytes]             // Neuron ID from source
│  │     ├─ PROJECTED_X [8 bytes]           // Screen x coordinate (float64)
│  │     ├─ PROJECTED_Y [8 bytes]           // Screen y coordinate (float64)
│  │     └─ PROJECTED_Z [4 bytes]           // Depth (float32) for occlusion
│  │
│  ├─ EDGE_MAPPING [variable]
│  │  ├─ MAPPED_EDGE_COUNT [4 bytes]
│  │  └─ [MAPPED_EDGE_COUNT × 48 bytes]
│  │     ├─ SOURCE_3D_EDGE_INDEX [8 bytes]
│  │     ├─ CAT_S_ID [8 bytes]
│  │     ├─ SOURCE_NODE_INDEX [8 bytes]    // 3D source
│  │     ├─ DEST_NODE_INDEX [8 bytes]      // 3D dest
│  │     ├─ LINE_SEGMENT_START_X [8 bytes] // 2D start
│  │     ├─ LINE_SEGMENT_START_Y [8 bytes]
│  │     ├─ LINE_SEGMENT_END_X [8 bytes]   // 2D end
│  │     ├─ LINE_SEGMENT_END_Y [8 bytes]
│  │     └─ DEPTH_MIN [4 bytes]            // Occlusion test
│  │
│  ├─ CAT_N_REFERENCE_ARRAY [variable]
│  │  ├─ ARRAY_SIZE [4 bytes]         // In-order list of CAT-N IDs visible
│  │  └─ [ARRAY_SIZE × 16 bytes]      // Sorted by 2D x-coordinate
│  │
│  ├─ CAT_S_REFERENCE_ARRAY [variable]
│  │  ├─ ARRAY_SIZE [4 bytes]
│  │  └─ [ARRAY_SIZE × 8 bytes]       // Sorted by depth (front to back)
│  │
│  ├─ PROJECTED_NODE_DIGEST [32 bytes]    // SHA-256(all 2D node positions)
│  ├─ PROJECTED_EDGE_DIGEST [32 bytes]    // SHA-256(all 2D edge segments)
│  ├─ REFERENCE_ARRAY_DIGEST [32 bytes]   // SHA-256(CAT-N/CAT-S arrays)
│  ├─ MAPPING_CONSISTENCY_HASH [32 bytes] // SHA-256(proof all mappings valid)
│  └─ [Padding]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_PROJECTION_DIGEST [32 bytes] // Previous 2D projection
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ SOURCE_3D_LINK_DIGEST [32 bytes]    // HMAC(source 3D snapshot)
│  ├─ INTEGRITY_HASH [32 bytes]           // SHA-256(BODY || SOURCE_LINK || PARENT)
│  └─ HMAC_TAG [32 bytes]                 // HMAC-SHA-256(K_master, canonical)
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]
```

---

## 4. PROJECTION_PARAMETERS ARTIFACT

Immutable description of projection algorithm and coordinate transformation.

```
PROJECTION_PARAMETERS
├─ METADATA (96 bytes)
│  ├─ PARAMETER_ID [32 bytes]        // UUID: algorithm_type + timestamp
│  ├─ VERSION [4 bytes]
│  ├─ CREATION_TIMESTAMP [8 bytes]
│  ├─ CREATOR [8 bytes]
│  ├─ SEALED_FLAG [1 byte]
│  ├─ MODEL_VERSION_HASH [32 bytes]
│  └─ CONNECTOME_VERSION_HASH [32 bytes]
│
├─ PROJECTION_ALGORITHM
│  ├─ ALGORITHM_TYPE [1 byte]         // 0=Orthogonal, 1=Perspective, 2=Circuit-Custom
│  ├─ ALGORITHM_NAME [64 bytes]       // UTF-8 description
│  ├─ ALGORITHM_PARAMETERS [variable] // Algorithm-specific constants
│  │  For orthogonal:
│  │    ├─ VIEWING_PLANE [1 byte]     // 0=XY, 1=XZ, 2=YZ
│  │    └─ SCALE [8 bytes]            // Zoom factor (float64)
│  │  For perspective:
│  │    ├─ FIELD_OF_VIEW [8 bytes]    // degrees (float64)
│  │    └─ ASPECT_RATIO [8 bytes]
│  │  For circuit-specific:
│  │    ├─ CIRCUIT_REGION [4 bytes]   // Which brain region
│  │    └─ LAYER_FOCUS [4 bytes]      // Which layer emphasized
│
├─ COORDINATE_TRANSFORM
│  ├─ TRANSFORM_TYPE [1 byte]         // 0=Matrix, 1=Euler, 2=Quaternion
│  ├─ TRANSFORM_MATRIX [128 bytes]    // 4×4 float64 (if applicable)
│  │  ├─ M[0..15]: 16 × 8 bytes each (IEEE 754)
│  │  └─ ROW_MAJOR order
│  │
│  ├─ SCALE_FACTORS [24 bytes]
│  │  ├─ SCALE_X [8 bytes] (float64)
│  │  ├─ SCALE_Y [8 bytes]
│  │  └─ SCALE_Z [8 bytes]
│  │
│  ├─ ROTATION_QUATERNION [32 bytes]
│  │  ├─ Q0 [8 bytes] (float64, w component)
│  │  ├─ Q1 [8 bytes] (x component)
│  │  ├─ Q2 [8 bytes] (y component)
│  │  └─ Q3 [8 bytes] (z component)
│  │
│  ├─ TRANSLATION [24 bytes]
│  │  ├─ TX [8 bytes] (float64)
│  │  ├─ TY [8 bytes]
│  │  └─ TZ [8 bytes]
│  │
│  ├─ INVERSE_TRANSFORM [128 bytes]   // Inverse matrix (to recover 3D from 2D)
│  ├─ DETERMINANT [8 bytes]           // float64 (must be non-zero)
│  ├─ CONDITION_NUMBER [8 bytes]      // Numerical stability metric
│  ├─ TRANSFORM_VALID [1 byte]        // 0x01 if invertible
│  └─ [Padding]
│
├─ CAMERA_INTRINSICS
│  ├─ CAMERA_ID [32 bytes]            // UUID of camera configuration
│  ├─ EYE_X [8 bytes] (float64)        // Camera position
│  ├─ EYE_Y [8 bytes]
│  ├─ EYE_Z [8 bytes]
│  ├─ CENTER_X [8 bytes]              // Look-at target
│  ├─ CENTER_Y [8 bytes]
│  ├─ CENTER_Z [8 bytes]
│  ├─ UP_X [8 bytes]                  // Up vector
│  ├─ UP_Y [8 bytes]
│  ├─ UP_Z [8 bytes]
│  ├─ NEAR_PLANE [8 bytes] (float64)
│  ├─ FAR_PLANE [8 bytes]
│  ├─ FOV_Y [8 bytes]                 // Vertical field of view (degrees)
│  └─ [Padding]
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_PARAMETERS_DIGEST [32 bytes]
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ ALGORITHM_DIGEST [32 bytes]     // SHA-256(algorithm + parameters)
│  ├─ TRANSFORM_DIGEST [32 bytes]     // SHA-256(all transformation matrices)
│  ├─ CAMERA_DIGEST [32 bytes]        // SHA-256(camera intrinsics)
│  └─ HMAC_TAG [32 bytes]
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]
```

---

## 5. ACTIVITY_FRAME STRUCTURE

Per-timestep snapshot of neuron/synapse activity with behavioral outputs.

```
ACTIVITY_FRAME
├─ METADATA (96 bytes)
│  ├─ FRAME_ID [32 bytes]             // UUID: 3d_snapshot_id + timestep
│  ├─ VERSION [4 bytes]
│  ├─ CREATION_TIMESTAMP [8 bytes]
│  ├─ CREATOR [8 bytes]               // PHASE_7_ACTIVITY_ENGINE
│  ├─ SEALED_FLAG [1 byte]
│  ├─ MODEL_VERSION_HASH [32 bytes]
│  └─ CONNECTOME_VERSION_HASH [32 bytes]
│
├─ TIMESTEP_INFO
│  ├─ TIMESTEP_INDEX [8 bytes]        // uint64: which step in simulation
│  ├─ TIMESTAMP_MS [8 bytes]          // Milliseconds (float64)
│  ├─ SIMULATION_TIME_START_MS [8 bytes]
│  ├─ SIMULATION_TIME_END_MS [8 bytes]
│  └─ [Padding]
│
├─ ACTIVE_NEURON_STATES [variable]
│  ├─ ACTIVE_NEURON_COUNT [4 bytes]
│  └─ [ACTIVE_NEURON_COUNT × 80 bytes]
│     ├─ CAT_N_ID [16 bytes]
│     ├─ MEMBRANE_POTENTIAL [8 bytes] // millivolts (float64)
│     ├─ SPIKE_FLAG [1 byte]           // 0x01 if spiked this timestep
│     ├─ FIRING_RATE [8 bytes]         // Hz (float64)
│     ├─ REFRACTORY_STATE [1 byte]     // 0=Excitable, 1=Refractory, 2=Recovery
│     ├─ NEURON_TYPE [2 bytes]
│     ├─ REGION_ID [4 bytes]
│     ├─ LAYER_ID [4 bytes]
│     ├─ TAU_M [8 bytes]               // Membrane time constant (float64)
│     ├─ V_THRESHOLD [8 bytes]         // Spike threshold (float64)
│     ├─ V_RESET [8 bytes]             // Reset potential (float64)
│     ├─ SPIKE_COUNT_LIFETIME [8 bytes] // Total spikes since start
│     ├─ LAST_SPIKE_TIMESTEP [8 bytes] // When this neuron last spiked
│     ├─ CONFIDENCE [1 byte]           // Data quality: 0-255 (255=validated)
│     └─ [Padding: 2 bytes]
│
├─ ACTIVE_SYNAPSE_STATES [variable]
│  ├─ ACTIVE_SYNAPSE_COUNT [4 bytes]
│  └─ [ACTIVE_SYNAPSE_COUNT × 64 bytes]
│     ├─ CAT_S_ID [8 bytes]
│     ├─ SOURCE_CAT_N [16 bytes]
│     ├─ DEST_CAT_N [16 bytes]
│     ├─ TRANSMITTER_CONCENTRATION [8 bytes] // nM (float64)
│     ├─ RECENT_SPIKE_COUNT [4 bytes] // Spikes in last 10ms
│     ├─ SYNAPTIC_CURRENT [8 bytes]   // pA (float64)
│     ├─ PLASTICITY_STATE [1 byte]    // 0=Static, 1=LTP, 2=LTD
│     └─ [Padding: 7 bytes]
│
├─ BEHAVIORAL_OUTPUTS [variable]
│  ├─ OUTPUT_COUNT [2 bytes]
│  └─ Per output:
│     ├─ OUTPUT_TYPE [1 byte]         // 0=Motor, 1=Cognitive, 2=Neuroendocrine
│     ├─ INTENSITY [8 bytes]          // Normalized 0.0-1.0 (float64)
│     ├─ DURATION_MS [8 bytes]
│     ├─ SOURCE_NEURON_COUNT [2 bytes]
│     └─ [SOURCE_NEURON_COUNT × 16 bytes] // CAT-N-IDs contributing
│
├─ COGNITIVE_STATE [variable]         // Aggregated state across regions
│  ├─ ATTENTION [8 bytes]             // float64, 0.0-1.0
│  ├─ AROUSAL [8 bytes]
│  ├─ VALENCE [8 bytes]               // Positive/negative emotional tone
│  ├─ DECISION_CONFIDENCE [8 bytes]
│  ├─ LEARNING_STATE [1 byte]         // 0=Idle, 1=Active, 2=Consolidation
│  └─ [Padding]
│
├─ STATE_DIGEST [32 bytes]             // SHA-256(canonical(neuron states))
├─ SYNAPSE_DIGEST [32 bytes]            // SHA-256(canonical(synapse states))
├─ OUTPUT_DIGEST [32 bytes]             // SHA-256(canonical(behavioral outputs))
├─ COGNITIVE_DIGEST [32 bytes]          // SHA-256(canonical(cognitive state))
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_FRAME_ID [32 bytes]      // Previous activity frame (chain link)
│  ├─ PARENT_FRAME_DIGEST [32 bytes]
│  ├─ BODY_DIGEST [32 bytes]
│  ├─ COHERENCE_HASH [32 bytes]       // Proof neuron/synapse states consistent
│  └─ HMAC_TAG [32 bytes]
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]
```

---

## 6. BEHAVIORAL_TRACE STRUCTURE

Episode-level recording of all activity frames and action sequences.

```
BEHAVIORAL_TRACE
├─ METADATA (96 bytes)
│  ├─ TRACE_ID [32 bytes]             // UUID: brain_id + episode_id + timestamp
│  ├─ VERSION [4 bytes]
│  ├─ CREATION_TIMESTAMP [8 bytes]
│  ├─ CREATOR [8 bytes]               // PHASE_7_TRACE_ENGINE
│  ├─ SEALED_FLAG [1 byte]
│  ├─ MODEL_VERSION_HASH [32 bytes]
│  └─ CONNECTOME_VERSION_HASH [32 bytes]
│
├─ EPISODE_METADATA
│  ├─ EPISODE_ID [32 bytes]
│  ├─ EPISODE_DURATION_MS [8 bytes]   // Total episode length
│  ├─ FRAME_COUNT [8 bytes]           // Number of activity frames
│  ├─ ACTION_COUNT [4 bytes]          // Number of behavioral actions
│  ├─ BRAIN_ID [32 bytes]             // Which brain instance
│  ├─ ENVIRONMENT_CONTEXT [64 bytes]  // Description of task/environment
│  ├─ EPISODE_START_TIME [8 bytes]    // Wall-clock timestamp
│  ├─ EPISODE_END_TIME [8 bytes]
│  └─ [Padding]
│
├─ ACTIVITY_FRAME_ARRAY [variable]
│  ├─ FRAME_ARRAY_SIZE [8 bytes]      // Bytes in array
│  └─ [FRAME_COUNT × ACTIVITY_FRAME]  // Array of sealed activity frames
│     Each frame is a complete ACTIVITY_FRAME structure (see section 5)
│     Frames are linked via PARENT_FRAME_ID (chain)
│
├─ ACTION_SEQUENCE [variable]
│  ├─ ACTION_ARRAY_SIZE [8 bytes]
│  └─ [ACTION_COUNT records, each ~100 bytes]
│     Per action:
│     ├─ ACTION_INDEX [4 bytes]
│     ├─ ACTION_TYPE [1 byte]         // Motor command type
│     ├─ INTENSITY [8 bytes]          // float64
│     ├─ SOURCE_NEURON_COUNT [2 bytes]
│     ├─ [SOURCE_NEURON_COUNT × 16 bytes] // CAT-N-IDs
│     ├─ TIMESTAMP_MS [8 bytes]       // When action occurred
│     ├─ FRAME_INDEX [8 bytes]        // Which activity frame triggered it
│     └─ OUTCOME [64 bytes]           // Result of action
│
├─ AGGREGATE_STATISTICS
│  ├─ TOTAL_SPIKES [8 bytes]
│  ├─ NEURONS_ACTIVE [8 bytes]        // Unique neurons that spiked
│  ├─ SYNAPSES_ACTIVE [8 bytes]
│  ├─ MEAN_FIRING_RATE [8 bytes]      // float64, Hz
│  ├─ MAX_FIRING_RATE [8 bytes]
│  ├─ SPIKE_ENTROPY [8 bytes]         // Information-theoretic measure
│  ├─ NETWORK_SYNCHRONY [8 bytes]     // 0.0-1.0 (float64)
│  └─ LEARNING_SCORE [8 bytes]        // Plasticity change metric
│
├─ TRACE_INTEGRITY
│  ├─ FRAME_ARRAY_DIGEST [32 bytes]   // SHA-256(all frames serialized)
│  ├─ ACTION_ARRAY_DIGEST [32 bytes]  // SHA-256(all actions serialized)
│  ├─ NEURON_PARTICIPATION_DIGEST [32 bytes] // SHA-256(sorted set of CAT-N-IDs)
│  ├─ SYNAPSE_PARTICIPATION_DIGEST [32 bytes] // SHA-256(sorted set of CAT-S-IDs)
│  ├─ STATISTICS_DIGEST [32 bytes]    // SHA-256(aggregate stats)
│  └─ BODY_DIGEST [32 bytes]          // SHA-256(canonical(episode_metadata))
│
├─ INTEGRITY FIELDS (128 bytes)
│  ├─ PARENT_TRACE_DIGEST [32 bytes]  // Previous episode
│  ├─ CUMULATIVE_DIGEST [32 bytes]    // SHA-256(all frames in order)
│  ├─ GRAPH_VERSION_DIGEST [32 bytes] // Link to 3D graph snapshot
│  ├─ INTEGRITY_HASH [32 bytes]       // SHA-256(all digests)
│  └─ HMAC_TAG [32 bytes]             // HMAC-SHA-256(K_master, canonical)
│
└─ SEAL [1 byte]
   └─ SEALED [1 byte]
```

---

## 7. BIDIRECTIONAL TRACEABILITY ALGORITHM

Forward and reverse verification ensuring complete provenance chain.

### 7.1 Forward Verification: 2D Projection → 3D Graph → GPU Artifact

```
verify_2d_projection_forward(projection, 3d_snapshot, gpu_artifact, master_key):
  
  // Step 1: Verify 2D projection is sealed
  if projection.sealed_flag != 0x01:
    return FAIL_PROJECTION_NOT_SEALED
  
  // Step 2: Load and verify source 3D snapshot
  source_3d = load_snapshot_by_id(projection.source_3d_snapshot_id)
  if not verify_3d_snapshot_hmac(source_3d, master_key):
    return FAIL_3D_SNAPSHOT_CORRUPTED
  
  // Step 3: Verify 3D snapshot is sealed and immutable
  if source_3d.sealed_flag != 0x01:
    return FAIL_3D_SNAPSHOT_NOT_SEALED
  
  // Step 4: Verify each projected 2D node maps to valid 3D node
  for each node_mapping in projection.node_mapping:
    source_3d_node = source_3d.node_table[node_mapping.source_3d_idx]
    
    // Verify CAT-N ID match
    if source_3d_node.cat_n_id != projection.cat_n_reference[node_mapping.2d_idx]:
      return FAIL_NODE_MAPPING_CAT_N_MISMATCH
    
    // Verify 2D position is correct projection of 3D point
    expected_2d_x, expected_2d_y = 
      project_3d_to_2d(source_3d_node.x, source_3d_node.y, source_3d_node.z, 
                       projection.projection_parameters)
    
    tolerance = 1.0  // pixels
    if distance(node_mapping.projected_x, node_mapping.projected_y,
                expected_2d_x, expected_2d_y) > tolerance:
      return FAIL_NODE_PROJECTION_POSITION_ERROR
  
  // Step 5: Verify each projected 2D edge maps to valid 3D edge
  for each edge_mapping in projection.edge_mapping:
    source_3d_edge = source_3d.edge_table[edge_mapping.source_3d_idx]
    
    // Verify CAT-S ID match
    if source_3d_edge.cat_s_id != projection.cat_s_reference[edge_mapping.2d_idx]:
      return FAIL_EDGE_MAPPING_CAT_S_MISMATCH
    
    // Verify source and dest match
    if source_3d_edge.source_cat_n != edge_mapping.source_node_index:
      return FAIL_EDGE_SOURCE_MISMATCH
    if source_3d_edge.dest_cat_n != edge_mapping.dest_node_index:
      return FAIL_EDGE_DEST_MISMATCH
    
    // Verify 2D edge is correct projection of 3D edge
    source_3d_node = source_3d.node_table[source_3d_edge.source_cat_n]
    dest_3d_node = source_3d.node_table[source_3d_edge.dest_cat_n]
    
    expected_start_x, expected_start_y = 
      project_3d_to_2d(source_3d_node.x, source_3d_node.y, source_3d_node.z, ...)
    expected_end_x, expected_end_y = 
      project_3d_to_2d(dest_3d_node.x, dest_3d_node.y, dest_3d_node.z, ...)
    
    if distance_from_line(
        edge_mapping.line_start_x, edge_mapping.line_start_y,
        expected_start_x, expected_start_y,
        expected_end_x, expected_end_y) > tolerance:
      return FAIL_EDGE_PROJECTION_ERROR
  
  // Step 6: Verify 3D snapshot links to GPU artifact
  if source_3d.gpu_phase6_link_digest != HMAC_SHA256(gpu_artifact):
    return FAIL_GPU_LINK_MISMATCH
  
  // Step 7: Verify HMAC of 2D projection
  computed_hmac = HMAC_SHA256(master_key, canonical_serialize(projection))
  if not constant_time_compare(computed_hmac, projection.hmac_tag):
    return FAIL_PROJECTION_HMAC_INVALID
  
  return PROJECTION_VERIFIED_COMPLETE
```

### 7.2 Reverse Verification: GPU Artifact → 3D Graph → 2D Projection

```
verify_gpu_to_2d_reverse(gpu_artifact, 3d_snapshot, projection, master_key):
  
  // Step 1: Load and verify GPU artifact from Phase 6
  if not gpu_buffer_verify(gpu_artifact, master_key):
    return FAIL_GPU_ARTIFACT_INVALID
  
  // Step 2: Verify 3D snapshot was derived from GPU artifact
  if 3d_snapshot.gpu_phase6_link_digest != HMAC_SHA256(gpu_artifact):
    return FAIL_3D_NOT_FROM_GPU
  
  // Step 3: Verify 3D graph has all nodes from GPU
  gpu_node_set = extract_cat_n_ids_from_gpu(gpu_artifact)
  snapshot_node_set = extract_cat_n_ids_from_3d(3d_snapshot)
  if gpu_node_set != snapshot_node_set:
    return FAIL_NODE_SET_MISMATCH
  
  // Step 4: Verify all GPU nodes appear in 2D projection
  projected_node_set = extract_cat_n_ids_from_2d(projection)
  if not projected_node_set.is_subset_of(snapshot_node_set):
    return FAIL_PROJECTED_NODES_NOT_IN_GPU
  
  // Step 5: Verify all GPU edges appear in 2D projection (if visible)
  gpu_edge_set = extract_cat_s_ids_from_gpu(gpu_artifact)
  projected_edge_set = extract_cat_s_ids_from_2d(projection)
  for each cat_s in projected_edge_set:
    if cat_s not_in gpu_edge_set:
      return FAIL_PROJECTED_EDGE_NOT_IN_GPU
  
  // Step 6: Verify 2D projection parameters are consistent
  if projection.projection_parameters not_sealed:
    return FAIL_PROJECTION_PARAMS_NOT_SEALED
  
  return GPU_TO_2D_VERIFIED_COMPLETE
```

### 7.3 Activity Frame to Behavioral Trace Link

```
verify_activity_frame_in_trace(frame, trace, master_key):
  
  // Step 1: Verify frame is sealed
  if frame.sealed_flag != 0x01:
    return FAIL_FRAME_NOT_SEALED
  
  // Step 2: Verify frame HMAC
  if not verify_hmac_sha256(master_key, frame):
    return FAIL_FRAME_HMAC_INVALID
  
  // Step 3: Verify frame appears in trace array
  frame_found = false
  for each candidate_frame in trace.activity_frame_array:
    if candidate_frame.frame_id == frame.frame_id:
      frame_found = true
      // Verify exact match
      if canonical_serialize(candidate_frame) != canonical_serialize(frame):
        return FAIL_FRAME_CONTENT_MISMATCH
      break
  
  if not frame_found:
    return FAIL_FRAME_NOT_IN_TRACE
  
  // Step 4: Verify frame chain linking
  if frame.timestep_index > 0:
    parent_frame_id = get_frame_at_index(trace, frame.timestep_index - 1).frame_id
    if frame.parent_frame_id != parent_frame_id:
      return FAIL_FRAME_CHAIN_BROKEN
  
  // Step 5: Verify neurons in frame are in connected graph
  for each neuron_state in frame.active_neuron_states:
    if not graph_contains_cat_n(neuron_state.cat_n_id):
      return FAIL_NEURON_NOT_IN_GRAPH
  
  // Step 6: Verify synapses in frame connect neurons in frame
  for each synapse_state in frame.active_synapse_states:
    source_exists = any(n.cat_n_id == synapse_state.source_cat_n 
                       for n in frame.active_neuron_states)
    dest_exists = any(n.cat_n_id == synapse_state.dest_cat_n 
                     for n in frame.active_neuron_states)
    if not (source_exists and dest_exists):
      return FAIL_SYNAPSE_NODES_NOT_IN_FRAME
  
  return ACTIVITY_FRAME_VERIFIED_IN_TRACE
```

---

## 8. CRYPTOGRAPHIC BINDING & CANONICAL SERIALIZATION

All artifacts use identical cryptographic primitives from Phase 6.

### 8.1 Cryptographic Primitives

```
SHA-256:       NIST FIPS 180-4 (32-byte output)
HMAC-SHA-256:  FIPS 198 with constant-time comparison (32-byte output)
Encoding:      Big-endian, IEEE 754 for floats
Key derivation: Master key K_master (256-bit) per deployment
```

### 8.2 Canonical Serialization Order (All Artifacts)

```
CANONICAL_SERIALIZE(artifact):
  buffer ← []
  
  // 1. METADATA (fixed order)
  buffer.append(artifact.artifact_id)                    // 32 bytes
  buffer.append(to_big_endian(artifact.version))         // 4 bytes
  buffer.append(to_big_endian_u64(artifact.timestamp))   // 8 bytes
  buffer.append(to_big_endian_u64(artifact.creator))     // 8 bytes
  buffer.append(uint8(artifact.sealed_flag))             // 1 byte
  buffer.append(artifact.model_version_hash)             // 32 bytes
  buffer.append(artifact.connectome_version_hash)        // 32 bytes
  
  // 2. TYPE-SPECIFIC BODY
  // (Each artifact type defines its canonical order)
  body_canonical ← CANONICAL_SERIALIZE_BODY(artifact.body)
  buffer.append(body_canonical)
  
  // 3. DIGEST FIELDS (if applicable)
  buffer.append(artifact.payload_digest)                 // 32 bytes
  buffer.append(artifact.parent_digest)                  // 32 bytes
  // ... other digests in defined order
  
  // 4. INTEGRITY HASH (computed from above)
  buffer.append(artifact.integrity_hash)                 // 32 bytes
  // NOTE: HMAC_TAG is computed AFTER all other fields serialized
  
  return buffer
```

---

## 9. ADA/SPARK FORMAL CONTRACTS

Complete formal specifications for visualization provenance layer.

### 9.1 3D_Graph_Snapshot_Seal Contract

```ada
package Visualization_WORM_3D_Snapshot is

  type 3D_Graph_Snapshot is record
    snapshot_id: Snapshot_ID_Type;
    graph_version_id: Graph_Version_Type;
    node_count: uint64;
    edge_count: uint64;
    node_table: Node_Coordinate_Array;
    edge_table: Edge_Topology_Array;
    sealed_flag: Boolean;
    hmac_tag: SHA256_Hash;
  end record;

  -- Contract: Seal a 3D snapshot with cryptographic integrity
  -- Precondition: Snapshot not already sealed
  -- Postcondition: Sealed, HMAC computed, immutable
  -- Invariant: All nodes and edges remain constant after sealing
  procedure Seal_3D_Snapshot(
    snapshot: in out 3D_Graph_Snapshot;
    master_key: in Master_Key_Type
  ) with
    Pre => not snapshot.sealed_flag,
    Post => snapshot.sealed_flag and
            snapshot.hmac_tag = HMAC_SHA256(master_key, snapshot'Old) and
            snapshot.node_count = snapshot'Old.node_count and
            snapshot.edge_count = snapshot'Old.edge_count,
    Depends_On => (snapshot, master_key);

  -- Contract: Verify a sealed 3D snapshot's integrity
  -- Precondition: Snapshot is sealed
  -- Postcondition: True iff HMAC valid and digests match
  function Verify_3D_Snapshot_Sealed(
    snapshot: in 3D_Graph_Snapshot;
    master_key: in Master_Key_Type
  ) return Boolean with
    Pre => snapshot.sealed_flag,
    Post => Verify_3D_Snapshot_Sealed'Result = 
            (snapshot.hmac_tag = HMAC_SHA256(master_key, snapshot) and
             Node_Table_Digest_Valid(snapshot) and
             Edge_Table_Digest_Valid(snapshot));

end Visualization_WORM_3D_Snapshot;
```

### 9.2 2D_Projection_Linkage Contract

```ada
package Visualization_WORM_2D_Projection is

  type 2D_Projection is record
    projection_id: Projection_ID_Type;
    source_3d_snapshot_id: Snapshot_ID_Type;
    node_mapping: Node_Mapping_Array;
    edge_mapping: Edge_Mapping_Array;
    sealed_flag: Boolean;
    hmac_tag: SHA256_Hash;
  end record;

  type Verification_Status is (VERIFIED, LINKAGE_BROKEN, NODE_MAPPING_INVALID,
                               EDGE_MAPPING_INVALID, HMAC_INVALID);

  -- Contract: Verify 2D projection links correctly to source 3D
  -- Precondition: Both projection and 3D snapshot are sealed
  -- Postcondition: Complete bidirectional verification
  -- Invariant: Every 2D node/edge maps to exactly one 3D node/edge
  function Verify_2D_To_3D_Linkage(
    projection: in 2D_Projection;
    snapshot_3d: in 3D_Graph_Snapshot;
    master_key: in Master_Key_Type
  ) return Verification_Status with
    Pre => projection.sealed_flag and snapshot_3d.sealed_flag,
    Post => (if Verify_2D_To_3D_Linkage'Result = VERIFIED then
             (for all node_map of projection.node_mapping =>
              Exists_In_3D(node_map.cat_n_id, snapshot_3d) and
              Position_Consistent(node_map, snapshot_3d)) and
             (for all edge_map of projection.edge_mapping =>
              Exists_In_3D(edge_map.cat_s_id, snapshot_3d) and
              Connectivity_Preserved(edge_map, snapshot_3d)) and
             HMAC_Valid(projection, master_key)
            else
             Verify_2D_To_3D_Linkage'Result in 
               (LINKAGE_BROKEN | NODE_MAPPING_INVALID |
                EDGE_MAPPING_INVALID | HMAC_INVALID)
            );

end Visualization_WORM_2D_Projection;
```

### 9.3 Activity_Frame_Coherence Contract

```ada
package Visualization_WORM_Activity_Frame is

  type Activity_Frame is record
    frame_id: Frame_ID_Type;
    timestep: uint64;
    active_neurons: Neuron_State_Array;
    active_synapses: Synapse_State_Array;
    behavioral_outputs: Behavioral_Output_Array;
    sealed_flag: Boolean;
    hmac_tag: SHA256_Hash;
  end record;

  -- Contract: Verify activity frame neuron/synapse coherence
  -- Precondition: Frame is sealed
  -- Postcondition: Neuron and synapse states are consistent
  -- Invariant: Each synapse's source and dest appear in active neurons
  function Verify_Activity_Frame_Coherence(
    frame: in Activity_Frame;
    master_key: in Master_Key_Type
  ) return Boolean with
    Pre => frame.sealed_flag,
    Post => (for all synapse of frame.active_synapses =>
             (Exists_Neuron(synapse.source_cat_n, frame) and
              Exists_Neuron(synapse.dest_cat_n, frame))) and
            HMAC_Valid(frame, master_key);

end Visualization_WORM_Activity_Frame;
```

### 9.4 Behavioral_Trace_Integrity Contract

```ada
package Visualization_WORM_Behavioral_Trace is

  type Behavioral_Trace is record
    trace_id: Trace_ID_Type;
    frame_array: Activity_Frame_Array;
    action_sequence: Action_Array;
    sealed_flag: Boolean;
    hmac_tag: SHA256_Hash;
  end record;

  -- Contract: Verify complete trace chain and action sequence
  -- Precondition: Trace is sealed
  -- Postcondition: All frames linked, actions consistent
  -- Invariant: Frame indices monotonic, actions within frame timesteps
  function Verify_Behavioral_Trace_Integrity(
    trace: in Behavioral_Trace;
    master_key: in Master_Key_Type
  ) return Boolean with
    Pre => trace.sealed_flag,
    Post => (for all i in 0 .. trace.frame_array'Length - 2 =>
             trace.frame_array(i).timestep < trace.frame_array(i+1).timestep) and
            (for all action of trace.action_sequence =>
             (action.frame_index < trace.frame_array'Length and
              Frame_Timestamp_Contains_Action(
                trace.frame_array(action.frame_index), action))) and
            HMAC_Valid(trace, master_key);

end Visualization_WORM_Behavioral_Trace;
```

### 9.5 Bidirectional_Traceability_Invariant

```ada
package Visualization_WORM_Bidirectional_Traceability is

  -- INVARIANT: Traceability in both directions
  -- Forward: 2D artifact → 3D snapshot → GPU phase 6 artifact
  -- Reverse: GPU artifact → 3D snapshot → 2D projection
  
  procedure Verify_Forward_Traceability(
    projection_2d: in 2D_Projection;
    snapshot_3d: in 3D_Graph_Snapshot;
    gpu_artifact: in GPU_Buffer;
    master_key: in Master_Key_Type
  ) with
    Pre => projection_2d.sealed_flag and
           snapshot_3d.sealed_flag and
           gpu_artifact.sealed_flag,
    Post => (snapshot_3d.gpu_phase6_link = GPU_Link(gpu_artifact) and
             projection_2d.source_3d_snapshot_id = snapshot_3d.snapshot_id and
             All_Projected_Nodes_In_3D(projection_2d, snapshot_3d) and
             All_Projected_Edges_In_3D(projection_2d, snapshot_3d));

  procedure Verify_Reverse_Traceability(
    gpu_artifact: in GPU_Buffer;
    snapshot_3d: in 3D_Graph_Snapshot;
    projection_2d: in 2D_Projection;
    master_key: in Master_Key_Type
  ) with
    Pre => gpu_artifact.sealed_flag and
           snapshot_3d.sealed_flag and
           projection_2d.sealed_flag,
    Post => (GPU_Nodes_In_3D(gpu_artifact, snapshot_3d) and
             GPU_Edges_In_3D(gpu_artifact, snapshot_3d) and
             GPU_Nodes_Subset_Of_Projected(gpu_artifact, projection_2d));

end Visualization_WORM_Bidirectional_Traceability;
```

---

## 10. FAIL-CLOSED GUARANTEE SPECIFICATION

### 10.1 Verification Failure Modes

```
FAILURE_MODE: 2D Projection HMAC Fails
  Detection: HMAC_SHA256(K, projection) != projection.hmac_tag
  Action: Set halt_flag = true, log tampering alert
  Recovery: None (artifact possibly corrupted)
  
FAILURE_MODE: 2D Node Maps to Non-Existent 3D Node
  Detection: node_mapping.source_3d_idx >= source_3d.node_count
  Action: Set halt_flag = true, log mapping error
  Recovery: None (linkage broken)
  
FAILURE_MODE: 2D Projected Position Diverges from 3D
  Detection: distance(projected_2d, expected_2d) > tolerance
  Action: Set halt_flag = true, log projection error
  Recovery: None (visualization corrupted)
  
FAILURE_MODE: Activity Frame CAT-N/CAT-S Not in Graph
  Detection: Neuron/synapse not in connected graph
  Action: Set halt_flag = true, log consistency error
  Recovery: None (frame data invalid)
  
FAILURE_MODE: Behavioral Trace Frame Chain Broken
  Detection: frame.parent_frame_digest != previous_frame.frame_digest
  Action: Set halt_flag = true, log chain error
  Recovery: None (trace integrity compromised)
```

### 10.2 Verification Pipeline at Visualization Start

```
VISUALIZATION_VERIFICATION_PIPELINE:

1. Load 2D projection artifact
2. Verify HMAC
   If fails → Halt with error
3. Load source 3D snapshot by ID
4. Verify 3D snapshot HMAC
   If fails → Halt with error
5. For each node mapping:
   a) Verify source index in bounds
   b) Verify CAT-N ID match
   c) Verify projected position within tolerance
   If any fails → Halt
6. For each edge mapping:
   a) Verify source index in bounds
   b) Verify CAT-S ID match
   c) Verify connectivity preserved
   If any fails → Halt
7. Load projection parameters
8. Verify transformation matrices invertible
   If fails → Halt
9. Verify 3D snapshot links to GPU artifact
   If fails → Halt
10. Load associated activity frames and behavioral trace
11. Verify all frames sealed and chained
    If any fails → Halt
12. Verify neuron/synapse coherence in each frame
    If any fails → Halt
13. If all verifications pass → Display visualization
14. Otherwise → Halt, show error, exit
```

---

## 11. PROJECTION TRACEABILITY EXAMPLES

### 11.1 Example: Visual Cortex Layer 2/3 Projection

```
ARTIFACT_CHAIN for Visual Cortex L2/3 Display:

GPU_PHASE6_ARTIFACT
  └─ Neuron_Index_Table (760M neurons, V1 region neurons in GPU)
     CAT-N IDs: [V1_pyr_0001, V1_pyr_0002, ..., V1_gaba_5432]
     
3D_GRAPH_SNAPSHOT
  └─ snapshot_id = SHA256(GPU_artifact_version + timestamp_t0)
     ├─ Links to: GPU_PHASE6_ARTIFACT via gpu_phase6_link_digest
     ├─ Node_Coordinate_Table:
     │  V1_pyr_0001: (10.5, 20.3, 15.2)
     │  V1_pyr_0002: (11.2, 21.1, 14.9)
     │  ... (760M nodes with x,y,z)
     ├─ Edge_Topology_Table:
     │  CAT_S_00001: V1_pyr_0001 → V1_pyr_0002 (Excitatory)
     │  CAT_S_00002: V1_gaba_5432 → V1_pyr_0001 (Inhibitory)
     │  ... (1B edges)
     ├─ Anatomical_Hierarchy:
     │  V1_pyr_0001: region=V1, layer=2/3
     │  V1_pyr_0002: region=V1, layer=2/3
     │  ... (360M V1 neurons)
     └─ Sealed with HMAC

PROJECTION_PARAMETERS
  └─ parameter_id = SHA256("Circuit-Specific-V1L2/3" + timestamp)
     ├─ Algorithm: Circuit-Specific with layer emphasis
     ├─ Viewing_Plane: XY (planar view of layer)
     ├─ Camera_Position: (2000, 2000, 5000) mm (above layer)
     ├─ Transform_Matrix: Orthogonal projection + layer rotation
     ├─ Anatomical_Filter: region=V1, layer=2/3
     └─ Sealed with HMAC

2D_PROJECTION
  └─ projection_id = SHA256(parameter_id + "viewport_1024x768" + timestamp)
     ├─ source_3d_snapshot_id = 3D_GRAPH_SNAPSHOT.snapshot_id
     ├─ resolution: 1024 x 768 pixels
     ├─ node_mapping: 120M visible neurons (subset of 360M L2/3 neurons)
     │  V1_pyr_0001 → (512, 384, 0.5)  // center of screen
     │  V1_pyr_0002 → (515, 387, 0.51)
     │  ... (120M entries)
     ├─ edge_mapping: 2B visible synapses
     │  CAT_S_00001: (512,384) → (515,387)
     │  CAT_S_00002: (510,382) → (512,384)
     │  ... (2B edges)
     ├─ CAT_N_reference_array: [V1_pyr_0001, ..., V1_pyr_N] (120M)
     ├─ CAT_S_reference_array: [CAT_S_00001, ..., CAT_S_M] (2B)
     └─ Sealed with HMAC

ACTIVITY_FRAME (timestep t = 50ms)
  └─ frame_id = SHA256(3D_snapshot_id + "t=50ms")
     ├─ active_neuron_states: 12M neurons spiking at t=50ms
     │  V1_pyr_0001: V_m=-55mV, spike=true, firing_rate=45Hz, ...
     │  V1_pyr_0002: V_m=-62mV, spike=false, firing_rate=12Hz, ...
     │  ... (12M active neurons)
     ├─ active_synapse_states: 85M active synapses
     │  CAT_S_00001: transmitter_conc=50nM, recent_spikes=3, ...
     │  CAT_S_00002: transmitter_conc=20nM, recent_spikes=1, ...
     │  ... (85M active synapses)
     ├─ behavioral_outputs: Motor action triggered
     │  Output: eye_movement, intensity=0.8, duration=100ms
     │  Source_neurons: [V1_pyr_N, ... (100 neurons from motor cortex)]
     └─ Sealed with HMAC

BEHAVIORAL_TRACE (episode: visual stimulus response, duration 5s)
  └─ trace_id = SHA256(brain_id + "stimulus_episode_1" + timestamp)
     ├─ episode_id = "visual_stimulus_response_5s"
     ├─ frame_count = 500 (one frame per 10ms)
     ├─ activity_frame_array:
     │  [ACTIVITY_FRAME(t=0), ACTIVITY_FRAME(t=10ms), ..., ACTIVITY_FRAME(t=490ms)]
     │  Each frame sealed and linked to previous via parent_frame_digest
     ├─ action_sequence:
     │  Action 0: t=100ms, eye_movement, left
     │  Action 1: t=200ms, eye_movement, right
     │  Action 2: t=400ms, pupil_dilation, 0.5
     │  ... (20 behavioral outputs)
     ├─ aggregate_statistics:
     │  total_spikes = 45M
     │  neurons_active = 250M
     │  mean_firing_rate = 8.5 Hz
     │  network_synchrony = 0.23
     └─ Sealed with HMAC

TRACEABILITY PROOF:
  ✓ V1_pyr_0001 visible in 2D projection (512, 384)
  ✓ Maps to 3D coordinate (10.5, 20.3, 15.2)
  ✓ Has CAT-N ID V1_pyr_0001
  ✓ 3D graph snapshot came from GPU Phase 6 artifact
  ✓ At t=50ms, V1_pyr_0001 spiked (found in activity frame)
  ✓ Contributed to motor action via 2 synapses
  ✓ Action recorded in behavioral trace
  ✓ All artifacts sealed and HMAC verified
  → Complete bidirectional traceability established
```

---

## 12. IMPLEMENTATION CHECKLIST

**Core Structures**:
- [ ] Implement 3D_Graph_Snapshot with coordinate table and edge topology
- [ ] Implement 2D_Projection with node/edge mapping and reference arrays
- [ ] Implement Projection_Parameters with transformation matrices
- [ ] Implement Activity_Frame with neuron/synapse state and behavioral outputs
- [ ] Implement Behavioral_Trace with frame array and action sequence

**Canonical Serialization**:
- [ ] Implement canonical serialization for all visualization artifacts
- [ ] Big-endian encoding for all numeric types
- [ ] IEEE 754 float64 encoding for coordinates
- [ ] Deterministic ordering for all variable-length arrays

**Cryptographic Operations**:
- [ ] SHA-256 digest computation for all artifacts
- [ ] HMAC-SHA-256 tagging with constant-time comparison
- [ ] Parent digest chain linking
- [ ] Digest verification at load time

**Traceability Verification**:
- [ ] Implement forward verification (2D → 3D → GPU)
- [ ] Implement reverse verification (GPU → 3D → 2D)
- [ ] Implement projection position tolerance checks
- [ ] Implement edge connectivity validation
- [ ] Implement activity frame coherence verification
- [ ] Implement behavioral trace chain verification

**Ada/SPARK Contracts**:
- [ ] Write formal contracts for all seal operations
- [ ] Write formal contracts for all verification functions
- [ ] Specify preconditions, postconditions, and invariants
- [ ] Document fail-closed guarantees

**Fail-Closed Integration**:
- [ ] Verify all artifacts sealed before visualization
- [ ] Halt on any HMAC verification failure
- [ ] Halt on any mapping validation failure
- [ ] Halt on any chain linkage failure
- [ ] Comprehensive error logging with timestamps

**Integration**:
- [ ] Link to Phase 6 GPU verification pipeline
- [ ] Verify 3D snapshots trace to GPU artifacts
- [ ] Verify activity frames trace to GPU behavioral outputs
- [ ] Maintain cryptographic key consistency across phases

---

## 13. PROOF OF TRACEABILITY

Every 2D visualization element is traceable to source via immutable artifact chain:

**Traceability Path**:
```
2D_Projection.pixel_element(x, y)
  └─ Maps to node_mapping[i].projected_position
     └─ References node_mapping[i].cat_n_id (e.g., V1_pyr_0001)
        └─ Resolves to 3D_Graph_Snapshot.node_table[index].cat_n_id
           └─ 3D coordinates (x,y,z) retrievable
              └─ 3D_Graph_Snapshot.gpu_phase6_link_digest
                 └─ GPU_Phase_6_Artifact.neuron_index_table[cat_n_id]
                    └─ CAT_N_ID immutably linked to neuron identity
                       └─ Activity_Frame.active_neuron_states[cat_n_id]
                          └─ Membrane potential, spike state, firing rate
                             └─ Behavioral_Trace.action_sequence
                                └─ Motor output triggered by this neuron
```

**Cryptographic Binding**:
- Each step in chain is cryptographically sealed (HMAC-SHA-256)
- Each artifact links to predecessor via digest (SHA-256)
- No artifact can be modified after sealing
- Tampering detection via HMAC verification
- Fail-closed guarantee: corrupted artifact halts visualization

---

## 14. SUMMARY

Phase 7 Visualization WORM Provenance Layer provides:

1. **Complete Artifact Catalog**: All visualization artifacts structured with cryptographic integrity
2. **Bidirectional Traceability**: Forward (2D→GPU) and reverse (GPU→2D) verification
3. **3D Graph Snapshots**: Complete node/edge/coordinate snapshots linked to GPU Phase 6
4. **2D Projections**: Screen-space rendering with complete mapping to source 3D elements
5. **Activity Frames**: Per-timestep neuron/synapse state with behavioral integration
6. **Behavioral Traces**: Episode-level traces chaining activity frames and actions
7. **Formal Contracts**: Ada/SPARK specifications with pre/post conditions and invariants
8. **Fail-Closed Guarantee**: Corrupted artifacts never silently used; all failures halt visualization
9. **Canonical Serialization**: Deterministic, reproducible, order-independent verification
10. **Scale Support**: 760M neurons, 1B synapses, 760B visualization elements

**Key Properties**:
- Every 2D pixel element traceable to 3D node/edge
- Every 3D graph traceable to GPU Phase 6 artifact
- Every activity state traceable to behavioral output
- All artifacts cryptographically sealed and chained
- Complete provenance from GPU simulation to visualization display

**End of Phase 7 Specification**
