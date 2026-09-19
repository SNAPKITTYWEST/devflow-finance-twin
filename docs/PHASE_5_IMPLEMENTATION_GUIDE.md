# PHASE 5: Implementation Guide and Verification Checklist

**Objective**: Implement 760-million-neuron neural dynamics engine with recurrent connectivity, individual state preservation, and deterministic reproducibility.

---

## PART 1: PRE-IMPLEMENTATION REQUIREMENTS

### 1.1 Hardware Setup (Minimum)

```
CPU: 64-core Xeon (e.g., Intel Xeon Platinum 8480)
     - 2+ GHz base, 3+ GHz turbo
     - 16 MB L3 cache
     - Support for AVX-512 SIMD

GPU: NVIDIA A100 (40-80 GB VRAM)
     - 6,912 CUDA cores
     - 300 TFlops peak (matrix operations)
     - Supports Zstd decompression in hardware

RAM: 16 TB
     - Tier 1 buffer: 8-10 TB (neurons + events)
     - OS + libraries: 100 GB
     - Scratch: 2 TB

Storage (SSD):
     100 TB NVMe (Tier 2 cache)
     - Read/write: 3+ GB/s
     - Endurance: 10,000+ PBW

Storage (Archive):
     Cloud object storage (S3/GCS) or 500 TB HDD
     - Append-only (WORM-compatible)
     - Zstd-compressed blocks
```

### 1.2 Software Stack

```
Base OS: Linux (Ubuntu 22.04 LTS preferred)
         or Windows Server 2022 with WSL2

Compilers:
  C++20: GCC 12.2+ or Clang 16+
  CUDA: NVIDIA CUDA Toolkit 12.0+
  Go: 1.21+ (for orchestration)

Libraries:
  Zstandard: v1.5.5+ (for compression)
  OpenMP: libgomp or libomp (for parallelization)
  MKL: Intel Math Kernel Library (for HH RK4)
  Protobuf: v3.21+ (for state serialization)

Version Control:
  Git 2.40+
  Large file storage: Git LFS for state blocks

CI/CD:
  GitHub Actions or GitLab CI for continuous verification
```

---

## PART 2: MODULE BREAKDOWN AND IMPLEMENTATION ORDER

### Phase 5A: Core Data Structures (Week 1-2)

**Deliverables**:
- [ ] NeuronStateRecord with hierarchical storage (region/neuron/timestep)
- [ ] SynapseRecord with dual indices (outgoing/incoming)
- [ ] SpikeEvent and priority queue
- [ ] Unit tests for all data structures

**Implementation Files**:
```
src/
  ├── data_structures/
  │   ├── neuron_state.hpp
  │   ├── neuron_state.cpp
  │   ├── synapse_record.hpp
  │   ├── synapse_record.cpp
  │   ├── spike_event.hpp
  │   ├── spike_event.cpp
  │   └── event_queue.hpp
  │
  ├── storage/
  │   ├── neuron_state_store.hpp
  │   ├── synapse_store.hpp
  │   ├── tier_1_buffer.hpp       (in-memory)
  │   ├── tier_2_cache.hpp        (SSD cache)
  │   └── tier_3_archive.hpp      (disk/WORM)
  │
  └── tests/
      ├── test_neuron_state.cpp
      ├── test_synapse_store.cpp
      └── test_event_queue.cpp
```

**Testing**:
- Create 100 neurons, verify O(1) lookup by CAT-N-ID
- Create 10,000 synapses, verify outgoing/incoming indices consistency
- Push/pop 1M events, verify heap ordering by delivery_time + source_cat_n

### Phase 5B: Neural Integration Kernels (Week 2-4)

**Deliverables**:
- [ ] Hodgkin-Huxley RK4 integrator (CPU + GPU)
- [ ] Leaky IAF Euler integrator (SIMD)
- [ ] IAF with dopamine modulation
- [ ] Accuracy tests (convergence to biological data)

