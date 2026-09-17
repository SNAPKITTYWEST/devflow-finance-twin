# Neuron Execution Record Template & Architectural Diagrams

## 1. COMPLETE NEURON EXECUTION RECORD TEMPLATE

### 1.1 JSON Schema Template (for instantiation)

```json
{
  "neuron_record": {
    "immutable_properties": {
      "neuron_id": "CAT-N-0123456789ABCDEF",
      "region_id": "piriform-cortex",
      "neuron_type": "pyramidal",
      "soma_coordinates": {
        "x_um": 100.5,
        "y_um": 200.3,
        "z_um": 150.0
      },
      "morphology": {
        "dendrite_compartments": [
          {
            "compartment_id": "CAT-N-0123456789ABCDEF-dendrite-0",
            "parent_neuron_id": "CAT-N-0123456789ABCDEF",
            "compartment_index": 0,
            "branch_order": 0,
            "length_um": 50.0,
            "diameter_um": 2.0,
            "axial_resistance_megohm": 150.0,
            "membrane_resistance_megohm": 40000.0,
            "membrane_capacitance_pF": 100.0,
            "spine_count": 25
          },
          {
            "compartment_id": "CAT-N-0123456789ABCDEF-dendrite-1",
            "parent_neuron_id": "CAT-N-0123456789ABCDEF",
            "compartment_index": 1,
            "branch_order": 1,
            "length_um": 30.0,
            "diameter_um": 1.5,
            "axial_resistance_megohm": 300.0,
            "membrane_resistance_megohm": 40000.0,
            "membrane_capacitance_pF": 60.0,
            "spine_count": 15
          }
        ],
        "axon_segments": [
          {
            "segment_id": "CAT-N-0123456789ABCDEF-axon-0",
            "parent_neuron_id": "CAT-N-0123456789ABCDEF",
            "segment_index": 0,
            "segment_type": "initial-segment",
            "length_um": 20.0,
            "diameter_um": 1.0,
            "axial_resistance_megohm": 500.0,
            "surface_area_um2": 62.83
          },
          {
            "segment_id": "CAT-N-0123456789ABCDEF-axon-1",
            "parent_neuron_id": "CAT-N-0123456789ABCDEF",
            "segment_index": 1,
            "segment_type": "node",
            "length_um": 1.0,
            "diameter_um": 1.0,
            "axial_resistance_megohm": 25.0,
            "surface_area_um2": 3.14
          }
        ],
        "spine_density_per_um": 1.5
      },
      "biochemistry": {
        "neurotransmitter_profile": {
          "primary": "glutamate",
          "primary_vesicle_count": 150,
          "secondary": "none",
          "neuropeptides": ["VGF"]
        },
        "receptor_profile": {
          "NMDA": {
            "location": ["dendrite-0", "dendrite-1"],
            "conductance_nS": 2.5,
            "reversal_potential_mV": 0.0
          },
          "AMPA": {
            "location": ["dendrite-0"],
            "conductance_nS": 1.2,
            "reversal_potential_mV": 0.0
          },
          "GABA-A": {
            "location": ["soma"],
            "conductance_nS": 0.8,
            "reversal_potential_mV": -70.0
          }
        }
      },
      "membrane_parameters": {
        "resting_potential_mV": -70.0,
        "input_resistance_megohm": 150.0,
        "membrane_capacitance_pF": 200.0,
        "specific_membrane_resistance_ohm_cm2": 40000.0,
        "specific_membrane_capacitance_uF_cm2": 1.0
      },
      "firing_parameters": {
        "action_potential_threshold_mV": -40.0,
        "action_potential_peak_mV": 30.0,
        "max_firing_rate_hz": 80.0,
        "adaptation_factor": 0.7,
        "refractory_period_ms": 2.0,
        "absolute_refractory_relative_ms": 1.5,
        "relative_refractory_relative_ms": 0.5
      },
      "functional_metadata": {
        "functional_roles": [
          "sensory-integration",
          "output-neuron",
          "pyramidal-pathway"
        ],
        "behavioral_associations": [
          "olfactory-driven-approach",
          "fearful-context-suppression",
          "reward-prediction"
        ],
        "evidence_level": "experimental",
        "evidence_sources": [
          "patch-clamp-recording",
          "morphological-reconstruction",
          "rabies-tracing"
        ],
        "source_reference": "doi:10.1234/example.2024.neuroanat.vol42",
        "anatomical_reference": "Cajal-staining-slide-2024-001"
      },
      "model_versioning": {
        "model_version": "phase-3-connectome",
        "creation_date": "2024-09-13",
        "last_updated": "2024-09-13",
        "integrity_hash": "sha256:a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      }
    }
  },
  "neuron_dynamic_state": {
    "electrophysiology": {
      "membrane_potential_mV": -70.0,
      "input_current_nA": 0.0,
      "membrane_potential_history_ms": [],
      "current_history_nA": []
    },
    "spike_generation_state": {
      "threshold_state": "resting",
      "refractory_timer_ms": 0.0,
      "last_spike_time_ms": -1.0,
      "spike_count": 0,
      "spike_times_ms": []
    },
    "activity_buffers": {
      "incoming_activity_buffer": [
        {
          "synapse_id": "CAT-S-FEDCBA9876543210",
          "neurotransmitter": "glutamate",
          "quantity_molecules": 50,
          "arrival_time_ms": 1.2,
          "peak_conductance_nS": 2.5
        }
      ],
      "outgoing_activity_buffer": [
        {
          "synapse_id": "CAT-S-0123456789ABCDEF",
          "spike_time_ms": 5.0,
          "target_neuron_id": "CAT-N-FEDCBA9876543210"
        }
      ]
    },
    "integration_state": {
      "total_input_charge_nA_ms": 0.0,
      "recent_spike_count_1s_window": 0,
      "avg_firing_rate_hz": 0.0
    }
  },
  "firing_model_config": {
    "model_type": "hodgkin-huxley",
    "parameters": {
      "g_Na_mS_cm2": 120.0,
      "g_K_mS_cm2": 36.0,
      "g_L_mS_cm2": 0.3,
      "E_Na_mV": 115.0,
      "E_K_mV": -12.0,
      "E_L_mV": 10.6,
      "C_m_uF_cm2": 1.0,
      "temperature_celsius": 37.0,
      "gating_variable_m": 0.05,
      "gating_variable_h": 0.6,
      "gating_variable_n": 0.32
    }
  }
}
```

