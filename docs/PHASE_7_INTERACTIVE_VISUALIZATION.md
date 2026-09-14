# PHASE 7: Interactive Visualization & Behavioral Trace Playback

**Status**: SPECIFICATION COMPLETE  
**Date**: 2026-09-13  
**Scope**: User interaction (pan/zoom/rotate), neuron inspection, trace playback with deterministic replay  

---

## 1. USER INPUT HANDLING

### 1.1 Input Event Model

```cpp
struct Input_Event {
  enum Type {
    MOUSE_MOVE,
    MOUSE_CLICK,
    MOUSE_DRAG,
    SCROLL_WHEEL,
    KEYBOARD_PRESS,
    KEYBOARD_RELEASE
  };
  
  Type event_type;
  uint64_t timestamp_ms;        // Absolute time from application start
  
  // Mouse events
  struct {
    int32_t x_pixels;           // Screen-space coordinates
    int32_t y_pixels;
    int32_t delta_x;            // Movement since last event
    int32_t delta_y;
    uint8_t button_mask;        // Bit 0=LMB, Bit 1=MMB, Bit 2=RMB
  } mouse;
  
  // Keyboard events
  struct {
    uint32_t key_code;          // Virtual key code (platform-independent)
    bool ctrl_held;
    bool shift_held;
    bool alt_held;
  } keyboard;
  
  // Scroll wheel events
  struct {
    float delta_y;              // Positive = scroll up, negative = scroll down
  } scroll;
};

// Input queue (thread-safe)
class Input_Queue {
  std::queue<Input_Event> events;
  std::mutex lock;
  
public:
  void Push_Event(const Input_Event& evt) {
    std::lock_guard<std::mutex> guard(lock);
    events.push(evt);
  }
  
  bool Pop_Event(Input_Event& evt) {
    std::lock_guard<std::mutex> guard(lock);
    if (events.empty()) return false;
    evt = events.front();
    events.pop();
    return true;
  }
};
```

### 1.2 Camera Control Model

