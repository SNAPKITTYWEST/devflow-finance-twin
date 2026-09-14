# PHASE 5: Detailed Data Structures and Reference Implementation

**Focus**: Concrete data structures, memory layouts, and performance-critical algorithms

---

## 1. CORE NEURON STATE STRUCTURE

### 1.1 Memory Layout (Per-Neuron Per-Timestep)

```
NeuronStateRecord (280 bytes total):
  
  [Immutable Metadata: 80 bytes]
  ├─ cat_n_id: [16 bytes] Unique neuron identifier (UUID128)
  ├─ region_id: [4 bytes] Region enum (V1, CA1, M1, etc.)
  ├─ neuron_type: [2 bytes] Type enum (pyramidal, GABAergic, etc.)
  ├─ firing_model_id: [2 bytes] Model enum (HH, IAF, IAF_MOD, SIMPLE)
  ├─ parameter_hash: [32 bytes] SHA256(all parameters for this neuron)
  ├─ soma_x: [4 bytes] float32 coordinate (μm)
  ├─ soma_y: [4 bytes] float32 coordinate (μm)
  ├─ soma_z: [4 bytes] float32 coordinate (μm)
  ├─ [8 bytes padding for alignment]
  
  [Dynamic State: 200 bytes]
  ├─ timestep: [8 bytes] uint64 (current step, monotonic)
  ├─ membrane_potential_mV: [8 bytes] float64 (IEEE 754)
  ├─ input_current_nA: [8 bytes] float64
  ├─ refractory_timer_ms: [8 bytes] float64
  ├─ refractory_state: [1 byte] enum (ACTIVE=0, ABS_REFR=1, REL_REFR=2)
  ├─ last_spike_time: [8 bytes] uint64 (timestep)
  ├─ spike_count: [8 bytes] uint64 (total spikes emitted)
  ├─ dopamine_concentration: [8 bytes] float64
  ├─ arousal_level: [8 bytes] float64
  
  [Firing Model State: 104 bytes]
  ├─ For Hodgkin-Huxley:
  │  ├─ V_prev: [8 bytes] float64 (for spike detection)
  │  ├─ m: [8 bytes] float64 (Na activation gate)
  │  ├─ h: [8 bytes] float64 (Na inactivation gate)
  │  ├─ n: [8 bytes] float64 (K activation gate)
  │  ├─ g_Na: [8 bytes] float64 (Na conductance)
  │  ├─ g_K: [8 bytes] float64 (K conductance)
  │  ├─ g_L: [8 bytes] float64 (leak conductance)
  │  ├─ [40 bytes additional state variables]
  │
  ├─ For Leaky IAF:
  │  ├─ V_prev: [8 bytes] float64
  │  ├─ tau_eff: [8 bytes] float64 (effective time constant)
  │  ├─ v_thresh_eff: [8 bytes] float64 (effective threshold)
  │  ├─ [80 bytes padding/future use]
```

**Cache-Line Alignment**: 280 bytes ≈ 4.4 cache lines (64-byte lines). Structure fits in modern L1/L2 cache.

### 1.2 Storage Indexing

```
// Three-level hierarchy for O(1) lookup
neurons_store[region_id][cat_n_id][timestep] = NeuronStateRecord

// Level 1: Region partitioning (8 regions, ~100 neurons each on average)
neurons_store = HashMap<RegionID, RegionNeuronStore>

// Level 2: Per-region neuron index (O(1) via CAT-N-ID hash)
class RegionNeuronStore:
  region_id: RegionID
  neurons: HashMap<CatNID, NeuronTimelineBuffer>
  
  // Level 3: Per-neuron temporal buffer (rolling window)
  class NeuronTimelineBuffer:
    cat_n_id: CatNID
    timestep_window_size: 10  // Last 10 timesteps in memory
    circular_buffer: [10]NeuronStateRecord
    write_head: uint32  // Points to oldest entry
    current_timestep: uint64

// Lookup complexity: O(1) average case
neuron_state = neurons_store[V1][CAT_N_00001][100]
  Step 1: HashMap.get(V1) → RegionNeuronStore [O(1)]
  Step 2: HashMap.get(CAT_N_00001) → NeuronTimelineBuffer [O(1)]
  Step 3: circular_buffer[(100 - window_start) % 10] → NeuronStateRecord [O(1)]
```