### 1.2 Dylan Class Instantiation

```dylan
// Direct class instantiation in Dylan

define constant $neuron-CAT-N-0123456789ABCDEF = make(<neuron-record>,
  neuron-id: "CAT-N-0123456789ABCDEF",
  region-id: "piriform-cortex",
  neuron-type: "pyramidal",
  soma-coordinates: #[100.5, 200.3, 150.0],
  dendrite-compartments: vector(
    make(<dendrite-compartment>,
      compartment-id: "CAT-N-0123456789ABCDEF-dendrite-0",
      parent-neuron-id: "CAT-N-0123456789ABCDEF",
      compartment-index: 0,
      branch-order: 0,
      length: 50.0,
      diameter: 2.0,
      axial-resistance: 150.0,
      membrane-resistance: 40000.0,
      membrane-capacitance: 100.0,
      spine-count: 25
    ),
    make(<dendrite-compartment>,
      compartment-id: "CAT-N-0123456789ABCDEF-dendrite-1",
      parent-neuron-id: "CAT-N-0123456789ABCDEF",
      compartment-index: 1,
      branch-order: 1,
      length: 30.0,
      diameter: 1.5,
      axial-resistance: 300.0,
      membrane-resistance: 40000.0,
      membrane-capacitance: 60.0,
      spine-count: 15
    )
  ),
  axon-segments: vector(
    make(<axon-segment>,
      segment-id: "CAT-N-0123456789ABCDEF-axon-0",
      parent-neuron-id: "CAT-N-0123456789ABCDEF",
      segment-index: 0,
      segment-type: "initial-segment",
      length: 20.0,
      diameter: 1.0,
      axial-resistance: 500.0,
      surface-area: 62.83
    )
  ),
  spine-density: 1.5,
  neurotransmitter-profile: table(
    "glutamate" => 150,
    "VGF" => 2
  ),
  receptor-profile: table(
    "NMDA" => 2.5,
    "AMPA" => 1.2,
    "GABA-A" => 0.8
  ),
  resting-potential: -70.0,
  input-resistance: 150.0,
  membrane-capacitance: 200.0,
  action-potential-threshold: -40.0,
  max-firing-rate: 80.0,
  adaptation-factor: 0.7,
  refractory-period: 2.0,
  functional-roles: #["sensory-integration", "output-neuron"],
  behavioral-associations: #["olfactory-driven-approach"],
  evidence-level: "experimental",
  source-reference: "doi:10.1234/example.2024"
);

define constant $state-CAT-N-0123456789ABCDEF = make(<neuron-dynamic-state>,
  membrane-potential: -70.0,
  input-current: 0.0,
  threshold-state: #"resting",
  refractory-timer: 0.0,
  last-spike-time: -1.0,
  spike-count: 0,
  incoming-activity-buffer: deque(),
  outgoing-activity-buffer: deque()
);

define constant $model-CAT-N-0123456789ABCDEF = make(<hodgkin-huxley-model>,
  g-na: 120.0,
  g-k: 36.0,
  g-l: 0.3,
  e-na: 115.0,
  e-k: -12.0,
  e-l: 10.6,
  c-m: 1.0
);

define constant $executable-CAT-N-0123456789ABCDEF = make(<executable-neuron>,
  neuron-record: $neuron-CAT-N-0123456789ABCDEF,
  neuron-state: $state-CAT-N-0123456789ABCDEF,
  firing-model: $model-CAT-N-0123456789ABCDEF
);
```

