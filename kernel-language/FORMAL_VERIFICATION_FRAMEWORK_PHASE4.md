# FORMAL VERIFICATION FRAMEWORK — PHASE 4 EXECUTION
## Independent Audit of Neural Dynamics Execution Model

**Auditor:** ORCHESTRATOR-2 (Formal Verification + Adversarial Auditor)  
**Date:** 2026-09-13  
**Status:** COMPREHENSIVE SPECIFICATION + ADVERSARIAL TESTING PROTOCOL  
**Authority:** NEURAL_DYNAMICS_EXECUTION.md (kernel-language specification)

---

## EXECUTIVE SUMMARY

This framework formally specifies invariants I1, I17-I20 governing PHASE 4 execution, designs adversarial attack scenarios to test each invariant's robustness, and establishes verification criteria for audit sign-off.

**Core Finding:** Phase 4 design preserves recurrent connectivity via delay-based event propagation, maintains complete neuron/synapse/neurotransmitter traceability through CAT-N-ID and CAT-S-ID tagging, and guarantees deterministic replay through comprehensive state logging.

**Risk Vector:** Non-deterministic event queue ordering, silent neuron aggregation in state snapshots, or implicit receptor filtering could violate I18/I19/I20.

---

## PART 1: FORMAL INVARIANT SPECIFICATIONS

### INVARIANT I1-CORRECTED: GRAPH TOPOLOGY PRESERVATION

#### Specification

**Claim:** The simulation preserves exact graph structure throughout execution:
- All 158 neurons remain distinct nodes (no aggregation or merging)
- All 102 synapses remain distinct edges (no creation, deletion, or splitting)
- All connectivity types supported (feedforward, recurrent, bidirectional feedback)

#### Formal Definition

```
∀ simulation_run S:
  ∃ neurons N = {CAT-N-001, CAT-N-002, ..., CAT-N-158}
  ∃ synapses E = {CAT-S-001, CAT-S-002, ..., CAT-S-102}
  
  I1-INIT: |N| = 158, |E| = 102
  
  ∀ timestep t ∈ [0, T]:
    I1-PRESERVED-NODES: |N_t| = 158 (neuron count unchanged)
    I1-PRESERVED-EDGES: |E_t| = 102 (synapse count unchanged)
    I1-NODE-IDENTITY: ∀n ∈ N_t: neuron_id(n) ∈ {CAT-N-001, ..., CAT-N-158}
    I1-EDGE-IDENTITY: ∀e ∈ E_t: synapse_id(e) ∈ {CAT-S-001, ..., CAT-S-102}
    
    # No intermediate aggregation nodes created
    I1-NO-AGGREGATION: ¬∃ node_id n_t: (n_t ∉ N)
    
    # No aggregate edges replacing original synapses
    I1-NO-EDGE-AGGREGATION: ∀ e ∈ E_t: 
      source(e) ∈ N AND target(e) ∈ N AND
      (source(e), target(e), synapse_id(e)) immutable across timesteps
```

#### Verification Criteria

**PASS:** Phase 4 implementation satisfies ALL conditions:

✓ **VC1-A:** Neuron registry snapshot at initialization == snapshot at t=T
  - Count: 158 neurons with distinct CAT-N-ID values
  - Uniqueness: No two neurons share CAT-N-ID

✓ **VC1-B:** Synapse registry snapshot at initialization == snapshot at t=T
  - Count: 102 synapses with distinct CAT-S-ID values
  - Connectivity: Each (source_id, target_id, synapse_id) tuple immutable

✓ **VC1-C:** State logs contain no neuron ID appearing after its registration
  - Forward scan: First log entry with neuron_id N → N exists in registry
  - No duplication: If CAT-N-042 logs spike at t=100, no CAT-N-042 spawned at t=50

✓ **VC1-D:** Event queue never creates intermediate nodes
  - Delivery verification: Every (source_id, target_id) pair in event_queue matches existing synapse
  - No orphaned spike events targeting non-existent neurons

✓ **VC1-E:** Behavioral output traces contain only registered neuron IDs
  - Action trace verification: Every source_neuron in ActionTrace ∈ N

**FAIL:** Any violation of above conditions, including:
- A neuron appearing in state log with unregistered CAT-N-ID
- A synapse appearing in event_queue with unregistered CAT-S-ID
- Total neuron count drifting away from 158
- Any split/merge operation on neuron or synapse IDs

---

### INVARIANT I17: RECURRENT CONNECTIVITY PRESERVED

#### Specification

**Claim:** All feedback loops from Phase 3 design remain executable in Phase 4 execution. Recurrent computation is not forced into DAG by eliminating cycles; instead, cycles are broken temporally via synaptic delays.

#### Formal Definition

```
∀ recurrent_connection r in Phase 3 design:
  ∃ path P = [neuron A → synapse s₁ → neuron B → synapse s₂ → neuron A]
  
  I17-CONNECTIVITY: P remains in Phase 4 model
  
  ∀ timestep t:
    I17-CYCLE-EXECUTABLE: Neuron A can fire, eventually trigger B, B can fire and eventually reach A
    
  # Synaptic delays break synchronous cycles
  I17-DELAY-BASED: ∀ cycle C:
    total_delay_ms(C) = Σ_{synapse ∈ C} delay(synapse) > 0
    
    AND ∀ path P in cycle:
      ∃ timestep t₀: spike generated at A
      ∃ timestep t₁ > t₀: spike delivered to B
      ∃ timestep t₂ > t₁: spike delivered back to A
      
    Min recurrence latency = total_delay_ms(C) ≥ 1 ms
    
  I17-NO-INSTANTANEOUS-CYCLES: ¬∃ spike delivered to same neuron in same timestep it originated
  
  # Bidirectional information flow preserved
  I17-BIDIRECTIONAL: ∀ neuron pair (A, B):
    if ∃ synapse from A to B AND ∃ synapse from B to A:
      Both synapses fire and deliver in both directions within simulation window
```

#### Verification Criteria

**PASS:** All conditions satisfied:

✓ **VC17-A:** Backward connectivity preserved
  - Query: For each synapse s_forward in forward direction, verify existence of corresponding s_backward
  - Count: All feedback synapses remain in registry
  - Example: If CAT-S-050 = (Motor→Sensory), verify CAT-S-051 = (Sensory→Motor) exists

✓ **VC17-B:** No cycle elimination via structure modification
  - Graph scan: Identify all cycles at initialization
  - Replay: Verify same cycles remain at t=T (even if not all fire)
  - Structural invariant: Graph topology unchanged

✓ **VC17-C:** Synaptic delays prevent instantaneous recursion
  - Event queue inspection: ∀ PostsynapticEvent e, delivery_time(e) > spike_time(e)
  - Delay verification: All connections have delay > 0 ms
  - Minimum delay: min(all delays) ≥ 0.1 ms

✓ **VC17-D:** Cycle latency >= 1 ms minimum
  - Trace analysis: For each recurrent neuron pair (A, B):
    - Time from A fires → B receives = delay(A→B)
    - Time from B fires → A receives = delay(B→A)
    - Total round-trip = delay(A→B) + delay(B→A) ≥ 1 ms
  - Log verification: No spike event records firing and receipt within same timestep

✓ **VC17-E:** Bidirectional firing observed in logs
  - Spike event analysis: For pairs with mutual connectivity, verify both directions fire during simulation
  - If pair (A, B) has synapses in both directions:
    - Spike log contains: CAT-N-A fires → CAT-N-B receives (via CAT-S-x)
    - Spike log contains: CAT-N-B fires → CAT-N-A receives (via CAT-S-y)

**FAIL:** Any violation, including:
- Cycle eliminated (e.g., feedback synapse marked "not for execution")
- Instantaneous cycle: spike delivered to same neuron in same timestep (delivery_time == spike_time)
- Synaptic delay ≤ 0 ms
- Neuron A fires, receives spike at same t: violates causality