---

## 2. SYNAPSE STORAGE (SPARSE CONNECTIVITY)

### 2.1 Synapse Record Structure

```
SynapseRecord (100 bytes):
  
  [Immutable Connectivity: 40 bytes]
  ├─ cat_s_id: [8 bytes] Synapse ID (uint64, globally unique)
  ├─ source_cat_n: [16 bytes] Source neuron ID
  ├─ target_cat_n: [16 bytes] Target neuron ID
  
  [Properties: 28 bytes]
  ├─ weight: [8 bytes] float64 (nanoSiemens, synaptic strength)
  ├─ delay_ms: [4 bytes] float32 (≥ 1ms)
  ├─ neurotransmitter: [1 byte] enum (GLUT=0, GABA=1, DA=2, etc.)
  ├─ receptor_type: [1 byte] enum (AMPA=0, NMDA=1, GABA_A=2, etc.)
  ├─ connection_type: [1 byte] enum (FF=0, REC=1, FB=2)
  ├─ plasticity_rule: [1 byte] enum (NONE=0, STDP=1, BCM=2, etc.)
  ├─ last_update_timestep: [8 bytes] uint64
  ├─ [4 bytes padding]
  
  [Plasticity State: 32 bytes]
  ├─ cumulative_depression: [8 bytes] float64
  ├─ cumulative_potentiation: [8 bytes] float64
  ├─ eligibility_trace: [8 bytes] float64
  ├─ last_presynaptic_spike: [8 bytes] uint64
```

### 2.2 Synapse Index (Hash Maps)

```
class SynapseStore:
  
  // Index 1: By source neuron (for spike propagation)
  outgoing_synapses: HashMap<CatNID, Vec<Ptr<SynapseRecord>>>
    Example:
      outgoing_synapses[CAT_N_00050] = [
        &synapse_001 (→ CAT_N_00100),
        &synapse_002 (→ CAT_N_00150),
        ...
        &synapse_100 (→ CAT_N_00500)
      ]
    Lookup time: O(1) to get array, then O(k) to iterate k outgoing synapses
    Typical k: 50-200 synapses per neuron
  
  // Index 2: By target neuron (for input aggregation)
  incoming_synapses: HashMap<CatNID, Vec<Ptr<SynapseRecord>>>
    Example:
      incoming_synapses[CAT_N_00100] = [
        &synapse_001 (← CAT_N_00050),
        &synapse_003 (← CAT_N_00075),
        ...
      ]
  
  // Index 3: By synapse ID (for updates)
  all_synapses: HashMap<CatSID, Ptr<SynapseRecord>>
  
  // Index 4: By region (for locality-aware iteration)
  by_source_region: HashMap<RegionID, Vec<Ptr<SynapseRecord>>>
  by_target_region: HashMap<RegionID, Vec<Ptr<SynapseRecord>>>

// Memory estimates:
// 76 billion synapses × 100 bytes/synapse = 7.6 TB (raw)
// With sparse storage (only non-zero) × 8 index pointers ≈ 61 TB indices
// Compressed with dictionary coding: ~500 GB
```

---

## 3. EVENT QUEUE (PRIORITY HEAP)

### 3.1 Spike Event Structure

```
SpikeEvent (40 bytes):
  
  [Delivery: 8 bytes]
  ├─ delivery_timestep: [8 bytes] uint64 (when synapse fires)
  
  [Source/Target: 32 bytes]
  ├─ source_cat_n: [16 bytes] CatNID
  ├─ target_cat_n: [16 bytes] CatNID
  
  [Synapse Properties: 8 bytes]
  ├─ cat_s_id: [8 bytes] Synapse ID
  
  [Weight & Neurotransmitter: 16 bytes]
  ├─ weight_amplitude: [8 bytes] float64
  ├─ neurotransmitter: [1 byte] enum
  ├─ receptor_type: [1 byte] enum
  ├─ [6 bytes padding]
```

### 3.2 Priority Heap Implementation

