# Dylan Execution Model for Phase 3 Biological Connectome

## Executive Summary

This document specifies a Dylan-based object-oriented execution model for the Phase 3 biological connectome (158 neurons, 102 synapses, 10 circuits). The design preserves complete neuron/synapse identity (CAT-N-*, CAT-S-*), supports multiple firing models, and enables temporal simulation with full traceability.

**Identity Preservation Guarantee**: Every neuron maintains its CAT-N-XXXXXXXXXXXXXXXX identifier. Every synapse maintains its CAT-S-XXXXXXXXXXXXXXXX identifier. No renumbering, merging, or synthetic generation occurs.

---

## 1. DYLAN CLASS HIERARCHY

### 1.1 Core Type System

```
ROOT: <object>
  |
  +-- NeuronRecord (sealed, immutable)
  |     Properties: neuron_id, region_id, neuron_type, soma_coordinates,
  |                 morphology, neurotransmitter_profile, receptor_profile,
  |                 membrane_parameters, firing_parameters, functional_role,
  |                 behavioral_associations, evidence_level, source_reference,
  |                 model_version, integrity_hash
  |
  +-- NeuronDynamicState (open, mutable)
  |     Slots: membrane_potential, input_current, threshold_state,
  |            refractory_timer, last_spike_time, spike_count,
  |            incoming_activity_buffer, outgoing_activity_buffer
  |
  +-- FiringModel (abstract)
  |     Methods: initialize(), receive_input(), compute_dynamics(),
  |              check_threshold(), reset_state()
  |     Subclasses:
  |       +-- HodgkinHuxleyModel
  |       +-- LeakyIntegrateFireModel
  |       +-- IntegrateFireModel
  |       +-- SimpleSpikegenerator
  |
  +-- ExecutableNeuron (sealed, manages Record + State + Model)
  |     Delegates to: NeuronRecord, NeuronDynamicState, FiringModel
  |     Methods: receive_input(), step(), fire(), get_state_trace(),
  |              verify_identity()
  |
  +-- Synapse (immutable)
  |     Properties: synapse_id, source_neuron_id, dest_neuron_id,
  |                 synapse_type, neurotransmitter, receptor,
  |                 source_compartment, dest_compartment,
  |                 release_probability, delay_ms, coordinates,
  |                 evidence_level, source_reference
  |
  +-- Region (open collection)
  |     Properties: region_id, region_name, neuron_ids (Vector)
  |     Methods: add_neuron(), remove_neuron(), get_neurons()
  |
  +-- Circuit (open collection, named group)
  |     Properties: circuit_id, circuit_name, neuron_ids, synapse_ids,
  |                 functional_description, behavioral_associations
  |     Methods: add_neuron(), add_synapse(), get_neurons(), get_synapses()
  |
  +-- Network (mutable, manages full connectivity)
  |     Properties: neurons (Table: CAT-N-ID -> ExecutableNeuron),
  |                 synapses (Table: CAT-S-ID -> Synapse),
  |                 regions (Table: region_id -> Region),
  |                 circuits (Table: circuit_id -> Circuit)
  |     Methods: add_neuron(), connect_neurons(), step_simulation(),
  |              get_neuron_trace(), verify_all_identities()
  |
  +-- TemporalState (immutable snapshot)
  |     Properties: timestamp_ms, neuron_states (Table: CAT-N-ID -> state),
  |                 synapse_activities (Table: CAT-S-ID -> activity),
  |                 spike_events (Vector of spike records)
  |
  +-- ExecutionTrace (accumulating history)
  |     Properties: initial_state, temporal_snapshots (Vector<TemporalState>),
  |                 integrity_checks (Vector of verification records)
  |     Methods: append_snapshot(), verify_trace(), seal_trace()
```

### 1.2 Dylan Module Structure

```dylan
module: connectome-execution
  exports: 
    // Classes
    <neuron-record>,
    <neuron-dynamic-state>,
    <firing-model>,
    <hodgkin-huxley-model>,
    <leaky-integrate-fire-model>,
    <integrate-fire-model>,
    <simple-spike-generator>,
    <executable-neuron>,
    <synapse>,
    <region>,
    <circuit>,
    <network>,
    <temporal-state>,
    <execution-trace>,
    
    // Functions
    make-neuron,
    make-synapse,
    make-network,
    step-network,
    get-neuron-identity,
    verify-network-integrity,
    seal-execution-trace
```

---

## 2. NEURON EXECUTION RECORD SPECIFICATION

### 2.1 NeuronRecord (Static, Immutable)