**Implementation Files**:
```
src/
  ├── kernels/
  │   ├── hodgkin_huxley.hpp
  │   ├── hodgkin_huxley_cuda.cu
  │   ├── leaky_iaf.hpp
  │   ├── leaky_iaf_simd.cpp
  │   ├── iaf_modulated.hpp
  │   └── spike_detector.hpp
  │
  └── tests/
      ├── test_hh_single.cpp        (vs. benchmark data)
      ├── test_iaf_single.cpp
      ├── test_iaf_modulated.cpp
      └── test_convergence.cpp      (RK4 error bounds)
```

**Testing**:
- Simulate single HH neuron for 1 second, compare membrane potential to published recordings
- Test IAF with different tau_m values, verify firing rates
- Test STDP-driven weight changes over 100 timesteps

### Phase 5C: Event Propagation & Timestep Loop (Week 3-5)

**Deliverables**:
- [ ] Master timestep loop (6 phases)
- [ ] Per-region parallel executors
- [ ] Spike detection and event generation
- [ ] Deterministic event ordering

**Implementation Files**:
```
src/
  ├── scheduler/
  │   ├── temporal_scheduler.hpp
  │   ├── temporal_scheduler.cpp
  │   ├── region_executor.hpp
  │   ├── phase_controller.hpp
  │   └── event_delivery.hpp
  │
  └── tests/
      ├── test_temporal_ordering.cpp
      ├── test_causality.cpp
      └── test_determinism.cpp
```

**Testing**:
- Simulate 1000 neurons, 5000 synapses for 1000 timesteps
- Verify causality: no spike affects its own generation
- Run twice with same seed, compare spike sequences (byte-for-byte identical)

### Phase 5D: Behavioral Output Mapping (Week 4-5)

**Deliverables**:
- [ ] Motor output aggregation from M1/M2 neurons
- [ ] Cognitive state encoding (motivation, social engagement)
- [ ] Context aggregation (neuromodulator state, vigilance)
- [ ] Full neural traceability (source neurons → action)

**Implementation Files**:
```
src/
  ├── behavior/
  │   ├── motor_output.hpp
  │   ├── motor_output.cpp
  │   ├── cognitive_state.hpp
  │   ├── cognitive_state.cpp
  │   ├── action_record.hpp
  │   └── behavioral_mapper.cpp
  │
  └── tests/
      ├── test_motor_mapping.cpp
      ├── test_cognitive_state.cpp
      └── test_action_traceability.cpp
```

**Testing**:
- Spike M1 neurons, verify motor intensity computed correctly
- Trace motor action backward to presynaptic neurons (5+ levels deep)
- Verify no action without source neurons

### Phase 5E: State Recording & Archival (Week 5-6)

**Deliverables**:
- [ ] Deterministic state snapshot serialization
- [ ] StateBlock archival every 1000 timesteps
- [ ] Zstd compression
- [ ] Hash chain integrity
- [ ] Tier 1/2/3 storage management

**Implementation Files**:
```
src/
  ├── state_recording/
  │   ├── state_snapshot.hpp
  │   ├── state_snapshot.cpp
  │   ├── state_block.hpp
  │   ├── state_block.cpp
  │   ├── serialization.hpp
  │   └── integrity_chain.hpp
  │
  └── tests/
      ├── test_snapshot_determinism.cpp
      ├── test_compression.cpp
      └── test_integrity_chain.cpp
```

**Testing**:
- Record 10,000 snapshots, verify deterministic serialization
- Compress/decompress blocks, verify data integrity (CRC)
- Verify hash chain: tampering breaks chain for all subsequent blocks

### Phase 5F: Sparse Execution & Optimization (Week 6-7)

**Deliverables**:
- [ ] Active neuron filtering (Bloom filter)
- [ ] Lazy event queue processing
- [ ] Performance profiling instrumentation
- [ ] Optimization passes (vectorization, GPU acceleration)

**Implementation Files**:
```
src/
  ├── optimization/
  │   ├── active_neuron_filter.hpp
  │   ├── sparse_executor.hpp
  │   ├── performance_metrics.hpp
  │   └── profiling.cpp
  │
  └── tests/
      ├── test_sparse_execution.cpp
      ├── test_performance.cpp
      └── benchmark_gflops.cpp
```

