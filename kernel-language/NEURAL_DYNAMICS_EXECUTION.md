# Neural Dynamics Execution Model

## Executive Summary

This specification defines the temporal execution model for neural state evolution in a recurrent neural system. It supports all connectivity patterns (feed-forward, recurrent, bidirectional feedback) through delay-based event propagation, preserves neuron (CAT-N) and synapse (CAT-S) identity throughout computation, and provides deterministic replay capability via comprehensive state logging.

**Core Principle**: Forward-time-only execution with synaptic delays breaks cycles synchronously, eliminating infinite recursion while preserving bidirectional connectivity semantics.

---

## 1. TIME EVOLUTION MODEL

### 1.1 Hodgkin-Huxley Neuron Model

**Membrane Potential Dynamics:**
```
dV/dt = (1/C) * [
  -g_Na * m³ * h * (V - E_Na)
  -g_K * n⁴ * (V - E_K)
  -g_L * (V - E_L)
  + I_input(t)
]
```

Where:
- V: membrane potential (mV)
- C: membrane capacitance (μF/cm²)
- g_X: maximal conductances (mS/cm²)
- m, h, n: gating variables (dimensionless, range [0,1])
- E_X: reversal potentials (mV)
- I_input: total synaptic + external current (μA/cm²)

**Gating Variable Dynamics:**
```
dx/dt = α_x(V) * (1 - x) - β_x(V) * x

where x ∈ {m, h, n}
```

Standard alpha/beta functions for squid axon:
```
α_m(V) = 0.1 * (V + 40) / (1 - exp(-(V + 40) / 10))
β_m(V) = 4 * exp(-(V + 65) / 18)

α_h(V) = 0.07 * exp(-(V + 65) / 20)
β_h(V) = 1 / (1 + exp(-(V + 35) / 10))

α_n(V) = 0.01 * (V + 55) / (1 - exp(-(V + 55) / 10))
β_n(V) = 0.125 * exp(-(V + 65) / 80)
```

**Numerical Integration:**
RK4 (Runge-Kutta 4th order) with dt = 0.01 ms:
```
k1 = dt * dV/dt(V, m, h, n, I_input)
k2 = dt * dV/dt(V + 0.5*k1, m + 0.5*dm1, h + 0.5*dh1, n + 0.5*dn1, I_input)
k3 = dt * dV/dt(V + 0.5*k2, m + 0.5*dm2, h + 0.5*dh2, n + 0.5*dn2, I_input)
k4 = dt * dV/dt(V + k3, m + dm3, h + dh3, n + dn3, I_input)

V(t+dt) = V(t) + (k1 + 2*k2 + 2*k3 + k4) / 6
```

**Spike Detection:**
```
SPIKE_THRESHOLD = -20 mV
if V(t) > SPIKE_THRESHOLD and V(t-dt) ≤ SPIKE_THRESHOLD:
  emit_spike_event(neuron_id, t, [affected_synapses])
  record_last_spike_time = t
```

---

### 1.2 Leaky Integrate-and-Fire (LIF) Model

**Membrane Potential Dynamics:**
```
dV/dt = -(V - E_rest) / τ_m + I_input(t) / C_m
```

Where:
- τ_m: membrane time constant (≈ 20 ms typical)
- E_rest: resting potential (≈ -70 mV)
- C_m: membrane capacitance (arbitrary units)
- I_input: integrated synaptic current

**Refractoriness:**
```
if V > V_THRESHOLD:
  emit_spike_event(neuron_id, t, [affected_synapses])
  V(t) := E_rest
  refractory_time := t + τ_refr
  
During refractory period [t, t + τ_refr]:
  All incoming synaptic currents ignored
  dV/dt = 0 (V stays at E_rest or decays)
```

**Numerical Integration (Euler method):**
```
V(t+dt) = V(t) + dt * [-(V(t) - E_rest) / τ_m + I_input(t) / C_m]

Then apply spike/reset logic
```

---

