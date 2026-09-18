# 3D ANATOMICAL GRAPH SPECIFICATION
## Phase 7: Dylan Visualization Engineer

**Version:** 1.0  
**Status:** Design Specification  
**Date:** 2026-09-13  
**Purpose:** Formal blueprint for 3D neural visualization graph preserving CAT-N-ID and CAT-S-ID identity

---

## SECTION 1: GRAPH ARCHITECTURE OVERVIEW

### 1.1 Core Principle
Every visualization node/edge retains biological identity. **No visualization-only IDs replace CAT-N/CAT-S.**

### 1.2 Graph Components
- **Vertex Layer:** Neurons (CAT-N-XXXXXXXXXXXXXXXX)
- **Edge Layer:** Synapses (CAT-S-XXXXXXXXXXXXXXXX)
- **Spatial Layer:** 3D coordinates (micrometers, immutable)
- **Hierarchical Layer:** Brain → Region → Subregion → Layer → Neuron
- **State Layer:** Membrane potential, spike state, activity metrics
- **Provenance Layer:** Evidence ledger references, source chain

---

## SECTION 2: 3D GRAPH NODE STRUCTURE

### 2.1 Node Identity (Immutable)
```
neuron_id:           CAT-N-XXXXXXXXXXXXXXXX  [immutable biological ID]
unique_3d_index:     uint32                  [graph-specific fast lookup, unique per LOD]
```

**Rule:** `neuron_id` is canonical. `unique_3d_index` exists for GPU buffer indexing only.

### 2.2 Spatial Position (Source Coordinates, Immutable)
```
x_um:                float64  [micrometers, from Phase 6 GPU validated]
y_um:                float64
z_um:                float64

display_x:           float32  [optional: transformed for viewport]
display_y:           float32
display_z:           float32
```

**Rule:** Source coordinates never overwritten. Display coordinates are computed, not stored permanently.

### 2.3 Anatomical Classification
```
region_id:           string   [enum: prefrontal_cortex, motor_cortex, hippocampus, 
                                      cerebellum, amygdala, striatum, thalamus,
                                      hypothalamus, brainstem, midbrain, pons,
                                      medulla, substantia_nigra, ventral_tegmentum,
                                      nucleus_accumbens, globus_pallidus, 
                                      putamen, caudate, insula, temporal_cortex]

subregion_id:        string   [ontology-qualified, e.g., "CA3_pyramidal_field"]

layer_id:            string   [cortex: "L1", "L2", "L3", "L4", "L5", "L6"
                                brainstem/cerebellum: "granule_layer", "molecular_layer"
                                hippocampus: "CA1", "CA3", "DG"
                                non-layered: "UNKNOWN"]

neuron_type:         string   [enum: pyramidal, fast_spiking_basket, chandelier,
                                      parvalbumin_positive, somatostatin_positive,
                                      vip_positive, dopaminergic, serotonergic,
                                      cholinergic, glutamatergic, gabaergic,
                                      purkinje, granule, interneuron, UNKNOWN]
```

### 2.4 Morphology
```
morphology: {
  soma_diameter_um:     float32  [soma radius in micrometers]
  dendrite_extent_um:   float32  [dendritic arbor span]
  axon_diameter_um:     float32  [axon caliber]
  axon_initial_segment_um: float32
  spine_density_per_um: float32  [spines per micrometer, if applicable]
}
```

### 2.5 Neural State (Phase 6 GPU Derived)
```
membrane_potential:  float32  [millivolts, −90mV to +30mV typical]
spike_count:         uint32   [cumulative spike events in current window]
last_spike_time:     float64  [milliseconds, simulation time]
refractory_state:    enum     [RESPONSIVE, REFRACTORY_ABSOLUTE, REFRACTORY_RELATIVE]
model_id:            enum     [HODGKIN_HUXLEY, INTEGRATE_AND_FIRE, 
                               IAF_WITH_ADAPTATION, POISSON_DECODER]
```

### 2.6 Provenance (Evidence Ledger)
```
evidence_level:      enum     [DOCUMENTED (gold standard),
                               OBSERVED (experimental patch clamp),
                               INFERRED (statistical model),
                               MODELED (synthetic for missing data),
                               UNKNOWN (no supporting evidence)]

source_reference:    string   [claim ID from Phase 5 evidence ledger]
model_version:       string   [e.g., "1.0", "1.1_with_A_current"]
graph_version:       string   [e.g., "7.0"]
validation_timestamp: float64  [when last validated against Phase 6 canonical state]
```