**Testing**:
- Baseline: simulate 10M neurons, measure wall time
- With sparse filtering: measure speedup (expect 10-50x)
- Profile each phase, identify bottlenecks

### Phase 5G: Integration & Scale Testing (Week 7-8)

**Deliverables**:
- [ ] Full integration test (100M neurons)
- [ ] Scale test (760M neurons for 100 timesteps)
- [ ] Reproducibility verification
- [ ] Causality verification
- [ ] Performance characterization

**Implementation Files**:
```
src/
  ├── tests/
  │   ├── integration_test_100m.cpp
  │   ├── scale_test_760m.cpp
  │   ├── reproducibility_test.cpp
  │   ├── causality_verification.cpp
  │   └── performance_characterization.cpp
```

**Testing**:
- Run 100M neuron simulation for 100 timesteps
- Verify memory usage stays within budget
- Run 760M neuron simulation for 1 timestep, measure wall time
- Re-run with same seed, verify identical spike sequence

---

## PART 3: BUILD SYSTEM AND COMPILATION

### 3.1 CMakeLists.txt (Root)

```cmake
cmake_minimum_required(VERSION 3.20)
project(SnapKitty-Phase5-Neural-Engine)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=native -fopenmp")

# GPU support
enable_language(CUDA)
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -O3 -gencode arch=compute_80,code=sm_80")

# Dependencies
find_package(OpenMP REQUIRED)
find_package(Zstandard REQUIRED)
find_package(Protobuf REQUIRED)
find_package(CUDAToolkit REQUIRED)

# Source directories
add_subdirectory(src/data_structures)
add_subdirectory(src/storage)
add_subdirectory(src/kernels)
add_subdirectory(src/scheduler)
add_subdirectory(src/behavior)
add_subdirectory(src/state_recording)
add_subdirectory(src/optimization)

# Main executable
add_executable(neural_engine src/main.cpp)
target_link_libraries(neural_engine
  PRIVATE
    data_structures
    storage
    kernels
    scheduler
    behavior
    state_recording
    optimization
    OpenMP::OpenMP_CXX
    zstd::zstd
    protobuf::libprotobuf
    CUDA::cudart
    CUDA::curand
)

# Tests
enable_testing()
add_subdirectory(src/tests)
```

### 3.2 Building and Running

```bash
# Build
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j 64

# Run single-threaded test
./neural_engine --mode test --neurons 1000 --timesteps 100

# Run 100M neuron integration test
./neural_engine --mode scale_test_100m --timesteps 100 --seed 12345

# Run full 760M simulation
./neural_engine --mode simulate --neurons 760000000 --timesteps 1000 --seed 42 --output-dir /data/simulation_0

# Verify reproducibility
./neural_engine --mode simulate --neurons 760000000 --timesteps 1000 --seed 42 --output-dir /data/simulation_1
diff /data/simulation_0/spike_log.bin /data/simulation_1/spike_log.bin && echo "REPRODUCIBLE"
```

---

## PART 4: INTEGRATION WITH PHASE 4

### 4.1 Dylan DSL Compatibility

Phase 4 specified neuron execution model in Dylan DSL. Phase 5 implementation must:

- [ ] Parse Dylan neuron definitions
- [ ] Extract CAT-N-ID, region_id, neuron_type, parameters
- [ ] Populate NeuronStateRecord from Dylan specs
- [ ] Validate firing model assignment

