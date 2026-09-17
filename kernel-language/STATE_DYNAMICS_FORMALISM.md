# Neural State Dynamics: Formal Specification

## Overview

This document provides the formal mathematical definitions of neural state evolution, indexed by CAT-N (neuron) and CAT-S (synapse) identifiers, with explicit recurrence handling and behavioral output mappings.

---

## 1. STATE VECTOR DEFINITION

### 1.1 Global Neural State

```
Ψ(t) = {
  V(t) ∈ ℝ^N,                    # Membrane potentials for N neurons
  x(t) ∈ ℝ^(N×m),                # Gating variables (m gates per HH neuron)
  C(t) ∈ ℝ^M,                    # Neuromodulator concentrations (M types)
  E_queue(t) ∈ Events,            # Queued synaptic events
  spike_history ⊆ ℝ × CAT-N,      # (time, neuron_id) pairs
  action_history ⊆ ℝ × CAT-N × Actions,  # Behavioral outputs
}
```

### 1.2 Per-Neuron State

```
For each neuron n ∈ CAT-N:

ψ_n(t) = {
  V_n(t) ∈ ℝ,                    # Membrane potential (mV)
  model ∈ {HH, LIF, LIF-mod},    # Firing model type
  
  # HH-specific
  m_n(t), h_n(t), n_n(t) ∈ [0,1], # Gating variables
  
  # Time state
  τ_refr_n(t) ∈ ℝ≥0,             # Remaining refractory time
  t_last_spike(n) ∈ ℝ,           # Last spike timestamp
  
  # Input aggregation
  I_input(t) ∈ ℝ,                # Total input current (μA)
  r_s(t) ∈ [0,1],                # Receptor open fractions for each incoming synapse
  
  # Neuromodulation
  D_n(t), A_n(t), ... ∈ ℝ≥0,     # Local neuromodulator concentrations
}
```

### 1.3 Per-Synapse State

```
For each synapse s ∈ CAT-S:

σ_s = {
  source(s) ∈ CAT-N,             # Presynaptic neuron
  target(s) ∈ CAT-N,             # Postsynaptic neuron
  delay_s ∈ ℝ>0 (ms),            # Conduction delay (always > 0)
  weight_s ∈ ℝ,                  # Synaptic strength
  g_max ∈ ℝ≥0,                   # Maximal conductance
  E_rev ∈ ℝ,                     # Reversal potential
  transmitter_s ∈ {Glut, GABA, DA, ACh, ...},
  receptor_s ∈ {AMPA, NMDA, GABA-A, GABA-B, D1, D2, ...},
  
  # Receptor kinetics parameters
  α_r(V), β_r(V) ∈ Functions,    # Voltage-dependent opening/closing rates
}
```

---

## 2. TIME EVOLUTION RULES

### 2.1 Hodgkin-Huxley Neuron ODE System

```
STATE VARIABLES: (V_n, m_n, h_n, n_n)

SYSTEM OF ODEs:

dV_n/dt = (1/C_m) * [
  -ḡ_Na * m_n³ * h_n * (V_n - E_Na)
  -ḡ_K * n_n⁴ * (V_n - E_K)
  -ḡ_L * (V_n - E_L)
  + I_input_n(t)
]

dm_n/dt = α_m(V_n) * (1 - m_n) - β_m(V_n) * m_n
dh_n/dt = α_h(V_n) * (1 - h_n) - β_h(V_n) * h_n
dn_n/dt = α_n(V_n) * (1 - n_n) - β_n(V_n) * n_n

I_input_n(t) = Σ_s [w_s * g_s_max * r_s(t) * (V_n(t) - E_rev_s)]
            + I_external_n(t)

where r_s(t) satisfies:
dr_s/dt = α_r_s(V_n, receptor_type) * (1 - r_s) - β_r_s(V_n, receptor_type) * r_s

SPIKE CONDITION:
V_n(t) crosses threshold from below:
  V_n(t) > V_thresh AND V_n(t-dt) ≤ V_thresh

ACTION: Emit spike event, reset refractory timer
```