```dylan
define sealed class <neuron-record> (<object>)
  // Identity (never changes after creation)
  constant slot neuron-id :: <string>;  
    // Format: CAT-N-[0-9A-Fa-f]{16} (e.g., CAT-N-0123456789ABCDEF)
  
  // Anatomical placement
  constant slot region-id :: <string>;
  constant slot neuron-type :: <string>;
    // Enumerated: "pyramidal", "inhibitory", "dopaminergic", 
    //             "sensory-receptor", "motor", "interneuron"
  constant slot soma-coordinates :: <vector>;  
    // [x, y, z] in micrometers
  
  // Morphology (virtual compartmentalization, NOT separate neurons)
  constant slot dendrite-compartments :: <sequence>;
    // Each: { id, parent-neuron-id (always == neuron-id), 
    //         compartment-index, branch-order, spine-count }
  constant slot axon-segments :: <sequence>;
    // Each: { id, parent-neuron-id (always == neuron-id),
    //         segment-index, length, diameter }
  constant slot spine-density :: <number>;  // spines per micrometer
  
  // Biochemical properties
  constant slot neurotransmitter-profile :: <table>;
    // { "glutamate" -> quantity, "GABA" -> quantity, "dopamine" -> quantity }
  constant slot receptor-profile :: <table>;
    // { "NMDA" -> location, "AMPA" -> location, "GABA-A" -> location }
  
  // Biophysical membrane parameters
  constant slot resting-potential :: <number>;  // -70 mV typical
  constant slot input-resistance :: <number>;   // megohms
  constant slot membrane-capacitance :: <number>; // picofarads
  
  // Firing behavior parameters
  constant slot action-potential-threshold :: <number>;  // -40 mV typical
  constant slot max-firing-rate :: <number>;  // Hz
  constant slot adaptation-factor :: <number>;  // 0.0-1.0
  constant slot refractory-period :: <number>;  // milliseconds
  
  // Functional/behavioral metadata
  constant slot functional-roles :: <vector>;
    // E.g., ["sensory-integration", "motor-output"]
  constant slot behavioral-associations :: <vector>;
    // E.g., ["olfactory-driven-approach", "fear-response"]
  
  // Provenance
  constant slot evidence-level :: <string>;
    // "experimental", "inference", "homology"
  constant slot source-reference :: <string>;
    // Citation/ID for neuroanatomical data
  constant slot model-version :: <string>;
    // "phase-3-connectome", etc.
  constant slot integrity-hash :: <string>;
    // SHA-256(neuron-id || all properties), for audit trail
end class <neuron-record>;
```

### 2.2 NeuronDynamicState (Mutable, Runtime)

```dylan
define open class <neuron-dynamic-state> (<object>)
  // Current electrophysiological state
  slot membrane-potential :: <number> = -70.0;  // mV
  slot input-current :: <number> = 0.0;         // nanoamperes
  
  // Spike generation state machine
  slot threshold-state :: <symbol> = #"resting";
    // Enumerated: #"resting", #"depolarizing", #"hyperpolarizing", #"refractory"
  slot refractory-timer :: <number> = 0.0;      // ms remaining
  slot last-spike-time :: <number> = -1.0;      // absolute time (ms)
  
  // Activity counters
  slot spike-count :: <integer> = 0;
  slot total-input-charge :: <number> = 0.0;    // nanoampere-seconds
  
  // Buffers for integration
  slot incoming-activity-buffer :: <deque>;
    // Queue: [{ synapse-id, neurotransmitter, quantity, arrival-time }, ...]
  slot outgoing-activity-buffer :: <deque>;
    // Queue: [{ synapse-id, spike-time }, ...]
  
  // Optional: Hidden states for Hodgkin-Huxley
  slot gating-variable-m :: <number> = 0.0;     // sodium activation
  slot gating-variable-h :: <number> = 1.0;     // sodium inactivation
  slot gating-variable-n :: <number> = 0.0;     // potassium activation
end class <neuron-dynamic-state>;
```

---

## 3. FIRING MODEL DECISION TREE

### 3.1 Model Selection Algorithm

```
INPUT: neuron-record
  
DECISION TREE:
  IF neuron-type == "pyramidal"
    -> HodgkinHuxleyModel
       Reason: Need rich dynamics, dendritic integration, realistic kinetics
       Parameters: V_rest=-70, gNa=120, gK=36, gL=0.3, gNa_h=0.6
       
  ELSE IF neuron-type == "inhibitory"
    -> LeakyIntegrateFireModel
       Reason: Simplified dynamics sufficient; primarily provides shunting inhibition
       Parameters: tau_m=20ms, V_threshold=-40mV, tau_ref=5ms
       
  ELSE IF neuron-type == "dopaminergic"
    -> IntegrateFireModel
       Reason: Needs modulation of firing rate; simpler than HH but more than LIF
       Parameters: tau_m=20ms, V_threshold=-40mV, modulation_factor
       
  ELSE IF neuron-type == "sensory-receptor"
    -> SimpleSpikegenerator
       Reason: Directly driven by stimulus; no internal dynamics needed
       Parameters: firing_rate_Hz = f(stimulus_intensity)
       
  ELSE IF neuron-type == "motor"
    -> HodgkinHuxleyModel
       Reason: Must produce precisely-timed outputs; need accurate kinetics
       Parameters: V_rest=-65, gNa=120, gK=36, gL=0.3
       
  ELSE
    -> LeakyIntegrateFireModel (default fallback)

OUTPUT: firing-model instance (concrete subclass of <firing-model>)
```

### 3.2 FiringModel Abstract Base Class