### 1.3 Integrate-and-Fire with Neuromodulation

**Extended Dynamics:**
```
dV/dt = -(V - E_rest) / τ_m(D, A, ...) + I_input(t) / C_m

τ_m(D, A, ...) = τ_m_base * [1 + ω_D * D(t) + ω_A * A(t)]
g_syn(D, A, ...) = g_syn_base * [1 + κ_D * D(t) + κ_A * A(t)]
V_THRESHOLD(D) = V_thresh_base - β_D * D(t)
```

Where:
- D(t), A(t), ...: neuromodulator concentrations (dopamine, acetylcholine, etc.)
- ω_X, κ_X, β_X: modulation gains
- Neuromodulators persist across brain regions but fade with time constant τ_neuro ≈ 100-500 ms

**Neuromodulator Evolution:**
```
dD/dt = -D(t) / τ_D + release_source(t)
```

Where `release_source` sums dopamine release from VTA neurons that fired within integration window.

---

## 2. EVENT PROPAGATION ALGORITHM

### 2.1 Timestep Execution (dt = 1 ms)

```
GLOBAL STATE:
  event_queue: PriorityQueue[Event, timestamp]
    - Event = (timestamp, event_type, source_id, target_id, payload)
  neuron_states: Map[CAT-N-ID → NeuronState]
  synapse_registry: Map[CAT-S-ID → SynapseInfo]
  current_time: float = 0

ALGORITHM simulate_timestep(time_current, dt):
  
  1. DELIVER QUEUED EVENTS
     while event_queue.next_timestamp <= time_current + dt:
       event = event_queue.pop()
       deliver_event(event)
       
       Event delivery updates postsynaptic_current of target neuron:
       I_input[target] += neurotransmitter_effect(event)
  
  2. AGGREGATE SYNAPTIC CURRENTS
     for each neuron n with state s:
       s.I_input_total = sum of all active postsynaptic currents
       
       Synaptic current calculation:
       I_syn = Σ_s [g_syn * (V_neuron - E_reversal) * open_fraction(t)]
       
       where open_fraction models receptor kinetics:
       dr/dt = α * transmitter * (1 - r) - β * r
       (r = fraction of open channels, modeled per receptor type)
  
  3. INTEGRATE NEURAL DYNAMICS
     for each neuron n with state s:
       if n is Hodgkin-Huxley type:
         solve ODE system {dV/dt, dm/dt, dh/dt, dn/dt} using RK4
         s.V_new = result.V
         s.m_new, s.h_new, s.n_new = result gates
       
       elif n is LIF type:
         if current_time < s.refractory_until:
           # Refractory: ignore inputs, V decays to E_rest
           s.V_new = E_rest + (s.V - E_rest) * exp(-dt / τ_decay_refr)
         else:
           s.V_new = solve_LIF_ODE(dt)
       
       elif n is LIF-modulated type:
         τ_eff = compute_modulated_tau(s.neuromodulator_state)
         s.V_new = solve_LIF_ODE_modulated(dt, τ_eff)
       
       Update state: s.V = s.V_new
  
  4. SPIKE DETECTION & EMISSION
     spike_events_this_step = []
     
     for each neuron n with state s:
       if is_spike(s.V, s.V_last):
         spike_events_this_step.append((n.id, current_time))
         s.last_spike_time = current_time
         s.spike_count += 1
         s.refractory_until = current_time + τ_refr
         
         # Record spike with source-synapse mapping
         for each synapse syn ∈ s.output_synapses:
           record_spike_transmission(n.id, syn.id, current_time)
  
  5. QUEUE POSTSYNAPTIC EVENTS (RECURRENT-SAFE)
     for each spike_event (source_id, spike_time) in spike_events_this_step:
       
       for each synapse syn with source == source_id:
         target_id = syn.target_neuron_id
         delivery_time = spike_time + syn.delay
         
         # This is KEY: delivery happens in future timestep
         # Synaptic delay prevents instantaneous cycles
         event_payload = {
           source_neuron: source_id,
           synapse_id: syn.id,
           neurotransmitter: syn.transmitter_type,
           weight: syn.weight,
           receptor_type: syn.postsynaptic_receptor,
           spike_amplitude: 1.0  # or modulated by source state
         }
         
         event_queue.push(
           Event(delivery_time, "POSTSYNAPTIC", source_id, target_id, payload)
         )
  
  6. NEUROMODULATOR UPDATES
     for each neuromodulator type (D, A, 5HT, ...):
       # Sum dopamine release from all neurons that fired
       dopamine_release = Σ_n [spike_count[n] * n.dopamine_release_per_spike]
       
       dD/dt = -D(t) / τ_D + dopamine_release
       D(t+dt) = D(t) + dt * dD/dt
       
       # Apply to all neurons (broadcast)
       for each neuron n:
         n.neuromodulator_state[D] = D(t+dt)
  
  7. RECORD STATE
     record_timestep_state(current_time, neuron_states, spike_events_this_step)
  
  8. ADVANCE TIME
     current_time += dt

END ALGORITHM
```

