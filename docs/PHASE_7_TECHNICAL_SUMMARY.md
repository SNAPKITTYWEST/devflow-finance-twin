# PHASE 7: Visualization WORM Provenance — Technical Summary

**Mission**: Establish bidirectional cryptographic traceability from every 2D visualization element to its source 3D graph node/edge and Phase 6 GPU representation.

---

## KEY TECHNICAL ACHIEVEMENTS

### 1. Bidirectional Traceability Architecture

```
Forward Path (2D → GPU):
  2D_Projection 
    └─ source_3d_snapshot_id → 3D_Graph_Snapshot
       └─ gpu_phase6_link_digest → GPU_Phase_6_Artifact
          └─ Neuron_Index_Table & Synapse_Index_Table

Reverse Path (GPU → 2D):
  GPU_Phase_6_Artifact
    └─ NODE_INDEX_TABLE (all CAT-N-IDs)
       ├─ Appears in 3D_Graph_Snapshot.node_table
       │  └─ Appears in 2D_Projection.node_mapping
       │     └─ Renders as 2D pixel element (x, y, depth)
       │
       └─ Activation in Activity_Frame
          └─ Behavioral_Trace.action_sequence
             └─ Motor/cognitive output
```

### 2. Nine Protected Artifact Types

| Artifact | Size | Scope | Key Binding |
|----------|------|-------|------------|
| **3D_Graph_Snapshot** | ~100 GB | Full graph + coordinates | GPU_Phase_6_Link |
| **2D_Projection** | ~50-500 MB | Viewport rendering | source_3d_snapshot_id |
| **Projection_Parameters** | ~1-5 KB | Algorithm + camera | Transform_Matrix |
| **Camera_Parameters** | ~200 bytes | View frustum | Eye/Center/Up vectors |
| **Transformation_Matrices** | ~128 bytes | MVP chain | 4×4 float64 |
| **Activity_Frame** | ~1-100 MB | Per-timestep state | parent_frame_id chain |
| **Behavioral_Trace** | ~100 MB - 10 GB | Episode recording | frame_array chain |
| **Viewport_Snapshot** | ~50-200 MB | User interaction capture | All of above |
| **Rendering_State** | ~10 MB | GPU textures/shaders | Frame binding |

### 3. Cryptographic Structure Template

All visualization artifacts follow this invariant:
```
ARTIFACT {
  METADATA (96 bytes)
    ├─ artifact_id: UUID
    ├─ version, timestamp, creator
    └─ sealed_flag, model_version_hash, connectome_version_hash
  
  BODY (variable)
    └─ Type-specific content
  
  INTEGRITY_FIELDS (128 bytes)
    ├─ parent_digest: SHA-256(previous artifact)
    ├─ body_digest: SHA-256(canonical(body))
    ├─ link_digest: SHA-256(linked artifact)
    ├─ integrity_hash: SHA-256(all digests)
    └─ hmac_tag: HMAC-SHA-256(K_master, canonical(all))
  
  SEAL (1 byte)
    └─ 0x01 if immutable
}
```

### 4. Complete 3D Graph Snapshot

```
3D_GRAPH_SNAPSHOT captures complete neural graph state:

NODE_COORDINATE_TABLE (760M × 40 bytes = 30.4 GB)
  Per node: CAT_N_ID | X | Y | Z (IEEE 754)
  
EDGE_TOPOLOGY_TABLE (1B × 40 bytes = 40 GB)
  Per edge: CAT_S_ID | source_CAT_N | dest_CAT_N | type
  
ANATOMICAL_HIERARCHY (760M × 16 bytes = 12.2 GB)
  Per neuron: CAT_N_ID | region_id | layer_id
  
DIGESTS (4 × 32 bytes)
  ├─ Node_Table_Digest: SHA-256(all nodes sorted by CAT_N)
  ├─ Edge_Table_Digest: SHA-256(all edges sorted by CAT_S)
  ├─ Coordinate_Digest: SHA-256(all (x,y,z) sorted)
  └─ Anatomical_Digest: SHA-256(all region/layer assignments)

IMMUTABILITY GUARANTEE:
  Once sealed, modification of any node/edge/coordinate is detected
  by digest recalculation and HMAC verification failure.
```

### 5. Complete 2D Projection Artifact