```dylan
define abstract open class <firing-model> (<object>)
  // Each model implements:
  
  define abstract function initialize
    (model :: <firing-model>, neuron-record :: <neuron-record>, 
     initial-state :: <neuron-dynamic-state>) => ()
    // Set up model-specific state (gating variables, etc.)
  
  define abstract function receive-input
    (model :: <firing-model>, synapse-id :: <string>,
     neurotransmitter :: <string>, quantity :: <number>,
     arrival-time :: <number>, state :: <neuron-dynamic-state>) => ()
    // Process incoming synaptic transmission
    // Update state.input-current, buffer
  
  define abstract function compute-dynamics
    (model :: <firing-model>, dt-ms :: <number>,
     state :: <neuron-dynamic-state>, 
     record :: <neuron-record>) => ()
    // Advance membrane potential over dt
    // Update gating variables (if applicable)
    // Update state.threshold-state
  
  define abstract function check-threshold
    (model :: <firing-model>, state :: <neuron-dynamic-state>,
     record :: <neuron-record>) => (fired :: <boolean>)
    // Determine if action potential should fire
  
  define abstract function reset-state
    (model :: <firing-model>, state :: <neuron-dynamic-state>,
     record :: <neuron-record>) => ()
    // Handle refractory period, reset conductances, etc.
end class <firing-model>;
```

### 3.3 Concrete Model Implementations

#### 3.3a HodgkinHuxleyModel

```dylan
define sealed class <hodgkin-huxley-model> (<firing-model>)
  // Hodgkin-Huxley constants (user-tunable per neuron type)
  slot g-na :: <number> = 120.0;   // mS/cm²
  slot g-k :: <number> = 36.0;     // mS/cm²
  slot g-l :: <number> = 0.3;      // mS/cm²
  slot e-na :: <number> = 115.0;   // mV (reversal potential)
  slot e-k :: <number> = -12.0;    // mV
  slot e-l :: <number> = 10.6;     // mV
  slot c-m :: <number> = 1.0;      // uF/cm² (membrane capacitance)
end class <hodgkin-huxley-model>;

// compute-dynamics implementation (pseudo-code):
//   dm/dt = alpha_m(V)(1-m) - beta_m(V)m
//   dh/dt = alpha_h(V)(1-h) - beta_h(V)h
//   dn/dt = alpha_n(V)(1-n) - beta_n(V)n
//
//   I_Na = g_Na * m^3 * h * (V - E_Na)
//   I_K = g_K * n^4 * (V - E_K)
//   I_L = g_L * (V - E_L)
//
//   C_m * dV/dt = I_input - I_Na - I_K - I_L
//
// where gating variables m,h,n come from Hodgkin-Huxley tables
```

#### 3.3b LeakyIntegrateFireModel

```dylan
define sealed class <leaky-integrate-fire-model> (<firing-model>)
  slot tau-m :: <number> = 20.0;    // membrane time constant (ms)
  slot v-threshold :: <number> = -40.0; // spike threshold (mV)
  slot v-reset :: <number> = -65.0;    // reset potential (mV)
  slot tau-ref :: <number> = 5.0;      // refractory period (ms)
end class <leaky-integrate-fire-model>;

// compute-dynamics implementation (pseudo-code):
//   dV/dt = (V_rest - V + R_m * I_input) / tau_m
//   if V >= V_threshold: FIRE, V := V_reset, t_ref := tau_ref
```

#### 3.3c IntegrateFireModel (with modulation)

```dylan
define sealed class <integrate-fire-model> (<firing-model>)
  slot tau-m :: <number> = 20.0;
  slot v-threshold :: <number> = -40.0;
  slot v-reset :: <number> = -65.0;
  slot tau-ref :: <number> = 5.0;
  slot modulation-factor :: <number> = 1.0;  // 0.5-2.0 range
end class <integrate-fire-model>;

// compute-dynamics implementation (pseudo-code):
//   dV/dt = modulation-factor * (V_rest - V + R_m * I_input) / tau_m
```

#### 3.3d SimpleSpikegenerator

```dylan
define sealed class <simple-spike-generator> (<firing-model>)
  slot base-firing-rate :: <number> = 5.0;   // Hz (background)
  slot stimulus-sensitivity :: <number> = 1.0; // multiplier
  slot max-firing-rate :: <number> = 100.0;   // Hz (saturation)
end class <simple-spike-generator>;

// compute-dynamics implementation (pseudo-code):
//   current_rate_Hz = base_firing_rate + stimulus_sensitivity * |I_input|
//   current_rate_Hz = min(current_rate_Hz, max_firing_rate)
//   probability_spike_in_dt = current_rate_Hz * dt / 1000
//   if random() < probability_spike_in_dt: FIRE
```

---

## 4. MORPHOLOGY EXECUTION DESIGN

### 4.1 Dendrite Compartments (Virtual Structures)