### 2.2 Event Record Schema

**Spike Event:**
```
SpikEvent {
  timestamp: float (ms)
  source_neuron_id: CAT-N-ID
  last_spike_time: float
  spike_count: int (cumulative in this run)
  refractory_until: float
  
  affected_synapses: [CAT-S-ID, ...]  # All output synapses from this neuron
}
```

**Postsynaptic Event (queued in event_queue):**
```
PostsynapticEvent {
  delivery_timestamp: float
  source_neuron_id: CAT-N-ID
  synapse_id: CAT-S-ID
  target_neuron_id: CAT-N-ID
  neurotransmitter_type: enum (Glutamate, GABA, Dopamine, ...)
  weight: float
  postsynaptic_receptor: enum (AMPA, NMDA, GABA-A, D1, ...)
  amplitude: float (0-1)
}
```

---

## 3. RECURRENT HANDLING STRATEGY

### 3.1 Delay-Based Feedback (Corrected I1)

**Problem:** Recurrent connections create cycles. Naive implementation causes infinite loops.

**Solution:** All spikes propagate with synaptic delays, creating guaranteed causality chain:

```
t=0:    Neuron A fires
t=d_AB: Spike arrives at B via synapse CAT-S-AB (delay d_AB)
        B receives input, may fire at t=d_AB + integration_time
t=d_AB+d_BA: 
        If B fired, spike arrives back at A via synapse CAT-S-BA (delay d_BA)
        
Total round-trip delay = d_AB + d_BA ≥ 2 * min_synaptic_delay (typically ≥ 1 ms)
```

**Pseudocode for cycle handling:**

```
ALGORITHM handle_recurrent_connection(source_id, synapse_id, target_id, delay_ms):
  
  # This is the ONLY place spike propagation happens
  # Delays are MANDATORY for all connections (even "fast" ones get ≥ 0.1 ms delay)
  
  delivery_time = current_time + delay_ms
  
  # INVARIANT: delivery_time > current_time
  # INVARIANT: no spike is delivered to same timestep it was emitted
  
  event = PostsynapticEvent(
    delivery_timestamp = delivery_time,
    source_neuron_id = source_id,
    synapse_id = synapse_id,
    target_neuron_id = target_id,
    ...
  )
  
  # Queue into future event processor
  event_queue.insert(event, priority=delivery_time)
  
END ALGORITHM
```

### 3.2 Example: Recurrent Cortical Loop

**Connectivity:**
- Pyramidal neuron A → Inhibitory interneuron I → Pyramidal neuron A
- Delays: A→I = 1 ms, I→A = 2 ms

**Execution timeline:**

```
t=0:      Pyramidal A fires (excitatory spike)
          Queue event: (t=1, A→I, Glutamate, AMPA)

t=1:      Interneuron I receives excitatory input
          I integrates, fires at t≈1.5 ms (LIF integration delay)
          Queue event: (t=3.5, I→A, GABA, GABA-A)

t=3.5:    Pyramidal A receives inhibitory input
          Hyperpolarization reduces firing probability
          
t=5:      A fires again (natural rhythm or external input)
          Queue event: (t=6, A→I, Glutamate, AMPA)
```