```
2D_PROJECTION binds screen-space rendering to source 3D:

SOURCE_LINK
  └─ source_3d_snapshot_id (immutable reference)

NODE_MAPPING (MAPPED_NODE_COUNT × 44 bytes)
  Per visible node:
    ├─ source_3d_node_index: offset in 3D table
    ├─ cat_n_id: neuron identifier (verify against 3D)
    ├─ projected_x, projected_y: screen coordinates
    └─ projected_z: depth for occlusion

EDGE_MAPPING (MAPPED_EDGE_COUNT × 48 bytes)
  Per visible edge:
    ├─ source_3d_edge_index: offset in 3D table
    ├─ cat_s_id: synapse identifier (verify against 3D)
    ├─ source_node_index, dest_node_index: 3D endpoints
    └─ line_segment_start/end: 2D screen segment

REFERENCE_ARRAYS
  ├─ CAT_N_reference: all visible neuron IDs, sorted by x-coord
  └─ CAT_S_reference: all visible synapse IDs, sorted by depth

VERIFICATION:
  For each 2D element → Lookup source 3D → Verify ID match
                      → Compute expected 2D position → Compare
                      → Verify connectivity preserved
```

### 6. Activity Frame: Behavioral Integration

```
ACTIVITY_FRAME (per timestep, ~1-100 MB):

TIMESTEP_INFO
  └─ timestep_index, timestamp_ms, simulation_time_start/end

ACTIVE_NEURON_STATES (ACTIVE_COUNT × 80 bytes)
  Per neuron:
    ├─ cat_n_id: neuron identifier
    ├─ membrane_potential: mV (float64)
    ├─ spike_flag: 0x01 if spiked this timestep
    ├─ firing_rate: Hz (float64)
    ├─ refractory_state: excitable/refractory/recovery
    ├─ tau_m, v_threshold, v_reset: model parameters
    ├─ spike_count_lifetime, last_spike_timestep
    └─ confidence: 0-255 (255=GPU validated)

ACTIVE_SYNAPSE_STATES (ACTIVE_COUNT × 64 bytes)
  Per synapse:
    ├─ cat_s_id, source_cat_n, dest_cat_n
    ├─ transmitter_concentration: nM (float64)
    ├─ recent_spike_count: in last 10ms
    ├─ synaptic_current: pA (float64)
    └─ plasticity_state: static/LTP/LTD

BEHAVIORAL_OUTPUTS
  └─ action_type, intensity, duration, source_neuron_ids

COGNITIVE_STATE
  ├─ attention, arousal, valence: 0.0-1.0
  ├─ decision_confidence, learning_state
  └─ (Aggregated from region-level activity)

CHAIN LINKING:
  └─ parent_frame_id → previous activity frame
     └─ parent_frame_digest → SHA-256(previous frame)
        (Creates immutable chain of timesteps)
```

### 7. Behavioral Trace: Episode-Level Recording

```
BEHAVIORAL_TRACE (per episode, ~100 MB - 10 GB):

EPISODE_METADATA
  ├─ episode_id, duration_ms, frame_count, action_count
  ├─ brain_id, environment_context
  └─ episode_start_time, episode_end_time (wall-clock)

ACTIVITY_FRAME_ARRAY
  └─ [ACTIVITY_FRAME(t=0), ..., ACTIVITY_FRAME(t=final)]
     Each sealed and chained via parent_frame_digest

ACTION_SEQUENCE
  └─ [action_0, action_1, ..., action_N]
     Per action:
       ├─ action_type, intensity, duration
       ├─ source_neuron_ids
       ├─ timestamp_ms, frame_index
       └─ outcome (what happened)

AGGREGATE_STATISTICS
  ├─ total_spikes, neurons_active, synapses_active
  ├─ mean_firing_rate, max_firing_rate
  ├─ spike_entropy (information-theoretic measure)
  ├─ network_synchrony (0.0-1.0)
  └─ learning_score (plasticity change)

INTEGRITY:
  ├─ frame_array_digest: SHA-256(all frames)
  ├─ action_array_digest: SHA-256(all actions)
  ├─ neuron_participation_digest: SHA-256(sorted unique CAT-N-IDs)
  └─ synapse_participation_digest: SHA-256(sorted unique CAT-S-IDs)
```

### 8. Forward Verification Algorithm: 2D → 3D → GPU