```
class EventQueue:
  heap: BinaryHeap<SpikeEvent, Comparator>
  comparator: fn(a, b) -> bool:
    if a.delivery_timestep != b.delivery_timestep:
      return a.delivery_timestep < b.delivery_timestep  // Min-heap on time
    return a.source_cat_n < b.source_cat_n  // Deterministic tie-break
  
  function pop_before_time(t):
    // Extract all events with delivery_timestep < t
    ready_events = Vec::new()
    while !heap.is_empty() && heap.peek().delivery_timestep < t:
      ready_events.push(heap.pop())
    return ready_events
  
  function push(event):
    heap.insert(event)

// Complexity:
// Push: O(log N) where N = queue size ≈ 1-2 billion events at peak
// Pop: O(k log N) where k = num_events delivered per timestep
// Typical k: 10-100 million events per 1ms timestep
```

**Optimization**: Separate event queues per target region for parallel processing:

```
class PartitionedEventQueue:
  queues: HashMap<RegionID, EventQueue>
  
  function pop_before_time(t):
    all_events = Vec::new()
    for (region_id, queue) in queues.items():
      all_events.extend(queue.pop_before_time(t))
    return all_events  // Mergeable from multiple regions in parallel
```

---

## 4. NEURAL INTEGRATION KERNELS

### 4.1 Hodgkin-Huxley RK4 (GPU-Optimized)

```cuda
// CUDA kernel for HH integration on GPU
// 1 thread per neuron, 256 threads per block

__global__ void integrate_hh_neurons(
  float64* V_in,           // Input voltage, shape [num_neurons]
  float64* m_in, h_in, n_in,
  float64* I_input,        // Input current
  float64* I_Na, I_K, I_L, // Precomputed conductances
  float64 dt,              // Timestep (0.01 ms)
  float64* V_out,          // Output voltage
  float64* m_out, h_out, n_out
) {
  int neuron_id = blockIdx.x * blockDim.x + threadIdx.x;
  
  if (neuron_id >= num_neurons) return;
  
  float64 V = V_in[neuron_id];
  float64 m = m_in[neuron_id];
  float64 h = h_in[neuron_id];
  float64 n = n_in[neuron_id];
  float64 I = I_input[neuron_id];
  
  // RK4 substeps (4 steps per ms)
  for (int substep = 0; substep < 4; substep++) {
    // k1
    float64 dV1 = hh_dV_dt(V, m, h, n, I);
    float64 dm1 = hh_dm_dt(V, m);
    float64 dh1 = hh_dh_dt(V, h);
    float64 dn1 = hh_dn_dt(V, n);
    
    // k2 (midpoint)
    float64 V2 = V + 0.005 * dV1;  // dt_substep/2 = 0.005
    float64 m2 = m + 0.005 * dm1;
    float64 h2 = h + 0.005 * dh1;
    float64 n2 = n + 0.005 * dn1;
    float64 dV2 = hh_dV_dt(V2, m2, h2, n2, I);
    float64 dm2 = hh_dm_dt(V2, m2);
    float64 dh2 = hh_dh_dt(V2, h2);
    float64 dn2 = hh_dn_dt(V2, n2);
    
    // k3 (midpoint with k2)
    float64 V3 = V + 0.005 * dV2;
    float64 m3 = m + 0.005 * dm2;
    float64 h3 = h + 0.005 * dh2;
    float64 n3 = n + 0.005 * dn2;
    float64 dV3 = hh_dV_dt(V3, m3, h3, n3, I);
    float64 dm3 = hh_dm_dt(V3, m3);
    float64 dh3 = hh_dh_dt(V3, h3);
    float64 dn3 = hh_dn_dt(V3, n3);
    
    // k4 (endpoint)
    float64 V4 = V + 0.01 * dV3;
    float64 m4 = m + 0.01 * dm3;
    float64 h4 = h + 0.01 * dh3;
    float64 n4 = n + 0.01 * dn3;
    float64 dV4 = hh_dV_dt(V4, m4, h4, n4, I);
    float64 dm4 = hh_dm_dt(V4, m4);
    float64 dh4 = hh_dh_dt(V4, h4);
    float64 dn4 = hh_dn_dt(V4, n4);
    
    // Combined update
    V += (0.01 / 6.0) * (dV1 + 2*dV2 + 2*dV3 + dV4);
    m += (0.01 / 6.0) * (dm1 + 2*dm2 + 2*dm3 + dm4);
    h += (0.01 / 6.0) * (dh1 + 2*dh2 + 2*dh3 + dh4);
    n += (0.01 / 6.0) * (dn1 + 2*dn2 + 2*dn3 + dn4);
  }
  
  V_out[neuron_id] = V;
  m_out[neuron_id] = m;
  h_out[neuron_id] = h;
  n_out[neuron_id] = n;
}

// Gate dynamics
__device__ inline float64 alpha_m(float64 V) {
  return 0.1 * (V + 40) / (1 - exp(-(V + 40) / 10));
}
__device__ inline float64 beta_m(float64 V) {
  return 4.0 * exp(-(V + 65) / 18);
}
// ... similar for h, n, alpha, beta

__device__ inline float64 hh_dm_dt(float64 V, float64 m) {
  return alpha_m(V) * (1 - m) - beta_m(V) * m;
}
```