**Key observations:**
1. No infinite loop: cycle completion takes ≥ 3.5 ms
2. All connections preserve CAT-S-ID: (A→I = CAT-S-xxx, I→A = CAT-S-yyy)
3. Bidirectional information flow is preserved
4. Firing pattern emerges from dynamics, not structure

### 3.3 Example: Thalamic Feedback Loop

**Connectivity:**
- Cortical pyramidal (L5) → Thalamic relay neuron (with VB nucleus)
- Thalamic relay → Cortical layer 4 (with thalamocortical delay)
- Cortical layer 4 → deeper cortical layers → back to L5 (polysynaptic)

**Delays:**
- Cortex → Thalamus: 2 ms (direct)
- Thalamus → Cortex (L4): 1 ms (fast synaptic)
- L4 → L5 feedback: 2-3 ms (polysynaptic)

**Execution:**

```
t=0:      L5 pyramidal fires
          Queue: (t=2, L5→Thal, dep. / EPSC)

t=2:      Thalamic relay integrates
          May fire if threshold reached
          Queue: (t=3, Thal→L4, EPSC)

t=3:      L4 spiny stellate receives input
          Integration and forward propagation
          Queue: (t=5.5, L4→L5, EPSC)

t=5.5:    L5 receives feedback input
          This closes the loop with ≥5.5 ms latency
```

**No synchronous cycle** because all delays are > 0 and sum to ≥ 5.5 ms.

---

## 4. BEHAVIORAL OUTPUT MAPPING

### 4.1 Motor Output Layer

**Definition:** Motor cortex neurons (CAT-N in region:motor_cortex) map to motor commands.

**Mapping schema:**

```
MotorNeuron {
  neuron_id: CAT-N-ID
  region: "motor_cortex"
  body_part: enum (right_forelimb, left_hindlimb, tail, jaw, ...)
  action_type: enum (flexion, extension, retraction, grip_strength, ...)
  
  output_mapping: {
    spike_rate_hz: float → action_intensity [0, 1]
    
    # Piecewise linear or sigmoid mapping
    # E.g., 0-10 Hz → no action (0.0)
    #       10-50 Hz → graded intensity
    #       50+ Hz → maximal intensity (1.0)
  }
}
```

**Execution per timestep:**

```
ALGORITHM compute_motor_output(neuron_state, dt):
  
  # Rolling window spike rate calculation
  spikes_in_window = count_spikes(neuron_id, current_time - window_ms, current_time)
  spike_rate_hz = (spikes_in_window / window_ms) * 1000
  
  action_intensity = neuron.output_mapping(spike_rate_hz)
  
  Record:
  {
    timestamp: current_time,
    neuron_id: neuron.id,
    body_part: neuron.body_part,
    action_type: neuron.action_type,
    spike_rate_hz: spike_rate_hz,
    action_intensity: action_intensity,
    trace: [neuron_id, upstream_synapses, ...]  # For traceability
  }
  
END ALGORITHM
```

### 4.2 Cognitive/Motivational Circuits

**Predatory motivation circuit:**

```
PredatoryMotivation {
  core_neurons: [
    CAT-N-xxx (anterior hypothalamus),
    CAT-N-yyy (dorsal raphe),
    CAT-N-zzz (lateral amygdala),
    ...
  ]
  
  # Aggregate firing across circuit
  circuit_activation = mean_firing_rate(core_neurons)
  
  hunt_behavior_intensity = sigmoid(circuit_activation - threshold)
  
  Output: hunt_bias → affects motor cortex gain
}
```

**Social cognition circuit:**