### 2.7 Node Summary
```json
{
  "neuron_id": "CAT-N-XXXXXXXXXXXXXXXX",
  "unique_3d_index": 12847,
  "position": {
    "x_um": 450.123,
    "y_um": 320.456,
    "z_um": 89.012,
    "display_x": 450.123,
    "display_y": 320.456,
    "display_z": 89.012
  },
  "anatomy": {
    "region_id": "prefrontal_cortex",
    "subregion_id": "dlpfc_layer5",
    "layer_id": "L5",
    "neuron_type": "pyramidal"
  },
  "morphology": {
    "soma_diameter_um": 20.5,
    "dendrite_extent_um": 450.0,
    "axon_diameter_um": 1.2,
    "axon_initial_segment_um": 25.0,
    "spine_density_per_um": 2.3
  },
  "state": {
    "membrane_potential": -65.4,
    "spike_count": 7,
    "last_spike_time": 125.3,
    "refractory_state": "RESPONSIVE",
    "model_id": "HODGKIN_HUXLEY"
  },
  "provenance": {
    "evidence_level": "OBSERVED",
    "source_reference": "claim_id_phase5_12847",
    "model_version": "1.1_with_A_current",
    "graph_version": "7.0",
    "validation_timestamp": 1694558400000.0
  }
}
```

---

## SECTION 3: 3D GRAPH EDGE STRUCTURE

### 3.1 Edge Identity (Immutable)
```
synapse_id:          CAT-S-XXXXXXXXXXXXXXXX  [immutable biological ID]
unique_3d_edge_index: uint32               [graph-specific fast lookup]
```

### 3.2 Connectivity (Immutable)
```
source_cat_n_id:     CAT-N-XXXXXXXXXXXXXXXX
destination_cat_n_id: CAT-N-XXXXXXXXXXXXXXXX

source_coordinates: {
  x_um: float64
  y_um: float64
  z_um: float64
}

destination_coordinates: {
  x_um: float64
  y_um: float64
  z_um: float64
}
```

**Rule:** Coordinates point to soma centers. No visualization rewiring allowed.

### 3.3 Transmission Properties
```
weight:              float32  [synaptic conductance, nanosiemens, 0.1 to 100.0 typical]
delay_ms:            float32  [axonal transmission delay, 0.5 to 5.0 ms typical]
neurotransmitter:    enum     [glutamate, GABA, dopamine, serotonin, acetylcholine, 
                               glycine, noradrenaline, UNKNOWN]
receptor_type:       enum     [AMPA, NMDA, GABA_A, GABA_B, D1, D2, 5HT, 
                               NICOTINIC_ACH, GLYCINE_A, UNKNOWN]
```

### 3.4 Edge Topology
```
connectivity_type:   enum     [FEEDFORWARD (one-way, i → j, i.out_degree < i.fanout),
                               RECURRENT (bidirectional mutual: i ↔ j),
                               FEEDBACK (j → i where i → j also exists, closure = true),
                               INTERLAYER (connects different cortical layers),
                               INTRAREGIONAL (both neurons in same region),
                               INTERREGIONAL (neurons in different regions)]

is_gap_junction:     bool     [electrical synapse, not chemical]
```

### 3.5 Provenance
```
evidence_level:      enum     [DOCUMENTED, OBSERVED, INFERRED, MODELED, UNKNOWN]
source_reference:    string   [claim ID from Phase 5 evidence ledger]
connectivity_probability: float32  [0.0 to 1.0, confidence in synapse existence]
```