---

### INVARIANT I18: TEMPORAL STATE PRESERVATION

#### Specification

**Claim:** State at time t is deterministically derived from state[0..t] + all inputs. No information is lost in discretization. Identical inputs guarantee identical outputs (deterministic replay).

#### Formal Definition

```
∀ simulation_run S with fixed parameters Θ and stimulus sequence I:
  Define state_vector(t) = {V[n,t], m[n,t], h[n,t], n[n,t], D(t), A(t), ... | ∀n ∈ neurons}
  Define output_vector(t) = {spike_events(t), behavioral_output(t)}
  
  I18-DETERMINISM: ∀ timestamp t:
    output_vector(t) = f(state_vector(0..t), inputs(0..t), Θ, seed)
    
    where f is pure (no side effects, no external randomness)
  
  I18-STATE-CONTINUITY: ∀ t:
    state_vector(t) depends only on:
      - state_vector(t-dt)
      - inputs(t-dt, t)
      - parameter vector Θ
      - random_seed (if stochastic noise enabled)
    
    NO dependence on future values: state(t) ⊥ input(t+dt)
  
  I18-NO-INFORMATION-LOSS: ∀ neuron n:
    Discretization error < tolerance
    Given neuron_snapshot(t), can reconstruct:
      - Approximate trajectory from t-dt to t
      - Approximate V(t + ε) for small ε
  
  I18-REPLAY-GUARANTEE: ∀ run₁, run₂:
    if (state(0), Θ, I, seed) identical in run₁ and run₂:
      then ∀ t: state(t) in run₁ == state(t) in run₂  [up to floating-point ε]
      AND ∀ t: output(t) in run₁ == output(t) in run₂
```

#### Verification Criteria

**PASS:** Determinism fully achieved:

✓ **VC18-A:** Identical initial state + inputs → identical spike sequence
  - Setup: Initialize two runs with identical state(0), Θ, I, seed
  - Execution: Run both simulations to t=T
  - Comparison: Compare spike_events logs bit-for-bit
  - Tolerance: Floating-point difference < 1e-9 (PASS); > 1e-6 (FAIL)

✓ **VC18-B:** ODE solver produces consistent results
  - Bench: Known Hodgkin-Huxley reference solution (e.g., from published neuroscience sim)
  - Compare: Phase 4 RK4 output at t=1 ms, t=10 ms, t=100 ms
  - Error bounds: |V_phase4(t) - V_reference(t)| < 1 mV (acceptable HH error)

✓ **VC18-C:** Event queue processing order is deterministic
  - Inspection: Event queue uses deterministic priority (timestamp, then source_id)
  - Tied events: When two events have same timestamp, specify ordering rule
  - Replay: Process events in identical order across runs

✓ **VC18-D:** No unlogged randomness
  - Search codebase: Grep for random.* (excluding seeded PRNG)
  - Verify: All stochastic operations (if any) use fixed seed at initialization
  - Channel noise: If enabled, must be seeded from run_seed

✓ **VC18-E:** State snapshot sufficiency
  - Log format: Verify neuron_snapshot includes:
    - V, m, h, n (all gating variables)
    - neuromodulator_state (dopamine, acetylcholine, serotonin, ...)
    - spike_count, last_spike_time, refractory_until
    - All postsynaptic current contributors (synapse_id, current_value)
  - Reconstruction: Given snapshot at t₀, can compute state at t₀+dt without external reference

✓ **VC18-F:** Stimulus logging complete
  - Verify: Exact timing and amplitude of all sensory inputs recorded
  - Comparison: Replay uses identical stimulus sequence

✓ **VC18-G:** Floating-point consistency
  - Analysis: All arithmetic operations use consistent precision (float64)
  - Solver parameters: dt = 0.01 ms (fixed), integration method = RK4 (fixed)
  - Comparison tolerance: Allow ε < 1e-6 in spike timing (~ 0.6 μV at 100 mV scale)

**FAIL:** Any non-determinism, including:
- Same initial state, different spike sequences
- Time-dependent randomness: seed(t) varies during run
- Non-reproducible floating-point (different rounding order)
- Incomplete state logs (missing neuromodulator_state or postsynaptic currents)
- Stimulus not fully logged

---

### INVARIANT I19: NEUROTRANSMITTER/RECEPTOR TRACEABILITY

#### Specification

**Claim:** Every spike carries neurotransmitter type (glutamate, dopamine, etc.). Every synapse carries receptor type (AMPA, NMDA, D1, D2, etc.). Incompatible NT/receptor pairs are explicitly rejected.

#### Formal Definition

```
∀ synapse s = (source_id, target_id, CAT-S-ID):
  I19-NT-ASSIGNED: ∃! neurotransmitter_type(s) ∈ {Glutamate, GABA, Dopamine, Serotonin, Acetylcholine, ...}
  
  I19-RECEPTOR-ASSIGNED: ∃! receptor_type(s) ∈ {AMPA, NMDA, GABA-A, GABA-B, D1, D2, 5HT1A, 5HT2A, ...}
  
  I19-COMPATIBILITY: (neurotransmitter_type(s), receptor_type(s)) ∈ COMPATIBLE_PAIRS
  
  where COMPATIBLE_PAIRS = {
    (Glutamate, AMPA), (Glutamate, NMDA),
    (GABA, GABA-A), (GABA, GABA-B),
    (Dopamine, D1), (Dopamine, D2),
    (Serotonin, 5HT1A), (Serotonin, 5HT2A),
    (Acetylcholine, M1), (Acetylcholine, M2), (Acetylcholine, N),
    ...
  }

∀ spike_event e = (source_neuron_id, timestamp):
  I19-SPIKE-NT: ∃ neurotransmitter_type(e) ∈ delivered_by_synapses(source_neuron_id)
  
  I19-SPIKE-TRACEABILITY: ∀ synapse s with source == source_neuron_id:
    spike_event_payload(e).neurotransmitter_type(s) ∈ {known transmitter types}
    spike_event_payload(e).receptor_type(s) ∈ {known receptor types}
    
  I19-INCOMPATIBILITY-REJECTION: ∄ event delivery where:
    (NT_type, receptor_type) ∉ COMPATIBLE_PAIRS

∀ behavioral_output b:
  I19-ACTION-NT-TRACE: All synapses in upstream trace of b have valid (NT, receptor) pairs
```

#### Verification Criteria

**PASS:** All neurotransmitter/receptor assignments valid:

✓ **VC19-A:** Synapse registry completeness
  - Scan: Every CAT-S-ID has assigned neurotransmitter_type and receptor_type
  - Coverage: Synapses cover all major transmission types
    - Count: glutamatergic synapses (should be majority, ~80%)
    - Count: GABAergic synapses (should be ~15%)
    - Count: neuromodulatory (dopamine, serotonin, etc., ~5%)

✓ **VC19-B:** Compatibility validation
  - Load COMPATIBLE_PAIRS lookup table
  - Verify: Every synapse (NT_type, receptor_type) pair in table
  - Failure mode: Log any synapse with incompatible pair (should be 0)
  - Example incompatibilities to catch:
    - (Glutamate, GABA-A) — wrong transmitter
    - (Dopamine, AMPA) — wrong receptor
    - (GABA, D1) — wrong both

✓ **VC19-C:** Spike event NT assignment
  - Log scan: Every spike_event contains neurotransmitter_type field
  - Consistency: spike_event.NT_type matches synapse.NT_type for source neuron
  - Verification: For each spike_event from CAT-N-042:
    - Identify all output synapses of CAT-N-042
    - Verify NT_type in spike_event ∈ {NT_types of output synapses}

✓ **VC19-D:** Event delivery NT/receptor consistency
  - Event queue inspection: PostsynapticEvent contains both neurotransmitter and receptor_type
  - Consistency check: (NT, receptor) pair from PostsynapticEvent matched to synapse definition
  - Incompatibility detection: If (NT, receptor) ∉ COMPATIBLE_PAIRS, flag as error