```cpp
// Integration point
void load_neurons_from_dylan(
  const std::string& dylan_file_path,
  NeuronStateStore& neurons,
  SynapseStore& synapses
) {
  DylanParser parser(dylan_file_path);
  
  for (const auto& neuron_spec : parser.neurons) {
    NeuronStateRecord neuron;
    neuron.cat_n_id = CatNID::from_string(neuron_spec.id);
    neuron.region_id = RegionID::from_string(neuron_spec.region);
    neuron.neuron_type = NeuronType::from_string(neuron_spec.type);
    neuron.firing_model_id = assign_firing_model(neuron.neuron_type);
    neuron.soma_coordinates = neuron_spec.coordinates;
    
    // Initialize state
    neuron.timestep = 0;
    neuron.membrane_potential_mV = neuron_spec.resting_potential;
    neuron.input_current_nA = 0;
    neuron.refractory_timer_ms = 0;
    // ... other initializations
    
    neurons.add_neuron(neuron);
  }
  
  for (const auto& synapse_spec : parser.synapses) {
    SynapseRecord synapse;
    synapse.cat_s_id = CatSID::from_string(synapse_spec.id);
    synapse.source_cat_n = CatNID::from_string(synapse_spec.source);
    synapse.target_cat_n = CatNID::from_string(synapse_spec.target);
    synapse.weight = synapse_spec.weight;
    synapse.delay_ms = synapse_spec.delay;  // Validate >= 1ms
    synapse.neurotransmitter = Neurotransmitter::from_string(synapse_spec.nt);
    synapse.receptor_type = ReceptorType::from_string(synapse_spec.receptor);
    
    // Validate compatibility
    assert(is_compatible(synapse.neurotransmitter, synapse.receptor_type));
    
    synapses.add_synapse(synapse);
  }
}
```

### 4.2 Ada/SPARK WORM Integration

Phase 4 specified cryptographic integrity layer. Phase 5 must:

- [ ] Use HMAC-SHA-256 for state records
- [ ] Implement hash chain linking
- [ ] Write STATE_BLOCKs to WORM storage
- [ ] Verify integrity on replay

```cpp
// Integration point
void record_state_with_integrity(
  const StateSnapshot& snapshot,
  IntegrityChain& chain,
  WORMStorage& worm
) {
  // Canonical serialization (from Phase 4 Ada/SPARK WORM layer)
  std::vector<uint8_t> canonical = snapshot.serialize();
  
  // HMAC-SHA-256 tag
  SHA256 hmac = HMAC_SHA256(master_key, canonical);
  
  // Hash chain link
  SHA256 hash_link = chain.extend_chain(canonical);
  
  // Write to WORM
  WORMBlock block;
  block.data = canonical;
  block.hmac_tag = hmac;
  block.hash_chain_link = hash_link;
  block.seal_timestamp = current_time_ns();
  
  worm.append_immutable_block(block);
}
```

---

## PART 5: VERIFICATION AND VALIDATION

### 5.1 Invariant Verification Tests

All Phase 4 invariants (I1, I17-I20) must pass:

```cpp
// I1: Graph Topology Preservation
bool verify_invariant_I1() {
  assert(neurons.size() == 760e6);
  assert(synapses.size() == 76e9);
  
  for (uint64 t = 0; t < max_timestep; t++) {
    assert(neurons.count_at(t) == 760e6);
    assert(synapses.connectivity_unchanged(t));
  }
  
  return true;
}

// I17: Recurrent Connectivity Preserved
bool verify_invariant_I17() {
  // For every cycle, verify no backward causality
  for (const auto& cycle : identify_cycles()) {
    uint64_t cycle_latency_ms = 0;
    for (const auto& edge : cycle) {
      cycle_latency_ms += edge.delay_ms;
    }
    
    assert(cycle_latency_ms >= 3);  // At least 3ms round-trip
  }
  
  return true;
}

// I18: Temporal State Preservation (Determinism)
bool verify_invariant_I18() {
  // Run simulation twice with same seed
  std::vector<SpikeEvent> log_1 = run_simulation(seed=12345, max_t=1000);
  std::vector<SpikeEvent> log_2 = run_simulation(seed=12345, max_t=1000);
  
  assert(log_1.size() == log_2.size());
  for (size_t i = 0; i < log_1.size(); i++) {
    assert(log_1[i].source_cat_n == log_2[i].source_cat_n);
    assert(log_1[i].target_cat_n == log_2[i].target_cat_n);
    assert(log_1[i].delivery_timestep == log_2[i].delivery_timestep);
  }
  
  return true;
}

// I19: Neurotransmitter/Receptor Traceability
bool verify_invariant_I19() {
  for (const auto& synapse : synapses) {
    assert(is_compatible(synapse.neurotransmitter, synapse.receptor_type));
  }
  
  for (const auto& event : spike_log) {
    assert(event.neurotransmitter != UNKNOWN);
    assert(event.receptor_type != UNKNOWN);
  }
  
  return true;
}

// I20: Behavioral Output Traceability
bool verify_invariant_I20() {
  for (const auto& action : behavioral_outputs) {
    assert(action.source_neurons.size() > 0);
    for (const auto& source_neuron : action.source_neurons) {
      assert(neurons.contains(source_neuron.cat_n_id));
      assert(source_neuron.firing_rate >= 0);
    }
    
    assert(action.source_synapses.size() > 0);
  }
  
  return true;
}
```