```
SocialCognition {
  core_neurons: [
    CAT-N-aaa (TPJ - theory of mind),
    CAT-N-bbb (Anterior insula - empathy),
    CAT-N-ccc (mPFC - self/other distinction),
    ...
  ]
  
  circuit_state = aggregate_state(core_neurons)
  
  social_engagement_level = extract_principal_component(circuit_state)
  
  Output: [affiliation_probability, dominance_signal, submission_signal, ...]
}
```

### 4.3 Traceability: Neuron→Synapse→Action Chain

**Full trace recorded for every action:**

```
ActionTrace {
  timestamp: float
  action_id: enum (motor_command, vocalization, posture_shift, ...)
  action_intensity: float
  
  source_neurons: [
    {
      neuron_id: CAT-N-ID,
      spike_time: float,
      firing_rate_hz: float,
      weight_in_output: float  # Contribution to this action
    },
    ...
  ],
  
  upstream_synapses: [
    {
      synapse_id: CAT-S-ID,
      source_neuron: CAT-N-ID,
      transmitter: enum,
      weight: float,
      delivery_time: float
    },
    ...
  ],
  
  circuit_context: {
    predatory_motivation_level: float,
    social_engagement_level: float,
    neuromodulator_state: {dopamine: float, serotonin: float, ...},
  }
}
```

---

## 5. STATE RECORDING SCHEMA

### 5.1 Per-Timestep Recording

**Neuron State Snapshot:**

```
NeuronSnapshot {
  timestamp: float (ms, monotonically increasing)
  neuron_id: CAT-N-ID
  firing_model: enum (HodgkinHuxley, LIF, LIF_modulated)
  
  # Membrane state
  membrane_potential_mV: float
  input_current_uA: float
  
  # Gating variables (HH only)
  gating_m: float (optional)
  gating_h: float (optional)
  gating_n: float (optional)
  
  # Firing state
  spike_occurred_this_timestep: bool
  spike_count_cumulative: int
  last_spike_time: float
  time_since_last_spike: float
  
  # Refractoriness
  refractory_remaining_ms: float
  
  # Neuromodulation
  dopamine_concentration: float
  acetylcholine_concentration: float
  serotonin_concentration: float
  [other_modulators...]
  
  # Synaptic inputs (decomposed)
  total_input_current: float
  
  input_breakdown: [
    {
      synapse_id: CAT-S-ID,
      source_neuron: CAT-N-ID,
      neurotransmitter: enum,
      receptor_type: enum,
      current_contribution: float,
      open_fraction: float  # Receptor open probability
    },
    ...
  ]
}
```

**Spike Event Record:**

```
SpikeEvent {
  timestamp: float
  source_neuron_id: CAT-N-ID
  spike_index: int  # Cumulative spike count
  
  # Which synapses transmitted this spike?
  transmitted_synapses: [CAT-S-ID, ...]
  
  # Postsynaptic delivery schedule
  postsynaptic_events_queued: [
    {
      synapse_id: CAT-S-ID,
      target_neuron: CAT-N-ID,
      delivery_time: float,
      neurotransmitter: enum,
      weight: float
    },
    ...
  ]
}
```

**Behavioral Output Record:**

```
BehavioralOutput {
  timestamp: float
  motor_commands: [
    {
      body_part: enum,
      action_type: enum,
      intensity: float,
      source_neuron_id: CAT-N-ID,
      source_synapse_ids: [CAT-S-ID, ...]
    },
    ...
  ],
  
  cognitive_state: {
    predatory_motivation: float,
    social_engagement: float,
    fear_level: float,
    [other_dimensions...]
  },
  
  vocalization: {
    acoustic_parameters: {...},
    source_circuit: [CAT-N-ID, ...],
  } or null
}
```

### 5.2 Logging Tier Strategy

**Tier 1 (Always):** Spike events + behavioral output (sparse, low overhead)
**Tier 2 (For debugging):** Neuron snapshots every 10 ms (manageable volume)
**Tier 3 (For replay):** Complete state + all synaptic currents every 1 ms (high volume, stored separately)

**Pseudo-code:**