### 2.2 Leaky Integrate-and-Fire ODE

```
STATE VARIABLES: (V_n, τ_refr_n)

DURING NON-REFRACTORY PERIOD (τ_refr_n(t) = 0):

dV_n/dt = -(V_n - E_rest) / τ_m + I_input_n(t) / C_m

I_input_n(t) = Σ_s [w_s * g_s_max * r_s(t) * (V_n - E_rev_s)]
            + I_external_n(t)

SPIKE CONDITION:
V_n(t) ≥ V_thresh

ACTION ON SPIKE:
  V_n(t⁺) ← E_rest                    # Reset voltage
  τ_refr_n(t⁺) ← τ_refr (e.g., 2 ms) # Set refractory timer
  Emit spike event
  
DURING REFRACTORY PERIOD (τ_refr_n(t) > 0):

dV_n/dt = 0                           # Voltage held at E_rest
τ_refr_n(t+dt) = max(0, τ_refr_n(t) - dt)  # Countdown
```

### 2.3 LIF with Neuromodulation

```
STATE VARIABLES: (V_n, τ_refr_n, D_n, A_n, ...)

MODULATED PARAMETERS:

τ_m_eff(t) = τ_m * [1 + ω_D * D_n(t) + ω_A * A_n(t)]
             # Dopamine shortens τ_m (ω_D < 0)
             # Acetylcholine lengthens τ_m (ω_A > 0)

g_eff_s(t) = g_s_max * [1 + κ_D * D_n(t) + κ_A * A_n(t)]
             # Dopamine enhances synaptic gain

V_thresh_eff(t) = V_thresh - β_D * D_n(t)
                 # Dopamine lowers threshold (easier to fire)

ODE SYSTEM:

dV_n/dt = -(V_n - E_rest) / τ_m_eff(t) + I_input_n(t, modulated) / C_m

I_input_n(t, modulated) = Σ_s [w_s * g_eff_s(t) * r_s(t) * (V_n - E_rev_s)]
                        + I_external_n(t)

SPIKE CONDITION:
V_n(t) ≥ V_thresh_eff(t)

SPIKE CONSEQUENCES (same as base LIF):
  V_n(t⁺) ← E_rest
  τ_refr_n(t⁺) ← τ_refr
  Emit spike event
```

### 2.4 Receptor Kinetics (All Models)

```
For each postsynaptic receptor r on target neuron with incoming synapse s:

AMPA & GABA-A (Fast synapses):
  Kinetic scheme: T + R ⇌ TR
  
  dr_s/dt = α_AMPA * T(t) * (1 - r_s) - β_AMPA * r_s
  
  α_AMPA ≈ 1.1 ms⁻¹ (for glutamate transient)
  β_AMPA ≈ 0.19 ms⁻¹
  (receptor open fraction r_s in [0,1])

NMDA (Voltage-dependent, slow):
  r_NMDA affected by Mg²⁺ blockade:
  
  blockade_factor(V) = 1 / [1 + [Mg²⁺] * exp(-0.062 * V) / 3.57]
  (typically 0.1-0.9 depending on V)
  
  dr_NMDA/dt = α_NMDA * T(t) * blockade_factor(V) * (1 - r_NMDA)
             - β_NMDA * r_NMDA
  
  α_NMDA ≈ 0.072 ms⁻¹
  β_NMDA ≈ 0.0066 ms⁻¹

D1/D2 Dopamine receptors (Neuromodulatory):
  Slower timescale, affects cAMP → gene expression
  Modeled as tonic influence on neuron parameters rather than synaptic current
```

### 2.5 Neuromodulator Dynamics