### 5.2 Causality Verification

```cpp
bool verify_causality(const SpikeStimulusLog& log) {
  // Build dependency graph
  for (const auto& spike : log) {
    // For each presynaptic input to source neuron
    for (const auto& input_event : incoming_events(spike.source_cat_n)) {
      if (input_event.delivery_time >= spike.spike_time) {
        log_error("Causality violation: event arrives after spike it causes");
        return false;
      }
    }
  }
  
  return true;
}
```

### 5.3 Performance Characterization

```
Expected performance metrics (on A100 + 64-core Xeon):

Timestep duration (1ms of simulated time):
  - Event delivery: 15 GFlops (1.5B events × 10 flops)
  - HH integration: 0.8 GFlops (8M neurons × 100 flops)
  - IAF integration: 7 MFlops (470M × 1 flop, 95% sparse)
  - Spike detection: 30 MFlops
  - State recording (amortized): 3 GFlops
  
  Total: ~18 GFlops per timestep

Walltime per timestep:
  - GPU (A100): 60 microseconds → 1M timesteps = 60 seconds
  - CPU (single core): 180 milliseconds → 1M timesteps = 5 hours
  - CPU (64 cores): 2.8 milliseconds → 1M timesteps = 2.8 kiloseconds ≈ 1 hour

Memory usage:
  - Tier 1 active buffer: 8 TB (within budget)
  - Event queue peak: 60 GB (acceptable)
  - Temporary allocations: <100 GB
  
  Total: <10 TB (fits in system RAM)

Simulation duration (1000 seconds = 1M timesteps):
  - GPU-based: ~60 seconds walltime
  - CPU-based (64 cores): ~1 hour walltime
  - I/O overhead (state archival): +10-20 seconds
```

---

## PART 6: DEPLOYMENT CHECKLIST

- [ ] All modules compile without warnings
- [ ] All unit tests pass (100% pass rate)
- [ ] Integration test (100M neurons) completes in <5 minutes
- [ ] Scale test (760M neurons, 10 timesteps) completes in <1 hour
- [ ] Reproducibility verified (2 runs with same seed → identical output)
- [ ] Causality verified (no backward-time dependencies)
- [ ] All 5 invariants (I1, I17-I20) pass
- [ ] Performance metrics documented
- [ ] Memory usage within budget
- [ ] Code reviewed and approved
- [ ] Documentation complete
- [ ] Docker image built and pushed to registry

---

## PART 7: HANDOFF TO PHASE 6

Phase 5 output feeds into Phase 6 (Biological Integration & Behavior Emergence):

**Outputs from Phase 5**:
1. Compiled neural_engine binary (GPU-optimized)
2. Reference connectome (760M neurons, 76B synapses)
3. State snapshot format specification (Protobuf schema)
4. Performance characterization report
5. Reproducibility verification log
6. Causality verification log

**Inputs to Phase 6**:
1. Sensory input stimuli (e.g., predatory prey visual input)
2. Neuromodulator control signals (dopamine, serotonin setpoints)
3. Behavioral outcome metrics (hunting success, social affiliation)
4. Learning parameters (STDP time windows, learning rates)

**Phase 6 Will Implement**:
1. Sensory input encoding (retina→LGN→V1)
2. Behavioral outcome mapping (motor output→environment interaction)
3. Reward/punishment feedback loops
4. Learning dynamics (synaptic plasticity over hours/days)
5. State-dependent neural responses (sleep/wake, arousal)