```
LOGGING_TIER = 2  # Configurable

if LOGGING_TIER >= 1:
  log_spike_event(spike_event)
  log_behavioral_output(motor_output)

if LOGGING_TIER >= 2 and current_time % 10 == 0:
  for each neuron n:
    log_neuron_snapshot(n.get_state())

if LOGGING_TIER >= 3:
  for each neuron n:
    log_neuron_snapshot(n.get_state())
```

---

## 6. DETERMINISM GUARANTEE

### 6.1 Requirements for Reproducible Replay

**Given identical:**
1. **Initial neural state:** All V, m, h, n, neuromodulator concentrations
2. **Synaptic weight matrix:** All CAT-S weights and delays
3. **Stimulus sequence:** Exact timing and amplitude of sensory inputs
4. **Model parameters:** All tau, conductances, reversal potentials
5. **Random seed:** If stochastic components present (channel noise, synaptic release probability)
6. **Solver configuration:** dt, integration method (RK4 vs Euler), tolerance

**Then:** Identical sequence of spikes and behavioral outputs (bitwise deterministic if using fixed-point arithmetic; within floating-point epsilon otherwise)

### 6.2 Sources of Non-Determinism to Eliminate

| Source | Risk | Mitigation |
|--------|------|-----------|
| Floating-point rounding | Low | Use consistent precision (float64); fix solver dt |
| Event queue ordering | High | Use deterministic priority (timestamp, then ID) |
| Random channel noise | High | Set fixed seed; use xorshift256 (deterministic) |
| Synaptic delay jitter | Medium | Specify exact delays; no randomness in delivery |
| Neuromodulator updates | Medium | Use synchronized, ordered summation |
| Thread scheduling | High | Single-threaded only; or use deterministic barriers |

### 6.3 Replay Procedure

**Forward pass (original simulation):**
```
1. Log every spike event + timestamp
2. Log every neuron state at logging_tier granularity
3. Log stimulus input exactly
4. Log random seed used
```

**Replay pass:**
```
1. Set identical initial state (from log or reset)
2. Set identical seed
3. Run simulation with identical dt, parameters
4. Compare spike events and behavioral outputs at each logged timestamp
5. If any divergence: identify first mismatch → debug floating-point or parameter issue
```

### 6.4 Determinism Proof Sketch

**Claim:** Given all inputs above fixed, simulation is deterministic.

**Proof:**
- ODE integration (RK4) with fixed dt is deterministic: same state → same derivatives → same step
- Event queue is deterministic: priority defined by (timestamp, source_id), all events processed in sorted order
- Spike detection is deterministic: threshold comparison on V(t) vs V(t-dt)
- No external randomness (if seed fixed)
- Therefore: T → T+dt transition is a pure function f(state, input, seed)
- By induction: entire sequence state(t) is deterministic

**Caveat:** Floating-point arithmetic is not associative. If you parallelize or reorder summations, you may get different rounding. Mitigation: always use same order, or use rational arithmetic for critical components.

---

## 7. EXAMPLE TRACE: PREDATORY DECISION

### Scenario
Mouse brain with predatory motivation circuit → motor output (pounce).