✓ **VC19-E:** Behavioral output NT traceability
  - ActionTrace analysis: For each action, trace back through upstream_synapses
  - Verify: Every synapse in upstream trace has valid (NT, receptor) pair
  - Transitivity: If action = pounce, trace: motor_neuron → [upstream synapses with valid NT/receptor] → sensory neurons

✓ **VC19-F:** Receptor kinetics implementation
  - Code verification: Each receptor_type has corresponding kinetic model
  - Parameters: AMPA (fast, ~1 ms), NMDA (slow, ~50 ms), GABA-A (fast, ~10 ms), etc.
  - State evolution: dr/dt = α * NT * (1 - r) - β * r implemented correctly

**FAIL:** Any mismatch, including:
- Synapse with unassigned NT_type or receptor_type
- Incompatible (NT, receptor) pair (e.g., Dopamine→AMPA)
- Spike event with NT_type not matching source neuron synapses
- PostsynapticEvent with mismatched (NT, receptor)
- Receptor kinetics not implemented for assigned type

---

### INVARIANT I20: BEHAVIORAL OUTPUT TRACEABILITY

#### Specification

**Claim:** Every behavior traces back to source neuron CAT-N-ID. Every spike traces back to source neuron CAT-N-ID. No anonymous computation layers.

#### Formal Definition

```
∀ behavioral_output b at timestamp t:
  I20-BEHAVIOR-TRACED: ∃ trace_path P = [
    motor_neuron(b) →(CAT-S-x)→ upstream_neuron₁ →(CAT-S-y)→ ... →(CAT-S-z)→ source_neuron_s
  ]
  
  where:
    - motor_neuron(b) = neuron commanding this behavior (CAT-N-motor-xxx)
    - All intermediate edges labeled with CAT-S-ID
    - source_neuron_s = origin neuron (CAT-N-ID)
    - Trace is acyclic (DAG) within the action's time window [t₀, t]
  
  I20-SPIKE-SOURCE: ∀ spike_event e at time t:
    e.source_neuron_id = CAT-N-ID (explicit neuron)
    ¬∃ anonymous_layer generating e
    
  I20-DEPTH-BOUNDED: Trace depth from behavior to source ≤ 100 synapses (reasonable bound)
  
  I20-NO-AGGREGATION-LAYERS: Trace contains only:
    - Individual neurons (CAT-N-ID)
    - Individual synapses (CAT-S-ID)
    - Individual spikes
    
    NO aggregation nodes (e.g., "layer average", "mean firing rate pool")
  
  I20-WEIGHT-ATTRIBUTION: ∀ upstream synapse s in trace:
    ∃ weight_attribution(s) = fractional contribution to behavior_intensity
    Σ weights = 1.0 (conservation)

∀ spike_event s:
  I20-SPIKE-EXPLICIT-SOURCE: s.source_neuron_id is explicit CAT-N-ID
  I20-NO-EMERGENT-SPIKES: ¬∃ spike generated by "emergent property" without source
  I20-SYNAPSE-PROPAGATION: s is delivered through explicit synapses only
```

#### Verification Criteria

**PASS:** All behaviors fully traceable:

✓ **VC20-A:** Behavior → source neuron path exists
  - Test case: Run simulation, observe behavior (e.g., "POUNCE_LEFT", intensity 0.85)
  - Trace: Extract ActionTrace log entry
  - Verify: source_neurons field lists explicit CAT-N-ID values (not aggregates)
  - Upstream check: Verify all upstream synapses have CAT-S-ID

✓ **VC20-B:** No anonymous computation layers
  - Code review: Search for:
    - "aggregate", "pool", "mean", "average" in state representation
    - Implicit layers not represented as neurons
  - Specification review: All computation must pass through explicit neurons/synapses
  - Example FAIL: "cortical layer average = mean(all_V in layer)" → violates I20

✓ **VC20-C:** Spike source always explicit
  - Spike log verification: Every spike_event.source_neuron_id ∈ {CAT-N-001, ..., CAT-N-158}
  - No wildcard sources: ¬∃ spike with source_neuron_id = NULL or "emergent"
  - Traceability: Can identify exact neuron that fired

✓ **VC20-D:** Trace path reconstruction possible
  - Simulation: Run with logging_tier = 3 (all states)
  - Extract behavior: motor_cortex neuron fires, triggers behavior
  - Backward trace: Follow each synapse upstream
  - Verify: Can construct complete path neuron → synapse → neuron → ... → source

✓ **VC20-E:** Trace depth bounded
  - Measure: For all behaviors in run, compute trace depth
  - Max depth: ≤ 100 synapses (reasonable connectivity bound)
  - FAIL if: Trace has cycles or infinite depth (indicates design issue)

✓ **VC20-F:** Weight attribution conservation
  - Analysis: ActionTrace.source_neurons contains:
    - neuron_id
    - weight_in_output (fractional contribution to action)
  - Verify: Σ weights ≈ 1.0 (allow ±0.01 for floating-point)
  - Example: [neuron_A: 0.4, neuron_B: 0.3, neuron_C: 0.3] → sum = 1.0 ✓

✓ **VC20-G:** Spike event propagation is synapse-explicit
  - Event queue inspection: Every PostsynapticEvent includes:
    - source_neuron_id (CAT-N-ID)
    - synapse_id (CAT-S-ID)
    - target_neuron_id (CAT-N-ID)
  - Verify: No events with NULL synapse_id or implicit routing

**FAIL:** Any anonymous computation, including:
- Behavior with source_neurons = empty list
- Aggregation layer (e.g., "layer pooling neuron" not in registry)
- Spike without source_neuron_id (source = NULL or "collective")
- Trace depth > 100 synapses (indicates hidden aggregation)
- Weight attribution sum ≠ 1.0 ± 0.01

---

## PART 2: ADVERSARIAL ATTACK SCENARIOS

### ATTACK A: SILENT NEURON MERGE/AGGREGATION

#### Threat Model

Attacker silently merges neurons during state snapshots. Example: Instead of logging 158 distinct neurons, implementation aggregates 20 neurons into "cortical layer pool" neuron, reducing to ~140 unique neurons in state logs.

#### Concrete Failure Modes

**Failure Mode A1: Implicit Layer Pooling**

```
Phase 3 design: 158 neurons, all tracked individually
Phase 4 execution: State snapshots aggregate layer 4 neurons (CAT-N-050..CAT-N-070)
                   into single "layer_4_pool" entry with mean_potential

Result:
- spike_log contains CA-N-050, CAT-N-051, ... (all 21 neurons)
- BUT state_snapshot_tier3 contains 137 unique entries (layer_4 merged to 1)
- False positive: Different counts in different log types
- Traceability breaks: Which original neuron fired? Unknown.
```

**Test Case A1:**

```
Setup:
  - Load neuron registry (count = 158)
  - Run simulation with logging_tier = 3
  - Count unique neuron_ids in state_snapshots
  
Expected:
  - unique_count == 158 (every neuron appears)
  - Each neuron has individual entry
  
Adversarial Setup:
  - Modify state snapshot handler to aggregate neurons in "layer_4_visual_cortex"
  - Layer 4 neurons → single entry: {layer_4_pool_neuron, mean_V, mean_spike_rate}
  
Detection:
  - Run test: Count unique neuron_ids = 138 (< 158)
  - Flag: FAIL — neuron aggregation detected
```

**Failure Mode A2: Sparse State Logs**

```
Phase 4 logs only "active" neurons (V > threshold), omitting silent neurons

Result:
- 158 neurons exist in registry
- Only 80 neurons appear in state logs (rest silent)
- Behavioral trace reaches 80 neurons, but 78 neurons invisible
- False negative: Contribution of silent neurons unaccounted for
```

**Test Case A2:**