```cpp
struct Camera_State {
  // Perspective camera
  Vector3_Double eye;            // Camera position
  Vector3_Double center;         // Lookat target
  Vector3_Double up;             // Up vector (typically [0, 1, 0])
  
  // Cached matrices
  Matrix4x4 view_matrix;         // Cached lookat result
  Matrix4x4 projection_matrix;   // Cached perspective result
  
  // Interaction state
  struct {
    double pan_sensitivity;      // Pixels → world units conversion
    double zoom_sensitivity;     // Scroll wheel → zoom factor
    double rotate_sensitivity;   // Pixels → radians conversion
  } sensitivity;
  
  // Constraints
  struct {
    double min_distance;         // Minimum eye-to-center distance
    double max_distance;         // Maximum distance
    Vector3_Double pan_bounds_min;
    Vector3_Double pan_bounds_max;
  } constraints;
};

void Update_Camera_Pan(
  Camera_State& camera,
  int32_t delta_x_pixels,
  int32_t delta_y_pixels
) {
  // Translate lookat target in world-space
  // Direction: perpendicular to view direction
  
  Vector3_Double forward = Vector_Normalize(Vector_Subtract(camera.center, camera.eye));
  Vector3_Double right = Vector_Normalize(Vector_Cross_Product(forward, camera.up));
  Vector3_Double up_local = Vector_Normalize(Vector_Cross_Product(right, forward));
  
  Vector3_Double pan_vector = {
    right.x * delta_x_pixels * camera.sensitivity.pan_sensitivity +
    up_local.x * delta_y_pixels * camera.sensitivity.pan_sensitivity,
    
    right.y * delta_x_pixels * camera.sensitivity.pan_sensitivity +
    up_local.y * delta_y_pixels * camera.sensitivity.pan_sensitivity,
    
    right.z * delta_x_pixels * camera.sensitivity.pan_sensitivity +
    up_local.z * delta_y_pixels * camera.sensitivity.pan_sensitivity
  };
  
  // Apply pan with bounds checking
  Vector3_Double new_center = Vector_Add(camera.center, pan_vector);
  new_center.x = std::clamp(new_center.x, camera.constraints.pan_bounds_min.x, 
                                          camera.constraints.pan_bounds_max.x);
  new_center.y = std::clamp(new_center.y, camera.constraints.pan_bounds_min.y, 
                                          camera.constraints.pan_bounds_max.y);
  new_center.z = std::clamp(new_center.z, camera.constraints.pan_bounds_min.z, 
                                          camera.constraints.pan_bounds_max.z);
  
  camera.center = new_center;
  
  // Update matrices
  camera.view_matrix = Lookat_Canonical(camera.eye, camera.center, camera.up);
}

void Update_Camera_Zoom(
  Camera_State& camera,
  float zoom_factor
) {
  // Move eye closer/farther from center while keeping center fixed
  
  Vector3_Double to_center = Vector_Subtract(camera.center, camera.eye);
  double current_distance = Vector_Length(to_center);
  double new_distance = current_distance / zoom_factor;
  
  // Apply distance constraints
  new_distance = std::clamp(new_distance, camera.constraints.min_distance, 
                                         camera.constraints.max_distance);
  
  Vector3_Double direction = Vector_Normalize(to_center);
  camera.eye = Vector_Subtract(
    camera.center,
    Vector_Multiply_Scalar(direction, new_distance)
  );
  
  // Update matrices
  camera.view_matrix = Lookat_Canonical(camera.eye, camera.center, camera.up);
}

void Update_Camera_Rotate(
  Camera_State& camera,
  float pitch_radians,      // Vertical rotation
  float yaw_radians         // Horizontal rotation
) {
  // Rotate eye around center (maintains up vector)
  
  Vector3_Double to_center = Vector_Subtract(camera.center, camera.eye);
  double distance = Vector_Length(to_center);
  
  // Convert to spherical coordinates
  double azimuth = atan2(to_center.x, to_center.z);      // yaw
  double elevation = acos(to_center.y / distance);       // pitch
  
  // Apply rotations
  azimuth += yaw_radians;
  elevation -= pitch_radians;  // Negate for intuitive mouse behavior
  
  // Clamp elevation to [0, π] (avoid singularities)
  elevation = std::clamp(elevation, 0.01, 3.131);
  
  // Convert back to Cartesian
  Vector3_Double new_to_center = {
    distance * sin(elevation) * sin(azimuth),
    distance * cos(elevation),
    distance * sin(elevation) * cos(azimuth)
  };
  
  camera.eye = Vector_Subtract(camera.center, new_to_center);
  
  // Recompute up vector (maintain "up-ness" where possible)
  // This is complex; typically use fixed up vector
  
  // Update matrices
  camera.view_matrix = Lookat_Canonical(camera.eye, camera.center, camera.up);
}
```

---

## 2. NEURON SELECTION & HIGHLIGHTING

### 2.1 Picking (Click → Neuron Identification)