---

## PART 8: DEBUGGING UTILITIES

### 8.1 State Inspection

```cpp
// Print neuron state at timestep
void inspect_neuron(CatNID neuron_id, uint64 timestep) {
  const NeuronStateRecord& state = neurons[neuron_id][timestep];
  
  printf("Neuron %s at timestep %lu:\n", neuron_id.str().c_str(), timestep);
  printf("  V = %.2f mV\n", state.membrane_potential_mV);
  printf("  I = %.2f nA\n", state.input_current_nA);
  printf("  Spike count = %lu\n", state.spike_count);
  printf("  Last spike = %lu\n", state.last_spike_time);
  printf("  Refractory timer = %.2f ms\n", state.refractory_timer_ms);
  
  if (state.firing_model_id == HODGKIN_HUXLEY) {
    printf("  HH gates: m=%.3f, h=%.3f, n=%.3f\n",
      state.hh_gates.m, state.hh_gates.h, state.hh_gates.n);
  }
}

// Print incoming events for a neuron
void inspect_incoming_events(CatNID neuron_id, uint64 timestep) {
  const auto& incoming = synapses.incoming_synapses[neuron_id];
  
  printf("Incoming synapses to %s:\n", neuron_id.str().c_str());
  for (const auto& synapse_ptr : incoming) {
    const SynapseRecord& syn = *synapse_ptr;
    printf("  %s → %s (weight=%.3f, delay=%.1fms)\n",
      syn.source_cat_n.str().c_str(),
      syn.target_cat_n.str().c_str(),
      syn.weight,
      syn.delay_ms);
  }
}

// Trace spike backward to source
void trace_spike_backward(CatNID neuron_id, uint64 timestep, int depth = 5) {
  if (depth <= 0) return;
  
  printf("%*sNeuron %s spiked at t=%lu\n", 
    (5-depth)*2, "", neuron_id.str().c_str(), timestep);
  
  // Find presynaptic spikes that contributed
  const auto& incoming = synapses.incoming_synapses[neuron_id];
  for (const auto& synapse_ptr : incoming) {
    const SynapseRecord& syn = *synapse_ptr;
    int64_t presynaptic_spike_time = timestep - syn.delay_ms;
    
    if (presynaptic_spike_time >= 0) {
      printf("%*s← from %s at t=%ld\n",
        (5-depth)*2, "",
        syn.source_cat_n.str().c_str(),
        presynaptic_spike_time);
      
      trace_spike_backward(syn.source_cat_n, presynaptic_spike_time, depth - 1);
    }
  }
}
```

### 8.2 Performance Profiling

```cpp
// Generate flamegraph
void profile_timestep_phases() {
  PhaseMetrics metrics;
  
  for (uint64 t = 0; t < 10000; t++) {
    {
      TimedPhase _("phase_1_deliver", metrics);
      deliver_events(...);
    }
    {
      TimedPhase _("phase_2_integrate", metrics);
      integrate_neural_dynamics(...);
    }
    // ... other phases
  }
  
  // Export to flamegraph format
  metrics.export_to_flamegraph("profile.txt");
  
  // Generate SVG
  // system("flamegraph.pl profile.txt > profile.svg");
}
```

---

## CONCLUSION

Phase 5 implementation plan outlined above spans 8 weeks with clear deliverables, testing, and verification gates. Following this roadmap ensures:

1. **Correctness**: All Phase 4 invariants verified at each step
2. **Performance**: 18 GFlops per timestep, 760M-neuron simulation in 1 hour
3. **Scalability**: Memory usage stays within budget (10 TB RAM)
4. **Reproducibility**: Deterministic replay with seed control
5. **Biological Fidelity**: Mixed neural models (HH for complex, IAF for simple)
6. **Traceability**: Full audit trail from action back to source neurons

Phase 5 readiness: Awaiting implementation team handoff.

---

**Workflow**: snapkitty-phase-5-implementation-guide  
**Date**: 2026-09-13  
**Status**: SPECIFICATION COMPLETE  
**Next**: Phase 5 Implementation (8-week sprint)