```
STATE VARIABLES: (D, A, 5HT, ACh, Opioids, ...)

For dopamine D(t):

dD/dt = -D(t) / τ_D + Release(t)

where:
  τ_D ≈ 100-200 ms (reuptake time constant)
  
  Release(t) = Σ_{n ∈ VTA_neurons} [
    spike_count[n, window] * dopamine_per_spike[n]
  ] / window_size
  
  (Dopamine release from ventral tegmental area neurons)

For acetylcholine A(t):

dA/dt = -A(t) / τ_A + Release_ACh(t)

where:
  τ_A ≈ 100 ms
  Release_ACh(t) = Σ_{n ∈ cholinergic_neurons} [spike_count[n]]

SPATIAL DIFFUSION (simplified):

D_n(t+dt) ≈ D(t) + diffusion_constant * ∇²D(t)

(In whole-brain model, treat as well-mixed within region)

SATURATION:

D(t) = min(D_max, D_computed)  # Prevent unbounded growth
```

---

## 3. EVENT PROPAGATION RULES

### 3.1 Timestep Update Equation

```
Formal update rule: ψ(t + dt) = U(ψ(t), I_stim(t), seed; θ)

where:
  ψ(t): neural state at time t
  I_stim(t): external stimulus input
  seed: random number generator state (if stochastic)
  θ: all model parameters (g_max, τ, E_rev, etc.)

DECOMPOSITION:

Step 1: Deliver queued events
  for each event e ∈ E_queue with e.delivery_time ≤ t + dt:
    r_s(t) ← r_s(t) + e.amplitude  # Open receptor fraction
    E_queue ← E_queue \ {e}

Step 2: Aggregate synaptic currents
  for each neuron n:
    I_input_n(t) ← Σ_s [w_s * g_max_s * r_s(t) * (V_n(t) - E_rev_s)]

Step 3: Integrate neural ODEs
  for each neuron n:
    if model[n] = HH:
      Δψ_n = RK4_HH(ψ_n, dt)
    elif model[n] = LIF:
      Δψ_n = Euler_LIF(ψ_n, dt)
    else model[n] = LIF_modulated:
      Δψ_n = Euler_LIF_modulated(ψ_n, dt)
    
    ψ_n(t+dt) ← ψ_n(t) + Δψ_n

Step 4: Check spike thresholds
  spike_events ← {}
  for each neuron n:
    if V_n(t+dt) crosses threshold:
      spike_events ← spike_events ∪ {(n, t+dt)}
      τ_refr_n(t+dt) ← τ_refr
      V_n(t+dt) ← E_reset

Step 5: Queue postsynaptic events
  for each (n, spike_time) ∈ spike_events:
    for each synapse s with source(s) = n:
      event_new = (
        delivery_time: spike_time + delay_s,
        source_neuron: n,
        synapse_id: s,
        target_neuron: target(s),
        amplitude: weight_s,
        transmitter: transmitter_s,
        receptor: receptor_s
      )
      E_queue ← E_queue ∪ {event_new}

Step 6: Update neuromodulators
  for each neuromodulator type X ∈ {D, A, 5HT, ...}:
    dX/dt = -X(t) / τ_X + Release_X(spike_events)
    X(t+dt) = X(t) + dt * dX/dt

Step 7: Record state
  Record snapshot of (ψ, spike_events, behavioral outputs)
```

### 3.2 Recurrent Connection Handling

```
THEOREM (Acyclicity through Delays):

A recurrent connection from neuron A → B → A has round-trip delay:
  Δ_round = delay_A→B + delay_B→A ≥ 2 * min_delay > 0

INVARIANT:
  ∀ spike event e emitted at time t_emit:
  ∃ delivery_time(e) > t_emit (strictly future)
  
  Therefore: No spike affects its own emission (causality preserved)

PROOF:
  1. All connections have delay_s > 0 (architectural constraint)
  2. Spike at t queues event at (t + delay_s) ∈ future
  3. Even if B fires immediately after event delivery, feedback arrives at A at:
     t + delay_AB + delivery_delay_B + delay_BA > t
  4. By induction: no synchronous cycle possible
```

---

## 4. STATE UPDATE RULES (Summary Table)