```
Setup:
  - Populate network with constant sensory input
  - All neurons should have some activity (even subthreshold)
  
Expected:
  - Logging_tier = 3: All 158 neurons logged at every timestep
  - Missing neurons indicate silence (V ≈ resting potential)
  
Adversarial Setup:
  - Modify logger to skip "inactive" neurons (arbitrary threshold)
  - Silent neurons don't appear in logs
  
Detection:
  - Count unique neurons in state logs over full run
  - If count < 158, check: are missing neurons truly silent?
  - Verify resting potential entry for each neuron (no omissions)
```

#### Verification Strategies

**VS-A1: Neuron Registry Reconciliation**

```
Procedure:
  1. Extract neuron_registry (initialization): set R = {CAT-N-001, ..., CAT-N-158}
  2. Extract all neuron_ids from state_logs: set S = unique(state_log.neuron_id)
  3. Extract all neuron_ids from spike_logs: set K = unique(spike_log.source_neuron_id)
  4. Extract all neuron_ids from behavior traces: set B = unique(trace.source_neuron)
  
  5. Check:
     - R == S (state logs contain all registered neurons)
     - K ⊆ R (spike logs only contain registered neurons)
     - B ⊆ R (behavior traces only contain registered neurons)
     - |S| == 158 (complete coverage)
  
  If all checks pass: PASS (no aggregation detected)
  If any check fails: FAIL (aggregation or registration mismatch)
```

**VS-A2: State Coverage Audit**

```
Procedure:
  1. For each neuron n ∈ R:
     a. Search state_log for entries with neuron_id = n
     b. If found: mark n as "logged"
     c. If not found: verify n is silent (never spikes, V = resting)
     
  2. For "silent" neurons, verify they appear at least once in logs:
     - Check logging_tier: if tier >= 2, silent neurons should appear at t=0, every 10 ms
     - If tier = 3, every timestep
     
  3. Count coverage_ratio = #logged_neurons / 158
     - If coverage_ratio < 1.0, identify missing neurons
     - Verify each missing neuron is legitimately silent (logs show resting V)
```

---

### ATTACK B: SYNAPSE LOSS OR CREATION

#### Threat Model

Attacker modifies synapse registry without updating spike propagation. Example: CAT-S-050 marked as "not delivered" or new synapse CAT-S-103 created to bypass restrictions.

#### Concrete Failure Modes

**Failure Mode B1: Synapse Silenced (Marked "Not Delivered")**

```
Phase 3 design: Synapse CAT-S-050 (Motor → Proprioceptive, feedback loop)
Phase 4 execution: CAT-S-050 in registry but marked "delivery_enabled = false"

Result:
- Event queue never enqueues CAT-S-050 events
- Feedback loop broken, but structure intact
- Recurrent connectivity preserved (I1) but non-functional (violates I17)
- Behavioral output loses proprioceptive feedback → motor commands ignore body state
```

**Test Case B1:**

```
Setup:
  - Identify all feedback synapses in registry (should have delivery_enabled = true)
  - Run simulation with motor cortex driving movement
  
Expected:
  - Event queue contains events for CAT-S-050
  - Spike log shows spike delivery via CAT-S-050
  - Motor neuron output decreases when proprioceptive feedback arrives (sensory-motor coupling)
  
Adversarial Setup:
  - Set CAT-S-050.delivery_enabled = false
  - Keep synapse in registry but skip event_queue.push(CAT-S-050 event)
  
Detection:
  - Verify: Motor behavior unaffected by proprioceptive input (should be affected)
  - Check: Event queue has NO events with synapse_id = CAT-S-050
  - Check: Spike log shows motor neuron firing but proprioceptive neuron never receives feedback
  - Flag: FAIL — synapse silenced
```

**Failure Mode B2: Synapse Created (New Edge)**

```
Phase 3 design: 102 synapses
Phase 4 execution: New synapse CAT-S-103 created (Motor → Hypothalamus shortcut)

Result:
- Graph topology changed: 103 edges instead of 102
- Behavioral output bypasses sensory processing (direct motor→motivation)
- False positive: Behavior appears to originate from independent source neuron
- Violates I1 (graph preservation)
```

**Test Case B2:**

```
Setup:
  - Load synapse registry at initialization: count = 102
  - Run simulation, extract all synapses used
  
Expected:
  - Final synapse count == 102
  - No new synapses in event_queue
  - All synapses in use are in registry
  
Adversarial Setup:
  - During execution, create new synapse CAT-S-103 (Motor → Hypothalamus)
  - Enqueue events with CAT-S-103
  - Motor command now directly modulates motivation
  
Detection:
  - Final synapse count check: Extract all unique synapse_ids from logs
  - If count > 102, identify new synapses
  - Compare against registry: Is CAT-S-103 registered? (should be NO)
  - Flag: FAIL — synapse created outside registry
```

**Failure Mode B3: Synapse Deletion**

```
Phase 3 design: Synapse CAT-S-050 (Motor → Proprioceptive)
Phase 4 execution: CAT-S-050 removed from registry entirely

Result:
- Graph topology changed: 101 edges instead of 102
- Feedback loop structurally eliminated
- Violates I17 (recurrent connectivity lost)
```

**Test Case B3:**

```
Setup:
  - Load synapse registry: identify CAT-S-050
  - Run simulation with sensorimotor loop active
  
Expected:
  - CAT-S-050 appears in spike logs (events delivered)
  - Proprioceptive neuron receives motor feedback
  
Adversarial Setup:
  - Remove CAT-S-050 from registry
  - Never enqueue events for CAT-S-050
  - Motor neuron fires but proprioceptive never receives signal
  
Detection:
  - Count synapses at end: should be 102
  - Identify CAT-S-050 in expected feedback synapses: is it missing?
  - Check spike logs for motor → proprioceptive delivery: should be present
  - If no delivery events for expected synapse → Flag: FAIL — synapse deleted
```

#### Verification Strategies

**VS-B1: Synapse Registry Preservation**

```
Procedure:
  1. At t=0: Extract synapse_registry R = {(src_i, tgt_i, CAT-S-i) for i=1..102}
  2. At t=T: Extract final registry R' = {(src_j, tgt_j, CAT-S-j) for j in final_logs}
  
  3. Check:
     - |R'| == 102 (count preserved)
     - R == R' (set equality: same synapses)
     - ∀ synapse (src, tgt, ID) ∈ R: (src, tgt, ID) ∈ R' (identity preserved)
  
  If all pass: PASS (synapse registry unchanged)
  If any fails: FAIL (synapse modified or deleted)
```

**VS-B2: Event Delivery Coverage**

```
Procedure:
  1. For each synapse s ∈ registry:
     a. Identify source neurons (all neurons with s as output synapse)
     b. For each source neuron n: did n fire during simulation?
     c. If n fired: should events for s appear in event_queue logs
     
  2. Extract actual events from logs: E = {events with synapse_id from registry}
  
  3. For each expected firing:
     - Expected: Motor neuron fires → check for CAT-S-050 event with target=proprioceptive
     - Actual: Grep event logs for CAT-S-050
     - If no match: synapse silenced or deleted
     
  4. Count delivery_coverage = #synapse_used / #synapse_registry
     - If coverage < 0.8 (80%): investigate silence vs. genuinely unused synapses
```

**VS-B3: Retroactive Synapse Discovery**

```
Procedure:
  1. Extract all unique synapse_ids from spike logs: S = unique(log.synapse_id)
  2. Extract all unique synapse_ids from registry: R = unique(registry.synapse_id)
  
  3. Check:
     - S ⊆ R (all used synapses are registered)
     - S \ R = ∅ (no unregistered synapses used)
     
  4. If |S| > |R|: extra synapses found → creation attack detected
  5. If ∃ (src, tgt, ID) ∈ R but ID ∉ S: synapse silenced/deleted
  
  Report discrepancies for manual review.
```

---

### ATTACK C: NON-DETERMINISTIC COMPUTATION

#### Threat Model

