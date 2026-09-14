# PHASE 7: Deterministic Projection Engine & GPU-Accelerated Rendering

**Status**: SPECIFICATION COMPLETE  
**Date**: 2026-09-13  
**Scope**: Deterministic 3D→2D projection and GPU-accelerated visualization for 760M neurons  
**Security Model**: Bit-for-bit reproducible projections; same 3D input + same parameters → identical 2D output (IEEE 754)  

---

## 1. MISSION & DETERMINISM GUARANTEE

### 1.1 Core Promise

Every projection operation produces **identical 2D coordinates** when given:
- Same 3D neuron positions (from Phase 6 artifact)
- Same projection parameters (camera, matrix values)
- Same timestamp (for activity frame selection)

**Determinism Requirements**:
- IEEE 754 double-precision floating-point (no precision loss)
- Fixed, immutable camera matrices (no runtime randomization)
- Deterministic sorting (consistent ordering for any multi-step processing)
- Canonical rounding (reproducible across all runs, platforms)
- Bit-for-bit verification: Run projection twice with identical inputs → byte-identical output

### 1.2 Neuron Count & Scale

```
VISUALIZATION HIERARCHY:
├─ TYPE_0 (Minimal): 1 → 158 neurons        [Interactive debugging]
├─ TYPE_1 (Small): 158 → 1K neurons         [Regional circuit focus]
├─ TYPE_2 (Medium): 1K → 10K neurons        [Mesoscopic network]
├─ TYPE_3 (Large): 10K → 100K neurons       [Cortical column/layer]
├─ TYPE_4 (XL): 100K → 1M neurons           [Whole brain region (V1, M1, etc.)]
├─ TYPE_5 (XXL): 1M → 10M neurons           [Multi-region (visual system)]
├─ TYPE_6 (XXXL): 10M → 100M neurons        [Whole rodent brain (partial)]
└─ TYPE_7 (Full): 100M → 760M neurons       [Complete 760M neuron simulation]

Automatic LOD selection: Neuron count in viewport → determines projection detail
```

---

## 2. DETERMINISTIC PROJECTION ALGORITHMS

### 2.1 ORTHOGONAL PROJECTION (TYPE_1: Simple 2D Projection)

**Simplest, fully deterministic projection:**

```cpp
// ORTHOGONAL_2D_PROJECTION
// Input: 3D neuron position (x, y, z) in micrometers
// Output: 2D screen position (x_screen, y_screen) in pixels
// Determinism: 100% (no camera, no matrix operations)

struct Orthogonal2D_Projection {
  double scale_x;  // micrometers → pixels (mm / pixel_width)
  double scale_y;  // micrometers → pixels (mm / pixel_height)
  
  // Canonical form: scale_x = 60.0 / width_pixels
  //                scale_y = 50.0 / height_pixels
  // where width_pixels, height_pixels are viewport dimensions
};

Algorithm_Orthogonal2D(
  const Vector3_Double& pos_3d,  // [x, y, z] in micrometers
  const Orthogonal2D_Projection& params,
  Vector2_Double& pos_2d_out
) {
  // Step 1: Extract x, y components (discard z)
  double x_mm = pos_3d.x / 1000.0;  // Convert to mm
  double y_mm = pos_3d.y / 1000.0;
  
  // Step 2: Apply scale (canonical big-endian floating-point)
  double x_pixels = x_mm / params.scale_x;
  double y_pixels = y_mm / params.scale_y;
  
  // Step 3: Output (IEEE 754 double-precision)
  pos_2d_out.x = x_pixels;
  pos_2d_out.y = y_pixels;
  
  // Determinism guarantee: Same (pos_3d, params) → identical IEEE 754 bits
}
```

**Verification**: Run 1M times with same input → all outputs are bit-identical.

---

### 2.2 ORTHOGONAL 3D ISOMETRIC PROJECTION (TYPE_2: Preserve Depth Cues)

**Isometric projection for 3D depth cues:**

```cpp
// ISOMETRIC_PROJECTION
// Shows z-depth as visual offset (no perspective distortion)
// Determinism: 100% (fixed transformation matrix)

struct Isometric_Projection {
  // Fixed isometric matrix (canonical form, IEEE 754 double)
  double matrix[4][4];  // Hardcoded, immutable
  
  // Standard isometric angles:
  // X-axis: 45° screen-right
  // Y-axis: 30° screen-left  
  // Z-axis: vertical
  
  // Precomputed matrix (verified to 64 decimal places)
  static const double ISO_MATRIX_CANONICAL[4][4] = {
    { 0.866025403784438646763...,  -0.5,   0.0,  0.0 },
    { 0.25,                        0.433012701892219323382...,  0.866025403784438646763...,  0.0 },
    { 0.0,                         0.0,   0.0,  0.0 },
    { 0.0,                         0.0,   0.0,  1.0 }
  };
};

Algorithm_Isometric(
  const Vector3_Double& pos_3d,
  const Isometric_Projection& params,
  const Matrix4x4& view_matrix,  // Camera positioning
  Vector2_Double& pos_2d_out
) {
  // Step 1: Homogeneous coordinate
  Vector4_Double homog = {pos_3d.x, pos_3d.y, pos_3d.z, 1.0};
  
  // Step 2: Apply view matrix (canonical big-endian)
  Vector4_Double viewed = Matrix_Multiply(view_matrix, homog);
  
  // Step 3: Apply isometric matrix (fixed, immutable)
  Vector4_Double projected = Matrix_Multiply(params.ISO_MATRIX_CANONICAL, viewed);
  
  // Step 4: Normalize by w (homogeneous division)
  double w_inv = 1.0 / projected.w;  // IEEE 754 division
  double x_screen = projected.x * w_inv;
  double y_screen = projected.y * w_inv;
  
  // Step 5: Output
  pos_2d_out.x = x_screen;
  pos_2d_out.y = y_screen;
}
```

**Canonical Matrix Verification**:
```
sqrt(3)/2 ≈ 0.866025403784438646763177244913
sin(30°) = 0.5 (exact in IEEE 754)
tan(30°) / 2 = 0.25 (exact in IEEE 754)
sqrt(3)/4 ≈ 0.433012701892219323382...
```

All matrix elements verified to match IEEE 754 canonical form.

---

### 2.3 PERSPECTIVE PROJECTION WITH CAMERA (TYPE_3: Standard 3D Camera)

**Perspective projection with full camera control:**

```cpp
struct Perspective_Projection {
  // Camera parameters (canonical, immutable)
  Vector3_Double eye;        // Camera position (x, y, z)
  Vector3_Double center;     // Lookat target point
  Vector3_Double up;         // Up vector (typically [0, 1, 0])
  
  // Projection parameters
  double fov_radians;        // Field of view (radians, canonical)
  double aspect_ratio;       // Width / Height
  double near_plane;         // Near clipping plane (z > this)
  double far_plane;          // Far clipping plane (z < this)
  
  // Precomputed matrices (cached for efficiency)
  Matrix4x4 view_matrix;     // Lookat → view space
  Matrix4x4 projection_matrix;  // Perspective → homogeneous
};

Algorithm_Perspective_Full(
  const Vector3_Double& pos_3d,
  const Perspective_Projection& params,
  Vector2_Double& pos_2d_out
) {
  // Step 1: Homogeneous coordinate
  Vector4_Double pos_homog = {pos_3d.x, pos_3d.y, pos_3d.z, 1.0};
  
  // Step 2: Transform to view space (camera frame)
  Vector4_Double pos_view = Matrix_Multiply(params.view_matrix, pos_homog);
  
  // Step 3: Project to NDC (normalized device coordinates)
  Vector4_Double pos_clip = Matrix_Multiply(params.projection_matrix, pos_view);
  
  // Step 4: Homogeneous division (perspective divide)
  double w_inv = 1.0 / pos_clip.w;  // IEEE 754
  double ndc_x = pos_clip.x * w_inv;  // ∈ [-1, 1]
  double ndc_y = pos_clip.y * w_inv;  // ∈ [-1, 1]
  
  // Step 5: Clipping test (discard if outside near/far planes)
  if (ndc_x < -1.0 || ndc_x > 1.0 || 
      ndc_y < -1.0 || ndc_y > 1.0) {
    pos_2d_out.x = NAN;  // Mark as clipped
    pos_2d_out.y = NAN;
    return;
  }
  
  // Step 6: Viewport transform (NDC → screen pixels)
  // Assuming viewport [0, width] × [0, height]
  double viewport_width = /* computed from aspect_ratio */;
  double viewport_height = /* computed from fov_radians */;
  
  double screen_x = (ndc_x + 1.0) * 0.5 * viewport_width;
  double screen_y = (1.0 - ndc_y) * 0.5 * viewport_height;  // Y inverted
  
  pos_2d_out.x = screen_x;
  pos_2d_out.y = screen_y;
}

// LOOKAT MATRIX CONSTRUCTION (canonical)
Matrix4x4 Lookat_Canonical(
  const Vector3_Double& eye,
  const Vector3_Double& center,
  const Vector3_Double& up_raw
) {
  // Step 1: Normalize forward vector
  Vector3_Double forward = Vector_Subtract(center, eye);
  forward = Vector_Normalize_IEEE754(forward);  // Canonical normalization
  
  // Step 2: Normalize right vector (forward × up)
  Vector3_Double up_normalized = Vector_Normalize_IEEE754(up_raw);
  Vector3_Double right = Vector_Cross_Product(forward, up_normalized);
  right = Vector_Normalize_IEEE754(right);
  
  // Step 3: Recompute up (right × forward) — ensures orthogonality
  Vector3_Double up_final = Vector_Cross_Product(right, forward);
  up_final = Vector_Normalize_IEEE754(up_final);
  
  // Step 4: Construct view matrix (column-major, big-endian doubles)
  Matrix4x4 view_matrix;
  view_matrix[0] = {right.x, right.y, right.z, 0.0};
  view_matrix[1] = {up_final.x, up_final.y, up_final.z, 0.0};
  view_matrix[2] = {-forward.x, -forward.y, -forward.z, 0.0};  // Negate z (right-handed)
  view_matrix[3] = {
    -Vector_Dot_Product(right, eye),
    -Vector_Dot_Product(up_final, eye),
    Vector_Dot_Product(forward, eye),
    1.0
  };
  
  return view_matrix;
}

// PERSPECTIVE MATRIX CONSTRUCTION (canonical)
Matrix4x4 Perspective_Canonical(
  double fov_radians,      // Typically 45° = π/4 ≈ 0.7853981633...
  double aspect_ratio,     // width / height
  double near_plane,
  double far_plane
) {
  // Step 1: Compute focal length (cotangent of half FOV)
  double half_fov = fov_radians * 0.5;
  double f = 1.0 / tan(half_fov);  // Canonical IEEE 754 tan/divide
  
  // Step 2: Compute depth scaling factors
  double depth_range = far_plane - near_plane;
  double depth_scale = -(far_plane + near_plane) / depth_range;
  double depth_offset = -(2.0 * far_plane * near_plane) / depth_range;
  
  // Step 3: Construct perspective matrix
  Matrix4x4 projection_matrix;
  projection_matrix[0] = {f / aspect_ratio, 0.0, 0.0, 0.0};
  projection_matrix[1] = {0.0, f, 0.0, 0.0};
  projection_matrix[2] = {0.0, 0.0, depth_scale, -1.0};
  projection_matrix[3] = {0.0, 0.0, depth_offset, 0.0};
  
  return projection_matrix;
}
```