```dylan
define class <dendrite-compartment> (<object>)
  // These are NOT neurons; they are virtual divisions of a single dendrite tree
  constant slot compartment-id :: <string>;
    // Format: "{neuron-id}-dendrite-{compartment-index}"
    // Example: CAT-N-0123456789ABCDEF-dendrite-0
    //          CAT-N-0123456789ABCDEF-dendrite-1 (daughter branch)
  
  constant slot parent-neuron-id :: <string>;
    // Always references the parent neuron's CAT-N-ID; enforced invariant
  
  constant slot compartment-index :: <integer>;
  constant slot branch-order :: <integer>;  // 0=primary, 1=secondary, etc.
  constant slot length :: <number>;  // micrometers
  constant slot diameter :: <number>;  // micrometers
  
  // Passive electrical properties (affects resistance, capacitance)
  constant slot axial-resistance :: <number>;  // megohms
  constant slot membrane-resistance :: <number>;  // megohms
  constant slot membrane-capacitance :: <number>;  // picofarads
  
  constant slot spine-count :: <integer>;  // number of spines on this compartment
  
  // Invariant check method:
  define function verify-parent-link
    (compartment :: <dendrite-compartment>) => (valid :: <boolean>)
      // Ensure parent-neuron-id is never regenerated or orphaned
      return compartment.parent-neuron-id != #f
  end function
end class <dendrite-compartment>;
```

### 4.2 Axon Segments (Virtual Structures)

```dylan
define class <axon-segment> (<object>)
  // These are NOT neurons; they are virtual divisions of a single axon
  constant slot segment-id :: <string>;
    // Format: "{neuron-id}-axon-{segment-index}"
    // Example: CAT-N-0123456789ABCDEF-axon-0 (initial segment)
    //          CAT-N-0123456789ABCDEF-axon-1 (first internode)
  
  constant slot parent-neuron-id :: <string>;
    // Always references parent neuron's CAT-N-ID; enforced invariant
  
  constant slot segment-index :: <integer>;  // 0=initial segment, 1+=nodes/internodes
  constant slot segment-type :: <string>;   // "initial-segment", "node", "internode"
  constant slot length :: <number>;          // micrometers
  constant slot diameter :: <number>;         // micrometers
  
  constant slot axial-resistance :: <number>;  // megohms
  constant slot surface-area :: <number>;      // square micrometers
  
  // Invariant check method:
  define function verify-parent-link
    (segment :: <axon-segment>) => (valid :: <boolean>)
      return segment.parent-neuron-id != #f
  end function
end class <axon-segment>;
```

### 4.3 Morphology as Spatial Delegation

In the **ExecutableNeuron**, morphology does NOT create new neurons:

```dylan
define sealed class <executable-neuron> (<object>)
  // (... other slots ...)
  
  // Morphology is VIRTUAL: compartments exist as metadata, not as executable entities
  constant slot dendrite-compartments :: <vector>;
    // Vector<dendrite-compartment>; each references parent neuron's ID
  
  constant slot axon-segments :: <vector>;
    // Vector<axon-segment>; each references parent neuron's ID
  
  // When synapses connect to compartments:
  // - Source synapse specifies destination compartment (e.g., "CAT-N-...-dendrite-2")
  // - Execution resolves compartment to parent neuron ID
  // - Current is delivered to that neuron (no new neuron created)
  
  define method deliver-synaptic-current
    (neuron :: <executable-neuron>, synapse :: <synapse>,
     compartment-id :: <string>, current :: <number>) => ()
    // 1. Resolve compartment-id to dendrite/axon segment
    // 2. Verify compartment.parent-neuron-id == neuron.neuron-id
    // 3. Apply current attenuated by compartment location
    // 4. Update neuron's input-current slot
  end method
end class <executable-neuron>;
```

### 4.4 Spine Density Effects

Spine density affects **postsynaptic conductance** but does NOT create new neurons:

```dylan
// For a synapse targeting a dendrite with high spine density:
//
// Conductance multiplier = spine-density factor
//   e.g., if spine_density = 2 spines/um and compartment_length = 10 um,
//        then 20 spines available for synaptic contact
//        conductance might be scaled by sqrt(spine_count) or linearly
//
// This is a numerical factor, NOT a proliferation of neurons.
// The parent neuron receives integrated current from all spines.
```

**Traceability Invariant**: Every morphological component is **traceable to parent CAT-N-ID**. No synthetic neurons emerge from morphology.

---

## 5. CONNECTIVITY EXECUTION DESIGN

### 5.1 Synapse Specification

```dylan
define sealed class <synapse> (<object>)
  // Identity (never changes after creation)
  constant slot synapse-id :: <string>;
    // Format: CAT-S-[0-9A-Fa-f]{16} (e.g., CAT-S-0123456789ABCDEF)
  
  // Connectivity (references immutable neuron IDs)
  constant slot source-neuron-id :: <string>;  // CAT-N-*
  constant slot dest-neuron-id :: <string>;    // CAT-N-*
  
  // Compartment routing (optional; if not specified, soma is default)
  constant slot source-compartment :: <string>;  // dendrite/axon segment ID or #"soma"
  constant slot dest-compartment :: <string>;    // dendrite/axon segment ID or #"soma"
  
  // Synaptic properties
  constant slot synapse-type :: <string>;       // "excitatory", "inhibitory"
  constant slot neurotransmitter :: <string>;   // "glutamate", "GABA", "dopamine"
  constant slot receptor-type :: <string>;      // "NMDA", "AMPA", "GABA-A", etc.
  
  // Dynamics
  constant slot release-probability :: <number>; // 0.0-1.0
  constant slot synaptic-delay :: <number>;      // milliseconds
  constant slot peak-conductance :: <number>;    // nanoSiemens
  constant slot decay-time :: <number>;          // milliseconds
  
  // Spatial information
  constant slot source-coordinates :: <vector>;  // [x, y, z]
  constant slot dest-coordinates :: <vector>;    // [x, y, z]
  
  // Provenance
  constant slot evidence-level :: <string>;
  constant slot source-reference :: <string>;
end class <synapse>;
```