### 3.6 Edge Summary
```json
{
  "synapse_id": "CAT-S-XXXXXXXXXXXXXXXX",
  "unique_3d_edge_index": 45821,
  "connectivity": {
    "source_cat_n_id": "CAT-N-AAAAAAAAAAAAAAAA",
    "destination_cat_n_id": "CAT-N-BBBBBBBBBBBBBBBB",
    "source_coordinates": {"x_um": 450.1, "y_um": 320.5, "z_um": 89.0},
    "destination_coordinates": {"x_um": 465.3, "y_um": 335.2, "z_um": 95.5}
  },
  "transmission": {
    "weight": 12.5,
    "delay_ms": 1.2,
    "neurotransmitter": "glutamate",
    "receptor_type": "AMPA"
  },
  "topology": {
    "connectivity_type": "FEEDFORWARD",
    "is_gap_junction": false
  },
  "provenance": {
    "evidence_level": "OBSERVED",
    "source_reference": "claim_id_phase5_45821",
    "connectivity_probability": 0.95
  }
}
```

---

## SECTION 4: HIERARCHICAL ANATOMICAL STRUCTURE

### 4.1 Brain Ontology (Preserved from Phase 6)
```
BRAIN
├── REGION_1 (e.g., "prefrontal_cortex")
│   ├── SUBREGION_1.1 (e.g., "dorsolateral_pfc")
│   │   ├── FUNCTIONAL_TERRITORY_1.1.1 (e.g., "working_memory_circuit")
│   │   │   ├── LAYER_L1
│   │   │   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   │   │   ├── LAYER_L2
│   │   │   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   │   │   ├── LAYER_L3
│   │   │   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   │   │   ├── LAYER_L4
│   │   │   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   │   │   ├── LAYER_L5
│   │   │   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   │   │   └── LAYER_L6
│   │   │       └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   │   └── (layer assignments where data unavailable: UNKNOWN)
│   ├── SUBREGION_1.2 (e.g., "ventromedial_pfc")
│   │   └── ... (same layer structure or UNKNOWN)
│   └── SUBREGION_1.N
├── REGION_2 (e.g., "motor_cortex")
│   └── ... (subcortical regions may lack layering)
├── REGION_3 (e.g., "hippocampus")
│   ├── CA1_FIELD
│   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   ├── CA3_FIELD
│   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   └── DG_FIELD
│       └── NEURONS: [CAT-N-*, CAT-N-*, ...]
├── REGION_4 (e.g., "cerebellum")
│   ├── GRANULE_LAYER
│   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   ├── MOLECULAR_LAYER
│   │   └── NEURONS: [CAT-N-*, CAT-N-*, ...]
│   └── PURKINJE_LAYER
│       └── NEURONS: [CAT-N-*, CAT-N-*, ...]
└── REGION_N
    └── NEURONS (non-layered or UNKNOWN): [CAT-N-*, CAT-N-*, ...]
```

### 4.2 Ontology Rules
- **Cortical regions:** Always have layers L1–L6. If data missing, mark layer as "UNKNOWN" (not invented).
- **Hippocampus:** Uses CA1, CA3, DG fields instead of cortical layers.
- **Cerebellum:** Uses granule, molecular, purkinje layers.
- **Subcortical/brainstem:** No mandatory layering; use region_id and subregion_id only.
- **Functional territories (optional):** Circuit tags (e.g., "working_memory_circuit", "motor_planning_circuit") applied post-hoc if available.

---

## SECTION 5: COORDINATE PRESERVATION STRATEGY

### 5.1 Immutable Source Coordinates
All biological coordinates from Phase 6 GPU validation are **never modified**:
```
x_um, y_um, z_um = IMMUTABLE biological space
```

### 5.2 Display Coordinates (Optional Transformation)
For visualization purposes, transformed coordinates may be computed:
```
display_x, display_y, display_z = Transform(x_um, y_um, z_um)
```

**Allowed transformations:**
- Identity (no change)
- Uniform scaling (isotropic or per-axis)
- Rotation (around axis)
- Orthogonal projection (onto 2D plane, e.g., z-elimination)
- Camera/viewport transformation
- Octree LOD spatial reorganization (for rendering only)

### 5.3 Transformation Metadata
```
transform_config: {
  transform_type: enum [IDENTITY, SCALE, ROTATE, ORTHOGONAL_PROJECTION, 
                        CAMERA_VIEW, CUSTOM],
  
  transform_matrix: array[16]  [4×4 homogeneous matrix, if applicable]
  
  inverse_transform: array[16]  [4×4 inverse matrix to recover source from display]
  
  applied_timestamp: float64  [when transformation computed]
  
  viewport_params: {
    camera_position: [x, y, z],
    camera_target: [x, y, z],
    field_of_view: float32,
    near_plane: float32,
    far_plane: float32
  }
}
```