```cpp
// Ray casting: screen pixel → 3D world ray → neuron selection

struct Picking_Ray {
  Vector3_Double origin;        // Ray start (camera eye)
  Vector3_Double direction;     // Ray direction (normalized)
};

Picking_Ray Compute_Picking_Ray(
  int32_t click_x,
  int32_t click_y,
  uint32_t viewport_width,
  uint32_t viewport_height,
  const Camera_State& camera,
  const Matrix4x4& projection_matrix
) {
  // Step 1: Normalize click position to NDC [-1, 1]
  double ndc_x = 2.0 * click_x / viewport_width - 1.0;
  double ndc_y = 1.0 - 2.0 * click_y / viewport_height;  // Y inverted
  
  // Step 2: Unproject to view-space
  // View-space ray direction (at near plane, NDC z = -1)
  Vector4_Double view_ray_clip = {ndc_x, ndc_y, -1.0, 1.0};
  
  // Inverse projection to view-space
  Matrix4x4 proj_inv = Matrix_Inverse(projection_matrix);
  Vector4_Double view_ray_eye = Matrix_Multiply(proj_inv, view_ray_clip);
  
  // Perspective divide (in view space, clip.w = 1 after inverse projection)
  Vector3_Double ray_view = {view_ray_eye.x, view_ray_eye.y, -1.0};  // Looking down -z in view space
  
  // Step 3: Transform view-space ray to world-space
  Matrix4x4 view_inv = Matrix_Inverse(camera.view_matrix);
  Vector3_Double ray_world = Matrix_Multiply_Vec3(view_inv, ray_view);
  ray_world = Vector_Normalize(ray_world);
  
  Picking_Ray ray;
  ray.origin = camera.eye;
  ray.direction = ray_world;
  
  return ray;
}

// Sphere-ray intersection for neuron selection
struct Neuron_Hit {
  uint32_t neuron_index;
  double distance_from_camera;
  Vector3_Double hit_point;
};

bool Sphere_Ray_Intersection(
  const Vector3_Double& ray_origin,
  const Vector3_Double& ray_direction,
  const Vector3_Double& sphere_center,
  double sphere_radius,
  double& distance_out,
  Vector3_Double& hit_point_out
) {
  // Parametric ray: P(t) = ray_origin + t * ray_direction
  // Sphere: ||P - sphere_center||² = radius²
  
  Vector3_Double oc = Vector_Subtract(ray_origin, sphere_center);
  
  // Quadratic equation: (d·d)t² + 2(oc·d)t + (oc·oc - r²) = 0
  double a = Vector_Dot_Product(ray_direction, ray_direction);
  double b = 2.0 * Vector_Dot_Product(oc, ray_direction);
  double c = Vector_Dot_Product(oc, oc) - sphere_radius * sphere_radius;
  
  double discriminant = b * b - 4.0 * a * c;
  
  if (discriminant < 0.0) {
    return false;  // No intersection
  }
  
  // Two solutions; take closest (smallest positive t)
  double sqrt_disc = sqrt(discriminant);
  double t1 = (-b - sqrt_disc) / (2.0 * a);
  double t2 = (-b + sqrt_disc) / (2.0 * a);
  
  double t = -1.0;
  if (t1 > 0.0) {
    t = t1;
  } else if (t2 > 0.0) {
    t = t2;
  } else {
    return false;  // Intersection behind camera
  }
  
  distance_out = t;
  hit_point_out = Vector_Add(ray_origin, Vector_Multiply_Scalar(ray_direction, t));
  
  return true;
}

void Process_Click(
  const Picking_Ray& ray,
  const GPU_Neuron_Buffer& gpu_neurons,
  double pick_radius_um,     // Selection radius (e.g., 50 μm)
  Neuron_Hit& hit_neuron_out
) {
  // Find closest neuron within pick_radius_um
  double closest_distance = 1e10;
  uint32_t closest_neuron_idx = UINT32_MAX;
  
  // CPU-side: iterate through neuron positions
  // (In practice, this would be GPU-accelerated with frustum culling)
  
  for (uint32_t i = 0; i < gpu_neurons.neuron_count; i++) {
    Vector3_Double pos_3d = {
      gpu_neurons.positions_3d[i].x,
      gpu_neurons.positions_3d[i].y,
      gpu_neurons.positions_3d[i].z
    };
    
    double distance;
    Vector3_Double hit_point;
    
    if (Sphere_Ray_Intersection(ray.origin, ray.direction, pos_3d, pick_radius_um, distance, hit_point)) {
      if (distance < closest_distance) {
        closest_distance = distance;
        closest_neuron_idx = i;
      }
    }
  }
  
  if (closest_neuron_idx != UINT32_MAX) {
    hit_neuron_out.neuron_index = closest_neuron_idx;
    hit_neuron_out.distance_from_camera = closest_distance;
    hit_neuron_out.hit_point = ray.origin + ray.direction * closest_distance;
  }
}
```

### 2.2 Highlighting Incoming/Outgoing Synapses