| Process | Input State | Rule | Output State | Timing |
|---------|-------------|------|--------------|--------|
| Event delivery | V, r_s, E_queue | r_s += event.amp | r_s (opened) | Every dt (queued) |
| Current aggregation | V, r_s, w_s, E_rev | I_input = Σ w*g*r*(V-E) | I_input | Every dt |
| ODE integration | V, m, h, n, I_input | RK4 or Euler | V', x' | Every dt |
| Spike detection | V, V_prev | if V crosses thresh | spike event | When V_thresh crossed |
| Event queueing | spike event, s, delay | e.delivery = t + delay | E_queue | After spike |
| Refractory update | τ_refr_remaining | max(0, τ_refr - dt) | τ_refr_new | Every dt |
| Modulator update | D, Release_D, τ_D | dD/dt = -D/τ + R | D_new | Every dt |

---

## 5. BEHAVIORAL OUTPUT MAPPING (Formal)

### 5.1 Motor Output Function

```
Define for each motor neuron m ∈ CAT-N_motor:

output_map_m: spike_rate(m,t) → action_intensity(m,t)

where spike_rate is computed as:

spike_rate_m(t) = [Σ_i spike_times[m,i] in window(t-W, t)] / W

(Count spikes in window W, divide by window width)

Typical mapping (piecewise linear or sigmoid):

IF spike_rate < 10 Hz:
  action_intensity = 0
  
ELSE IF 10 ≤ spike_rate < 50 Hz:
  action_intensity = (spike_rate - 10) / 40  # Linear
  
ELSE:
  action_intensity = 1.0  # Saturation
```

### 5.2 Action Encoding (Traceability)

```
For each behavioral action a emitted at time t:

action_a(t) = {
  body_part: enum (right_forelimb, left_hindlimb, tail, jaw, mouth, ...)
  action_type: enum (flexion, extension, rotation, grip, vocalization, ...)
  intensity: float ∈ [0, 1]
  
  source_neurons: [
    (neuron_id: CAT-N, firing_rate: float, weight_in_output: float),
    ...
  ]
  
  source_synapses: [
    (synapse_id: CAT-S, transmitter: enum, weight: float),
    ...
  ]
  
  circuit_context: {
    dopamine_level: float,
    motivation_state: float,
    fear_level: float,
    social_engagement: float,
    ...
  }
  
  trace_id: unique identifier for full computation chain
}
```

---

## 6. DETERMINISM GUARANTEE (Formal)

### 6.1 Determinism Hypothesis

```
HYPOTHESIS:
  Given identical:
    1. Initial state: ψ(0) = ψ₀
    2. Stimulus: I_stim[0..T] = I⁰_stim[0..T]
    3. Parameters: θ = θ₀
    4. Random seed: seed = seed₀
    5. Solver config: dt, integration_method, precision
  
  THEN: Simulation trajectories are identical
    ψ_run1(t) = ψ_run2(t)  ∀ t ∈ [0, T]
    
    (Within floating-point rounding error ε ≤ machine_epsilon * sensitivity)
```

### 6.2 Requirements for Reproducibility

```
To enable deterministic replay, the following MUST be logged:

1. INITIAL STATE:
   - V_n(0), m_n(0), h_n(0), n_n(0) for each neuron
   - D(0), A(0), 5HT(0) for each neuromodulator
   - Random seed for PRNG

2. PARAMETERS:
   - Model parameters (g_max, τ_m, E_rev, all α_x, β_x functions)
   - Synaptic connectivity: (source, target, weight, delay, receptor type)
   - Integration parameters: dt, RK4 vs Euler choice

3. STIMULUS:
   - I_external[0..T] for each timestep
   - Or: stimulus specification + random seed for stochastic stimuli

4. EXECUTION LOG:
   - All spike events: (t, neuron_id)
   - Event queue contents at key checkpoints
   - Floating-point checksums (SHA256 of state vectors) at regular intervals

DETERMINISM CHECK:
  Replay run with identical inputs
  Compare spike sequences and checksums
  Any divergence indicates:
    a) Precision issue (FP rounding)
    b) Parameter mismatch
    c) Algorithm bug
```

### 6.3 Proof Sketch