**Performance**: 8 million HH neurons × 4 RK4 substeps × 100 operations = 3.2 billion operations
GPU (A100): 300 TFlops → 10 milliseconds

### 4.2 Leaky IAF Euler (CPU-Optimized)

```cpp
// CPU vectorized (using SIMD AVX-512)
void integrate_iaf_neurons_simd(
  float64* V,              // Voltage array
  float64* I_input,        // Input currents
  float64* tau_m,          // Time constants
  int num_neurons,
  float64 dt
) {
  // Process 8 neurons at a time (AVX-512 double precision)
  for (int i = 0; i < num_neurons; i += 8) {
    // Load data into SIMD registers
    __m512d V_vec = _mm512_loadu_pd(&V[i]);
    __m512d I_vec = _mm512_loadu_pd(&I_input[i]);
    __m512d tau_vec = _mm512_loadu_pd(&tau_m[i]);
    
    // dV/dt = -(V - E_rest) / tau + I / C
    __m512d E_rest = _mm512_set1_pd(-70.0);
    __m512d C_m = _mm512_set1_pd(1.0);
    __m512d dt_vec = _mm512_set1_pd(dt);
    
    __m512d drift = _mm512_div_pd(
      _mm512_sub_pd(E_rest, V_vec),
      tau_vec
    );
    __m512d drive = _mm512_div_pd(I_vec, C_m);
    __m512d dV = _mm512_mul_pd(
      _mm512_add_pd(drift, drive),
      dt_vec
    );
    
    // V_new = V_old + dV
    __m512d V_new = _mm512_add_pd(V_vec, dV);
    
    // Store result
    _mm512_storeu_pd(&V[i], V_new);
  }
}
```

**Performance**: 470 million IAF neurons, 1 operation each = 470 million flops
CPU (single core): 100 GFlops → 4.7 milliseconds (but parallelizes across 64 cores)

---

## 5. SPIKE DETECTION AND EVENT GENERATION

### 5.1 Spike Detection Loop

```cpp
void detect_spikes_and_generate_events(
  const NeuronState* neurons,  // Current state
  const NeuronState* neurons_prev,  // Previous timestep
  const SynapseStore* synapses,
  EventQueue* event_queue,
  uint64 current_timestep,
  float64 SIMULATION_STEP_MS
) {
  #pragma omp parallel for num_threads(64)
  for (int neuron_idx = 0; neuron_idx < NUM_NEURONS; neuron_idx++) {
    const NeuronState& neuron = neurons[neuron_idx];
    const NeuronState& neuron_prev = neurons_prev[neuron_idx];
    
    // Skip if in absolute refractory period
    if (neuron.refractory_state == ABSOLUTE_REFR) {
      continue;
    }
    
    // Spike detection: threshold crossing from below
    if (neuron_prev.V <= neuron.V_threshold &&
        neuron.V > neuron.V_threshold) {
      
      // Record spike
      SpikeEvent spike_event;
      spike_event.source_timestep = current_timestep;
      spike_event.source_cat_n = neuron.cat_n_id;
      spike_event.spike_voltage = neuron.V;
      
      // Generate outgoing events for all postsynaptic targets
      const Vec<Ptr<SynapseRecord>>& outgoing = 
        synapses->outgoing_synapses[neuron.cat_n_id];
      
      for (const Ptr<SynapseRecord>& synapse_ptr : outgoing) {
        const SynapseRecord& synapse = *synapse_ptr;
        
        SpikeEvent event;
        event.delivery_timestep = current_timestep + (uint64)synapse.delay_ms;
        event.source_cat_n = neuron.cat_n_id;
        event.target_cat_n = synapse.target_cat_n;
        event.cat_s_id = synapse.cat_s_id;
        event.weight_amplitude = synapse.weight;
        event.neurotransmitter = synapse.neurotransmitter;
        event.receptor_type = synapse.receptor_type;
        
        // Thread-safe queue push (uses lock-free or atomic operations)
        event_queue->push(event);
      }
    }
  }
}
```