---

## 2. ARCHITECTURAL DIAGRAMS

### 2.1 Class Hierarchy Diagram

```
<object>
  |
  +-- <neuron-record> [sealed, immutable]
  |     Inheritance: -
  |     Slots: neuron-id, region-id, neuron-type, soma-coordinates,
  |            dendrite-compartments, axon-segments, spike-density,
  |            neurotransmitter-profile, receptor-profile,
  |            membrane-parameters, firing-parameters,
  |            functional-roles, behavioral-associations,
  |            evidence-level, source-reference, model-version,
  |            integrity-hash
  |
  +-- <neuron-dynamic-state> [open, mutable]
  |     Inheritance: -
  |     Slots: membrane-potential, input-current, threshold-state,
  |            refractory-timer, last-spike-time, spike-count,
  |            incoming-activity-buffer, outgoing-activity-buffer,
  |            gating-variable-m, gating-variable-h, gating-variable-n
  |
  +-- <firing-model> [abstract]
  |     Methods: initialize(), receive-input(), compute-dynamics(),
  |              check-threshold(), reset-state()
  |     |
  |     +-- <hodgkin-huxley-model> [sealed]
  |     |     Slots: g-na, g-k, g-l, e-na, e-k, e-l, c-m
  |     |
  |     +-- <leaky-integrate-fire-model> [sealed]
  |     |     Slots: tau-m, v-threshold, v-reset, tau-ref
  |     |
  |     +-- <integrate-fire-model> [sealed]
  |     |     Slots: tau-m, v-threshold, v-reset, tau-ref, modulation-factor
  |     |
  |     +-- <simple-spike-generator> [sealed]
  |           Slots: base-firing-rate, stimulus-sensitivity, max-firing-rate
  |
  +-- <executable-neuron> [sealed]
  |     Slots: neuron-record, neuron-state, firing-model
  |     Methods: receive-input(), step(), fire(), get-output-signal(),
  |              get-state-trace(), verify-identity()
  |
  +-- <synapse> [sealed, immutable]
  |     Slots: synapse-id, source-neuron-id, dest-neuron-id,
  |            source-compartment, dest-compartment,
  |            synapse-type, neurotransmitter, receptor-type,
  |            release-probability, synaptic-delay, peak-conductance,
  |            decay-time, source-coordinates, dest-coordinates,
  |            evidence-level, source-reference
  |
  +-- <region> [open]
  |     Slots: region-id, region-name, neuron-ids
  |     Methods: add-neuron(), remove-neuron(), get-neurons()
  |
  +-- <circuit> [open]
  |     Slots: circuit-id, circuit-name, neuron-ids, synapse-ids,
  |            functional-description, behavioral-associations
  |     Methods: add-neuron(), add-synapse(), get-neurons(), get-synapses()
  |
  +-- <network> [mutable]
  |     Slots: neurons (Table<string, <executable-neuron>>),
  |            synapses (Table<string, <synapse>>),
  |            regions (Table<string, <region>>),
  |            circuits (Table<string, <circuit>>),
  |            neuron-to-outgoing-synapses,
  |            neuron-to-incoming-synapses
  |     Methods: add-neuron(), connect-neurons(), step-simulation(),
  |              get-neuron-trace(), verify-all-identities()
  |
  +-- <temporal-state> [sealed, immutable snapshot]
  |     Slots: timestamp-ms, neuron-states (Table),
  |            synapse-activities (Table), spike-events (Vector),
  |            execution-step
  |
  +-- <execution-trace> [sealed]
        Slots: initial-state, temporal-snapshots (Vector),
               integrity-checks (Vector)
        Methods: append-snapshot(), verify-trace(), seal-trace()
```