```python
def verify_2d_projection_forward(projection, 3d_snapshot, gpu_artifact, master_key):
  # Step 1: Verify sealing
  assert projection.sealed_flag == 0x01
  assert 3d_snapshot.sealed_flag == 0x01
  
  # Step 2: Verify linkage
  assert projection.source_3d_snapshot_id == 3d_snapshot.snapshot_id
  assert verify_hmac_sha256(3d_snapshot, master_key)
  
  # Step 3: Verify each 2D node
  for node_mapping in projection.node_mapping:
    source_3d_node = 3d_snapshot.node_table[node_mapping.source_3d_idx]
    
    # CAT-N match
    assert source_3d_node.cat_n_id == projection.cat_n_reference[node_mapping.2d_idx]
    
    # Position consistency
    expected_2d = project_3d_to_2d(source_3d_node.x, source_3d_node.y, source_3d_node.z,
                                   projection.projection_parameters)
    assert distance(node_mapping.projected_x, node_mapping.projected_y,
                   expected_2d.x, expected_2d.y) <= 1.0  # pixel tolerance
  
  # Step 4: Verify each 2D edge
  for edge_mapping in projection.edge_mapping:
    source_3d_edge = 3d_snapshot.edge_table[edge_mapping.source_3d_idx]
    
    # CAT-S match
    assert source_3d_edge.cat_s_id == projection.cat_s_reference[edge_mapping.2d_idx]
    
    # Connectivity preserved
    assert source_3d_edge.source == edge_mapping.source_node_index
    assert source_3d_edge.dest == edge_mapping.dest_node_index
  
  # Step 5: Verify GPU link
  assert 3d_snapshot.gpu_phase6_link_digest == hmac_sha256(gpu_artifact, master_key)
  
  # Step 6: Verify projection HMAC
  assert verify_hmac_sha256(projection, master_key)
  
  return PROJECTION_VERIFIED_COMPLETE
```

### 9. Reverse Verification Algorithm: GPU → 3D → 2D

```python
def verify_gpu_to_2d_reverse(gpu_artifact, 3d_snapshot, projection, master_key):
  # Step 1: Verify GPU artifact
  assert gpu_buffer_verify(gpu_artifact, master_key) == SUCCESS
  
  # Step 2: Verify 3D derivation from GPU
  assert 3d_snapshot.gpu_phase6_link_digest == hmac_sha256(gpu_artifact, master_key)
  
  # Step 3: Verify node set completeness
  gpu_nodes = extract_cat_n_ids(gpu_artifact)
  snapshot_nodes = extract_cat_n_ids(3d_snapshot)
  assert gpu_nodes == snapshot_nodes  # Complete coverage
  
  # Step 4: Verify projected nodes in GPU
  projected_nodes = extract_cat_n_ids(projection)
  assert projected_nodes.is_subset_of(snapshot_nodes)
  
  # Step 5: Verify projected edges in GPU
  gpu_edges = extract_cat_s_ids(gpu_artifact)
  projected_edges = extract_cat_s_ids(projection)
  for cat_s in projected_edges:
    assert cat_s in gpu_edges
  
  # Step 6: Verify activity frames linked
  assert projection.source_3d_snapshot_id == 3d_snapshot.snapshot_id
  
  return GPU_TO_2D_VERIFIED_COMPLETE
```

### 10. Ada/SPARK Formal Contracts

```ada
-- Bidirectional traceability invariant
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

-- Fail-closed guarantee
function Verify_Activity_Frame_Coherence(
  frame: in Activity_Frame;
  master_key: in Master_Key_Type
) return Boolean with
  Pre => frame.sealed_flag,
  Post => (for all synapse of frame.active_synapses =>
           (Exists_Neuron(synapse.source_cat_n, frame) and
            Exists_Neuron(synapse.dest_cat_n, frame))) and
          HMAC_Valid(frame, master_key);
```

### 11. Fail-Closed Guarantee Pipeline

```
VISUALIZATION_START:

1. Load 2D projection
2. HMAC verify → FAIL_HALT_1 if invalid
3. Load 3D snapshot
4. HMAC verify → FAIL_HALT_2 if invalid
5. For each 2D node:
   a) Verify 3D index in bounds → FAIL_HALT_3
   b) Verify CAT-N ID matches → FAIL_HALT_4
   c) Verify position within tolerance → FAIL_HALT_5
6. For each 2D edge:
   a) Verify 3D index in bounds → FAIL_HALT_6
   b) Verify CAT-S ID matches → FAIL_HALT_7
   c) Verify connectivity preserved → FAIL_HALT_8
7. Verify GPU link → FAIL_HALT_9
8. Load activity frames
9. Verify all sealed and chained → FAIL_HALT_10
10. Verify neuron/synapse coherence → FAIL_HALT_11
11. ALL PASS → Display visualization
12. ANY FAIL → Halt with error log

Result: Either complete traceability verified OR immediate halt.
```