**Parallelization**: 64 threads (one per CPU core) iterate neurons in parallel. Event queue uses lock-free MPMC (multi-producer, multi-consumer) for thread safety.

---

## 6. STATE SNAPSHOT SERIALIZATION

### 6.1 Canonical Snapshot Format

```cpp
class StateSnapshot {
public:
  uint64 global_timestep;
  uint64 wall_clock_timestamp_ns;
  
  // Neuron states, sorted by CAT-N-ID for determinism
  struct NeuronSnapshot {
    CatNID cat_n_id;
    float64 membrane_potential;
    float64 input_current;
    uint64 spike_count;
    uint64 last_spike_time;
    float64 refractory_timer;
    // Gates (if HH)
    float64 gates[3];  // m, h, n
  };
  
  std::vector<NeuronSnapshot> neurons;  // Sorted
  std::vector<SpikeEvent> spike_events;  // Sorted by source_cat_n
  
  // Serialization
  std::vector<uint8_t> serialize() const {
    std::vector<uint8_t> buffer;
    
    // Header
    buffer.push_back_uint64_be(global_timestep);
    buffer.push_back_uint64_be(wall_clock_timestamp_ns);
    
    // Neuron count
    buffer.push_back_uint32_be(neurons.size());
    
    // Neurons (already sorted)
    for (const auto& neuron : neurons) {
      buffer.push_back(neuron.cat_n_id.serialize());      // 16 bytes
      buffer.push_back_float64_ieee754(neuron.membrane_potential);  // 8 bytes
      buffer.push_back_float64_ieee754(neuron.input_current);       // 8 bytes
      buffer.push_back_uint64_be(neuron.spike_count);     // 8 bytes
      buffer.push_back_uint64_be(neuron.last_spike_time); // 8 bytes
      buffer.push_back_float64_ieee754(neuron.refractory_timer);    // 8 bytes
      for (int i = 0; i < 3; i++) {
        buffer.push_back_float64_ieee754(neuron.gates[i]);  // 24 bytes
      }
    }
    
    // Spike events count
    buffer.push_back_uint32_be(spike_events.size());
    
    // Spike events (sorted)
    for (const auto& event : spike_events) {
      buffer.push_back(event.source_cat_n.serialize());     // 16 bytes
      buffer.push_back(event.target_cat_n.serialize());     // 16 bytes
      buffer.push_back_uint64_be(event.cat_s_id);           // 8 bytes
      buffer.push_back_uint8(event.neurotransmitter);       // 1 byte
      buffer.push_back_uint8(event.receptor_type);          // 1 byte
      buffer.push_back_float64_ieee754(event.weight_amplitude);  // 8 bytes
    }
    
    return buffer;
  }
  
  // Hash chain link
  SHA256 compute_hash_chain_link(const SHA256& previous_hash) const {
    std::vector<uint8_t> canonical = serialize();
    canonical.append(previous_hash.bytes());
    return SHA256(canonical);
  }
};
```

**Determinism**: All structures sorted lexicographically before serialization. No randomness.

### 6.2 State Block Archival

```cpp
class StateBlock {
public:
  uint64 start_timestep;
  uint64 end_timestep;
  std::string block_id;
  std::vector<StateSnapshot> snapshots;  // 1000 snapshots = 10 seconds
  
  std::vector<uint8_t> serialize_and_compress() {
    // Serialize all snapshots
    std::vector<uint8_t> canonical;
    for (const auto& snapshot : snapshots) {
      canonical.append(snapshot.serialize());
    }
    
    // Compress with Zstd
    ZSTD_CCtx* cctx = ZSTD_createCCtx();
    std::vector<uint8_t> compressed(ZSTD_compressBound(canonical.size()));
    size_t compressed_size = ZSTD_compress2(
      cctx,
      compressed.data(), compressed.size(),
      canonical.data(), canonical.size(),
      10  // Compression level (1-22, 10 is balanced)
    );
    compressed.resize(compressed_size);
    ZSTD_freeCCtx(cctx);
    
    // Add metadata
    std::vector<uint8_t> block_data;
    block_data.push_back_uint64_be(start_timestep);
    block_data.push_back_uint64_be(end_timestep);
    block_data.push_back_uint64_be(compressed_size);
    block_data.append(compressed);
    
    // Compute integrity hash
    SHA256 hash = SHA256(block_data);
    block_data.append(hash.bytes());
    
    return block_data;
  }
};
```