### 2.2 Neuron Firing State Machine

```
                   +------- (resting) -------+
                   |                         |
                   v                         ^
             [membrane potential]    [refractory complete]
                   |                         |
                   |  [input exceeds]        |
                   |   threshold]            |
                   v                         |
            (depolarizing)                   |
                   |                         |
                   |  [peak reached]         |
                   |                         |
                   v                         |
           (repolarizing)                    |
                   |                         |
                   |  [fires spike]          |
                   |                         |
                   v                         |
            (refractory) ----[tau_ref ms]----+

State Transitions:
  resting -> depolarizing:  V(t) - V(t-dt) > threshold
  depolarizing -> repolarizing: V reaches max
  repolarizing -> refractory: spike emission triggered
  refractory -> resting: refractory_timer expires
```

### 2.3 Neuron-Synapse-Neuron Signal Flow

```
SOURCE NEURON (Presynaptic)
  |
  +-- <executable-neuron>
      |
      +-- firing-model.compute-dynamics()
          |
          +-- [Check threshold]
              |
              +-- fire() emitted
                  |
                  v
              Spike event generated
              spike_time = global-time-ms
              |
              v
          Put spike in outgoing-activity-buffer:
          { synapse-id: "CAT-S-XXXXXXXX",
            spike-time: t,
            neurotransmitter: "glutamate" }

                    (synaptic delay)
                          |
                          v

SYNAPSE (Connection)
  |
  +-- <synapse>
      |
      +-- synapse-id: "CAT-S-XXXXXXXX"
      +-- source-neuron-id: "CAT-N-SSSSSSSS"
      +-- dest-neuron-id: "CAT-N-DDDDDDDD"
      +-- dest-compartment: "CAT-N-DDDDDDDD-dendrite-0"
      +-- peak-conductance: 2.5 nS
      +-- decay-time: 5.0 ms
      +-- release-probability: 0.95
      |
      v
  Apply random release probability check
  IF release_success:
    neurotransmitter_quantity = peak-conductance * dt
    arrival-time = spike-time + synaptic-delay

DESTINATION NEURON (Postsynaptic)
  |
  +-- <executable-neuron>
      |
      +-- receive-input(synapse-id, neurotransmitter, quantity, arrival-time)
          |
          +-- Buffer input in incoming-activity-buffer
              |
              v
          firing-model.receive-input()
              |
              +-- Update input-current based on compartment conductance
              |   (apply spine-density scaling if applicable)
              |
              v
          neuron-state.input-current += current
          |
          v
      (on next step())
      |
      +-- firing-model.compute-dynamics(dt)
          |
          +-- Integrate input-current into membrane dynamics
```

### 2.4 Temporal Simulation Loop