### 5.4 Invariant Rules
1. **Never overwrite source:** `x_um, y_um, z_um` stored separately from `display_x, display_y, display_z`
2. **Bidirectional recovery:** From display coords, apply `inverse_transform` to recover source
3. **Provenance chain:** If transformation applied, document reason (LOD, camera, filtering)

---

## SECTION 6: CONNECTIVITY VIEW SPECIFICATIONS

### 6.1 View Type 1: Feedforward Only
**Purpose:** Show stimulus-response propagation paths without loops  
**Selection criteria:**
```
edges WHERE connectivity_type == FEEDFORWARD
```
**Semantics:** One-way information flow (e.g., sensory input → cortex → motor output)  
**Typical use:** Pathway analysis, feedforward circuit decomposition

### 6.2 View Type 2: Recurrent Only
**Purpose:** Show closed loops and self-reinforcing circuits  
**Selection criteria:**
```
edges WHERE connectivity_type IN {RECURRENT, FEEDBACK}
```
**Semantics:** Bidirectional or feedback circuits (e.g., working memory loops, echo states)  
**Typical use:** Attractors, reverberating activity, stability analysis

### 6.3 View Type 3: All Connectivity
**Purpose:** Show complete connectome without filtering  
**Selection criteria:**
```
edges (all)
```
**Semantics:** Unfiltered view of all synaptic connections  
**Typical use:** Overview, structural analysis, centrality metrics

### 6.4 View Type 4: Circuit-Specific
**Purpose:** Show connections within named functional circuit  
**Selection criteria:**
```
edges WHERE 
  (source_neuron.functional_territory == TARGET_CIRCUIT 
   AND destination_neuron.functional_territory == TARGET_CIRCUIT)
  OR (source_neuron ∈ CIRCUIT_MEMBERS AND destination_neuron ∈ CIRCUIT_MEMBERS)
```
**Examples:** "working_memory_circuit", "motor_planning_circuit", "fear_circuit"  
**Typical use:** Circuit-level analysis, intervention modeling

### 6.5 View Type 5: Region-Specific
**Purpose:** Show intra-regional or inter-regional connectivity  
**Selection criteria:**

**Intra-regional variant:**
```
edges WHERE source_neuron.region_id == REGION_X 
      AND destination_neuron.region_id == REGION_X
```

**Inter-regional variant:**
```
edges WHERE (source_neuron.region_id == REGION_X 
            AND destination_neuron.region_id == REGION_Y)
      OR (source_neuron.region_id == REGION_Y 
          AND destination_neuron.region_id == REGION_X)
```

**Typical use:** Regional interaction analysis, hierarchical pathway tracing

---

## SECTION 7: NEURAL ACTIVITY VISUALIZATION MAPPING

### 7.1 Color Mapping (Membrane Potential)
```
membrane_potential [-90 mV, -70 mV, -50 mV, -30 mV, 0 mV, +20 mV, +30 mV]
            ↓         ↓        ↓       ↓       ↓      ↓       ↓       ↓
         deep_blue   blue    cyan    green  yellow orange   red   bright_red
         (inactive)                        (threshold)        (spike)

Mapping function:
  v_clamped = clamp(membrane_potential, -90, +30)
  t = (v_clamped + 90) / 120  [normalize to [0, 1]]
  
  if t < 0.33:
    color = lerp(deep_blue, cyan, t * 3)
  elif t < 0.67:
    color = lerp(cyan, yellow, (t - 0.33) * 3)
  else:
    color = lerp(yellow, red, (t - 0.67) * 3)
```

### 7.2 Size Mapping (Spike Count)
```
spike_count [0, 1, 5, 10, 20, 50, 100+]
     ↓       ↓  ↓  ↓   ↓   ↓   ↓    ↓
   size  [0.5, 0.6, 0.8, 1.0, 1.3, 1.6, 2.0] × base_soma_diameter

Mapping function:
  base_size = soma_diameter_um / 20.0  [normalized]
  spike_factor = 0.5 + log(spike_count + 1) * 0.3  [logarithmic scaling]
  display_size = base_size * spike_factor
  display_size = clamp(display_size, 0.3, 3.0)
```