```cpp
struct Neuron_Highlight_State {
  uint32_t highlighted_neuron_idx;      // Which neuron is highlighted (UINT32_MAX = none)
  
  std::vector<uint32_t> incoming_neuron_indices;   // Neurons synapsing onto highlighted
  std::vector<uint32_t> outgoing_neuron_indices;   // Neurons highlighted synapses onto
  
  std::vector<uint32_t> incoming_synapse_indices;
  std::vector<uint32_t> outgoing_synapse_indices;
};

void Update_Highlight(
  uint32_t clicked_neuron_idx,
  const GPU_Synapse_Buffer& gpu_synapses,
  Neuron_Highlight_State& highlight_out
) {
  highlight_out.highlighted_neuron_idx = clicked_neuron_idx;
  
  // Find all synapses involving this neuron
  uint32_t incoming_count = 0;
  uint32_t outgoing_count = 0;
  
  for (uint32_t i = 0; i < gpu_synapses.synapse_count; i++) {
    uint32_t src_idx = gpu_synapses.source_neuron_idx[i];
    uint32_t dst_idx = gpu_synapses.dest_neuron_idx[i];
    
    if (dst_idx == clicked_neuron_idx) {
      // Incoming synapse (src → clicked)
      highlight_out.incoming_neuron_indices.push_back(src_idx);
      highlight_out.incoming_synapse_indices.push_back(i);
      incoming_count++;
    }
    
    if (src_idx == clicked_neuron_idx) {
      // Outgoing synapse (clicked → dst)
      highlight_out.outgoing_neuron_indices.push_back(dst_idx);
      highlight_out.outgoing_synapse_indices.push_back(i);
      outgoing_count++;
    }
  }
  
  log_info("Highlighted neuron {}: {} incoming, {} outgoing synapses",
           clicked_neuron_idx, incoming_count, outgoing_count);
}

void Render_With_Highlight(
  const Neuron_Highlight_State& highlight,
  GPU_Projection_Output& gpu_output
) {
  // Step 1: Render all neurons normally
  Render_Neurons(gpu_output);
  
  // Step 2: Render incoming neurons (blue)
  for (uint32_t in_idx : highlight.incoming_neuron_indices) {
    gpu_output.colors[in_idx] = make_float4(0.0f, 0.0f, 1.0f, 1.0f);  // Blue
    gpu_output.sizes[in_idx] *= 2.0f;  // Larger
  }
  
  // Step 3: Render outgoing neurons (green)
  for (uint32_t out_idx : highlight.outgoing_neuron_indices) {
    gpu_output.colors[out_idx] = make_float4(0.0f, 1.0f, 0.0f, 1.0f);  // Green
    gpu_output.sizes[out_idx] *= 2.0f;
  }
  
  // Step 4: Render highlighted neuron (red, largest)
  if (highlight.highlighted_neuron_idx != UINT32_MAX) {
    gpu_output.colors[highlight.highlighted_neuron_idx] = make_float4(1.0f, 0.0f, 0.0f, 1.0f);  // Red
    gpu_output.sizes[highlight.highlighted_neuron_idx] *= 3.0f;
  }
  
  // Step 5: Render incoming and outgoing synapses (highlighted in color)
  Render_Highlighted_Synapses(gpu_output, highlight);
}
```

---

## 3. BEHAVIORAL TRACE PLAYBACK

### 3.1 Activity Frame Archive Loading