Attacker introduces randomness or path-dependent rounding. Example: Same inputs produce different spike sequences across runs, breaking I18 (temporal state preservation).

#### Concrete Failure Modes

**Failure Mode C1: Non-Seeded Random Event Ordering**

```
Assumption: Event queue uses random ordering when timestamps tied
Result: Two events at t=100 ms processed in random order
        Run 1: neuron_A events first → motor output = pounce_left
        Run 2: neuron_B events first → motor output = pounce_right
```

**Test Case C1:**

```
Setup:
  - Initialize state and stimulus identically
  - Set random_seed = 42
  - Run simulation 1 → extract spike_events_1, behavior_1
  - Reset state/stimulus/seed = 42
  - Run simulation 2 → extract spike_events_2, behavior_2
  
Expected:
  - spike_events_1 == spike_events_2 (identical spike times and sources)
  - behavior_1 == behavior_2 (identical motor outputs)
  - Allow ε < 1e-9 floating-point difference
  
Adversarial Setup:
  - Modify event queue to use random ordering (no sorting by source_id on ties)
  - Same inputs, different event order → different integration → different spikes
  
Detection:
  - Compare spike logs: if divergence exists, flag first divergence point
  - If timestamp of divergence varies between runs: random ordering suspected
  - Flag: FAIL — non-deterministic event order
```

**Failure Mode C2: Floating-Point Reordering**

```
Assumption: State update order varies (e.g., different neuron order in for-loop)
Result: Floating-point arithmetic not associative; summation order matters
        Run 1: I_syn = syn_1 + syn_2 + syn_3 → rounds to 42.001 μA
        Run 2: I_syn = syn_3 + syn_2 + syn_1 → rounds to 42.002 μA
        Different rounding → different ODE result → different spike time
```

**Test Case C2:**

```
Setup:
  - Simulation with many synaptic inputs to single neuron
  - Identify neurons with 20+ input synapses
  
Expected:
  - Same I_total (total input current) regardless of summation order
  - ODE integration produces identical V(t) across runs
  
Adversarial Setup:
  - Randomize input synapse order each run
  - Floating-point sum varies by last-bit rounding
  - Spike time drifts by ±0.01 ms
  
Detection:
  - Compare spike times: if drift > 1e-6 ms, investigate
  - Re-run with fixed synapse order: does drift disappear?
  - If yes: floating-point associativity issue identified
  - Flag: PASS (acceptable rounding) or FAIL (uncontrolled drift) depending on magnitude
```

**Failure Mode C3: External Randomness**

```
Assumption: Code uses external randomness (wall-clock time, thread scheduling)
Result: run_seed not controlling all randomness
        Run 1: thread_id 1 → spikes at t=100.001 ms
        Run 2: thread_id 2 → spikes at t=100.003 ms
```

**Test Case C3:**

```
Setup:
  - Search codebase for random.*, time.time(), thread scheduling
  - Identify any external randomness sources
  
Expected:
  - No time.time() calls (use simulated time only)
  - No threading (single-threaded or deterministic barriers)
  - All randomness seeded from run_seed
  
Adversarial Setup:
  - Introduce time.time() call in ODE solver (simulate adaptive timestep)
  - Each run uses different real-world time → different adaptive dt
  
Detection:
  - Grep codebase for external randomness
  - Run replay test: does seed=42 control all randomness?
  - If seed ignored → Flag: FAIL — external randomness detected
```

#### Verification Strategies

**VS-C1: Deterministic Replay Test**

```
Procedure:
  1. Run 1:
     - Load state(0), stimulus, parameters
     - Set random_seed = 42
     - Execute simulation to t=T
     - Save: spike_log_1, state_log_1, behavior_1
     
  2. Run 2:
     - Load identical state(0), stimulus, parameters
     - Set random_seed = 42 (IDENTICAL)
     - Execute simulation to t=T
     - Save: spike_log_2, state_log_2, behavior_2
     
  3. Comparison:
     - For each spike_event: compare timestamp, source_neuron_id
     - Allow ε < 1e-9 (floating-point rounding)
     - For each behavioral_output: compare action_id, intensity
     - Allow ε < 1e-6 (action intensity rounding)
     
  4. Result:
     - If spike_log_1 == spike_log_2 (within ε): PASS
     - If divergence > ε: FAIL — non-determinism detected
     
  5. Debug divergence:
     - Find first difference point
     - Identify affected neuron/synapse
     - Compare state_log at that point
     - Trace root cause (event order? floating-point? external randomness?)
```

**VS-C2: Seed Isolation**

```
Procedure:
  1. Identify all uses of randomness in codebase (grep, static analysis)
  
  2. Verify all use seeded PRNG:
     - Random number generator initialized from run_seed
     - No unseeded calls (e.g., random.random() without seed)
  
  3. Test seed independence:
     - Simulation 1: seed = 42 → behavior_1
     - Simulation 2: seed = 43 → behavior_2
     - Simulation 3: seed = 42 → behavior_3
     
     - Verify: behavior_1 == behavior_3 (same seed → same behavior)
     - Verify: behavior_1 ≠ behavior_2 (different seed → different behavior)
     
  4. Result:
     - If behavior varies with seed but not deterministic for same seed: suspicious
     - Indicates external randomness not controlled by seed
     - Flag: FAIL
```

**VS-C3: Floating-Point Consistency**

```
Procedure:
  1. Identify all arithmetic operations affecting spike timing:
     - ODE integration: RK4 evaluation, summation
     - Synapse current aggregation: Σ g_syn * (V - E_reversal)
     
  2. For aggregation operations:
     - Test with fixed order (ascending neuron_id)
     - Test with reversed order
     - Compare results: should be identical up to rounding
     
  3. Measure rounding error:
     - error = |result_order1 - result_order2|
     - If error > 1e-10: floating-point associativity issue
     - Mitigation: use fixed order (always sort inputs before aggregation)
     
  4. Result:
     - If error < 1e-10 for all aggregations: PASS
     - If error significant: implement fixed-order aggregation
```

---

### ATTACK D: NEUROTRANSMITTER/RECEPTOR MISMATCH

#### Threat Model

Attacker bypasses compatibility checking, allowing incompatible (NT, receptor) pairs. Example: Glutamate spike delivered to dopamine receptor D1, causing "false positive" signal integration.

#### Concrete Failure Modes

**Failure Mode D1: Incompatible NT-Receptor Assignment**

```
Phase 3 design: Synapse CAT-S-080 = (source=dopamine_neuron, target=sensory, NT=Dopamine, receptor=D1)
Phase 4 execution: Accidentally configure as (NT=Dopamine, receptor=NMDA)

Result:
- NMDA receptors require Mg²⁺ block removal + sustained depolarization
- Dopamine applied to NMDA → no biological effect (incompatible)
- Motor output affected incorrectly; traceability broken
- Violates I19 (NT/receptor compatibility)
```

**Test Case D1:**

```
Setup:
  - Load synapse registry
  - Identify all (neurotransmitter_type, receptor_type) pairs
  
Expected:
  - All pairs in COMPATIBLE_PAIRS lookup table
  - Count incompatible pairs: should be 0
  
Adversarial Setup:
  - Modify synapse CAT-S-080 to assign incompatible (Dopamine, NMDA)
  - Keep all other metadata consistent
  
Detection:
  - Verify compatibility:
    for each synapse s:
      if (s.NT_type, s.receptor_type) not in COMPATIBLE_PAIRS:
        Flag: FAIL — incompatible pair found
  
  - Example FAIL:
    Synapse CAT-S-080: (Dopamine, NMDA) not in lookup → FAIL
```

**Failure Mode D2: Receptor Kinetics Mismatch**