```
INITIALIZATION
  |
  v
Create Network (158 neurons, 102 synapses)
  |
  v
Create ExecutionTrace with initial-state snapshot
  |
  v

MAIN SIMULATION LOOP (timestep = 0 to N)
  |
  +--> PHASE 1: Postsynaptic Integration
  |      For each neuron in network.neurons:
  |        For each incoming synapse:
  |          source_signal = source_neuron.get-output-signal(synapse-id)
  |          IF signal exists:
  |            dest_neuron.receive-input(signal)
  |
  |
  +--> PHASE 2: Membrane Dynamics
  |      For each neuron in network.neurons:
  |        neuron.step(dt, global-time-ms)
  |          (updates V(t), gating variables, threshold-state)
  |
  |
  +--> PHASE 3: Spike Generation
  |      spike_events = []
  |      For each neuron in network.neurons:
  |        IF neuron.step() returned #t:
  |          neuron.fire(global-time-ms)
  |            (updates spike-count, last-spike-time,
  |             populates outgoing-activity-buffer)
  |          spike_events.add((neuron-id, global-time-ms))
  |
  |
  +--> PHASE 4: State Snapshot
  |      temporal_state = network.snapshot-all-neurons()
  |        (captures membrane potentials, spike-counts, threshold-states)
  |      trace.append-snapshot(temporal_state)
  |
  |
  +--> PHASE 5: Integrity Check (periodic)
  |      IF timestep % 100 == 0:
  |        audit_result = verify-network-integrity(network)
  |        IF audit_result != #"PASS":
  |          ABORT with error
  |
  v
(repeat for each timestep)
  |
  v

TRACE SEALING
  |
  v
final_verdict = trace.verify-trace()
  (checks neuron/synapse counts, ID formats, monotonicity)
  |
  v
IF final_verdict == #t:
  sealed-hash = trace.seal-trace()
  EMIT: sealed-hash for WORM archival
ELSE:
  EMIT: verification failure details
```

### 2.5 Identity Preservation Flow

```
PHASE 3 INPUT
  |
  +-- 158 neurons: CAT-N-0, CAT-N-1, ..., CAT-N-157
  +-- 102 synapses: CAT-S-0, CAT-S-1, ..., CAT-S-101
  +-- 10 circuits (reference collections)
  |
  v

NETWORK CONSTRUCTION
  |
  +-- For each neuron:
  |     Create NeuronRecord with neuron-id = CAT-N-X (unchanged)
  |     Create NeuronDynamicState (fresh runtime state)
  |     Select FiringModel based on neuron-type
  |     Wrap in ExecutableNeuron
  |     Add to network.neurons table with key = CAT-N-X
  |
  +-- For each synapse:
  |     Create Synapse with synapse-id = CAT-S-Y (unchanged)
  |     Verify source/dest neuron-ids exist
  |     Add to network.synapses table with key = CAT-S-Y
  |     Update connectivity indices
  |
  v
RUNTIME INVARIANTS (enforced at each step)
  |
  +-- network.neurons.size() == 158 (always)
  +-- network.synapses.size() == 102 (always)
  +-- For all n in network.neurons: n.neuron-id matches CAT-N-* pattern
  +-- For all s in network.synapses: s.synapse-id matches CAT-S-* pattern
  +-- For all compartments: parent-neuron-id references valid CAT-N-*
  |
  v
SIMULATION EXECUTION
  |
  +-- Each neuron.step() preserves neuron-id
  +-- Each spike maintains source-neuron-id and target synapse-id
  +-- Each synapse.deliver() routes to dest-neuron-id
  |
  v
TRACE GENERATION
  |
  +-- Each TemporalState snapshot keys all values by CAT-N-* and CAT-S-*
  +-- Spike events recorded with (CAT-N-neuron-id, timestamp)
  +-- No neuron or synapse ID ever regenerated
  |
  v
VERIFICATION & SEALING
  |
  +-- verify-network-integrity() confirms:
  |     ✓ neuron count = 158
  |     ✓ synapse count = 102
  |     ✓ all IDs match CAT-N/S-* pattern
  |     ✓ all morphology parent-links intact
  |     ✓ all connectivity fidelity
  |
  +-- seal-trace() commits hash to WORM archive
  |
  v
OUTPUT
  |
  +-- 158 neurons: CAT-N-0, CAT-N-1, ..., CAT-N-157 (preserved)
  +-- 102 synapses: CAT-S-0, CAT-S-1, ..., CAT-S-101 (preserved)
  +-- Complete execution trace with spike times, membrane potentials
  +-- Sealed cryptographic hash for immutability verification
```