### 7.3 Opacity Mapping (Firing Rate)
```
firing_rate [0 Hz, 0.1 Hz, 1 Hz, 5 Hz, 10 Hz, 50 Hz, 100+ Hz]
    ↓        ↓    ↓      ↓     ↓     ↓     ↓       ↓
 opacity  [0.1,  0.2,    0.4,  0.6,  0.8,  0.95,   1.0]

Firing rate calculation:
  firing_rate_hz = spike_count / window_duration_seconds
  
Mapping:
  opacity = 0.1 + 0.9 * sigmoid((firing_rate_hz - 2.0) / 5.0)
  opacity = clamp(opacity, 0.1, 1.0)
```

### 7.4 Edge Opacity Mapping (Activity Traffic)
```
Recent synaptic events at edge (past 100ms simulation time):
  event_count [0, 1, 5, 10, 50+]
       ↓      ↓  ↓  ↓   ↓   ↓
    opacity [0.0, 0.2, 0.5, 0.75, 1.0]

Decay function (exponential, half-life = 50ms):
  edge_opacity = ∑_i (decay_factor ^ time_since_event_i)
                where decay_factor = 2^(-1/50) ≈ 0.986
  edge_opacity = clamp(edge_opacity, 0.0, 1.0)
```

### 7.5 Edge Width Mapping (Synaptic Strength)
```
weight [0.1, 1.0, 5.0, 12.5, 25.0, 50.0, 100+] nanosiemens
  ↓     ↓    ↓    ↓     ↓      ↓     ↓      ↓
width [0.2, 0.5, 1.0,  1.5,   2.0,  2.5,   3.0] pixels

Mapping:
  edge_width = 0.2 + log(weight + 1) * 0.5
  edge_width = clamp(edge_width, 0.2, 3.0)
```

---

## SECTION 8: LEVEL-OF-DETAIL (LOD) HIERARCHY

### 8.1 LOD Levels Defined
```
LOD_0: 158 neurons (Phase 4 prototype, validation set)
  ├─ All nodes visible with full detail
  ├─ All edges visible
  ├─ All morphology rendered
  └─ Use: Detailed circuit study, validation

LOD_1: 1,000 neurons
  ├─ Individual neuron detail preserved
  ├─ All edges shown, but culled by viewport frustum
  ├─ Full morphology per neuron
  └─ Use: Mesoscale circuit (column, mini-cortex)

LOD_2: 10,000 neurons
  ├─ Individual neurons rendered, grouped into regions
  ├─ Edges shown within region; inter-regional edges as summary
  ├─ Morphology detail reduced (simplified arbors)
  └─ Use: Local circuit population level

LOD_3: 100,000 neurons
  ├─ Distant neurons aggregated into region nodes
  ├─ Only nearby neurons (<1mm) rendered individually
  ├─ Inter-regional edges as bezier curves between region centroids
  ├─ Intra-regional edges sparse (sample ~5%)
  └─ Use: Area-level (e.g., entire visual cortex area)

LOD_4: 1 million neurons
  ├─ Entire regions shown as single nodes
  ├─ Regional connectivity shown only
  ├─ Individual neuron detail eliminated
  ├─ Region nodes colored by average activity
  └─ Use: Whole-brain overview at region granularity

LOD_5: 10 million neurons
  ├─ Major brain divisions (telencephalon, brainstem, cerebellum)
  ├─ Simplified geometry (bounding boxes or ellipsoids)
  ├─ Only macro-scale connectivity
  └─ Use: Evolutionary/comparative perspective

LOD_6: 100 million neurons
  ├─ Brain hemisphere-level (left/right)
  ├─ Major divisions only (cortex, basal ganglia, limbic)
  ├─ Aggregate activity heatmaps
  └─ Use: Clinical or population-level overview

LOD_7: 760 million neurons (full human brain)
  ├─ Whole brain as single entity
  ├─ Global activity state via heatmap overlay
  ├─ Zoom capability to progressively reveal lower LOD
  └─ Use: Full-brain state visualization, zoom-tree navigation
```