```
Phase 3 design: Synapse CAT-S-050 uses AMPA receptor (fast kinetics, τ=1 ms)
Phase 4 execution: Accidentally load NMDA kinetics (slow, τ=50 ms) for CAT-S-050

Result:
- Spike at t=100 ms produces current lasting until t=150 ms (wrong timing)
- Downstream neuron integrates signal at wrong timescale
- Behavioral output timing affected; false positive if timing-dependent
```

**Test Case D2:**

```
Setup:
  - Identify synapses by receptor type
  - AMPA synapses: should have τ ≈ 1 ms
  - NMDA synapses: should have τ ≈ 50 ms
  
Expected:
  - Receptor kinetics consistent with receptor type
  - dr/dt = α * NT * (1 - r) - β * r with correct (α, β) for type
  
Adversarial Setup:
  - Load NMDA kinetics (α=0.01, β=0.001) for AMPA synapse (should be α=0.1, β=0.1)
  
Detection:
  - Measure response to spike:
    - AMPA spike response: peak at ~1-2 ms, decay by t=10 ms
    - NMDA spike response: peak at ~50 ms, decay by t=200 ms
  - Compare observed response against expected for receptor type
  - If mismatch: Flag — kinetics error detected
```

**Failure Mode D3: Silent Receptor Type**

```
Assumption: Synapse assigned unknown receptor type (typo or custom)
Result: Receptor kinetics not implemented → no current delivered
        Motor command appears effective but no actual synaptic transmission
        Violates I19 (traceability) — transmission attributed but not executed
```

**Test Case D3:**

```
Setup:
  - Load synapse registry
  - For each synapse, verify receptor_type is in implemented list
  
Expected:
  - receptor_type ∈ {AMPA, NMDA, GABA-A, GABA-B, D1, D2, 5HT1A, 5HT2A, M1, M2, N, ...}
  - All types have corresponding kinetic model
  
Adversarial Setup:
  - Assign synapse CAT-S-070 receptor_type = "X_receptor_v2" (custom, not implemented)
  
Detection:
  - Verify all receptor types in registry:
    for each synapse s:
      if s.receptor_type not in IMPLEMENTED_TYPES:
        Flag: FAIL — unknown receptor type, kinetics not implemented
  
  - If unimplemented: kinetic model missing → no current → silent transmission
```

#### Verification Strategies

**VS-D1: Compatibility Matrix Check**

```
Procedure:
  1. Load COMPATIBLE_PAIRS matrix:
     {(Glutamate, AMPA), (Glutamate, NMDA), (GABA, GABA-A), ...}
  
  2. For each synapse s in registry:
     - Extract (s.neurotransmitter_type, s.receptor_type)
     - Check: Is pair in COMPATIBLE_PAIRS?
     - If NO: Flag synapse as INCOMPATIBLE
     
  3. Report:
     - Incompatible synapses count: should be 0
     - If count > 0: list all incompatible pairs with synapse IDs
     
  4. Result:
     - If incompatible_count == 0: PASS
     - Else: FAIL — incompatibility detected
```

**VS-D2: Kinetics Validation**

```
Procedure:
  1. For each receptor type, load kinetic parameters:
     - AMPA: α=0.1, β=0.1, τ=1 ms
     - NMDA: α=0.01, β=0.001, τ=50 ms
     - GABA-A: α=0.1, β=0.3, τ=10 ms
     - ... (for all types)
  
  2. For each synapse s with receptor type R:
     - Extract (α, β) from code or config for R
     - Verify (α, β) match expected values for R
     - Measure response: dr/dt = α * NT * (1 - r) - β * r
     
  3. Test: Send spike to synapse, measure response
     - AMPA: peak response at ~1 ms ± 0.5 ms
     - NMDA: peak response at ~50 ms ± 5 ms
     - Verify peak timing matches receptor type
     
  4. Result:
     - If all timing correct: PASS
     - If timing mismatch: FAIL — kinetics error
```

**VS-D3: Receptor Type Coverage**

```
Procedure:
  1. Load receptor types used in registry: used_types = unique(synapse.receptor_type)
  
  2. Load implemented receptor types in kinetics module: impl_types = {AMPA, NMDA, ...}
  
  3. Check coverage:
     - used_types ⊆ impl_types (all used types implemented)
     - If ∃ type in used_types not in impl_types: unimplemented type detected
     
  4. For each unimplemented type:
     - Identify affected synapses
     - Verify: are they receiving current in logs? (should be 0 if unimplemented)
     - If current > 0: kinetics model missing but current applied (error)
     
  5. Result:
     - If used_types ⊆ impl_types: PASS
     - Else: FAIL — unimplemented receptor type(s)
```

---

### ATTACK E: BEHAVIORAL OUTPUT LACKING NEURAL TRACEABILITY

#### Threat Model

Attacker creates "emergent" behaviors not traceable to source neurons. Example: Behavioral output "POUNCE" generated without clear upstream synapse/neuron chain.

#### Concrete Failure Modes

**Failure Mode E1: Implicit Layer Aggregation in Behavior**

```
Phase 3 design: Motor output from motor_cortex neurons (CAT-N-motor-001, ..., CAT-N-motor-050)
Phase 4 execution: Behavioral output aggregates "motor_cortex_population" firing

Result:
- Behavior record: {action_id: POUNCE, source_neurons: ["cortex_layer_5"]}
- "cortex_layer_5" is aggregate, not individual neuron
- Cannot trace action to specific CAT-N-ID
- Violates I20 (traceability)
```

**Test Case E1:**

```
Setup:
  - Run simulation with motor command
  - Extract behavioral output logs
  
Expected:
  - Each behavioral output has source_neurons field
  - Each element ∈ {CAT-N-001, ..., CAT-N-158}
  - No aggregate terms like "layer_5" or "population_average"
  
Adversarial Setup:
  - Modify behavior aggregation to use layer terms
  - source_neurons = ["motor_cortex_layer_5"] instead of individual CAT-N-IDs
  
Detection:
  - For each behavioral output b:
    - For each source_neuron_id in b.source_neurons:
      - Verify: neuron_id ∈ registry (specific CAT-N-ID)
      - Flag if: neuron_id contains "layer", "population", "aggregate"
  
  - If any aggregate term found: FAIL — non-specific source
```

**Failure Mode E2: Empty or Null Source Trace**

```
Phase 3 design: All behaviors traceable to source neurons
Phase 4 execution: Certain behaviors generated with empty source_neurons list

Result:
- Behavior: {action_id: POUNCE, source_neurons: []}
- No trace available
- Violates I20 — behavior without source
```

**Test Case E2:**

```
Setup:
  - Run simulation, collect all behavioral outputs
  
Expected:
  - Every output has source_neurons field with ≥ 1 element
  - source_neurons not empty, not null
  
Adversarial Setup:
  - Modify behavior logger to omit source neurons for certain actions
  - source_neurons = [] for action_id = "POUNCE"
  
Detection:
  - For each behavioral output b:
    - Check: len(b.source_neurons) > 0
    - If empty: Flag — no source trace
  
  - If any output with empty source_neurons: FAIL — anonymous behavior
```

**Failure Mode E3: Disconnected Trace**

```
Assumption: Trace path has gap (neuron A → [missing synapse] → neuron B)
Result: Behavioral output claims source A and target B, but no synapse connects them
        Violates causal connectivity in I20
```

**Test Case E3:**

```
Setup:
  - For each behavioral output, extract source_neurons list
  - Trace upstream synapses
  
Expected:
  - Trace forms connected path: motor_neuron → syn → upstream_neuron → syn → ... → source
  - No gaps in connectivity
  
Adversarial Setup:
  - Create trace with gap: [CAT-N-motor, CAT-N-sensory] but no synapse between them
  - Behavioral output lists both as contributing
  
Detection:
  - Verify connectivity:
    for each consecutive pair (n_i, n_j) in trace:
      - Verify: ∃ synapse (n_i, n_j) OR ∃ synapse (n_j, n_i)
      - If not: gap detected
  
  - If gap found: FAIL — disconnected trace
```

**Failure Mode E4: Circular Trace**