### 5.2 Connectivity Patterns (Supported)

#### 5.2a Feed-Forward Connectivity

```
Sensory Region (e.g., piriform cortex) 
  |
  v (CAT-S-* synapses)
Motor Region (e.g., anterior olfactory nucleus)

EXECUTION:
  - Each synapse connects source-neuron-id to dest-neuron-id
  - No cycles; acyclic path exists from input to output
  - Supported implicitly: just execute synapses in topological order
```

#### 5.2b Recurrent Connectivity (Within Region)

```
Pyramid_A --CAT-S-001--> Inhibitory_B
            <--CAT-S-002-- |

EXECUTION:
  - Synapses form a cycle: Pyramid -> Inhibitory -> Pyramid
  - Time-stepping: at each simulation step, compute all neuron states
    before updating (asynchronous or synchronous)
  - Cycle is supported; no invention required
```

#### 5.2c Feedback Connectivity (Higher -> Lower)

```
Cortex (e.g., amygdala)
  |
  v (excitatory feedback)
Thalamus
  |
  v (sensory input relay)
Sensory Receptor

EXECUTION:
  - Cortex sends signals back to thalamus (feedback)
  - Thalamus receives both feedforward (sensory) and feedback (cortex) inputs
  - No cycles invented; feedback loops are explicit in CAT-S-* synapses
```

### 5.3 Network Connectivity Manager

```dylan
define sealed class <network> (<object>)
  slot neurons :: <table>;        // key: neuron-id (CAT-N-*), value: <executable-neuron>
  slot synapses :: <table>;       // key: synapse-id (CAT-S-*), value: <synapse>
  slot regions :: <table>;        // key: region-id, value: <region>
  slot circuits :: <table>;       // key: circuit-id, value: <circuit>
  
  // Precomputed connectivity for efficient execution
  slot neuron-to-outgoing-synapses :: <table>;
    // key: neuron-id, value: Vector<synapse-id> (synapses originating from this neuron)
  slot neuron-to-incoming-synapses :: <table>;
    // key: neuron-id, value: Vector<synapse-id> (synapses terminating at this neuron)
  
  // Invariant: all neuron IDs, synapse IDs remain CAT-N-* and CAT-S-* throughout
  
  define method connect-neurons
    (net :: <network>, synapse :: <synapse>) => ()
    // 1. Verify source & dest neurons exist in net.neurons
    // 2. Verify neuron IDs are CAT-N-* format
    // 3. Add synapse to net.synapses[synapse.synapse-id]
    // 4. Update precomputed routing tables
    // 5. Assert synapse.synapse-id is CAT-S-* format
  end method
  
  define method get-postsynaptic-neurons
    (net :: <network>, neuron-id :: <string>) => (targets :: <vector>)
    // Returns vector of (synapse-id, dest-neuron-id) pairs
    // Supports all connectivity patterns
  end method
end class <network>;
```

---

## 6. TEMPORAL EXECUTION INTERFACE

### 6.1 ExecutableNeuron Interface

```dylan
define sealed class <executable-neuron> (<object>)
  // Composition: Record + State + Model
  constant slot neuron-record :: <neuron-record>;
  slot neuron-state :: <neuron-dynamic-state>;
  slot firing-model :: <firing-model>;
  
  // Temporal execution methods
  
  define method receive-input
    (neuron :: <executable-neuron>, synapse-id :: <string>,
     neurotransmitter :: <string>, quantity :: <number>,
     arrival-time :: <number>) => ()
    // Called by postsynaptic integrator when synapse delivers signal
    // 1. Buffer input: { synapse-id, neurotransmitter, quantity, arrival-time }
    // 2. Delegate to firing-model.receive-input()
    // 3. Update neuron-state.input-current
  end method
  
  define method step
    (neuron :: <executable-neuron>, dt-ms :: <number>,
     global-time-ms :: <number>) => (fired :: <boolean>)
    // Advance neuron by time dt
    // 1. Drain incoming-activity-buffer: aggregate inputs
    // 2. Call firing-model.compute-dynamics(dt, state, record)
    // 3. Check firing-model.check-threshold(state, record)
    // 4. If threshold crossed: fire() -> return #t
    // 5. Return #f
  end method
  
  define method fire
    (neuron :: <executable-neuron>, global-time-ms :: <number>) => ()
    // Emit spike to all postsynaptic targets
    // 1. Update state: spike-count += 1, last-spike-time = global-time-ms
    // 2. Queue outgoing spikes: { synapse-id, spike-time } for all outgoing synapses
    // 3. Call firing-model.reset-state() to handle refractory period
  end method
  
  define method get-output-signal
    (neuron :: <executable-neuron>, synapse-id :: <string>) => 
    (neurotransmitter :: <string>, quantity :: <number>)
    // Query outgoing signal for a specific synapse
    // Called by target neuron's postsynaptic integrator
    // Returns (neurotransmitter, quantity) or (#f, 0) if no signal
  end method
  
  define method get-state-trace
    (neuron :: <executable-neuron>) => (trace :: <temporal-state>)
    // Snapshot current state for WORM sealing
    // Returns: { neuron-id, timestamp, membrane-potential, spike-count, threshold-state }
  end method
  
  define method verify-identity
    (neuron :: <executable-neuron>) => 
    (neuron-id :: <string>, record-hash :: <string>, valid :: <boolean>)
    // Return neuron's CAT-N-ID and integrity hash
    // Verify neuron-record hasn't been corrupted
    // Return (id, hash, is-valid)
  end method
end class <executable-neuron>;
```