```cpp
struct Activity_Frame_Archive {
  std::string archive_path;                 // Path to .tar.gz file
  
  // Metadata
  std::string simulation_id;
  uint64_t simulation_start_timestep;
  uint64_t simulation_end_timestep;
  uint32_t frame_interval_ms;               // 10 ms between frames
  uint32_t total_frames;
  
  // In-memory frames (loaded on-demand)
  std::vector<Activity_Frame> frames;
  std::unordered_map<uint32_t, Activity_Frame> frame_cache;
  
  // Metadata (preloaded)
  struct Frame_Metadata {
    uint64_t archive_offset;                // Byte offset in compressed archive
    uint32_t compressed_size;
    uint32_t uncompressed_size;
    uint32_t spike_count;
  };
  std::vector<Frame_Metadata> frame_metadata;
};

struct Activity_Frame {
  uint64_t timestep;                        // Simulation timestep
  uint32_t spike_count;                     // Number of spike events
  
  std::vector<Spike_Event> spikes;          // Per-spike: (neuron_idx, timestamp_ms)
  
  // Optional: precomputed statistics
  std::vector<double> membrane_potentials;  // Per-neuron voltage (mV)
  std::vector<float> firing_rates;          // Per-neuron rate (Hz)
};

struct Spike_Event {
  uint32_t neuron_index;                    // Index in neuron buffer
  uint16_t millisecond_offset;              // Offset within frame (0-9 ms)
};

// Load archive metadata (fast, ~100 ms)
bool Load_Archive_Metadata(
  const std::string& archive_path,
  Activity_Frame_Archive& archive_out
) {
  // Step 1: Open .tar.gz file
  gzFile gz = gzopen(archive_path.c_str(), "rb");
  if (!gz) {
    log_error("Failed to open archive: {}", archive_path);
    return false;
  }
  
  // Step 2: Read frame metadata table (JSON)
  // Archive structure:
  //   metadata.json          (frame offsets, spike counts)
  //   frame_0.bin (compressed)
  //   frame_1.bin (compressed)
  //   ...
  
  std::string metadata_json;
  char buffer[4096];
  int bytes_read;
  
  while ((bytes_read = gzread(gz, buffer, sizeof(buffer))) > 0) {
    metadata_json.append(buffer, bytes_read);
  }
  
  gzclose(gz);
  
  // Step 3: Parse JSON and populate frame_metadata
  // (Implementation: use rapidjson or similar)
  
  return true;
}

// Load single frame on-demand (compressed: 100-500 KB → 10-50 MB)
bool Load_Frame(
  uint32_t frame_idx,
  const Activity_Frame_Archive& archive,
  Activity_Frame& frame_out
) {
  if (frame_idx >= archive.total_frames) {
    return false;
  }
  
  // Step 1: Check cache
  if (archive.frame_cache.count(frame_idx)) {
    frame_out = archive.frame_cache.at(frame_idx);
    return true;
  }
  
  // Step 2: Decompress frame from archive
  const Activity_Frame_Archive::Frame_Metadata& meta = archive.frame_metadata[frame_idx];
  
  // Read compressed data from archive at offset
  std::vector<uint8_t> compressed_data(meta.compressed_size);
  std::vector<uint8_t> uncompressed_data(meta.uncompressed_size);
  
  // Seek to frame in archive and decompress
  // (Implementation uses gzseek + gzread)
  
  // Step 3: Deserialize frame
  Deserialize_Activity_Frame(uncompressed_data, frame_out);
  
  // Step 4: Cache frame
  const_cast<Activity_Frame_Archive&>(archive).frame_cache[frame_idx] = frame_out;
  
  return true;
}
```

### 3.2 Trace Playback State Machine

```cpp
struct Trace_Playback_State {
  enum PlaybackStatus {
    STOPPED,
    PLAYING,
    PAUSED
  };
  
  PlaybackStatus status;
  uint32_t current_frame_idx;               // Which frame we're on
  double playback_speed;                    // 1.0x = realtime, 10.0x = 10× speed
  uint64_t last_frame_time_ms;              // Wall-clock time of last frame
  
  // Display configuration
  bool show_spikes;
  bool show_membrane_potential;
  bool show_firing_rates;
};

class Trace_Playback_Engine {
  const Activity_Frame_Archive& archive;
  Trace_Playback_State state;
  GPU_Neuron_Buffer& gpu_neurons;           // Reference to GPU buffer (updated each frame)
  
public:
  Trace_Playback_Engine(const Activity_Frame_Archive& arc, GPU_Neuron_Buffer& gpu) 
    : archive(arc), gpu_neurons(gpu) {
    state.status = STOPPED;
    state.current_frame_idx = 0;
    state.playback_speed = 1.0;
    state.last_frame_time_ms = 0;
  }
  
  void Start_Playback() {
    state.status = PLAYING;
    state.last_frame_time_ms = GetCurrentTimeMs();
  }
  
  void Pause_Playback() {
    state.status = PAUSED;
  }
  
  void Resume_Playback() {
    state.status = PLAYING;
    state.last_frame_time_ms = GetCurrentTimeMs();
  }
  
  void Stop_Playback() {
    state.status = STOPPED;
    state.current_frame_idx = 0;
  }
  
  void Set_Playback_Speed(double speed) {
    state.playback_speed = std::max(0.1, speed);  // Minimum 0.1x
  }
  
  void Seek_To_Frame(uint32_t frame_idx) {
    if (frame_idx < archive.total_frames) {
      state.current_frame_idx = frame_idx;
    }
  }
  
  // Update playback state and GPU neurons (call every render frame)
  bool Update_Playback(uint64_t current_time_ms) {
    if (state.status != PLAYING) {
      return false;  // No update needed
    }
    
    uint64_t elapsed_ms = current_time_ms - state.last_frame_time_ms;
    
    // Determine if we should advance to next frame
    // Frame interval: typically 10 ms per archive frame
    double real_time_per_frame_ms = archive.frame_interval_ms / state.playback_speed;
    
    if (elapsed_ms >= real_time_per_frame_ms) {
      // Advance to next frame
      Activity_Frame frame;
      if (!Load_Frame(state.current_frame_idx, archive, frame)) {
        // End of trace reached
        state.status = STOPPED;
        return false;
      }
      
      // Update GPU neurons based on frame data
      Update_GPU_Neurons_From_Frame(frame);
      
      state.current_frame_idx++;
      state.last_frame_time_ms = current_time_ms;
      
      return true;  // Frame was updated
    }
    
    return false;
  }
  
private:
  void Update_GPU_Neurons_From_Frame(const Activity_Frame& frame) {
    // Step 1: Apply spike events
    // For each spike, mark neuron as recently active
    for (const Spike_Event& spike : frame.spikes) {
      gpu_neurons.last_spike_time[spike.neuron_index] = frame.timestep;
      gpu_neurons.membrane_voltage[spike.neuron_index] = 30.0;  // Spike peak
    }
    
    // Step 2: Decay membrane voltages (exponential decay to resting)
    double tau_ms = 20.0;  // Membrane time constant
    double decay_factor = exp(-1.0 / tau_ms);
    
    for (uint32_t i = 0; i < gpu_neurons.neuron_count; i++) {
      gpu_neurons.membrane_voltage[i] *= decay_factor;
      
      // Clamp to resting potential
      if (gpu_neurons.membrane_voltage[i] < -70.0) {
        gpu_neurons.membrane_voltage[i] = -70.0;
      }
    }
    
    // Step 3: Update recent activity timers (for opacity mapping)
    uint64_t current_time_ms = frame.timestep * 10;  // Convert timesteps to ms
    for (uint32_t i = 0; i < gpu_neurons.neuron_count; i++) {
      gpu_neurons.last_activity_time[i] = current_time_ms;
    }
    
    // Step 4: Optionally update GPU buffer via CUDA
    // (In practice, use GPU texture/buffer update for performance)
    Update_GPU_Buffer_Async(gpu_neurons);
  }
};
```