```
LEMMA 1 (ODE Solver is deterministic):
  RK4(x₀, dt, f, seed) produces identical output when given identical inputs.
  Proof: RK4 is a pure function with no random choices.

LEMMA 2 (Event queue processing is deterministic):
  Events processed in order (priority = timestamp, then source_id).
  Same state + same events = same effect.
  Proof: Event queue is a total order; update rule is a function.

LEMMA 3 (Spike detection is deterministic):
  Spike occurs iff V crosses threshold.
  Threshold crossing is a boolean predicate (deterministic).
  Proof: V(t) and V_thresh are numbers; comparison is deterministic.

THEOREM (Full simulation is deterministic):
  ψ(t+dt) = U(ψ(t), I_stim(t), seed; θ)
  U is a pure function.
  By induction: ψ(T) is deterministic from ψ(0), I_stim, seed, θ.
  
CAVEAT: Floating-point arithmetic may have rounding errors.
  These are bounded by machine epsilon; practical trajectories diverge only
  after ~10^6 timesteps if sensitivities are > 1.
  
MITIGATION:
  - Use fixed precision (float64) consistently
  - Avoid parallel summation (use sequential for reproducibility)
  - Log checksums to detect divergence early
```

---

## 7. RECURRENCE EXAMPLE: THALAMIC LOOP (Formal)

### Connectivity

```
CAT-N-L5: Layer 5 pyramidal neuron
CAT-N-Th: Thalamic relay neuron
CAT-N-L4: Layer 4 spiny stellate neuron

CAT-S-1: L5 → Th, delay = 2 ms, weight = 0.8, transmitter = Glutamate
CAT-S-2: Th → L4, delay = 1 ms, weight = 0.9, transmitter = Glutamate
CAT-S-3: L4 → L5, delay = 3 ms, weight = 0.7, transmitter = Glutamate
```

### Execution Trace

```
t=0 ms:
  ψ = {V_L5=-65, V_Th=-65, V_L4=-65, E_queue=[]}
  I_external_L5 = 10 μA (stimulus)

t=1-5 ms:
  L5 integrates external current, reaches threshold
  Event emission: t=5 ms: spike(CAT-N-L5)
  
t=5 ms:
  spike(CAT-N-L5) → queue event:
    Event(delivery=7, source=CAT-N-L5, target=CAT-N-Th, synapse=CAT-S-1, ...)

t=6-7 ms:
  Th and L4 integrate baseline current (V drifts slowly)

t=7 ms:
  Event delivery: r_Th (AMPA) opens
  dr_Th/dt active, AMPA receptor kinetics
  
t=7-9 ms:
  Th integrates AMPA current
  Th potential rises, reaches threshold at t≈8.5 ms
  
t=8.5 ms:
  spike(CAT-N-Th) → queue event:
    Event(delivery=9.5, source=CAT-N-Th, target=CAT-N-L4, synapse=CAT-S-2, ...)

t=9.5 ms:
  Event delivery: r_L4 (AMPA) opens
  L4 integrates AMPA current

t=9.5-12 ms:
  L4 potential rises, reaches threshold at t≈11 ms
  
t=11 ms:
  spike(CAT-N-L4) → queue event:
    Event(delivery=14, source=CAT-N-L4, target=CAT-N-L5, synapse=CAT-S-3, ...)

t=12-14 ms:
  L5 back to baseline (V drifts down)

t=14 ms:
  Event delivery: r_L5 (AMPA) opens
  L5 receives feedback after 14 ms latency
  
Round-trip delay = 14 - 0 = 14 ms >> min_delay
  (No synchronous cycle)
```

---

## 8. VERIFICATION CHECKLIST

- [ ] ODE solver (RK4) tested against published benchmarks
- [ ] Event queue guarantees FIFO + deterministic ordering
- [ ] Spike detection: threshold crossing only (no false positives)
- [ ] Refractory period: input ignored for τ_refr duration
- [ ] Receptor kinetics: verified against voltage-clamp recordings
- [ ] Neuromodulator diffusion: bounded, no blow-up
- [ ] Recurrent loops: verified stable (bounded firing rates)
- [ ] Behavioral mapping: firing rate → action intensity is injective
- [ ] Determinism: identical inputs produce identical spike sequences
- [ ] Computational efficiency: 1000× real-time on single CPU