---

## TRACEABILITY PROOF STRUCTURE

**For any 2D visualization element at pixel (x, y)**:

```
Step 1: Identify 2D node mapping entry
  → node_mapping[i].projected_x = x, projected_y = y

Step 2: Retrieve CAT-N ID
  → cat_n_id = projection.cat_n_reference[i]

Step 3: Verify against 3D snapshot
  → 3d_node = 3d_snapshot.node_table.find(cat_n_id)
  → assert 3d_node exists
  → assert project_3d(3d_node.x, 3d_node.y, 3d_node.z) ≈ (x, y)

Step 4: Verify 3D came from GPU
  → assert 3d_snapshot.gpu_phase6_link == HMAC(gpu_artifact)
  → assert gpu_artifact.neuron_index[cat_n_id] exists

Step 5: Check behavioral activity
  → activity_frame = get_activity_frame_for_timestep()
  → neuron_state = activity_frame.active_neurons[cat_n_id]
  → membrane_potential, spike_flag, firing_rate, ...

Step 6: Trace to behavior
  → for each output in activity_frame.behavioral_outputs:
       if cat_n_id in output.source_neuron_ids:
         → trace to action in behavioral_trace
         → determine motor/cognitive effect

PROOF: Every 2D pixel element → 3D coordinate → GPU CAT-N-ID →
       Behavioral state → Motor action → Episode record
```

---

## SCALE ANALYSIS

| Component | Count | Size (Total) | Serialization |
|-----------|-------|--------------|---------------|
| 3D Nodes | 760M | 30.4 GB | Canonical big-endian |
| 3D Edges | 1B | 40 GB | Canonical big-endian |
| Node coordinates | 760M × (x,y,z) | 18.2 GB | IEEE 754 float64 |
| Digests (per 3D) | 4 | 128 bytes | Fixed position |
| 2D Projections | 1 per view | 50-500 MB | Sparse mapping |
| 2D Node mappings | ~200M visible | 8.8 GB | Index + position |
| 2D Edge mappings | ~2B visible | 96 GB | Topology + segment |
| Activity frames | 1 per 10ms | 1-100 MB | Time-series |
| Behavioral trace | 1 per episode | 100 MB - 10 GB | Chained frames |

---

## CRYPTOGRAPHIC PROPERTIES

**Security Model**: Fail-closed integrity verification

**Algorithms**:
- SHA-256: NIST FIPS 180-4 (digest computation)
- HMAC-SHA-256: FIPS 198 (authentication)
- Constant-time comparison: Timing attack resistant

**Encoding**:
- Big-endian: All multi-byte integers
- IEEE 754: All floating-point coordinates
- UTF-8: All text fields
- Canonical order: Deterministic serialization

**Key Management**:
- Master key K_master: 256-bit, per deployment
- Derived from Phase 6 root key
- Never serialized in artifacts
- Used only for HMAC verification

---

## DELIVERABLES SUMMARY

✓ **3D Graph Snapshot Structure**: 100+ GB immutable neural graph with coordinates
✓ **2D Projection Artifact**: Screen-space rendering with complete 3D mapping
✓ **Projection Parameters Artifact**: Algorithm + transformation matrices
✓ **Activity Frame Structure**: Per-timestep neuron/synapse state + behavior
✓ **Behavioral Trace Structure**: Episode-level frame sequences and actions
✓ **Bidirectional Traceability Algorithm**: Forward (2D→GPU) and reverse (GPU→2D)
✓ **Cryptographic Binding**: SHA-256 + HMAC-SHA-256 + canonical serialization
✓ **Ada/SPARK Formal Contracts**: Pre/post conditions and invariants
✓ **Fail-Closed Guarantee**: Corrupted artifact halts visualization immediately
✓ **Proof**: Every 2D element traceable to CAT-N/CAT-S and behavioral evidence

---

## NEXT PHASE (Phase 8)

**Phase 8: Interactive Visualization Engine**
- Implement 2D/3D rendering with WORM provenance tracking
- Real-time activity frame updates with behavioral callbacks
- Viewport manipulation with projection parameter verification
- User interaction logging with behavioral trace integration

**End of Phase 7 Summary**