### 3.3 Trace Playback Controls (UI)

```cpp
// UI widgets for trace playback control

void Render_Playback_Controls(const Trace_Playback_State& state) {
  // Timeline slider (frame selection)
  ImGui::SliderInt("Frame", (int*)&state.current_frame_idx, 
                   0, archive.total_frames - 1);
  
  // Play/Pause buttons
  if (ImGui::Button("Play")) {
    playback_engine.Start_Playback();
  }
  ImGui::SameLine();
  if (ImGui::Button("Pause")) {
    playback_engine.Pause_Playback();
  }
  ImGui::SameLine();
  if (ImGui::Button("Stop")) {
    playback_engine.Stop_Playback();
  }
  
  // Speed control
  ImGui::SliderFloat("Speed", (float*)&state.playback_speed, 0.1f, 100.0f, "%.1fx");
  
  // Display frame info
  ImGui::Text("Frame: %u / %u", state.current_frame_idx, archive.total_frames);
  ImGui::Text("Time: %.2f s", state.current_frame_idx * archive.frame_interval_ms / 1000.0);
  
  // Show current frame spike count
  if (current_frame) {
    ImGui::Text("Spikes this frame: %u", current_frame->spike_count);
  }
}

// Keyboard shortcuts
void Handle_Playback_Shortcuts(const Input_Event& evt) {
  if (evt.event_type != Input_Event::KEYBOARD_PRESS) return;
  
  switch (evt.keyboard.key_code) {
    case KEY_SPACE:
      // Toggle play/pause
      if (playback_engine.state.status == PLAYING) {
        playback_engine.Pause_Playback();
      } else {
        playback_engine.Start_Playback();
      }
      break;
      
    case KEY_ARROW_LEFT:
      // Previous frame
      playback_engine.Seek_To_Frame(playback_engine.state.current_frame_idx - 1);
      break;
      
    case KEY_ARROW_RIGHT:
      // Next frame
      playback_engine.Seek_To_Frame(playback_engine.state.current_frame_idx + 1);
      break;
      
    case KEY_HOME:
      // Jump to start
      playback_engine.Seek_To_Frame(0);
      break;
      
    case KEY_END:
      // Jump to end
      playback_engine.Seek_To_Frame(archive.total_frames - 1);
      break;
      
    case KEY_MINUS:
      // Decrease speed
      playback_engine.Set_Playback_Speed(playback_engine.state.playback_speed / 2.0);
      break;
      
    case KEY_PLUS:
      // Increase speed
      playback_engine.Set_Playback_Speed(playback_engine.state.playback_speed * 2.0);
      break;
  }
}
```