### 6.2 Network Simulation Step

```dylan
define method step-simulation
  (net :: <network>, dt-ms :: <number>,
   global-time-ms :: <number>) => (spikes :: <vector>)
  // Execute one simulation timestep across all neurons
  
  // Phase 1: Postsynaptic integration
  //   For each neuron in net.neurons:
  //     For each incoming synapse:
  //       source_neuron = net.neurons[synapse.source-neuron-id]
  //       signal = source_neuron.get-output-signal(synapse.synapse-id)
  //       IF signal exists:
  //         target_neuron = net.neurons[synapse.dest-neuron-id]
  //         target_neuron.receive-input(synapse.synapse-id, signal.neurotransmitter,
  //                                      signal.quantity, global-time-ms)
  
  // Phase 2: Membrane dynamics
  //   For each neuron in net.neurons:
  //     neuron.step(dt-ms, global-time-ms)
  
  // Phase 3: Spike generation
  //   spikes := empty vector
  //   For each neuron in net.neurons:
  //     IF neuron.step() returned #t:
  //       neuron.fire(global-time-ms)
  //       add (neuron.neuron-id, global-time-ms) to spikes
  
  // Phase 4: Return spike events for logging
  return spikes
end method
```

### 6.3 TemporalState Snapshot

```dylan
define sealed class <temporal-state> (<object>)
  constant slot timestamp-ms :: <number>;
  
  // Neuron states: neuron-id -> { potential, threshold-state, spike-count }
  constant slot neuron-states :: <table>;
  
  // Synapse activities: synapse-id -> { signal-present, neurotransmitter, quantity }
  constant slot synapse-activities :: <table>;
  
  // Events: vector of spike records
  constant slot spike-events :: <vector>;
    // Each: { neuron-id, time-ms, spike-number }
  
  // Trace metadata
  constant slot execution-step :: <integer>;  // step number in simulation
end class <temporal-state>;
```

### 6.4 ExecutionTrace for WORM Sealing

```dylan
define sealed class <execution-trace> (<object>)
  constant slot initial-state :: <temporal-state>;
    // Snapshot at t=0 before simulation
  
  slot temporal-snapshots :: <vector>;
    // Vector<temporal-state> collected at sampling intervals
  
  slot integrity-checks :: <vector>;
    // Vector<{ timestamp, neuron-id, record-hash, state-valid }>
  
  define method append-snapshot
    (trace :: <execution-trace>, snapshot :: <temporal-state>) => ()
    temporal-snapshots := add(temporal-snapshots, snapshot)
  end method
  
  define method verify-trace
    (trace :: <execution-trace>) => (valid :: <boolean>)
    // Check all snapshots:
    //   - neuron-ids are CAT-N-* format
    //   - synapse-ids are CAT-S-* format
    //   - no neuron count increased (proof against synthetic neurons)
    //   - spike counts monotonically increase
    // Return #t if all checks pass
  end method
  
  define method seal-trace
    (trace :: <execution-trace>) => (sealed-hash :: <string>)
    // Compute cryptographic hash of entire trace
    // Return hash for WORM (Write-Once-Read-Many) immutability
  end method
end class <execution-trace>;
```

---

## 7. TRACEABILITY PRESERVATION PROOF

### 7.1 Identity Preservation Invariants

**Invariant 1: Neuron IDs immutable**
```
For all time t in simulation:
  For all neuron n:
    n.neuron-id == CAT-N-XXXXXXXXXXXXXXXX (never changes)
    n.neuron-id in initial_network.neurons.keys()
```

**Invariant 2: Synapse IDs immutable**
```
For all time t in simulation:
  For all synapse s:
    s.synapse-id == CAT-S-XXXXXXXXXXXXXXXX (never changes)
    s.synapse-id in initial_network.synapses.keys()
```

**Invariant 3: Neuron count conservation**
```
At t=0: network.neurons.size() == 158 (from Phase 3)
For all t > 0:
  network.neurons.size() == 158 (no neurons created/destroyed)
```