**Storage**: 1000 snapshots × 60 GB uncompressed = 60 TB
With Zstd level 10 compression: ~12 TB per block

---

## 7. ACTIVE NEURON FILTERING OPTIMIZATION

### 7.1 Bloom Filter for Recent Activity

```cpp
class ActiveNeuronFilter {
private:
  // Bloom filter: 760M bits = 95 MB
  // 4 hash functions for ~1% false positive rate
  std::vector<uint64_t> bloom_filter;  // 95M bytes
  
  static const size_t NUM_HASHES = 4;
  
  uint64_t hash_1(CatNID id) {
    return hash::xxhash64(id, 0);
  }
  uint64_t hash_2(CatNID id) {
    return hash::xxhash64(id, 1);
  }
  // ... hash_3, hash_4 similarly
  
public:
  void mark_active(CatNID neuron_id) {
    for (int i = 0; i < NUM_HASHES; i++) {
      uint64_t hash_val = hash_function(i, neuron_id);
      size_t bit_idx = hash_val % (760e6 * 8);  // 760M bits total
      bloom_filter[bit_idx / 64] |= (1ULL << (bit_idx % 64));
    }
  }
  
  bool might_be_active(CatNID neuron_id) {
    for (int i = 0; i < NUM_HASHES; i++) {
      uint64_t hash_val = hash_function(i, neuron_id);
      size_t bit_idx = hash_val % (760e6 * 8);
      if (!(bloom_filter[bit_idx / 64] & (1ULL << (bit_idx % 64)))) {
        return false;  // Definitely not active
      }
    }
    return true;  // Probably active (may be false positive)
  }
  
  void clear() {
    memset(bloom_filter.data(), 0, bloom_filter.size());
  }
};

void integrate_only_active_neurons(
  std::vector<NeuronState>& neurons,
  ActiveNeuronFilter& activity_filter,
  float64 dt
) {
  activity_filter.clear();
  
  // Mark neurons with recent input
  for (const SpikeEvent& event : pending_events) {
    if (event.delivery_timestep == current_timestep) {
      activity_filter.mark_active(event.target_cat_n);
    }
  }
  
  // Integrate only potentially active neurons
  #pragma omp parallel for
  for (int i = 0; i < neurons.size(); i++) {
    NeuronState& neuron = neurons[i];
    
    if (!activity_filter.might_be_active(neuron.cat_n_id)) {
      // Skip: definitely inactive, leave at resting state
      continue;
    }
    
    // Double-check: is it actually active?
    if (neuron.refractory_timer <= 0 && 
        neuron.last_input_time < current_timestep - 5) {
      // Inactive: skip
      continue;
    }
    
    // Active: integrate
    integrate_neuron(neuron, dt);
  }
}
```

**Benefit**: Skips 95% of neurons at baseline, only integrating ~15M active neurons per timestep.

---

## 8. HASH CHAIN AND INTEGRITY VERIFICATION

### 8.1 HMAC-Based Integrity Chain