### Simulation
```
Initial state (t=0):
  - V_motor_cortex = -65 mV
  - V_hypothalamus = -68 mV
  - dopamine = 0.1 μM (baseline)
  - stimulus = visual prey at left, auditory sound at right

t=0-50 ms: Sensory processing
  Visual input → lateral geniculate nucleus (LGN) → primary visual cortex
  Auditory input → inferior colliculus (IC) → auditory thalamus
  
  t=10 ms: LGN neurons fire (CAT-N-visual-001, ..., CAT-N-visual-050)
           via synapses CAT-S-optic-nerve-001, ...
           
  t=15 ms: Primary visual cortex neurons fire (CAT-N-V1-left-001, ...)
  
  t=18 ms: Superior colliculus integrates (CAT-N-SC-001)
           fires → hypothalamus (anterior, lateral)

t=50-100 ms: Decision formation
  t=52 ms: Lateral hypothalamus fires (CAT-N-hyp-lateral-001)
           → dopamine release, VTA activation
  
  t=55 ms: Dopamine spreads across cortex, amygdala
           Modulates synaptic gains: τ_m reduced, thresholds lowered
  
  t=60 ms: Dorsal motor cortex (CAT-N-motor-left-001, -002, ...)
           receive strong lateral hypothalamus input
           Begin firing synchronously

t=100-150 ms: Motor execution
  t=105-110 ms: Motor cortex population fires at 80 Hz
                → motor output mapping:
                   right_forelimb: flexion intensity = 0.9
                   left_forelimb: extension intensity = 0.8
                   trunk: rotation intensity = 0.7
                   
  t=120-150 ms: Sustained firing, pounce trajectory executed
                Feedback from proprioceptive cortex modulates gain
```

### Trace Record (excerpt)

```
Spike events logged:
- t=10: CAT-N-visual-001 fires → synapses [CAT-S-LGN-001, CAT-S-LGN-002]
- t=15: CAT-N-V1-left-001 fires
- ...
- t=60: CAT-N-motor-left-001 fires
- t=61: CAT-N-motor-left-002 fires
- ...

Action trace:
- t=105: action_id=POUNCE_LEFT, intensity=0.85
  source_neurons: [CAT-N-motor-left-001 (weight=0.3), CAT-N-motor-left-002 (weight=0.25), ...]
  upstream_synapses: [CAT-S-hyp-motor-001, CAT-S-SC-motor-003, ...]
  circuit_context: dopamine=0.8, social_engagement=0.1, fear=0.05

Determinism check:
- If replayed with same seed + stimulus: identical spike times ± < 0.1 ms (floating-point error)
- Behavioral output identical (pounce_left, intensity 0.85)
```

---

## 8. IMPLEMENTATION CHECKLIST

- [ ] Implement Hodgkin-Huxley ODE solver with RK4, verify against published benchmarks
- [ ] Implement LIF dynamics with configurable tau_m, refractory periods
- [ ] Implement LIF with neuromodulation (dopamine, acetylcholine, serotonin scaling)
- [ ] Implement event queue with deterministic priority (timestamp, then source_id)
- [ ] Implement spike detection logic with hysteresis (V_now > V_thresh and V_prev <= V_thresh)
- [ ] Implement synaptic delay handling (all connections must have delay > 0)
- [ ] Implement receptor kinetics (open fraction dynamics)
- [ ] Implement neuromodulator diffusion and reuptake
- [ ] Implement motor output mapping (spike rate → action intensity)
- [ ] Implement full traceability logging (CAT-N, CAT-S through entire chain)
- [ ] Implement deterministic replay from logs
- [ ] Test recurrent circuit stability (verify no infinite loops, bounded firing)
- [ ] Test thalamic feedback loop (verify bidirectional information flow)
- [ ] Test behavioral output correctness (motor commands trace back to source neurons)
- [ ] Performance benchmark: target 1000× real-time on typical workstations

---

## 9. REFERENCES & NOTES

### Biological Accuracy
- Hodgkin-Huxley model from squid axon; parameters can be adjusted for mammalian neurons
- Synaptic delays: cortical intracortical ≈ 1-2 ms, thalamocortical ≈ 1-2 ms, polysynaptic ≈ 2-5 ms
- Neuromodulator time constants: dopamine τ ≈ 100-200 ms, acetylcholine τ ≈ 100 ms, serotonin τ ≈ 200-500 ms

### Computational Efficiency
- Use sparse matrix representation for synaptic connectivity
- Only integrate neurons with non-zero input current
- Event-driven simulation: skip timesteps with no events (on subthreshold neurons only)

### Validation
- Bench against known neural oscillations (theta 4-12 Hz, gamma 30-100 Hz)
- Verify phase locking between coupled oscillators
- Confirm bistability of winner-take-all circuits