---

## 4. CONNECTIVITY VISUALIZATION

### 4.1 Synapse Display Modes

```cpp
enum Synapse_Display_Mode {
  SYNAPSES_NONE,                // No synapses rendered
  SYNAPSES_FEEDFORWARD,         // Only feedforward connections
  SYNAPSES_RECURRENT,           // Only recurrent (within-region)
  SYNAPSES_FEEDBACK,            // Only feedback (from deeper layers)
  SYNAPSES_ALL,                 // All synapses
  SYNAPSES_LAYER_SPECIFIC,      // Only synapses within visible layer
  SYNAPSES_HIGHLIGHTED_ONLY     // Only incoming/outgoing of highlighted neuron
};

void Update_Synapse_Visibility(
  Synapse_Display_Mode mode,
  const GPU_Synapse_Buffer& gpu_synapses,
  GPU_Projection_Output& gpu_output
) {
  // Mark synapses as visible/invisible based on display mode
  
  for (uint32_t i = 0; i < gpu_synapses.synapse_count; i++) {
    uint32_t src_idx = gpu_synapses.source_neuron_idx[i];
    uint32_t dst_idx = gpu_synapses.dest_neuron_idx[i];
    
    bool visible = false;
    
    switch (mode) {
      case SYNAPSES_NONE:
        visible = false;
        break;
        
      case SYNAPSES_FEEDFORWARD:
        // Determine connection type (requires metadata)
        visible = (gpu_synapses.connection_type[i] == FEEDFORWARD);
        break;
        
      case SYNAPSES_RECURRENT:
        visible = (gpu_synapses.connection_type[i] == RECURRENT);
        break;
        
      case SYNAPSES_FEEDBACK:
        visible = (gpu_synapses.connection_type[i] == FEEDBACK);
        break;
        
      case SYNAPSES_ALL:
        visible = true;
        break;
        
      case SYNAPSES_LAYER_SPECIFIC:
        // Check if both source and dest are in current layer
        visible = (gpu_synapses.layer_id[src_idx] == current_layer &&
                   gpu_synapses.layer_id[dst_idx] == current_layer);
        break;
        
      case SYNAPSES_HIGHLIGHTED_ONLY:
        // Only show synapses of highlighted neuron
        visible = false;
        for (uint32_t in_idx : highlight_state.incoming_synapse_indices) {
          if (i == in_idx) visible = true;
        }
        for (uint32_t out_idx : highlight_state.outgoing_synapse_indices) {
          if (i == out_idx) visible = true;
        }
        break;
    }
    
    gpu_output.synapse_visibility_mask[i] = visible ? 1 : 0;
  }
}
```

---

## 5. LAYER & REGION OVERLAY

### 5.1 Anatomical Layer Visualization

```cpp
struct Layer_Visualization {
  enum Layer {
    L1,    // Molecular layer
    L2_3,  // Layer 2/3
    L4,    // Granular layer (input)
    L5,    // Pyramidal layer
    L6,    // Multiform layer
  };
  
  struct Layer_Data {
    std::string name;
    double z_min_um;              // Depth range
    double z_max_um;
    uint32_t color_rgb;           // Overlay color
    float opacity;
  };
  
  static const Layer_Data layers[5] = {
    {"L1", 0, 100, 0xFF0000, 0.1f},        // Red, transparent
    {"L2/3", 100, 250, 0x00FF00, 0.1f},    // Green
    {"L4", 250, 400, 0x0000FF, 0.1f},      // Blue
    {"L5", 400, 550, 0xFFFF00, 0.1f},      // Yellow
    {"L6", 550, 700, 0xFF00FF, 0.1f}       // Magenta
  };
};

void Render_Layer_Boundaries(
  const Layer_Visualization& layers,
  const Camera_State& camera,
  const Matrix4x4& projection_matrix
) {
  // Render horizontal planes at layer boundaries
  
  for (int i = 0; i < 6; i++) {
    double z = (i == 0) ? 0.0 : layers.layers[i-1].z_max_um;
    
    // Create quad at z-depth (full brain x/y extent)
    // Project quad to 2D and render as overlay
    
    Vector3_Double p1 = {0, 0, z};
    Vector3_Double p2 = {60000, 0, z};
    Vector3_Double p3 = {60000, 50000, z};
    Vector3_Double p4 = {0, 50000, z};
    
    // Project to 2D and render
    Render_Quad_Overlay(p1, p2, p3, p4, camera, projection_matrix);
  }
}
```