```cpp
class IntegrityChain {
private:
  // Master key (kept secure)
  std::array<uint8_t, 32> master_key;
  
  // Hash chain
  std::vector<SHA256> hash_chain;
  
public:
  IntegrityChain(const std::array<uint8_t, 32>& key) : master_key(key) {
    hash_chain.push_back(SHA256::ZERO);  // Genesis block
  }
  
  void record_snapshot(const StateSnapshot& snapshot) {
    // Canonical serialization
    std::vector<uint8_t> canonical = snapshot.serialize();
    
    // HMAC-SHA-256 tag (deterministic)
    std::vector<uint8_t> hmac_input;
    hmac_input.append(master_key);
    hmac_input.append(canonical);
    
    SHA256 hmac = SHA256_HMAC(master_key, canonical);
    
    // Hash chain link
    std::vector<uint8_t> chain_input;
    chain_input.append(canonical);
    chain_input.append(hash_chain.back().bytes());  // Previous hash
    
    SHA256 current_hash = SHA256(chain_input);
    hash_chain.push_back(current_hash);
  }
  
  bool verify_chain_integrity() {
    // Verify each link in the chain
    for (size_t i = 1; i < hash_chain.size(); i++) {
      // Recompute hash[i] from hash[i-1]
      std::vector<uint8_t> chain_input;
      chain_input.append(snapshots[i].serialize());
      chain_input.append(hash_chain[i-1].bytes());
      
      SHA256 recomputed = SHA256(chain_input);
      
      if (recomputed != hash_chain[i]) {
        log_error("Hash chain broken at index {}", i);
        return false;
      }
    }
    return true;
  }
};
```

---

## 9. PERFORMANCE PROFILING INSTRUMENTATION

### 9.1 Per-Phase Timing

```cpp
struct PhaseMetrics {
  struct Phase {
    std::string name;
    uint64_t total_time_ns;
    uint64_t min_time_ns;
    uint64_t max_time_ns;
    uint64_t call_count;
    
    double average_time_ms() const {
      return total_time_ns / (call_count * 1e6);
    }
  };
  
  std::map<std::string, Phase> phases;
  
  void log_metrics(uint64 timestep) {
    if (timestep % 10000 == 0) {
      print("=== Performance Metrics at Timestep {} ===", timestep);
      for (const auto& [phase_name, phase] : phases) {
        print("{}: avg={:.2f}ms, min={:.2f}ms, max={:.2f}ms, calls={}",
          phase_name,
          phase.average_time_ms(),
          phase.min_time_ns / 1e6,
          phase.max_time_ns / 1e6,
          phase.call_count
        );
      }
    }
  }
};

class TimedPhase {
private:
  PhaseMetrics& metrics;
  std::string phase_name;
  uint64_t start_time;
  
public:
  TimedPhase(PhaseMetrics& m, const std::string& name)
    : metrics(m), phase_name(name), start_time(rdtsc()) {}
  
  ~TimedPhase() {
    uint64_t end_time = rdtsc();
    uint64_t elapsed = end_time - start_time;
    
    auto& phase = metrics.phases[phase_name];
    phase.total_time_ns += elapsed;
    phase.min_time_ns = std::min(phase.min_time_ns, elapsed);
    phase.max_time_ns = std::max(phase.max_time_ns, elapsed);
    phase.call_count++;
  }
};

// Usage in timestep loop
for (uint64 t = 0; t < max_timestep; t++) {
  {
    TimedPhase _("PHASE_1_DELIVER_EVENTS", metrics);
    deliver_events(event_queue, neurons, t);
  }
  
  {
    TimedPhase _("PHASE_2_INTEGRATE", metrics);
    integrate_neural_dynamics(neurons, dt);
  }
  
  {
    TimedPhase _("PHASE_3_SPIKES", metrics);
    detect_spikes_and_generate_events(neurons, synapses, event_queue, t);
  }
  
  metrics.log_metrics(t);
}
```

---

## 10. SUMMARY: Data Structures Overview

| Structure | Size | Count | Total Memory | Access Pattern |
|-----------|------|-------|--------------|-----------------|
| NeuronState | 280 bytes | 760M | 213 GB | O(1) hash + circular buffer |
| SynapseRecord | 100 bytes | 76B | 7.6 TB | O(1) outgoing/incoming indices |
| SpikeEvent | 40 bytes | 1.5B (peak queue) | 60 GB | O(log N) priority heap |
| StateSnapshot | 60 GB | 1 per 10ms | 6 TB/100s | Sequential write + compress |
| Hash Chain | 32 bytes | 100K (per 1000 timesteps) | 3.2 MB | Sequential append |

**Total Tier 1 (RAM)**: ~8-10 TB (Tier 1 neurons + event queue)
**Total Tier 2 (SSD)**: ~54 TB (900 timestep window)
**Total Tier 3 (Archive)**: Unbounded (~12 TB per 10 seconds)

---

**End of Data Structures Reference**