### 8.2 LOD Selection Algorithm
```
function select_lod(viewport_size, camera_distance_to_content):
  frustum_volume = compute_frustum_volume()
  visible_neuron_count_at_detail = count_neurons_in_frustum()
  
  if visible_neuron_count_at_detail < 500:
    return LOD_0 or LOD_1
  elif visible_neuron_count_at_detail < 5000:
    return LOD_1 or LOD_2
  elif visible_neuron_count_at_detail < 50000:
    return LOD_2 or LOD_3
  elif visible_neuron_count_at_detail < 500000:
    return LOD_3 or LOD_4
  elif visible_neuron_count_at_detail < 5000000:
    return LOD_4 or LOD_5
  else:
    return LOD_6 or LOD_7
```

### 8.3 LOD Transition (Smooth)
- Interpolate node positions between LODs during zoom
- Fade in/out nodes based on LOD membership
- Update edge connectivity smoothly (no jump discontinuities)
- Cache pre-computed aggregates per LOD level

---

## SECTION 9: GPU-COMPATIBLE RENDERING FORMAT

### 9.1 Vertex Buffer Structure (Per-LOD)
```
struct Vertex {
  position[3]:     float32[3]    [x, y, z in micrometers or display coords]
  color[4]:        uint8[4]      [RGBA: 0-255 per channel]
  size:            float32       [vertex size in pixels or world units]
  activity_level:  uint8         [normalized firing rate 0-255]
  neuron_id_low:   uint32        [lower 32 bits of CAT-N-ID hash]
  neuron_id_high:  uint32        [upper 32 bits of CAT-N-ID hash for picking]
}

Total: 36 bytes per vertex
```

### 9.2 Edge Buffer Structure
```
struct Edge {
  source_index:    uint32        [index into vertex buffer]
  dest_index:      uint32        [index into vertex buffer]
  color[4]:        uint8[4]      [RGBA based on neurotransmitter/activity]
  width:           float32       [edge thickness in pixels]
  activity_level:  uint8         [recent event traffic 0-255]
  synapse_id_low:  uint32        [lower 32 bits of CAT-S-ID hash]
  synapse_id_high: uint32        [upper 32 bits of CAT-S-ID hash for picking]
}

Total: 28 bytes per edge
```

### 9.3 Indirect Draw Buffers (For LOD Rendering)
```
struct DrawCommand {
  vertex_count:      uint32
  first_vertex:      uint32
  base_vertex:       uint32
  base_instance:     uint32
  
  task_sequence: [
    {type: "draw_lod_0_nodes", vertex_count: 158, first_index: 0},
    {type: "draw_lod_0_edges", edge_count: 2847, first_index: 0},
    {type: "draw_lod_1_nodes", vertex_count: 1000-158, first_index: 158},
    {type: "draw_lod_1_edges", edge_count: ..., first_index: 2847},
    ...
  ]
}
```

### 9.4 Compute Shader Pipeline
```
Stage 1: Update Neural State (per-neuron)
  Input: membrane_potential buffer from Phase 6 GPU
  Compute: color, size, opacity per neuron based on mappings (Section 7)
  Output: Updated vertex color/size/activity_level

Stage 2: Update Synaptic Activity (per-synapse)
  Input: recent spike event buffer (source → dest pairs + timestamps)
  Compute: edge_opacity, width, color per synapse
  Output: Updated edge color/width/activity_level

Stage 3: LOD Aggregation (per LOD transition)
  Input: Previous LOD vertex/edge buffers
  Compute: Regional aggregates (centroid, average activity, connectivity)
  Output: Higher-LOD node/edge buffers

Stage 4: Viewport Frustum Culling
  Input: camera frustum + vertex buffer
  Compute: visibility flags per node
  Output: Indirect draw command buffer with culled vertices/edges
```

### 9.5 No CPU Synchronization Required
- Vertex/edge buffers pre-allocated on GPU
- Activity updates pushed via compute shaders
- Rendering occurs directly from GPU buffers
- Pick-through-rendering queries use GPU read-back only on demand

---

## SECTION 10: SPATIAL INDEXING STRUCTURE

### 10.1 Octree for 3D Range Queries
```
OctreeNode {
  bounds:         AABB (min/max corner coords)
  neuron_list:    [CAT-N-ID, CAT-N-ID, ...]  [if leaf]
  children[8]:    [OctreeNode, OctreeNode, ...]  [if internal]
  unique_index:   uint32  [for GPU addressing]
}
```