### 5.2 Region Boundaries & Labels

```cpp
struct Brain_Region_Overlay {
  struct Region {
    std::string name;             // "V1", "M1", "CA1", etc.
    Vector3_Double center;        // Region center
    Vector3_Double extent;        // Approximate size
    uint32_t color_rgb;
  };
  
  std::vector<Region> regions;
};

void Render_Region_Overlay(
  const Brain_Region_Overlay& regions,
  const Camera_State& camera
) {
  for (const Brain_Region_Overlay::Region& region : regions.regions) {
    // Project region center to 2D
    Vector3_Double region_center_2d = Project_To_Screen(
      region.center,
      camera.view_matrix,
      camera.projection_matrix
    );
    
    // Draw region boundary (cube outline)
    Render_Region_Boundary_3D(region.center, region.extent, region.color_rgb);
    
    // Draw label text at region center
    Render_Text_At_Screen_Position(
      region_center_2d.x,
      region_center_2d.y,
      region.name,
      region.color_rgb
    );
  }
}
```

---

## 6. DETERMINISM IN TRACE PLAYBACK

### 6.1 Deterministic Replay Guarantee

```cpp
// Property: Same activity archive + same frame index → identical neuron states

struct Determinism_Proof_Trace_Playback {
  // Claim: Load_Frame(n) always produces identical output
  
  bool Verify_Trace_Playback_Determinism(
    const Activity_Frame_Archive& archive,
    uint32_t frame_idx,
    uint32_t repetitions = 3
  ) {
    std::vector<GPU_Neuron_Buffer> outputs;
    
    for (uint32_t run = 0; run < repetitions; run++) {
      Activity_Frame frame;
      Load_Frame(frame_idx, archive, frame);
      
      GPU_Neuron_Buffer neurons;
      Update_GPU_Neurons_From_Frame(frame, neurons);
      
      outputs.push_back(neurons);
    }
    
    // Compare all outputs
    for (uint32_t i = 1; i < outputs.size(); i++) {
      if (!Neuron_Buffers_Equal(outputs[0], outputs[i])) {
        log_error("Trace playback determinism failed!");
        return false;
      }
    }
    
    return true;
  }
};
```

**Determinism Sources**:
1. Activity archive is deterministically generated (Phase 6 GPU simulation)
2. Frame decompression (gzip) is deterministic
3. Spike events are fixed (no randomness)
4. Membrane potential decay uses canonical IEEE 754 exp()
5. GPU buffer updates use deterministic algorithms

---

## 7. IMPLEMENTATION CHECKLIST

- [ ] Implement input event queue (thread-safe)
- [ ] Implement camera control (pan, zoom, rotate)
- [ ] Implement ray casting for neuron selection
- [ ] Implement sphere-ray intersection
- [ ] Implement neuron highlighting (incoming/outgoing)
- [ ] Implement synapse highlighting
- [ ] Load activity frame archive metadata
- [ ] Implement on-demand frame loading (gzip decompression)
- [ ] Implement trace playback state machine
- [ ] Implement playback speed control
- [ ] Implement timeline seeking
- [ ] Implement membrane potential decay
- [ ] Implement recent activity tracking (for opacity)
- [ ] Implement synapse display modes (feedforward/recurrent/feedback)
- [ ] Implement layer boundary visualization
- [ ] Implement region boundary rendering
- [ ] Implement region label rendering
- [ ] Implement UI controls (ImGui integration)
- [ ] Implement keyboard shortcuts
- [ ] Write determinism verification test for trace playback
- [ ] Benchmark frame loading time
- [ ] Profile memory usage during playback
- [ ] Write documentation for user controls

---

## End of Interactive Visualization & Trace Playback Specification