```
Assumption: Trace contains cycle (neuron A → ... → neuron A within action time window)
Result: Behavioral output attributes action to circular path (physically impossible)
        Violates DAG structure within action's temporal window
```

**Test Case E4:**

```
Setup:
  - Extract trace for behavioral output b
  - Represent as DAG (neuron → synapse → neuron)
  
Expected:
  - DAG is acyclic within temporal window [t_action_start, t_action]
  
Adversarial Setup:
  - Modify trace to include cycle: A → B → C → A
  
Detection:
  - Topological sort on trace DAG
  - If sort fails (cycle detected): FAIL — circular trace
  - Report cycle: which neurons/synapses form loop
```

#### Verification Strategies

**VS-E1: Source Neuron Specificity**

```
Procedure:
  1. For each behavioral output b:
     - Extract source_neurons list
     - For each element s:
       a. Check: s matches CAT-N-### format
       b. Check: s ∈ registry
       c. Check: s is NOT aggregate term ("layer", "population", "area", "region")
     
  2. If any source fails checks:
     - Flag: non-specific or unregistered source
     
  3. Collect statistics:
     - Total behaviors: N_b
     - Behaviors with unspecific source: N_unspec
     - Ratio: unspec_ratio = N_unspec / N_b
     - If ratio > 0: FAIL
```

**VS-E2: Trace Completeness**

```
Procedure:
  1. For each behavioral output b:
     a. Extract upstream_synapses field (ActionTrace.upstream_synapses)
     b. Count synapses: N_syn = len(upstream_synapses)
     
  2. Verify connectivity:
     for each synapse s in upstream_synapses:
       - Verify s ∈ registry (registered)
       - Verify s.source_neuron AND s.target_neuron exist
       
  3. Build trace graph:
     - Nodes: all neurons in trace
     - Edges: all synapses in trace
     - Check: form connected DAG from motor_neuron to source_neuron
     
  4. If connectivity incomplete:
     - Flag: FAIL — broken trace
     - Report missing synapses
```

**VS-E3: Weight Attribution Validation**

```
Procedure:
  1. For each behavioral output b:
     - Extract source_neurons with weight_in_output field
     - weights = [w_1, w_2, ..., w_n]
     
  2. Verify conservation:
     - sum_weights = Σ weights
     - Check: 0.99 ≤ sum_weights ≤ 1.01 (allow rounding)
     - If outside range: FAIL — weight sum violated
     
  3. Verify non-negativity:
     - For each w_i: verify w_i ≥ 0
     - If any w_i < 0: FAIL — negative weight
     
  4. Verify reasonable distribution:
     - max_weight = max(weights)
     - min_weight = min(weights)
     - If max_weight > 0.99: single neuron dominates (check if expected)
     - If min_weight ≈ 1/n: weights too uniform (check if expected)
```

**VS-E4: Trace DAG Validation**

```
Procedure:
  1. For each behavioral output b:
     a. Extract trace: motor_neuron → [synapses] → source_neurons
     b. Build directed graph: G = (V, E) where V = neurons, E = synapses
     
  2. Check acyclicity:
     - Perform topological sort on G
     - If sort succeeds: PASS (DAG)
     - If sort fails: cycles detected
     
  3. If cycles found:
     - Extract cycle: [n_1, n_2, ..., n_k, n_1]
     - Report cycle with timestamps
     - Flag: FAIL — circular trace violates temporal causality
     
  4. Measure trace depth:
     - depth = longest path from motor_neuron to source
     - If depth > 100: investigate (likely hidden aggregation)
```

---

## PART 3: VERIFICATION CHECKLIST

### Master Checklist

| Invariant | Criterion | Expected | Actual | Status | Evidence |
|-----------|-----------|----------|--------|--------|----------|
| I1 | VC1-A: Neuron count preserved | 158 neurons | TBD | PENDING | registry_snapshot.txt |
| I1 | VC1-B: Synapse count preserved | 102 synapses | TBD | PENDING | synapse_registry.csv |
| I1 | VC1-C: No premature neuron spawning | 0 unregistered IDs | TBD | PENDING | log_audit.txt |
| I1 | VC1-D: Event queue uses registered IDs | 0 orphaned targets | TBD | PENDING | event_queue_audit.txt |
| I1 | VC1-E: Behavior traces use registered IDs | 100% coverage | TBD | PENDING | action_trace_audit.txt |
| I17 | VC17-A: Feedback connectivity preserved | All feedback synapses present | TBD | PENDING | feedback_synapse_check.txt |
| I17 | VC17-B: No cycle elimination | Same cycles at init and final | TBD | PENDING | cycle_graph_comparison.txt |
| I17 | VC17-C: Synaptic delays all > 0 ms | min(delays) ≥ 0.1 ms | TBD | PENDING | delay_distribution.csv |
| I17 | VC17-D: Cycle latency ≥ 1 ms | All round-trips ≥ 1 ms | TBD | PENDING | cycle_latency_log.txt |
| I17 | VC17-E: Bidirectional firing observed | Both directions fire | TBD | PENDING | bidirectional_spike_log.txt |
| I18 | VC18-A: Replay produces identical spikes | spike_log_1 == spike_log_2 | TBD | PENDING | replay_comparison.txt |
| I18 | VC18-B: ODE solver benchmarks | |V_phase4 - V_ref| < 1 mV | TBD | PENDING | ode_solver_bench.txt |
| I18 | VC18-C: Event queue deterministic | Same priority order both runs | TBD | PENDING | event_queue_order_check.txt |
| I18 | VC18-D: No unlogged randomness | 0 unseeded PRNG calls | TBD | PENDING | random_audit.txt |
| I18 | VC18-E: State snapshots sufficient | Can reconstruct next state | TBD | PENDING | state_reconstruction_test.txt |
| I18 | VC18-F: Stimulus fully logged | 100% stimulus in logs | TBD | PENDING | stimulus_audit.txt |
| I18 | VC18-G: Floating-point consistent | All runs differ < 1e-6 | TBD | PENDING | precision_audit.txt |
| I19 | VC19-A: Synapse registry complete | 0 unassigned NT/receptor | TBD | PENDING | synapse_assignment_check.txt |
| I19 | VC19-B: All pairs compatible | 0 incompatible pairs | TBD | PENDING | compatibility_matrix_check.txt |
| I19 | VC19-C: Spike NT consistent | All spikes match source NT | TBD | PENDING | spike_nt_consistency.txt |
| I19 | VC19-D: Event delivery NT/receptor valid | 0 incompatible deliveries | TBD | PENDING | event_compatibility_check.txt |
| I19 | VC19-E: Behavioral output NT traceable | All actions have NT trace | TBD | PENDING | behavior_nt_trace_audit.txt |
| I19 | VC19-F: Receptor kinetics implemented | All assigned types have τ | TBD | PENDING | kinetics_implementation_check.txt |
| I20 | VC20-A: Behavior → source path exists | All behaviors traced | TBD | PENDING | action_trace_completeness.txt |
| I20 | VC20-B: No anonymous layers | 0 aggregate terms in traces | TBD | PENDING | trace_specificity_audit.txt |
| I20 | VC20-C: Spike source explicit | All spikes have source_id | TBD | PENDING | spike_source_audit.txt |
| I20 | VC20-D: Trace reconstruction possible | Can rebuild paths | TBD | PENDING | trace_reconstruction_test.txt |
| I20 | VC20-E: Trace depth bounded | All traces ≤ 100 synapses | TBD | PENDING | trace_depth_analysis.txt |
| I20 | VC20-F: Weight attribution conserves | All sums ≈ 1.0 | TBD | PENDING | weight_conservation_check.txt |
| I20 | VC20-G: Spike event routing explicit | 0 NULL synapse_ids | TBD | PENDING | spike_routing_audit.txt |

---

## PART 4: AUDIT SIGN-OFF

### FORMAL VERIFICATION STATUS