**Rules:**
- Each leaf node contains up to K neurons (e.g., K=16)
- Maximum depth: log₈(brain_size) ≈ 3-4 levels for human brain (0.1-10mm scale)
- Leaf bounds entirely contain neuron soma centers

### 10.2 BVH Tree Alternative (For Complex Morphology)
```
BVHNode {
  bounds:         AABB
  left_child:     BVHNode
  right_child:    BVHNode
  primitive_list: [neuron_id, ...]  [if leaf]
  split_axis:     enum [X, Y, Z]
}
```

**Rules:**
- Binary splits (X, Y, or Z axis chosen for tightest fit)
- Allows fast SIMD-friendly traversal
- Better for ray-casting (e.g., picking)

### 10.3 Query Operations

**Frustum Culling (viewport visibility):**
```
function frustum_culling(camera_frustum):
  visible_nodes = []
  queue = [octree.root]
  
  while queue not empty:
    node = queue.pop()
    if frustum.intersects(node.bounds):
      if node.is_leaf:
        visible_nodes.extend(node.neuron_list)
      else:
        queue.extend(node.children)
  
  return visible_nodes
```

**Range Query (interactive selection):**
```
function range_query(center: [x, y, z], radius_um: float):
  matching_neurons = []
  queue = [octree.root]
  
  while queue not empty:
    node = queue.pop()
    if sphere(center, radius_um).intersects(node.bounds):
      if node.is_leaf:
        for neuron in node.neuron_list:
          if distance(neuron.position, center) <= radius_um:
            matching_neurons.append(neuron)
      else:
        queue.extend(node.children)
  
  return matching_neurons
```

**k-Nearest Neighbors (connectivity suggestions):**
```
function knn_query(neuron: CAT-N-ID, k: int):
  target_position = neurons[neuron].position
  neighbors = []
  
  queue = [octree.root]
  while queue not empty:
    node = queue.pop()
    
    if node.is_leaf:
      for other_neuron in node.neuron_list:
        if other_neuron != neuron:
          dist = distance(other_neuron.position, target_position)
          neighbors.append((dist, other_neuron))
  
  neighbors.sort_by_distance()
  return neighbors[:k]
```

### 10.4 Build Algorithm (Post-Phase-6-Validation)
```
function build_octree(neurons: [CAT-N-ID]):
  root_bounds = compute_bounding_box(neurons)
  return recursive_build(neurons, root_bounds, depth=0, max_depth=4)

function recursive_build(neurons, bounds, depth, max_depth):
  if len(neurons) <= leaf_threshold OR depth >= max_depth:
    return OctreeNode(is_leaf=True, bounds=bounds, neuron_list=neurons)
  
  # Split bounds into 8 octants
  octants = subdivide_box(bounds)
  children = []
  
  for octant in octants:
    octant_neurons = [n for n in neurons if n.position in octant]
    if len(octant_neurons) > 0:
      child = recursive_build(octant_neurons, octant, depth+1, max_depth)
      children.append(child)
  
  return OctreeNode(is_leaf=False, bounds=bounds, children=children)
```

---

## SECTION 11: PROOF OF BIOLOGICAL IDENTITY PRESERVATION

### 11.1 Invariants Guaranteed by Design

**Invariant 1: Every 3D node is CAT-N-ID**
```
For all vertices in rendering:
  neuron_id ∈ {CAT-N-XXXXXXXXXXXXXXXX}
  neuron_id is immutable (never reassigned)
  ∃ exactly one unique_3d_index per neuron_id per LOD
```

**Invariant 2: Every edge is CAT-S-ID**
```
For all edges in rendering:
  synapse_id ∈ {CAT-S-XXXXXXXXXXXXXXXX}
  synapse_id is immutable (never reassigned)
  source_cat_n_id and dest_cat_n_id are valid CAT-N-IDs
```

**Invariant 3: Coordinates preserved**
```
For all neurons:
  x_um, y_um, z_um = original Phase 6 GPU validated coordinates
  display_x, display_y, display_z = optional transformed copy only
  ∄ code path that overwrites source coordinates
```