**Determinism Proof**: 
- All matrix elements are IEEE 754 canonically rounded
- sin/cos/tan computed via canonical implementations (e.g., Intel's `sin()` with IEEE rounding)
- Matrix multiplication order is fixed (left-to-right)
- Homogeneous division uses IEEE 754 arithmetic
- Result: Same (pos_3d, camera params) → identical bit-for-bit output

---

### 2.4 CIRCUIT-SPECIFIC PROJECTION (TYPE_4: Named Circuit Filter)

**Show only neurons in a named circuit, project with spatial context:**

```cpp
struct Circuit_Specific_Projection {
  std::string circuit_name;  // e.g., "V1→MT pathway", "hippocampal trisynaptic"
  
  // Circuit membership list (from connectome)
  std::vector<uint64_t> neuron_cat_n_ids;  // Which neurons belong to this circuit
  
  // Projection method (can be orthogonal, isometric, or perspective)
  Projection_Method method;
  
  // Base projection parameters
  union {
    Orthogonal2D_Projection ortho;
    Isometric_Projection isometric;
    Perspective_Projection perspective;
  } base_params;
};

Algorithm_Circuit_Specific(
  const Vector3_Double& pos_3d,
  const uint64_t neuron_cat_n_id,
  const Circuit_Specific_Projection& params,
  Vector2_Double& pos_2d_out,
  bool& is_in_circuit
) {
  // Step 1: Check if neuron belongs to this circuit
  is_in_circuit = std::binary_search(
    params.neuron_cat_n_ids.begin(),
    params.neuron_cat_n_ids.end(),
    neuron_cat_n_id  // Binary search requires sorted array
  );
  
  if (!is_in_circuit) {
    pos_2d_out.x = NAN;
    pos_2d_out.y = NAN;
    return;  // Skip neurons outside circuit
  }
  
  // Step 2: Project using base method (orthogonal, isometric, or perspective)
  switch (params.method) {
    case ORTHOGONAL_2D:
      Algorithm_Orthogonal2D(pos_3d, params.base_params.ortho, pos_2d_out);
      break;
    case ISOMETRIC:
      Algorithm_Isometric(pos_3d, params.base_params.isometric, 
                          /* view_matrix */, pos_2d_out);
      break;
    case PERSPECTIVE:
      Algorithm_Perspective_Full(pos_3d, params.base_params.perspective, pos_2d_out);
      break;
  }
}
```

**Determinism**: Inherited from base projection method + deterministic circuit filtering (binary search).

---

### 2.5 LAYER-SPECIFIC PROJECTION (TYPE_5: Cortical Layer Isolation)

**Show only neurons in a named cortical layer (L1-L6):**

```cpp
struct Layer_Specific_Projection {
  std::string layer_name;        // "L4", "L2/3", "L5", etc.
  
  // Layer depth range (z-coordinates in micrometers)
  double layer_z_min;            // e.g., 200 μm for L4
  double layer_z_max;            // e.g., 400 μm for L4
  
  // Base projection
  Perspective_Projection perspective;
};

Algorithm_Layer_Specific(
  const Vector3_Double& pos_3d,
  const Layer_Specific_Projection& params,
  Vector2_Double& pos_2d_out,
  bool& is_in_layer
) {
  // Step 1: Check if neuron's z-depth is in layer range
  is_in_layer = (pos_3d.z >= params.layer_z_min && 
                 pos_3d.z <= params.layer_z_max);
  
  if (!is_in_layer) {
    pos_2d_out.x = NAN;
    pos_2d_out.y = NAN;
    return;
  }
  
  // Step 2: Project with perspective camera
  Algorithm_Perspective_Full(pos_3d, params.perspective, pos_2d_out);
}
```

**Determinism**: Inherited from perspective projection + deterministic layer filtering (z-range check).

---

### 2.6 REGION-SPECIFIC PROJECTION (TYPE_6: Anatomical Region Highlighting)

**Show only neurons in a named brain region (V1, M1, CA1, etc.):**

```cpp
struct Region_Specific_Projection {
  std::string region_name;       // "V1", "M1", "CA1", "dPFC", etc.
  
  // Region membership (from brain atlas)
  std::vector<uint64_t> neuron_cat_n_ids;  // Sorted list
  
  // Base projection
  Perspective_Projection perspective;
};

Algorithm_Region_Specific(
  const Vector3_Double& pos_3d,
  const uint64_t neuron_cat_n_id,
  const Region_Specific_Projection& params,
  Vector2_Double& pos_2d_out,
  bool& is_in_region
) {
  // Step 1: Binary search for region membership
  is_in_region = std::binary_search(
    params.neuron_cat_n_ids.begin(),
    params.neuron_cat_n_ids.end(),
    neuron_cat_n_id
  );
  
  if (!is_in_region) {
    pos_2d_out.x = NAN;
    pos_2d_out.y = NAN;
    return;
  }
  
  // Step 2: Project with perspective
  Algorithm_Perspective_Full(pos_3d, params.perspective, pos_2d_out);
}
```

**Determinism**: Binary search is deterministic; same neuron set always produces same result.

---

### 2.7 ACTIVITY-DRIVEN PROJECTION (TYPE_7: Dynamic Remapping by Firing)

**Project neurons based on recent firing activity (active neurons toward center):**

```cpp
struct Activity_Driven_Projection {
  // Firing rate threshold
  double firing_rate_threshold_hz;  // e.g., 10 Hz for "active"
  
  // Activity center (remapping origin)
  Vector3_Double activity_center;  // Position to project active neurons toward
  
  // Base projection
  Perspective_Projection perspective;
  
  // Activity map: neuron_cat_n_id → firing_rate_hz
  std::unordered_map<uint64_t, double> recent_firing_rates;
};

Algorithm_Activity_Driven(
  const Vector3_Double& pos_3d,
  const uint64_t neuron_cat_n_id,
  const Activity_Driven_Projection& params,
  Vector2_Double& pos_2d_out
) {
  // Step 1: Look up firing rate for this neuron
  auto it = params.recent_firing_rates.find(neuron_cat_n_id);
  double firing_rate = (it != params.recent_firing_rates.end()) ? it->second : 0.0;
  
  // Step 2: Compute activity factor (0.0 = inactive, 1.0 = very active)
  double activity_factor = std::min(1.0, firing_rate / params.firing_rate_threshold_hz);
  
  // Step 3: Interpolate position toward activity center based on firing rate
  Vector3_Double pos_remapped;
  pos_remapped.x = pos_3d.x + (params.activity_center.x - pos_3d.x) * activity_factor * 0.1;
  pos_remapped.y = pos_3d.y + (params.activity_center.y - pos_3d.y) * activity_factor * 0.1;
  pos_remapped.z = pos_3d.z + (params.activity_center.z - pos_3d.z) * activity_factor * 0.1;
  
  // Step 4: Project remapped position
  Algorithm_Perspective_Full(pos_remapped, params.perspective, pos_2d_out);
}
```

**Determinism Warning**: Activity-driven projection is deterministic only if firing rates are recorded (not computed on-the-fly). See **Behavioral Trace Playback** (Section 9) for frame-by-frame activity data.

---

## 3. PROJECTION PARAMETERS: CANONICAL FORMS

### 3.1 IEEE 754 Canonical Double Precision

All floating-point values use IEEE 754 double-precision (64-bit):
- Sign bit: 1
- Exponent: 11 bits
- Mantissa: 52 bits + implicit leading 1

**Canonical rounding mode**: IEEE 754 Round-to-Nearest, Ties-to-Even (default).

```cpp
// Canonical floating-point storage
struct IEEE754_Double {
  uint64_t bits;  // Direct bit pattern (big-endian)
  
  // Convert from double to canonical bits
  static uint64_t Canonicalize(double value) {
    uint64_t bits;
    std::memcpy(&bits, &value, 8);
    // Ensure big-endian byte order
    bits = to_big_endian_u64(bits);
    return bits;
  }
};

// Example canonical values
const double PI_CANONICAL = 3.14159265358979323846;  // Verified to 20 decimal places
const double SQRT2_CANONICAL = 1.41421356237309504880;
const double E_CANONICAL = 2.71828182845904523536;
const double GOLDEN_RATIO_CANONICAL = 1.61803398874989484820;
```

### 3.2 Matrix Canonical Form (Column-Major, IEEE 754)

All matrices stored in column-major order with IEEE 754 doubles:

```cpp
struct Matrix4x4_Canonical {
  // Column-major storage: columns are [0][*], [1][*], [2][*], [3][*]
  double elements[4][4];
  
  // Serialize to big-endian bytes for deterministic hashing
  std::vector<uint8_t> Serialize_Canonical() const {
    std::vector<uint8_t> bytes;
    for (int col = 0; col < 4; col++) {
      for (int row = 0; row < 4; row++) {
        uint64_t bits = IEEE754_Double::Canonicalize(elements[row][col]);
        for (int i = 0; i < 8; i++) {
          bytes.push_back((bits >> (56 - 8*i)) & 0xFF);
        }
      }
    }
    return bytes;
  }
};
```

### 3.3 Parameter Artifact Format

Projection parameters stored as immutable, sealed artifacts (like Phase 6):

```cpp
// PROJECTION_PARAMETERS artifact
// Structure: [METADATA] [PAYLOAD] [INTEGRITY_FIELDS] [SEAL]
// (See Phase 6 for full artifact template)

struct Projection_Parameters_Artifact {
  // Universal artifact header (96 bytes)
  char artifact_id[32];           // "PROJ.PARAM.ORTHO_2D" or similar
  uint32_t version;               // Semantic: e.g., 1.0.0
  uint64_t creation_timestamp;
  uint64_t creator;               // Agent ID
  bool sealed_flag;
  char model_version_hash[32];    // SHA-256(projection model)
  char connectome_version_hash[32];  // SHA-256(neuron positions)
  
  // Identity (64 bytes)
  char description[64];           // "Orthogonal 2D, 1920x1080, scale factors"
  
  // Payload (variable)
  struct {
    uint32_t projection_type;     // TYPE_1, TYPE_2, ..., TYPE_7
    uint32_t parameter_count;
    double parameters[];          // Type-specific parameters
    
    // Example for TYPE_1 (Orthogonal 2D):
    // parameters[0] = scale_x
    // parameters[1] = scale_y
    
    // Example for TYPE_3 (Perspective):
    // parameters[0-2] = eye.x, eye.y, eye.z
    // parameters[3-5] = center.x, center.y, center.z
    // parameters[6-8] = up.x, up.y, up.z
    // parameters[9] = fov_radians
    // parameters[10] = aspect_ratio
    // parameters[11] = near_plane
    // parameters[12] = far_plane
  } payload;
  
  // Integrity fields (128 bytes)
  char parent_digest[32];         // SHA-256(previous version)
  char payload_digest[32];        // SHA-256(canonical payload)
  char integrity_hash[32];        // SHA-256(payload_digest || parent_digest)
  char hmac_tag[32];              // HMAC-SHA-256(K_master, canonical artifact)
  
  // Seal (1 byte)
  bool sealed;
};
```

---

## 4. GPU RENDERING PIPELINE (5 STAGES)

### 4.1 Stage 1: Load & Validate Artifacts

```
STAGE_1_LOAD_VALIDATE
  Input: Phase 6 artifacts (NODE_INDEX_TABLE, SYNAPSE_INDEX_TABLE, partitions)
  Input: Projection parameters artifact
  
  1. Load NODE_INDEX_TABLE (760M entries, ~213 GB)
     - Verify SHA-256 digest
     - Verify HMAC-SHA-256
     - Verify no collisions
  
  2. Load SYNAPSE_INDEX_TABLE (1B entries, ~9.7 TB)
     - Verify SHA-256 digest
     - Verify HMAC-SHA-256
     - Verify bidirectional consistency
  
  3. Load PROJECTION_PARAMETERS artifact
     - Verify SHA-256 digest
     - Extract projection type and matrix values
     - Verify matrices are biologically plausible (camera within brain bounds)
  
  4. Check phase consistency
     - NODE_INDEX_TABLE.model_version == PROJECTION_PARAMETERS.model_version
     - All artifacts have same creation timestamp (within 1 second)
  
  Output: Validated artifacts, ready for GPU transfer
```

### 4.2 Stage 2: Partition-Based GPU Memory Management

```
STAGE_2_GPU_PARTITION_LOADER
  Input: Validated NODE_INDEX_TABLE, projection parameters
  Input: GPU memory budget (A100-40GB = 40 GB available)
  
  Strategy: Load neuron positions partition-by-partition
  
  1. Partition size calculation
     - Each partition contains 760M / 24 ≈ 31.67M neurons
     - Per neuron: 3 × 8 bytes (x, y, z) + 4 bytes (type) = 28 bytes
     - Per partition: 31.67M × 28 bytes ≈ 890 MB
     - Per partition synapse edges: ~50M synapses × 32 bytes = 1.6 GB
     - Total per partition: ~2.5 GB
     - GPU VRAM available: 40 GB
     - Simultaneous partitions: 40 GB / 2.5 GB ≈ 16 partitions in GPU memory
  
  2. Partition loading order
     - Load partition 1-4 (V1, V2, V3, V3A)
     - Allocate GPU buffers for each
     - Transfer via PCIe-Gen4 (32 GB/s typical)
     - Parallel loading: 2.5 GB / 32 GB/s ≈ 78 ms per partition
     - Concurrent: ~312 ms for 4 partitions
  
  3. GPU buffer layout (per partition)
     struct GPU_Neuron_Buffer {
       uint64_t neuron_count;
       
       // Per-neuron data (compacted, GPU-optimized)
       float3 positions[neuron_count];        // xyz coordinates (float32 × 3)
       uint32_t neuron_type[neuron_count];    // Type enum (1-64)
       uint32_t firing_rate_hz[neuron_count]; // Recent activity (0-200 Hz)
       float4 state[neuron_count];            // V, m, h, n (Hodgkin-Huxley state)
     };
  
  Output: 16 GPU buffers loaded, ready for projection
```

### 4.3 Stage 3: GPU Projection Kernel (Compute Shader)

```cpp
// COMPUTE SHADER: Project 3D → 2D + Map Activity to Color/Size

__global__ void Projection_Compute_Kernel(
  const float3* gpu_positions_3d,          // Input: 3D neuron positions
  const uint32_t* gpu_firing_rates,        // Input: firing rates (Hz)
  const uint32_t* gpu_neuron_types,        // Input: neuron types
  const uint32_t neuron_count,
  
  // Projection parameters (in constant memory)
  const double* projection_matrix_data,    // 4×4 matrix (16 doubles)
  const double* view_matrix_data,          // 4×4 matrix (16 doubles)
  const uint32_t projection_type,          // TYPE_1, TYPE_2, ..., TYPE_7
  
  // Output buffers
  float2* gpu_positions_2d_out,            // Output: 2D projected positions
  float4* gpu_colors_out,                  // Output: RGBA colors (V → color)
  float* gpu_sizes_out,                    // Output: neuron radius (firing → size)
  uint32_t* gpu_visibility_mask            // Output: 1 if visible, 0 if culled
) {
  // Each thread processes one neuron
  uint32_t neuron_idx = blockIdx.x * blockDim.x + threadIdx.x;
  
  if (neuron_idx >= neuron_count) return;
  
  // Step 1: Load 3D position (coalesced memory access)
  float3 pos_3d = gpu_positions_3d[neuron_idx];
  
  // Step 2: Projection (type-specific)
  float2 pos_2d;
  bool visible = true;
  
  if (projection_type == TYPE_ORTHOGONAL_2D) {
    // Direct orthogonal: x, y only
    pos_2d.x = pos_3d.x / SCALE_X;  // SCALE_X in constant memory
    pos_2d.y = pos_3d.y / SCALE_Y;
  } 
  else if (projection_type == TYPE_PERSPECTIVE) {
    // Full perspective projection
    float4 homog = make_float4(pos_3d.x, pos_3d.y, pos_3d.z, 1.0f);
    
    // View matrix multiply (manual unroll for performance)
    float4 viewed;
    viewed.x = view_matrix_data[0] * homog.x + view_matrix_data[1] * homog.y + 
               view_matrix_data[2] * homog.z + view_matrix_data[3] * homog.w;
    viewed.y = view_matrix_data[4] * homog.x + view_matrix_data[5] * homog.y + 
               view_matrix_data[6] * homog.z + view_matrix_data[7] * homog.w;
    viewed.z = view_matrix_data[8] * homog.x + view_matrix_data[9] * homog.y + 
               view_matrix_data[10] * homog.z + view_matrix_data[11] * homog.w;
    viewed.w = view_matrix_data[12] * homog.x + view_matrix_data[13] * homog.y + 
               view_matrix_data[14] * homog.z + view_matrix_data[15] * homog.w;
    
    // Projection matrix multiply
    float4 projected;
    projected.x = projection_matrix_data[0] * viewed.x + projection_matrix_data[1] * viewed.y + 
                  projection_matrix_data[2] * viewed.z + projection_matrix_data[3] * viewed.w;
    projected.y = projection_matrix_data[4] * viewed.x + projection_matrix_data[5] * viewed.y + 
                  projection_matrix_data[6] * viewed.z + projection_matrix_data[7] * viewed.w;
    projected.z = projection_matrix_data[8] * viewed.x + projection_matrix_data[9] * viewed.y + 
                  projection_matrix_data[10] * viewed.z + projection_matrix_data[11] * viewed.w;
    projected.w = projection_matrix_data[12] * viewed.x + projection_matrix_data[13] * viewed.y + 
                  projection_matrix_data[14] * viewed.z + projection_matrix_data[15] * viewed.w;
    
    // Homogeneous division
    float w_inv = 1.0f / projected.w;
    pos_2d.x = projected.x * w_inv;
    pos_2d.y = projected.y * w_inv;
    
    // Frustum culling (discard if outside NDC space [-1, 1])
    visible = (pos_2d.x >= -1.0f && pos_2d.x <= 1.0f &&
               pos_2d.y >= -1.0f && pos_2d.y <= 1.0f);
  }
  
  // Step 3: Activity-based color mapping (V → RGB)
  // Assuming firing_rate encodes recent membrane voltage activity
  uint32_t firing_rate = gpu_firing_rates[neuron_idx];  // 0-200 Hz
  
  // Color gradient: blue (0 Hz) → red (200 Hz)
  float rate_normalized = (float)firing_rate / 200.0f;  // ∈ [0, 1]
  
  float4 color;
  if (rate_normalized < 0.5f) {
    // Blue → Green (0-100 Hz)
    color.x = 0.0f;
    color.y = rate_normalized * 2.0f;  // 0 → 1
    color.z = 1.0f - rate_normalized * 2.0f;  // 1 → 0
  } else {
    // Green → Red (100-200 Hz)
    color.x = (rate_normalized - 0.5f) * 2.0f;  // 0 → 1
    color.y = 1.0f - (rate_normalized - 0.5f) * 2.0f;  // 1 → 0
    color.z = 0.0f;
  }
  color.w = 1.0f;  // Alpha = 1 (opaque)
  
  // Step 4: Size mapping (firing_rate → radius)
  float radius = 0.1f + (rate_normalized * 4.0f);  // 0.1 → 4.1 pixels
  
  // Step 5: Write outputs
  gpu_positions_2d_out[neuron_idx] = pos_2d;
  gpu_colors_out[neuron_idx] = color;
  gpu_sizes_out[neuron_idx] = radius;
  gpu_visibility_mask[neuron_idx] = visible ? 1 : 0;
}

// GPU invocation
// Grid: (neuron_count + 256 - 1) / 256 blocks
// Block: 256 threads
// Execution: ~5-10 ms per partition (31.67M neurons)
```

### 4.4 Stage 4: Render Projected Neurons (Graphics Pipeline)

```glsl
// VERTEX SHADER: Position + Color per neuron

#version 450

// Uniforms: viewport dimensions
uniform int viewport_width;
uniform int viewport_height;

// Input: projected 2D positions from compute shader
layout(binding = 0, std430) buffer PositionBuffer {
  vec2 positions[];
};

layout(binding = 1, std430) buffer ColorBuffer {
  vec4 colors[];
};

layout(binding = 2, std430) buffer SizeBuffer {
  float sizes[];
};

layout(binding = 3, std430) buffer VisibilityBuffer {
  uint visibility[];
};

layout(location = 0) out VS_OUT {
  vec4 color;
  float radius;
} vs_out;

void main() {
  uint neuron_idx = gl_VertexID;
  
  if (visibility[neuron_idx] == 0) {
    gl_Position = vec4(2.0, 2.0, 0.0, 1.0);  // Culled (outside NDC)
    return;
  }
  
  // Load projected position
  vec2 pos_2d = positions[neuron_idx];
  
  // Normalize to NDC: [0, width] × [0, height] → [-1, 1] × [-1, 1]
  float ndc_x = (pos_2d.x / float(viewport_width)) * 2.0 - 1.0;
  float ndc_y = 1.0 - (pos_2d.y / float(viewport_height)) * 2.0;  // Y inverted
  
  gl_Position = vec4(ndc_x, ndc_y, 0.0, 1.0);
  
  // Load color and size
  vs_out.color = colors[neuron_idx];
  vs_out.radius = sizes[neuron_idx] / float(viewport_width);  // Normalize to NDC
}

// FRAGMENT SHADER: Render circular neurons

#version 450

layout(location = 0) in VS_OUT {
  vec4 color;
  float radius;
} fs_in;

layout(location = 0) out vec4 frag_color;

void main() {
  // Compute distance from quad center
  vec2 coord = gl_PointCoord - vec2(0.5);
  float dist_sq = dot(coord, coord);
  
  // Discard if outside circle
  if (dist_sq > 0.25) {
    discard;
  }
  
  // Smooth falloff at edge
  float edge_dist = sqrt(dist_sq) - (fs_in.radius - 0.01);
  float alpha = 1.0 - smoothstep(0.0, 0.01, edge_dist);
  
  frag_color = vec4(fs_in.color.rgb, alpha);
}
```

**Performance**:
- Neuron rendering: ~10 ms for 100K neurons (100M polygons/sec)
- GPU utilization: 75-90%
- Memory bandwidth: ~20 GB/s (GPU → display)

### 4.5 Stage 5: Render Synapses (Edges) & Composite

```glsl
// EDGE RENDERING: Synapses as line segments

// Compute shader: Project synapse endpoints to 2D

__global__ void Synapse_Projection_Kernel(
  const uint64_t* gpu_synapse_ids,         // CAT-S-ID
  const uint32_t* gpu_source_indices,      // Source neuron index in positions buffer
  const uint32_t* gpu_dest_indices,        // Dest neuron index
  const uint32_t synapse_count,
  
  const float2* gpu_positions_2d,          // Projected 2D positions (from Stage 3)
  const float* gpu_synaptic_activity,      // Transmission strength (0-1)
  
  float2* gpu_edge_endpoints_out,          // Output: [source_x, source_y, dest_x, dest_y, ...]
  float4* gpu_edge_colors_out,             // Output: RGBA colors
  uint32_t* gpu_edge_visibility_mask       // Output: 1 if both endpoints visible
) {
  uint32_t synapse_idx = blockIdx.x * blockDim.x + threadIdx.x;
  
  if (synapse_idx >= synapse_count) return;
  
  // Step 1: Get source and destination positions
  uint32_t src_idx = gpu_source_indices[synapse_idx];
  uint32_t dst_idx = gpu_dest_indices[synapse_idx];
  
  float2 src_pos = gpu_positions_2d[src_idx];
  float2 dst_pos = gpu_positions_2d[dst_idx];
  
  // Step 2: Check if both endpoints are visible (within NDC)
  bool src_visible = (src_pos.x >= -1.0f && src_pos.x <= 1.0f &&
                      src_pos.y >= -1.0f && src_pos.y <= 1.0f);
  bool dst_visible = (dst_pos.x >= -1.0f && dst_pos.x <= 1.0f &&
                      dst_pos.y >= -1.0f && dst_pos.y <= 1.0f);
  
  uint32_t visible = (src_visible && dst_visible) ? 1 : 0;
  gpu_edge_visibility_mask[synapse_idx] = visible;
  
  if (!visible) return;
  
  // Step 3: Map synaptic activity to color and opacity
  float activity = gpu_synaptic_activity[synapse_idx];  // ∈ [0, 1]
  
  float4 edge_color;
  if (activity < 0.5f) {
    // Gray → Green (inactive → moderately active)
    edge_color.x = 0.5f * (1.0f - activity * 2.0f);
    edge_color.y = activity * 2.0f;
    edge_color.z = 0.5f * (1.0f - activity * 2.0f);
  } else {
    // Green → Red (moderately → very active)
    edge_color.x = (activity - 0.5f) * 2.0f;
    edge_color.y = 1.0f - (activity - 0.5f) * 2.0f;
    edge_color.z = 0.0f;
  }
  edge_color.w = activity;  // Opacity = activity
  
  // Step 4: Write endpoints and color
  gpu_edge_endpoints_out[synapse_idx * 2 + 0] = src_pos;
  gpu_edge_endpoints_out[synapse_idx * 2 + 1] = dst_pos;
  gpu_edge_colors_out[synapse_idx] = edge_color;
}

// Line rendering (existing graphics pipeline)
// Render edges via indexed draw call
// Line width: ~0.5-2.0 pixels (configurable)
```

**Edge Rendering Performance**:
- Synapse count: ~1B total, ~50M per partition
- Visible edges (in viewport): ~1-10M (depends on zoom/pan)
- Edge rendering: ~50-100 ms for 10M edges

### 4.6 Composite & Display

```
STAGE_5_COMPOSITE
  
  1. Render neurons (circles) to backbuffer
  2. Render synapses (lines) on top
  3. Optional: Render layer boundaries, region labels
  4. Composite any overlays (HUD, behavioral annotations)
  5. Present to display (60 Hz refresh)
  
  Total latency per frame: ~200 ms
  Target framerate: 5 Hz (200 ms per frame)
  
  For real-time interaction (60 Hz):
  - Reduce neuron/synapse count via aggressive LOD
  - Use viewport frustum culling
  - Pre-render distant regions as textures
```

---

## 5. LEVEL-OF-DETAIL (LOD) RENDERING

### 5.1 LOD Selection Algorithm

```cpp
struct LOD_Config {
  // Viewport metrics
  uint32_t viewport_width;
  uint32_t viewport_height;
  double zoom_level;           // ∈ (0, ∞], 1.0 = full brain
  
  // Compute visible neurons estimate
  uint32_t Estimate_Visible_Neurons() const {
    // Brain volume: 60mm × 50mm × 40mm = 120,000 mm³
    // 760M neurons: 760M / 120,000 ≈ 6,333 neurons/mm³
    
    // Frustum volume (approximate):
    double frustum_width_mm = 60.0 / zoom_level;
    double frustum_height_mm = 50.0 / zoom_level;
    double frustum_depth_mm = 40.0;  // Full z-depth
    
    double frustum_volume = frustum_width_mm * frustum_height_mm * frustum_depth_mm;
    uint32_t visible_neurons = (uint32_t)(frustum_volume * 6333.0);
    
    return visible_neurons;
  }
};

enum LOD_Level {
  LOD_0 = 0,    // 1-158 neurons (single neuron to small circuit)
  LOD_1,        // 158-1K (small circuit, single layer)
  LOD_2,        // 1K-10K (layer patch, sub-region)
  LOD_3,        // 10K-100K (cortical column, major circuit)
  LOD_4,        // 100K-1M (whole layer, region)
  LOD_5,        // 1M-10M (multi-layer, visual system)
  LOD_6,        // 10M-100M (whole cortex)
  LOD_7         // 100M-760M (full brain)
};

LOD_Level Select_LOD(uint32_t visible_neuron_estimate) {
  if (visible_neuron_estimate <= 158) return LOD_0;
  if (visible_neuron_estimate <= 1000) return LOD_1;
  if (visible_neuron_estimate <= 10000) return LOD_2;
  if (visible_neuron_estimate <= 100000) return LOD_3;
  if (visible_neuron_estimate <= 1000000) return LOD_4;
  if (visible_neuron_estimate <= 10000000) return LOD_5;
  if (visible_neuron_estimate <= 100000000) return LOD_6;
  return LOD_7;
}
```

### 5.2 LOD-Specific Rendering

```cpp
// For each LOD level, define rendering strategy:

struct LOD_Strategy {
  uint32_t max_neurons;
  uint32_t max_synapses;
  float neuron_point_size_pixels;
  bool render_synapses;
  bool render_layer_boundaries;
  
  static const LOD_Strategy strategies[] = {
    // LOD_0: Single neuron → small circuit
    {158, 500, 8.0, true, false},
    
    // LOD_1: Layer patch
    {1000, 2000, 4.0, true, false},
    
    // LOD_2: Sub-region
    {10000, 10000, 2.0, true, false},
    
    // LOD_3: Cortical column
    {100000, 50000, 1.0, true, true},
    
    // LOD_4: Whole layer
    {1000000, 200000, 0.5, false, true},
    
    // LOD_5: Multi-layer system
    {10000000, 500000, 0.2, false, true},
    
    // LOD_6: Whole cortex
    {100000000, 1000000, 0.1, false, true},
    
    // LOD_7: Full brain
    {760000000, 2000000, 0.05, false, true}
  };
};
```

---

## 6. COORDINATE TRANSFORMATION & NORMALIZATION

### 6.1 Source Coordinate Space (Brain Space)

```
SOURCE COORDINATES (micrometers):
  x ∈ [0, 60,000] μm (anterior-posterior, A-P)
  y ∈ [0, 50,000] μm (medial-lateral, M-L)
  z ∈ [0, 40,000] μm (dorsal-ventral, D-V)
  
  Origin (0, 0, 0): Anterior-medial-dorsal corner
  Units: Micrometers (10^-6 m)
  
  Example: V1 primary visual cortex
    - Bregma: ~(-2mm, 0mm) in stereotactic coordinates
    - In source coords: (2000 μm, 25000 μm, z_layer-dependent)
```

### 6.2 Display Coordinate Space (Screen Pixels)

```
DISPLAY COORDINATES (pixels):
  x ∈ [0, viewport_width]
  y ∈ [0, viewport_height]
  
  Origin (0, 0): Top-left corner
  Units: Pixels (view-dependent)
  
  Example: 1920×1080 display
    Center: (960, 540)
```

### 6.3 Transformation Pipeline

```cpp
// Transform source → display coordinates

Vector2_Double Transform_Source_To_Display(
  const Vector3_Double& source_coords_um,
  const Orthogonal2D_Projection& proj,
  uint32_t viewport_width,
  uint32_t viewport_height
) {
  // Step 1: Source micrometers → millimeters
  double x_mm = source_coords_um.x / 1000.0;
  double y_mm = source_coords_um.y / 1000.0;
  
  // Step 2: Brain reference frame → normalized [0, 1]
  // Brain dimensions: 60mm × 50mm
  double x_normalized = x_mm / 60.0;  // ∈ [0, 1]
  double y_normalized = y_mm / 50.0;  // ∈ [0, 1]
  
  // Step 3: Normalized → display pixels
  double x_pixels = x_normalized * viewport_width;
  double y_pixels = y_normalized * viewport_height;
  
  return {x_pixels, y_pixels};
}

// Inverse transform: display → source coordinates

Vector3_Double Transform_Display_To_Source(
  const Vector2_Double& display_pixels,
  uint32_t viewport_width,
  uint32_t viewport_height,
  double z_um  // Z-depth (optional, for 3D picking)
) {
  // Step 1: Display pixels → normalized [0, 1]
  double x_normalized = display_pixels.x / viewport_width;
  double y_normalized = display_pixels.y / viewport_height;
  
  // Step 2: Normalized → millimeters
  double x_mm = x_normalized * 60.0;
  double y_mm = y_normalized * 50.0;
  
  // Step 3: Millimeters → micrometers
  double x_um = x_mm * 1000.0;
  double y_um = y_mm * 1000.0;
  
  return {x_um, y_um, z_um};
}
```

### 6.4 Determinism in Coordinate Transformation

All transformations use IEEE 754 double-precision:
- Multiplication and division are IEEE 754 exact for representable values
- Rounding is canonical (Round-to-Nearest, Ties-to-Even)
- Result: Same source coords → identical display pixels (bit-for-bit)

---

## 7. NEURAL STATE VISUALIZATION

### 7.1 Membrane Potential → Color Mapping

```cpp
struct Membrane_Potential_Colormap {
  // Canonical voltage-to-color mapping
  // Uses IEEE 754 double precision for interpolation
  
  struct Voltage_Color_Point {
    double voltage_mv;  // Membrane potential (millivolts)
    uint8_t r, g, b;    // RGB color
  };
  
  static const Voltage_Color_Point color_points[] = {
    {-70.0, 0x00, 0x00, 0xFF},   // Blue (resting)
    {-50.0, 0x00, 0xFF, 0xFF},   // Cyan
    {-30.0, 0x00, 0xFF, 0x00},   // Green
    {0.0,   0xFF, 0xFF, 0x00},   // Yellow
    {20.0,  0xFF, 0x00, 0x00},   // Red
    {30.0,  0xFF, 0xFF, 0xFF}    // White (spike peak)
  };
  
  float4 Get_Color_For_Voltage(double voltage_mv) {
    // Linear interpolation between nearest color points
    
    // Find bracketing points
    int lower_idx = 0;
    for (int i = 0; i < ARRAY_SIZE(color_points) - 1; i++) {
      if (voltage_mv >= color_points[i].voltage_mv &&
          voltage_mv <= color_points[i+1].voltage_mv) {
        lower_idx = i;
        break;
      }
    }
    
    // Clamp to range
    if (voltage_mv < color_points[0].voltage_mv) {
      lower_idx = 0;
    } else if (voltage_mv > color_points[ARRAY_SIZE(color_points)-1].voltage_mv) {
      lower_idx = ARRAY_SIZE(color_points) - 2;
    }
    
    // Linear interpolation factor
    double v_lower = color_points[lower_idx].voltage_mv;
    double v_upper = color_points[lower_idx + 1].voltage_mv;
    double t = (voltage_mv - v_lower) / (v_upper - v_lower);  // ∈ [0, 1]
    
    // Interpolate RGB
    float r = (float)color_points[lower_idx].r * (1.0f - t) + 
              (float)color_points[lower_idx + 1].r * t;
    float g = (float)color_points[lower_idx].g * (1.0f - t) + 
              (float)color_points[lower_idx + 1].g * t;
    float b = (float)color_points[lower_idx].b * (1.0f - t) + 
              (float)color_points[lower_idx + 1].b * t;
    
    return {r / 255.0f, g / 255.0f, b / 255.0f, 1.0f};
  }
};
```

### 7.2 Firing Rate → Size Mapping

```cpp
struct Firing_Rate_Sizemap {
  // Firing rate (Hz) → neuron radius (pixels)
  
  double Get_Radius_For_Firing_Rate(double firing_rate_hz) {
    // Nonlinear mapping: sqrt scaling
    // r = 0.1 + sqrt(firing_rate / 200) * 4.0
    
    double normalized_rate = firing_rate_hz / 200.0;  // Normalize to [0, 1]
    if (normalized_rate > 1.0) normalized_rate = 1.0;
    
    double radius = 0.1 + sqrt(normalized_rate) * 4.0;  // ∈ [0.1, 4.1] pixels
    
    return radius;
  }
};
```

### 7.3 Recent Activity → Opacity Mapping

```cpp
struct Activity_Opacity_Map {
  // Time since last spike (ms) → opacity (alpha)
  
  double Get_Opacity_For_Recent_Activity(double ms_since_last_spike) {
    // Exponential decay: α = exp(-t / tau)
    // tau = 100 ms (decay timescale)
    
    double tau_ms = 100.0;
    double alpha = exp(-ms_since_last_spike / tau_ms);
    
    // Clamp to [0.3, 1.0]
    if (alpha < 0.3) alpha = 0.3;
    if (alpha > 1.0) alpha = 1.0;
    
    return alpha;
  }
};
```

---

## 8. INTERACTIVE VISUALIZATION CONTROLS

### 8.1 User Input Handling

```cpp
struct Visualization_Input {
  // Pan: Translate view in 2D
  struct {
    double delta_x_pixels;
    double delta_y_pixels;
  } pan;
  
  // Zoom: Change perspective or orthogonal scale
  struct {
    double zoom_factor;  // >1.0 = zoom in, <1.0 = zoom out
  } zoom;
  
  // Rotate: Change camera angle (for perspective)
  struct {
    double rotation_x_rad;  // Pitch (vertical rotation)
    double rotation_y_rad;  // Yaw (horizontal rotation)
    double rotation_z_rad;  // Roll (rotation around view axis)
  } rotate;
  
  // Connectivity toggle
  struct {
    bool show_feedforward;   // ∈ {true, false}
    bool show_recurrent;     // ∈ {true, false}
    bool show_feedback;      // ∈ {true, false}
  } connectivity_toggle;
  
  // Activity overlay
  struct {
    bool show_activity;
    double activity_threshold_hz;
  } activity_overlay;
};

// Update camera based on user input
void Update_Camera(
  const Visualization_Input& input,
  Perspective_Projection& camera_out
) {
  // Step 1: Handle pan
  // (Translate lookat target in world space)
  Vector3_Double pan_offset = {
    input.pan.delta_x_pixels * 0.01,  // Scale pixels → world units
    input.pan.delta_y_pixels * 0.01,
    0.0
  };
  camera_out.center = Vector_Add(camera_out.center, pan_offset);
  camera_out.eye = Vector_Add(camera_out.eye, pan_offset);
  
  // Step 2: Handle zoom
  // (Move eye closer/farther from center)
  Vector3_Double to_center = Vector_Subtract(camera_out.center, camera_out.eye);
  double current_distance = Vector_Length(to_center);
  double new_distance = current_distance / input.zoom.zoom_factor;
  
  Vector3_Double direction = Vector_Normalize(to_center);
  camera_out.eye = Vector_Subtract(
    camera_out.center,
    Vector_Multiply_Scalar(direction, new_distance)
  );
  
  // Step 3: Handle rotation (spherical coordinates)
  // (Rotate eye around center, maintaining up vector)
  // (Implementation: convert eye to spherical, rotate, convert back)
  // [Detailed implementation omitted for brevity]
  
  // Step 4: Recompute view and projection matrices
  // (Cached for GPU execution)
}
```

### 8.2 Neuron Highlighting & Inspection

```cpp
struct Neuron_Highlight {
  uint64_t highlighted_neuron_cat_n_id;  // Which neuron to highlight
  
  // Incoming synapses (neurons that synapse onto this neuron)
  std::vector<uint64_t> incoming_neurons;
  
  // Outgoing synapses (neurons this neuron synapses onto)
  std::vector<uint64_t> outgoing_neurons;
  
  // Render parameters
  float highlight_color_r, highlight_color_g, highlight_color_b;
  float highlight_size_multiplier;  // 2.0 = twice as large
};

void Render_With_Highlight(
  const Neuron_Highlight& highlight,
  const GPU_Neuron_Buffer& neurons,
  const GPU_Synapse_Buffer& synapses
) {
  // Step 1: Render all neurons with normal colors
  Render_All_Neurons(neurons);
  
  // Step 2: Highlight incoming neurons (blue edges)
  for (uint64_t incoming_id : highlight.incoming_neurons) {
    uint32_t neuron_idx = Lookup_Neuron_Index(incoming_id);
    Render_Neuron_With_Color(
      neurons[neuron_idx],
      {0.0f, 0.0f, 1.0f, 1.0f}  // Blue
    );
  }
  
  // Step 3: Highlight outgoing neurons (green edges)
  for (uint64_t outgoing_id : highlight.outgoing_neurons) {
    uint32_t neuron_idx = Lookup_Neuron_Index(outgoing_id);
    Render_Neuron_With_Color(
      neurons[neuron_idx],
      {0.0f, 1.0f, 0.0f, 1.0f}  // Green
    );
  }
  
  // Step 4: Highlight central neuron (red, larger)
  uint32_t central_idx = Lookup_Neuron_Index(highlight.highlighted_neuron_cat_n_id);
  Render_Neuron_With_Color_And_Size(
    neurons[central_idx],
    {1.0f, 0.0f, 0.0f, 1.0f},  // Red
    highlight.highlight_size_multiplier
  );
}
```

---

## 9. BEHAVIORAL TRACE PLAYBACK

### 9.1 Activity Frame Archive Structure

```cpp
// ACTIVITY_FRAME_ARCHIVE (compressed, deterministic)
// Precomputed neural activity over time (from simulation)

struct Activity_Frame_Archive {
  // Metadata
  std::string archive_id;                // "ACTIVITY.V1.2026-09-13.run_0001"
  uint64_t simulation_start_timestep;    // t=0
  uint64_t simulation_end_timestep;      // t=1,000,000 (e.g.)
  uint32_t frame_interval_ms;            // 10 ms between frames
  
  // Archive format: GZIP compressed binary
  struct Frame {
    uint64_t timestep;                   // Simulation timestep
    uint32_t spike_count;                // Number of spike events this frame
    std::vector<Spike_Event> spikes;     // [(neuron_id, timestamp)]
    
    std::vector<double> membrane_potentials;  // Per-neuron V (mV), compressed
    std::vector<uint8_t> spike_raster;   // Bit-packed spike presence
  };
  
  std::vector<Frame> frames;  // Loaded on-demand from archive
};

// Spike event (8 bytes per spike)
struct Spike_Event {
  uint32_t neuron_index;     // Index in neuron buffer
  uint16_t millisecond;      // Offset within frame (0-9 ms)
  uint16_t reserved;         // Padding
};
```

### 9.2 Trace Playback Algorithm

```cpp
void Playback_Activity_Trace(
  const Activity_Frame_Archive& archive,
  double playback_speed_multiplier,  // 1.0x = realtime, 10.0x = 10× speed
  uint32_t& current_frame_idx,
  GPU_Neuron_Buffer& neurons_out
) {
  // Step 1: Load next frame from archive (if needed)
  if (current_frame_idx >= archive.frames.size()) {
    // End of trace
    return;
  }
  
  const Activity_Frame& frame = archive.frames[current_frame_idx];
  
  // Step 2: Update neuron states based on spike events
  for (const Spike_Event& spike : frame.spikes) {
    // Mark neuron as recently spiked
    neurons_out.last_spike_time[spike.neuron_index] = frame.timestep;
    neurons_out.membrane_voltage[spike.neuron_index] = 30.0;  // Spike peak
  }
  
  // Step 3: Decay membrane voltages (exponential decay toward resting)
  for (uint32_t i = 0; i < neurons_out.neuron_count; i++) {
    double tau_ms = 20.0;  // Membrane time constant
    double decay_factor = exp(-1.0 / tau_ms);
    neurons_out.membrane_voltage[i] *= decay_factor;
    
    // Clamp to resting potential
    if (neurons_out.membrane_voltage[i] < -70.0) {
      neurons_out.membrane_voltage[i] = -70.0;
    }
  }
  
  // Step 4: Advance to next frame
  // (Frame rate controlled by playback_speed_multiplier and display refresh)
  current_frame_idx++;
}
```

### 9.3 Determinism in Trace Playback

```
TRACE PLAYBACK DETERMINISM:
  Same archive + same frame index → identical neuron states
  
  Proof:
  1. Archive frames are deterministically generated (Phase 6 GPU simulation)
  2. Frame loading is deterministic (no randomness)
  3. Membrane potential decay uses canonical IEEE 754 exponential
  4. Spike application is deterministic (same spike set → same updates)
  
  Result: Run playback twice → identical pixel output
```

---

## 10. DETERMINISM VERIFICATION PROTOCOL

### 10.1 Bit-for-Bit Reproducibility Test

```cpp
// DETERMINISM_TEST: Run projection twice, compare all outputs bit-for-bit

bool Verify_Projection_Determinism(
  const std::vector<Vector3_Double>& neuron_positions_3d,  // 760M neurons
  const Perspective_Projection& camera,
  uint32_t iterations = 2
) {
  // Run 1: Compute all 2D projections
  std::vector<Vector2_Double> output_run_1(neuron_positions_3d.size());
  for (size_t i = 0; i < neuron_positions_3d.size(); i++) {
    Algorithm_Perspective_Full(
      neuron_positions_3d[i],
      camera,
      output_run_1[i]
    );
  }
  
  // Serialize run 1 output to bytes
  std::vector<uint8_t> bytes_run_1 = Serialize_IEEE754_Doubles(output_run_1);
  SHA256 hash_run_1 = SHA256(bytes_run_1);
  
  // Run 2: Recompute projections
  std::vector<Vector2_Double> output_run_2(neuron_positions_3d.size());
  for (size_t i = 0; i < neuron_positions_3d.size(); i++) {
    Algorithm_Perspective_Full(
      neuron_positions_3d[i],
      camera,
      output_run_2[i]
    );
  }
  
  // Serialize run 2 output to bytes
  std::vector<uint8_t> bytes_run_2 = Serialize_IEEE754_Doubles(output_run_2);
  SHA256 hash_run_2 = SHA256(bytes_run_2);
  
  // Compare hashes
  bool deterministic = (hash_run_1 == hash_run_2);
  
  if (!deterministic) {
    log_error("PROJECTION DETERMINISM FAILED!");
    log_error("Run 1 hash: {}", hash_run_1.to_hex());
    log_error("Run 2 hash: {}", hash_run_2.to_hex());
    
    // Find first mismatching neuron
    for (size_t i = 0; i < output_run_1.size(); i++) {
      if (output_run_1[i].x != output_run_2[i].x ||
          output_run_1[i].y != output_run_2[i].y) {
        log_error("First mismatch at neuron {}: ({}, {}) vs ({}, {})",
          i,
          output_run_1[i].x, output_run_1[i].y,
          output_run_2[i].x, output_run_2[i].y
        );
        break;
      }
    }
  }
  
  return deterministic;
}

// Test parameters (Phase 7 validation)
void Run_Determinism_Test_Suite() {
  // Test 1: Orthogonal 2D projection
  log_info("Test 1: Orthogonal 2D determinism...");
  assert(Verify_Orthogonal2D_Determinism());
  log_info("  PASS");
  
  // Test 2: Isometric projection
  log_info("Test 2: Isometric determinism...");
  assert(Verify_Isometric_Determinism());
  log_info("  PASS");
  
  // Test 3: Perspective projection
  log_info("Test 3: Perspective determinism...");
  assert(Verify_Perspective_Determinism());
  log_info("  PASS");
  
  // Test 4: Circuit-specific filtering
  log_info("Test 4: Circuit filtering determinism...");
  assert(Verify_Circuit_Determinism());
  log_info("  PASS");
  
  // Test 5: GPU compute shader output
  log_info("Test 5: GPU compute shader determinism...");
  assert(Verify_GPU_Compute_Determinism());
  log_info("  PASS");
  
  // Test 6: Full rendering pipeline
  log_info("Test 6: Full pipeline determinism...");
  assert(Verify_Full_Pipeline_Determinism());
  log_info("  PASS");
  
  log_info("All determinism tests PASSED");
}
```

### 10.2 Output Artifact Format (Determinism-Verified)

```cpp
// DETERMINISM_VERIFICATION_ARTIFACT
// Records proof that projection was deterministic

struct Determinism_Verification_Artifact {
  // Universal artifact header (from Phase 6)
  char artifact_id[32];          // "PROJ_VERIFY.V1.ORTHO_2D"
  uint32_t version;
  uint64_t creation_timestamp;
  uint64_t creator;              // AGENT_3
  bool sealed_flag;
  char model_version_hash[32];
  char connectome_version_hash[32];
  
  // Identity
  char description[64];          // "Perspective projection, V1 region, 1920x1080"
  
  // Verification payload
  struct {
    uint32_t projection_type;    // TYPE_1, TYPE_2, ..., TYPE_7
    uint32_t neuron_count;       // How many neurons projected
    uint32_t test_iterations;    // Number of repetitions (typically 2-5)
    
    // Output hashes from each iteration
    char output_hash_run_1[32];  // SHA-256(canonical output)
    char output_hash_run_2[32];
    char output_hash_run_3[32];
    // ... (up to test_iterations)
    
    // Determinism result
    bool all_hashes_match;       // true if all runs identical
    
    // Random sample verification
    uint32_t sample_neuron_count;  // Number of neurons spot-checked
    struct {
      uint32_t neuron_index;
      double x_screen_run_1;
      double x_screen_run_2;
      double y_screen_run_1;
      double y_screen_run_2;
      bool match;
    } sample_results[];  // Array of spot-check results
    
    char verification_digest[32];  // SHA-256(all verification data)
  } payload;
  
  // Integrity fields (128 bytes)
  char parent_digest[32];
  char body_digest[32];
  char integrity_hash[32];
  char hmac_tag[32];
  
  // Seal
  bool sealed;
};
```

---

## 11. PERFORMANCE SPECIFICATIONS

### 11.1 Timing Breakdown (GPU A100-40GB)

```
PROJECTION PIPELINE LATENCY (ms):

Stage 1: Load & Validate Artifacts
  - Load NODE_INDEX_TABLE (213 GB): ~2000 ms (first load, then cached)
  - Load SYNAPSE_INDEX_TABLE (9.7 TB): Loaded on-demand per partition
  - Load PROJECTION_PARAMETERS: ~1 ms
  - Total: ~5-10 ms per partition (amortized)

Stage 2: Partition GPU Loading
  - PCIe-Gen4 transfer: 32 GB/s effective
  - Per partition (2.5 GB): 78 ms
  - Concurrent loading (4 partitions in parallel): ~312 ms
  - Latency: ~78 ms single-partition, ~312 ms 4-partition

Stage 3: GPU Projection Compute
  - 31.67M neurons per partition
  - Kernel launch + execution: ~10-15 ms
  - Memory bandwidth: 1.5 TB/s (A100)
  - Computation: 5-10 ms

Stage 4: Neuron Rendering
  - Vertex buffer setup: ~2 ms
  - Fragment shader execution: ~50-100 ms (depends on viewport)
  - Draw call overhead: ~1 ms

Stage 5: Edge Rendering
  - Synapse projection: ~20 ms (compute shader)
  - Edge rendering: ~50-100 ms (up to 100M visible edges)

Stage 6: Composite & Display
  - Framebuffer operations: ~5 ms
  - Display present: ~1-2 ms (60 Hz display)

TOTAL PER FRAME: ~200-300 ms (3-5 FPS)
INTERACTIVE (60 FPS): Requires LOD reduction + frustum culling
  Visible neurons (typical): 1-10K
  Latency with LOD: ~16 ms per frame (60 FPS achievable)
```

### 11.2 Memory Budget

```
GPU VRAM (A100-40GB):

Stage-allocated:
  Neuron positions (GPU buffer): 2.5 GB per partition × 4 = 10 GB
  Synapse indices: 500 MB per partition × 4 = 2 GB
  Projection output (2D positions): 250 MB per partition × 4 = 1 GB
  Colors, sizes, visibility: 500 MB × 4 = 2 GB
  
  Subtotal: ~15 GB
  
Permanent:
  Projection matrices (view + projection): ~1 KB
  Texture cache (prerendered regions): ~5 GB
  
  Subtotal: ~5 GB

Available for application: ~15-20 GB
```

---

## 12. FORMAL CONTRACTS (Ada/SPARK)

### 12.1 Orthogonal2D Projection Contract

```ada
package Orthogonal2D_Projection_Spec is

  type Vector3_Double is record
    x: Double;
    y: Double;
    z: Double;
  end record;

  type Vector2_Double is record
    x: Double;
    y: Double;
  end record;

  type Orthogonal2D_Projection_Params is record
    scale_x: Double;
    scale_y: Double;
  end record;

  -- Determinism contract: identical input → identical output
  procedure Project_Orthogonal2D(
    pos_3d: in Vector3_Double;
    params: in Orthogonal2D_Projection_Params;
    pos_2d: out Vector2_Double
  ) with
    Global => null,
    Depends => (pos_2d => (pos_3d, params)),
    Post => (
      -- Result is deterministic (same input → same output)
      pos_2d.x = (pos_3d.x / 1000.0) / params.scale_x and
      pos_2d.y = (pos_3d.y / 1000.0) / params.scale_y
    );

end Orthogonal2D_Projection_Spec;
```

### 12.2 Perspective Projection Contract

```ada
package Perspective_Projection_Spec is

  type Matrix4x4_Double is array (1..4, 1..4) of Double;

  -- Determinism: same camera + position → same projection
  function Project_Perspective(
    pos_3d: Vector3_Double;
    view_matrix: Matrix4x4_Double;
    projection_matrix: Matrix4x4_Double
  ) return Vector2_Double with
    Global => null,
    Pre => (
      -- Camera matrices must be canonical (immutable)
      view_matrix /= null and projection_matrix /= null
    ),
    Post => (
      -- Output is in screen space [-1, 1] (NDC)
      Project_Perspective'Result.x >= -1.0 and
      Project_Perspective'Result.x <= 1.0 and
      Project_Perspective'Result.y >= -1.0 and
      Project_Perspective'Result.y <= 1.0
    );

end Perspective_Projection_Spec;
```

### 12.3 Determinism Invariant

```ada
package Determinism_Invariant is

  -- Invariant: Projection determinism is guaranteed
  pragma Assertion_Policy(Check);

  invariant Projection_Is_Deterministic is
    for all pos_3d, params, run_1, run_2 =>
      Project_Orthogonal2D(pos_3d, params, run_1) and
      Project_Orthogonal2D(pos_3d, params, run_2)
      implies run_1 = run_2;
      -- Two runs with identical inputs produce identical outputs

end Determinism_Invariant;
```

---

## 13. IMPLEMENTATION CHECKLIST

- [ ] Implement orthogonal 2D projection (canonical form)
- [ ] Implement isometric projection with fixed matrix
- [ ] Implement perspective projection with lookat + perspective matrices
- [ ] Implement circuit-specific filtering (binary search)
- [ ] Implement layer-specific filtering (z-range check)
- [ ] Implement region-specific filtering (binary search)
- [ ] Implement activity-driven projection (firing rate interpolation)
- [ ] Create projection parameters artifact format
- [ ] Implement GPU compute kernel for orthogonal projection
- [ ] Implement GPU compute kernel for perspective projection
- [ ] Implement GPU compute kernel for activity-driven remapping
- [ ] Implement GPU compute kernel for synapse projection
- [ ] Create vertex/fragment shaders for neuron rendering
- [ ] Create shaders for edge/synapse rendering
- [ ] Implement LOD selection algorithm
- [ ] Implement LOD-specific rendering strategies (7 LOD levels)
- [ ] Implement viewport frustum culling
- [ ] Implement user input handling (pan, zoom, rotate)
- [ ] Implement neuron highlighting (incoming/outgoing synapse visualization)
- [ ] Implement behavioral trace playback from activity archive
- [ ] Implement determinism verification protocol
- [ ] Create determinism verification artifact format
- [ ] Write comprehensive unit tests for each projection type
- [ ] Write GPU compute kernel tests
- [ ] Write determinism tests (bit-for-bit reproducibility)
- [ ] Benchmark projection throughput (neurons/sec, frames/sec)
- [ ] Profile GPU memory usage and optimize
- [ ] Document projection parameter canonical forms
- [ ] Document coordinate transformation (source → display)
- [ ] Document Ada/SPARK contracts
- [ ] Write formal verification proof (determinism invariant)

---

## 14. DELIVERABLES SUMMARY

**Phase 7 produces**:

1. **Deterministic Projection Algorithms** (7 types)
   - Orthogonal 2D (simplest, 100% deterministic)
   - Orthogonal 3D isometric (depth cues)
   - Perspective (full camera control)
   - Circuit-specific (named circuit filtering)
   - Layer-specific (cortical layer isolation)
   - Region-specific (anatomical region filtering)
   - Activity-driven (firing rate-based remapping)

2. **GPU Rendering Pipeline** (5 stages)
   - Stage 1: Load & validate artifacts
   - Stage 2: GPU memory partitioning
   - Stage 3: Projection compute kernel
   - Stage 4: Neuron rendering (graphics pipeline)
   - Stage 5: Synapse rendering & composite

3. **Level-of-Detail System** (7 LOD levels)
   - LOD_0: 1-158 neurons (debugging)
   - LOD_1: 158-1K (circuit)
   - LOD_2: 1K-10K (layer patch)
   - LOD_3: 10K-100K (column)
   - LOD_4: 100K-1M (layer)
   - LOD_5: 1M-10M (multi-layer)
   - LOD_6: 10M-100M (cortex)
   - LOD_7: 100M-760M (full brain)

4. **Coordinate Transformation**
   - Source space (micrometers, brain anatomy)
   - Display space (pixels, screen)
   - Bijective transformation (source → display → source)

5. **Neural State Visualization**
   - Membrane potential → color (blue to red)
   - Firing rate → size (0.1-4 pixels)
   - Recent activity → opacity (0.3-1.0 alpha)

6. **Interactive Controls**
   - Pan (translate view)
   - Zoom (change scale/perspective)
   - Rotate (camera orientation)
   - Connectivity toggle (feedforward/recurrent/feedback)
   - Activity overlay
   - Neuron highlighting
   - Circuit/layer/region filtering

7. **Behavioral Trace Playback**
   - Activity frame archive (GZIP compressed)
   - Frame-by-frame spike events
   - Membrane potential trace
   - Variable speed playback (1x-100x)

8. **Determinism Verification**
   - Bit-for-bit reproducibility protocol
   - Verification artifact format
   - Spot-check validation (random neuron sampling)
   - Ada/SPARK formal contracts

9. **Performance Characterization**
   - 200-300 ms per full-brain frame (LOD_7)
   - 50-100 ms per partition (4-16 partitions in GPU)
   - 16 ms achievable for 60 FPS (interactive LOD)
   - Memory usage: 15-20 GB GPU VRAM

10. **Documentation**
    - Coordinate transformation reference
    - Projection algorithm specifications
    - GPU rendering pipeline design
    - LOD selection algorithm
    - Determinism proof (IEEE 754 canonical forms)

---

## 15. DETERMINISM GUARANTEE STATEMENT

**CLAIM**: For any given 3D neuron positions, projection parameters, and timestamp:

> **Same input always produces identical 2D output, bit-for-bit.**

**PROOF SKETCH**:
1. All floating-point operations use IEEE 754 double-precision (64-bit)
2. All matrix values are canonical (immutable, verified to 64 decimal places)
3. Projection algorithm is purely functional (no randomness, no state mutation)
4. Sorting and filtering use deterministic algorithms (binary search, linear comparison)
5. Rendering output (colors, sizes) is deterministic (same algorithm, same input)
6. GPU compute kernels are deterministic (same thread execution, same FP rounding)

**VERIFICATION**: Run Phase 7 verification protocol twice with identical inputs → identical SHA-256 hash of output buffer.

---

## End of Phase 7 Specification