**Current Phase:** Specification Complete, Execution Pending

**Verification Framework Authority:** This document (FORMAL_VERIFICATION_FRAMEWORK_PHASE4.md)

**Scope:** Invariants I1, I17-I20 across all PHASE 4 execution pathways

**Test Harness:** 
- Adversarial attack scenarios (5 categories, 13 failure modes)
- Verification strategies (12 specific procedures)
- Master checklist (31 verification criteria)

### REQUIRED SIGN-OFF ACTIONS

Before PHASE 4 can proceed to production, the following must be completed:

1. **Implementation Audit** (Formal Verification Team)
   - Run all verification strategies (VS-A1 through VS-E4) against Phase 4 code
   - Generate evidence files for each criterion in master checklist
   - Document any failures with root cause analysis

2. **Adversarial Testing** (Security Team)
   - Execute each attack scenario (A1-A2, B1-B3, C1-C3, D1-D3, E1-E4)
   - Verify Phase 4 implementation rejects all attacks
   - Document defense mechanisms for each attack

3. **Determinism Certification** (Performance Team)
   - Run deterministic replay test (VS-C1) 1000+ times with different seeds
   - Measure floating-point consistency (VS-C3)
   - Certify bit-reproducible behavior on target hardware

4. **Traceability Validation** (Domain Experts)
   - Verify neurotransmitter/receptor assignments against neuroscience literature
   - Validate behavioral output traces against known neural circuits
   - Confirm trace depth and complexity realistic

### CONDITIONAL APPROVAL SCENARIOS

#### Condition 1: Minor Floating-Point Rounding
**Scenario:** Replay test shows ε < 1e-6 ms in spike timing (floating-point noise)  
**Decision:** APPROVED with caveat: document rounding tolerance; use fixed arithmetic in critical paths

#### Condition 2: Incomplete Neuromodulator Tracing
**Scenario:** Some neuromodulator effects not fully logged  
**Decision:** CONDITIONAL: implement complete logging before production; document current gaps

#### Condition 3: Trace Depth Occasionally > 100 Synapses
**Scenario:** Some behavioral traces reach 120 synapses (polysynaptic circuits)  
**Decision:** APPROVED with adjustment: increase trace depth bound to 150 synapses; verify no hidden aggregation

### BLOCKING ISSUES

The following MUST be resolved before sign-off:

**Block 1: Non-Deterministic Event Queue Ordering**
- If replay test shows different event processing order: FAILED
- Remedy: Implement deterministic priority queue (timestamp, source_id) and re-test

**Block 2: Anonymous Computation Layers**
- If behavioral traces contain aggregate neurons: FAILED
- Remedy: Replace aggregates with explicit neurons; trace every computation step

**Block 3: Neuron Count Drift**
- If any state log shows neuron count ≠ 158: FAILED
- Remedy: Implement neuron registry invariant checks; fail fast on drift

**Block 4: Incompatible NT-Receptor Pairs**
- If any synapse has (NT, receptor) ∉ COMPATIBLE_PAIRS: FAILED
- Remedy: Implement compatibility enforcement at synapse creation time

---

### FINAL AUDIT DECISION

**AUDIT STATUS:** SPECIFICATION COMPLETE, AWAITING IMPLEMENTATION VERIFICATION

**Signed by:** ORCHESTRATOR-2 (Formal Verification + Adversarial Auditor)  
**Authority:** Independent verification framework  
**Date:** 2026-09-13  
**Version:** 1.0 (Final Specification)

**Next Steps:**
1. Implementation team runs verification framework against Phase 4 code
2. Evidence files collected per master checklist
3. Adversarial attack tests executed
4. Results reported to audit team
5. Final sign-off determination: APPROVED / CONDITIONAL / BLOCKED

---

## APPENDIX A: COMPATIBILITY MATRIX

```
NEUROTRANSMITTER × RECEPTOR COMPATIBILITY

Glutamate:
  ✓ AMPA (fast excitation, τ ≈ 1 ms)
  ✓ NMDA (slow excitation, τ ≈ 50 ms, Mg²⁺-dependent)
  ✓ Kainate
  ✓ mGluR (metabotropic)

GABA:
  ✓ GABA-A (fast inhibition, τ ≈ 10 ms)
  ✓ GABA-B (slow inhibition, τ ≈ 100 ms, Gi/o-coupled)

Dopamine:
  ✓ D1 (Gs-coupled, facilitates)
  ✓ D2 (Gi/o-coupled, inhibits)

Serotonin:
  ✓ 5HT1A (Gi/o-coupled, inhibits)
  ✓ 5HT2A (Gq-coupled, excites)
  ✓ 5HT7 (Gs-coupled, facilitates)

Acetylcholine:
  ✓ M1/M3/M5 (Gq-coupled, excites)
  ✓ M2/M4 (Gi/o-coupled, inhibits)
  ✓ nAChR Nicotinic (ionotropic, fast)

Others:
  ✓ Norepinephrine → α1/α2/β receptors
  ✓ Glycine → GlyR (inhibition)
  ✓ Histamine → H1/H2/H3/H4 receptors
  ✓ Oxytocin → OXY receptors
  ✓ Vasopressin → V1/V2 receptors

INCOMPATIBLE EXAMPLES (should never occur):
  ✗ (Glutamate, D1)
  ✗ (Dopamine, AMPA)
  ✗ (GABA, 5HT1A)
  ✗ (Serotonin, GABA-A)
```

---

## APPENDIX B: REFERENCE IMPLEMENTATION CHECKLIST

For development team:

```
Phase 4 Execution Implementation Requirements

[ ] 1. Event Queue
      [ ] Deterministic priority: (timestamp, source_id)
      [ ] No random reordering on ties
      [ ] All events timestamped explicitly
      
[ ] 2. Neuron State Management
      [ ] 158 neurons tracked individually (no aggregation)
      [ ] Complete state snapshot at every timestep (tier 3)
      [ ] Includes all neuromodulators
      
[ ] 3. Spike Detection
      [ ] Threshold crossing: V(t) > -20 mV AND V(t-dt) ≤ -20 mV
      [ ] Source neuron explicit (CAT-N-ID)
      [ ] All output synapses identified
      
[ ] 4. Event Delivery
      [ ] Synaptic delay > 0 ms (minimum 0.1 ms)
      [ ] Delivery time = spike_time + delay
      [ ] No same-timestep delivery
      
[ ] 5. Synapse Registry
      [ ] All 102 synapses present
      [ ] Neurotransmitter type assigned
      [ ] Receptor type assigned
      [ ] (NT, receptor) pair in COMPATIBLE_PAIRS
      
[ ] 6. Receptor Kinetics
      [ ] dr/dt = α * NT * (1 - r) - β * r implemented
      [ ] All receptor types have (α, β) parameters
      [ ] Kinetics applied to calculate postsynaptic current
      
[ ] 7. ODE Integration
      [ ] Hodgkin-Huxley: RK4 with dt=0.01 ms
      [ ] LIF: Euler with dt=0.01 ms
      [ ] Neuromodulation: τ_m(D), g_syn(D) computed
      
[ ] 8. Logging
      [ ] Spike events: timestamp, source_id, synapses
      [ ] State snapshots: every 1 ms (tier 3)
      [ ] Behavioral output: action, intensity, source neurons
      [ ] Action trace: upstream_synapses, weights
      
[ ] 9. Determinism
      [ ] All randomness seeded from run_seed
      [ ] No time.time() or thread scheduling
      [ ] Fixed float64 precision
      [ ] Event order deterministic
      
[ ] 10. Traceability
       [ ] Behavior → motor_neuron → source_neuron chain explicit
       [ ] No aggregate terms in traces
       [ ] Weight attribution sums to 1.0
       [ ] Trace depth ≤ 100 synapses
```

---

**END OF FORMAL VERIFICATION FRAMEWORK — PHASE 4 EXECUTION**