**Invariant 4: Connectivity fidelity**
```
For all edges:
  source_coordinates = soma_position[source_neuron]
  destination_coordinates = soma_position[destination_neuron]
  No edge rewiring or phantom synapses created
```

### 11.2 Validation Checklist

- [ ] Every vertex buffer entry has non-null neuron_id (CAT-N-ID)
- [ ] Every edge buffer entry has non-null synapse_id (CAT-S-ID)
- [ ] No visualization creates new "temporary" nodes without CAT-N-ID
- [ ] Source coordinates (x_um, y_um, z_um) never modified post-initialization
- [ ] Display coordinates computed fresh per frame; source remains canonical
- [ ] Octree/BVH index structures reference neuron_id, not unique_3d_index
- [ ] All UI selections (e.g., picking) return CAT-N-ID or CAT-S-ID, not visualization-only IDs
- [ ] Provenance chain unbroken: each node/edge traces back to Phase 5 evidence ledger

---

## SECTION 12: IMPLEMENTATION PATHWAYS

### 12.1 Recommended Technology Stack

**Rendering Engine:**
- WebGPU or Vulkan (compute shaders for real-time activity update)
- Three.js or Babylon.js wrapper (for rapid development)
- Point cloud rendering optimized for 760M nodes

**Data Storage:**
- Graph serialization: JSON-LD (RDF-compliant) or Protocol Buffers (binary compact)
- Spatial indexing: Persistent octree (file-mapped or memory-mapped)
- Neural state: Time-series database (influxDB, TimescaleDB) for activity history

**Coordinate System:**
- Store all coordinates in micrometers (SI unit)
- GPU shaders handle scaling for viewport (100um → pixels)

**Picking/Interaction:**
- Ray-cast through octree for click selection
- Return neuron_id immediately (no temporary IDs)
- Query Phase 5 evidence ledger for neuron history

### 12.2 Phase 7 Deliverables Checklist

- [ ] 3D graph node schema (JSON-LD class definition)
- [ ] 3D graph edge schema (JSON-LD class definition)
- [ ] Hierarchical anatomical structure (RDF ontology, e.g., OWL)
- [ ] Coordinate transformation specification (4×4 matrix algebra)
- [ ] Connectivity view definitions (query grammar)
- [ ] Activity visualization mapping (shader code templates)
- [ ] LOD selection algorithm (pseudocode + complexity analysis)
- [ ] GPU vertex/edge buffer layout spec (byte-aligned struct definitions)
- [ ] Compute shader pipeline design (WGSL or GLSL specification)
- [ ] Octree/BVH build algorithm (with complexity analysis)
- [ ] Proof document (invariant verification checklist)

---

## SECTION 13: REFERENCES AND DEPENDENCIES

### 13.1 Upstream Phases
- **Phase 4:** 158-neuron prototype circuit + validation coordinates
- **Phase 5:** Evidence ledger claims (CAT-N-ID, CAT-S-ID, source references)
- **Phase 6:** GPU-validated membrane potential, spike state, canonical coordinates

### 13.2 Related Standards
- **Allen Brain Atlas:** Regional ontology reference
- **OpenConnectome Project:** Connectome graph standards
- **NeuroDB:** Neuron morphology database (SWC format)
- **BIDS (Brain Imaging Data Structure):** Coordinate system conventions

### 13.3 Downstream (Phase 8+)
- Interactive UI layer (node selection, connectivity probing)
- Circuit analysis tools (motif detection, path tracing)
- Electrophysiology simulation engine (feed GPU state into simulator)
- Publication and archival (version control for graph snapshots)

---

## CONCLUSION

This 3D Anatomical Graph Specification provides the formal blueprint for Dylan visualization, preserving **every CAT-N-ID, CAT-S-ID, coordinate, and biological property** from Phase 6 canonical representation. The design enforces biological identity at every layer—rendering, indexing, and interaction—ensuring the visualization is **faithful to the underlying neuroscience**, not a visual artifact.

The graph is ready for implementation by developers following this specification without modifications to the core constraints: immutable identities, coordinate preservation, connectivity fidelity, and provenance transparency.

---

**Specification Approved For Implementation**  
**Phase 7, Dylan Visualization Engineer**  
**2026-09-13**