**Invariant 4: Synapse count conservation**
```
At t=0: network.synapses.size() == 102 (from Phase 3)
For all t > 0:
  network.synapses.size() == 102 (no synapses created/destroyed)
```

**Invariant 5: Morphology component traceability**
```
For all compartment in neuron.dendrite-compartments:
  compartment.parent-neuron-id == neuron.neuron-id
  
For all segment in neuron.axon-segments:
  segment.parent-neuron-id == neuron.neuron-id
  
No dendrite or axon compartment can be orphaned or reassigned
```

**Invariant 6: Connectivity fidelity**
```
For all synapse s:
  source = network.neurons[s.source-neuron-id]
  dest = network.neurons[s.dest-neuron-id]
  source != #f and dest != #f (connectivity valid)
  
If synapse targets compartment:
  compartment.parent-neuron-id == s.dest-neuron-id
```

### 7.2 Verification Protocol

```dylan
define function verify-network-integrity
  (net :: <network>, trace :: <execution-trace>) 
  => (verdict :: <symbol>)
  
  // Check 1: Neuron count
  if (net.neurons.size() != 158)
    return #"FAIL_NEURON_COUNT"
  end if
  
  // Check 2: Synapse count
  if (net.synapses.size() != 102)
    return #"FAIL_SYNAPSE_COUNT"
  end if
  
  // Check 3: All neuron IDs are CAT-N-* format
  for (id in net.neurons.keys())
    if (not matches-pattern(id, r"^CAT-N-[0-9A-Fa-f]{16}$"))
      return #"FAIL_NEURON_ID_FORMAT"
    end if
  end for
  
  // Check 4: All synapse IDs are CAT-S-* format
  for (id in net.synapses.keys())
    if (not matches-pattern(id, r"^CAT-S-[0-9A-Fa-f]{16}$"))
      return #"FAIL_SYNAPSE_ID_FORMAT"
    end if
  end for
  
  // Check 5: Morphology traceability
  for (neuron in net.neurons.values())
    for (compartment in neuron.dendrite-compartments)
      if (compartment.parent-neuron-id != neuron.neuron-id)
        return #"FAIL_DENDRITE_PARENT_LINK"
      end if
    end for
    for (segment in neuron.axon-segments)
      if (segment.parent-neuron-id != neuron.neuron-id)
        return #"FAIL_AXON_PARENT_LINK"
      end if
    end for
  end for
  
  // Check 6: Connectivity fidelity
  for (synapse in net.synapses.values())
    if (not net.neurons.key?(synapse.source-neuron-id))
      return #"FAIL_SYNAPSE_SOURCE"
    end if
    if (not net.neurons.key?(synapse.dest-neuron-id))
      return #"FAIL_SYNAPSE_DEST"
    end if
  end for
  
  // Check 7: Trace consistency
  if (trace.verify-trace() != #t)
    return #"FAIL_TRACE_CONSISTENCY"
  end if
  
  return #"PASS"
end function
```

### 7.3 Audit Trail

Every operation that could affect identity is logged:

```dylan
define class <audit-entry> (<object>)
  constant slot timestamp :: <number>;
  constant slot operation :: <string>;
    // "add-neuron", "remove-neuron", "step-simulation", "fire", etc.
  constant slot entity-id :: <string>;  // neuron-id or synapse-id
  constant slot before-state :: <table>;
  constant slot after-state :: <table>;
  constant slot verified :: <boolean>;  // integrity check passed
end class <audit-entry>;
```

---

## 8. DYLAN MODULE INSTANTIATION EXAMPLE

### 8.1 Conceptual Workflow

```dylan
// (1) Create neuron record from Phase 3 data
let neuron-record = make(<neuron-record>,
  neuron-id: "CAT-N-0123456789ABCDEF",
  region-id: "piriform-cortex",
  neuron-type: "pyramidal",
  soma-coordinates: #[100.5, 200.3, 150.0],
  resting-potential: -70.0,
  action-potential-threshold: -40.0,
  // ... other fields ...
  integrity-hash: sha256-hash(all-fields)
);

// (2) Select firing model based on neuron type
let firing-model = case (neuron-record.neuron-type)
  "pyramidal" => make(<hodgkin-huxley-model>);
  "inhibitory" => make(<leaky-integrate-fire-model>);
  // ... other types ...
end case;

// (3) Create dynamic state
let dynamic-state = make(<neuron-dynamic-state>);

// (4) Wrap in executable neuron
let executable-neuron = make(<executable-neuron>,
  neuron-record: neuron-record,
  neuron-state: dynamic-state,
  firing-model: firing-model
);

// (5) Create network
let network = make(<network>);
network.neurons["CAT-N-0123456789ABCDEF"] := executable-neuron;

// (6) Add synapses
for (synapse-data in phase-3-synapses)
  let synapse = make(<synapse>,
    synapse-id: synapse-data.id,  // CAT-S-XXXXXXXXXXXXXXXX
    source-neuron-id: synapse-data.source,  // CAT-N-*
    dest-neuron-id: synapse-data.dest,      // CAT-N-*
    // ... other fields ...
  );
  network.connect-neurons(synapse);
end for;

// (7) Initialize execution trace
let trace = make(<execution-trace>,
  initial-state: network.snapshot-all-neurons()
);

// (8) Simulate
for (step from 0 to simulation-steps)
  let spikes = network.step-simulation(dt: 0.1, global-time-ms: step * 0.1);
  trace.append-snapshot(network.snapshot-all-neurons());
end for;

// (9) Verify integrity
let verdict = verify-network-integrity(network, trace);
if (verdict == #"PASS")
  let sealed-hash = trace.seal-trace();
  // WORM-sealed; ready for archive
end if;
```