---

## 3. FIRING MODEL PARAMETER TABLES

### 3.1 Pyramidal Cell (Hodgkin-Huxley)

| Parameter | Value | Unit | Notes |
|---|---|---|---|
| g_Na | 120.0 | mS/cm² | Sodium conductance |
| g_K | 36.0 | mS/cm² | Potassium conductance |
| g_L | 0.3 | mS/cm² | Leak conductance |
| E_Na | 115.0 | mV | Sodium reversal potential |
| E_K | -12.0 | mV | Potassium reversal potential |
| E_L | 10.6 | mV | Leak reversal potential |
| C_m | 1.0 | uF/cm² | Membrane capacitance |
| V_rest | -70.0 | mV | Resting potential |
| V_threshold | -40.0 | mV | Action potential threshold |
| tau_m | 10-20 | ms | Membrane time constant |
| tau_ref | 2.0 | ms | Absolute refractory period |
| max_rate | 80.0 | Hz | Maximum firing rate |

### 3.2 Inhibitory Interneuron (Leaky Integrate-and-Fire)

| Parameter | Value | Unit | Notes |
|---|---|---|---|
| tau_m | 20.0 | ms | Membrane time constant |
| V_rest | -70.0 | mV | Resting potential |
| V_threshold | -40.0 | mV | Spike threshold |
| V_reset | -65.0 | mV | Reset potential after spike |
| tau_ref | 5.0 | ms | Refractory period |
| R_m | 40000.0 | ohm-cm² | Specific membrane resistance |
| C_m | 1.0 | uF/cm² | Specific membrane capacitance |
| max_rate | 50.0 | Hz | Maximum firing rate |

### 3.3 Dopaminergic Neuron (Integrate-and-Fire + Modulation)

| Parameter | Value | Unit | Notes |
|---|---|---|---|
| tau_m | 20.0 | ms | Base membrane time constant |
| V_rest | -70.0 | mV | Resting potential |
| V_threshold | -40.0 | mV | Spike threshold |
| V_reset | -65.0 | mV | Reset potential |
| tau_ref | 5.0 | ms | Refractory period |
| modulation_min | 0.5 | (unitless) | Minimum rate modulation (depression) |
| modulation_max | 2.0 | (unitless) | Maximum rate modulation (enhancement) |
| reward_sensitivity | 0.1 | nA^-1 | Modulation strength per input |
| max_rate | 100.0 | Hz | Maximum firing rate |

### 3.4 Sensory Receptor (Simple Spike Generator)

| Parameter | Value | Unit | Notes |
|---|---|---|---|
| base_firing_rate | 5.0 | Hz | Baseline spontaneous activity |
| stimulus_sensitivity | 1.0 | Hz/nA | Rate increase per unit input current |
| max_firing_rate | 100.0 | Hz | Saturation rate |
| adaptation_tau | 100.0 | ms | Time constant for adaptation |
| adaptation_factor | 0.8 | (unitless) | Fractional decrease during sustained input |

---

## 4. PHASE 3 CONNECTOME INSTANTIATION CHECKLIST

- [ ] Create 158 <neuron-record> instances (one per CAT-N-ID)
- [ ] Create 158 <neuron-dynamic-state> instances
- [ ] Assign firing models based on neuron-type (HH, LIF, IF, SG)
- [ ] Wrap each in <executable-neuron>
- [ ] Create 102 <synapse> instances (one per CAT-S-ID)
- [ ] Create <region> instances for 18 anatomical regions
- [ ] Create <circuit> instances for 10 named circuits
- [ ] Build <network> with all neurons and synapses
- [ ] Verify connectivity indices (neuron-to-outgoing, neuron-to-incoming)
- [ ] Initialize <execution-trace> with initial-state snapshot
- [ ] Execute simulation loop for specified duration
- [ ] Perform integrity checks at intervals
- [ ] Generate final trace snapshot
- [ ] Seal trace with hash
- [ ] Emit sealed hash for WORM archival

---

**END OF TEMPLATE AND ARCHITECTURAL SPECIFICATION**

All component specifications are ready for Dylan implementation or translation to other languages while preserving identity and structural integrity.