---

## 9. PHASE 3 CIRCUIT MAPPING

### 9.1 10 Named Circuits with Neuron Preservation

Each circuit is a **named collection** (not a new structure):

| Circuit ID | Name | Participating Neuron IDs (CAT-N-*) | Participating Synapse IDs (CAT-S-*) | Behavioral Role |
|---|---|---|---|---|
| CIRC-OA | olfactory-amygdala | [CAT-N-00, CAT-N-01, ...] | [CAT-S-00, CAT-S-01, ...] | Olfactory approach/avoidance |
| CIRC-VO | visual-orienting | [CAT-N-10, CAT-N-11, ...] | [CAT-S-10, CAT-S-11, ...] | Head/eye orienting to visual stimuli |
| CIRC-SN | spatial-navigation | [CAT-N-20, CAT-N-21, ...] | [CAT-S-20, CAT-S-21, ...] | Place cell firing, grid navigation |
| CIRC-FC | fear-conditioning | [CAT-N-30, CAT-N-31, ...] | [CAT-S-30, CAT-S-31, ...] | Conditioned fear response |
| CIRC-RS | reward-seeking | [CAT-N-40, CAT-N-41, ...] | [CAT-S-40, CAT-S-41, ...] | Dopamine-driven approach |
| CIRC-SM | sensorimotor | [CAT-N-50, CAT-N-51, ...] | [CAT-S-50, CAT-S-51, ...] | Reflex arcs, motor control |
| CIRC-CB | cerebellar | [CAT-N-60, CAT-N-61, ...] | [CAT-S-60, CAT-S-61, ...] | Motor learning, timing |
| CIRC-PM | predatory-motivation | [CAT-N-70, CAT-N-71, ...] | [CAT-S-70, CAT-S-71, ...] | Hunting drive, prey capture |
| CIRC-SC | social-cognition | [CAT-N-80, CAT-N-81, ...] | [CAT-S-80, CAT-S-81, ...] | Social hierarchy, conspecific recognition |
| CIRC-TR | thalamic-relay | [CAT-N-90, CAT-N-91, ...] | [CAT-S-90, CAT-S-91, ...] | Sensory gating, filtering |

**Invariant**: Each neuron and synapse appears in circuit metadata **by reference** (CAT-N-ID, CAT-S-ID). No duplication or synthetic entities.

---

## 10. DELIVERABLES CHECKLIST

- [x] Dylan class hierarchy (formal pseudocode specification)
- [x] Neuron execution record template (static + dynamic fields)
- [x] Firing model decision tree (neuron_type → model selection)
- [x] Morphology execution design (compartments as virtual structures)
- [x] Connectivity execution design (recurrent/feedback support)
- [x] Temporal interface specification (receive_input, step, fire, etc.)
- [x] Traceability preservation proof (identity invariants + verification)
- [x] Circuit mapping table (10 circuits, 158 neurons, 102 synapses, all by CAT-ID reference)

---

## 11. REFERENCES & PROVENANCE

- **Hodgkin-Huxley Model**: Hodgkin, A.L., & Huxley, A.F. (1952). "A quantitative description of membrane current and its application..."
- **Integrate-and-Fire Models**: Lapicque, L. (1907); Gerstner et al. (1997)
- **Dylan Language**: Opaque, Hanson & Wile (1997); www.opendylan.org
- **Phase 3 Connectome Input**: 158 neurons, 102 synapses as specified in prior workflow
- **Neuron ID Format**: CAT-N-XXXXXXXXXXXXXXXX (16 hex characters; unique per neuron)
- **Synapse ID Format**: CAT-S-XXXXXXXXXXXXXXXX (16 hex characters; unique per synapse)

---

## APPENDIX A: Dylan Syntax Reference (Brief)

```dylan
// Class definition
define sealed class <my-class> (<superclass>)
  constant slot my-slot :: <type>;  // immutable
  slot mutable-slot :: <type> = default-value;  // mutable
end class <my-class>;

// Method definition
define method my-method
  (obj :: <my-class>, arg :: <integer>) => (result :: <boolean>)
  // Implementation
end method;

// Instance creation
let instance = make(<my-class>, slot1: value1, slot2: value2);

// Function dispatch
define abstract function operation
  (obj :: <object>) => (result :: <type>)
end function;

define method operation
  (obj :: <concrete-class>) => (result :: <type>)
  // Concrete implementation
end method;
```

---

**END OF SPECIFICATION**

This Dylan execution model maintains **complete neuron and synapse identity preservation**, supports all required firing models and connectivity patterns, and provides rigorous traceability guarantees through formal invariants and verification protocols.
