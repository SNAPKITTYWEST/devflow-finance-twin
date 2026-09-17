# Neural Execution Engine: Implementation Pseudocode

## Overview

This document provides pseudocode for implementing the neural dynamics execution engine, with focus on handling recurrent connectivity, preserving CAT-N/CAT-S identity, and ensuring deterministic replay.

---

## 1. CORE DATA STRUCTURES

### 1.1 Neuron State Object

```python
class NeuronState:
    """Per-neuron state vector."""
    
    def __init__(self, neuron_id: str, firing_model: str):
        # Identity
        self.neuron_id: str = neuron_id  # CAT-N-XXXXXXXXXXXXXXXX
        self.region: str = extract_region(neuron_id)
        self.firing_model: str = firing_model  # "HH", "LIF", "LIF-mod"
        
        # Membrane potential (mV)
        self.V: float = -65.0
        self.V_prev: float = -65.0
        
        # HH-specific gating variables
        self.m: float = 0.05
        self.h: float = 0.6
        self.n: float = 0.32
        
        # Input current (μA)
        self.I_input: float = 0.0
        
        # Spike tracking
        self.spike_count: int = 0
        self.last_spike_time: float = -1e9
        self.refractory_until: float = 0.0
        
        # Neuromodulators (μM concentration)
        self.dopamine: float = 0.1
        self.acetylcholine: float = 0.1
        self.serotonin: float = 0.1
        
        # Receptor open fractions (one per incoming synapse)
        # Key: synapse_id, Value: open_fraction ∈ [0, 1]
        self.receptor_open: Dict[str, float] = {}
        
        # References to incoming/outgoing synapses
        self.incoming_synapses: List[SynapseRef] = []
        self.outgoing_synapses: List[SynapseRef] = []
        
        # Parameters (class-specific)
        self.params: Dict[str, float] = {}
    
    def is_refractory(self, t: float) -> bool:
        """Check if neuron is in refractory period."""
        return t < self.refractory_until
    
    def get_snapshot(self, t: float) -> Dict:
        """Create timestep snapshot for logging."""
        return {
            "timestamp": t,
            "neuron_id": self.neuron_id,
            "V": self.V,
            "I_input": self.I_input,
            "m": self.m,
            "h": self.h,
            "n": self.n,
            "spike_count": self.spike_count,
            "last_spike_time": self.last_spike_time,
            "dopamine": self.dopamine,
            "acetylcholine": self.acetylcholine,
            "receptor_open": dict(self.receptor_open),  # copy
        }
```

### 1.2 Synapse Object

```python
class Synapse:
    """Synaptic connection between two neurons."""
    
    def __init__(self, synapse_id: str, source_id: str, target_id: str):
        # Identity
        self.synapse_id: str = synapse_id  # CAT-S-XXXXXXXXXXXXXXXX
        self.source_neuron_id: str = source_id  # CAT-N
        self.target_neuron_id: str = target_id  # CAT-N
        
        # Transmission parameters
        self.weight: float = 1.0
        self.delay_ms: float = 1.0  # Minimum 0.1 ms
        self.conductance_max: float = 1.0  # mS/cm²
        self.reversal_potential: float = 0.0  # mV
        
        # Transmitter and receptor types
        self.neurotransmitter: str = "Glutamate"  # or "GABA", "Dopamine", etc.
        self.receptor_type: str = "AMPA"  # or "NMDA", "GABA-A", etc.
        
        # Receptor kinetics parameters
        self.alpha_rate: float = 1.1  # ms^-1
        self.beta_rate: float = 0.19  # ms^-1
        
        # Plasticity (for future)
        self.last_presynaptic_spike: float = -1e9
        self.last_postsynaptic_spike: float = -1e9
    
    def get_conductance(self, source_state: NeuronState, 
                       target_state: NeuronState) -> float:
        """Get effective conductance (with modulation)."""
        g = self.conductance_max
        
        # Dopamine modulation on target
        if self.neurotransmitter == "Glutamate":
            g *= (1.0 + 0.5 * target_state.dopamine)  # Dopamine enhances
        
        return g
```

### 1.3 Event Queue

```python
class SpikeEvent:
    """Event to be delivered at a future timestep."""
    
    def __init__(self, delivery_time: float, source_neuron: str,
                 target_neuron: str, synapse_id: str,
                 neurotransmitter: str, receptor: str,
                 weight: float, amplitude: float = 1.0):
        self.delivery_time: float = delivery_time
        self.source_neuron: str = source_neuron
        self.target_neuron: str = target_neuron
        self.synapse_id: str = synapse_id
        self.neurotransmitter: str = neurotransmitter
        self.receptor: str = receptor
        self.weight: float = weight
        self.amplitude: float = amplitude
    
    def __lt__(self, other: "SpikeEvent") -> bool:
        """Define ordering for heap queue (deterministic)."""
        if self.delivery_time != other.delivery_time:
            return self.delivery_time < other.delivery_time
        # Tie-break by source_neuron ID (lexicographic)
        return self.source_neuron < other.source_neuron


class EventQueue:
    """Priority queue for future spike events."""
    
    def __init__(self):
        self.events: List[SpikeEvent] = []
    
    def push(self, event: SpikeEvent):
        """Add event to queue."""
        heapq.heappush(self.events, event)
    
    def pop_until(self, max_time: float) -> List[SpikeEvent]:
        """Pop all events with delivery_time <= max_time."""
        delivered = []
        while self.events and self.events[0].delivery_time <= max_time:
            delivered.append(heapq.heappop(self.events))
        return delivered
    
    def peek(self) -> Optional[SpikeEvent]:
        """View next event without removing."""
        return self.events[0] if self.events else None
```

### 1.4 Neural Network (Container)

```python
class NeuralNetwork:
    """Entire neural system state."""
    
    def __init__(self):
        # Neurons indexed by CAT-N-ID
        self.neurons: Dict[str, NeuronState] = {}
        
        # Synapses indexed by CAT-S-ID
        self.synapses: Dict[str, Synapse] = {}
        
        # Event queue for future spike deliveries
        self.event_queue: EventQueue = EventQueue()
        
        # Global neuromodulator pools
        self.dopamine_global: float = 0.1
        self.acetylcholine_global: float = 0.1
        self.serotonin_global: float = 0.1
        
        # Time tracking
        self.current_time: float = 0.0
        self.dt: float = 0.001  # 1 ms timesteps
        
        # Logging
        self.spike_log: List[Dict] = []
        self.neuron_log: List[Dict] = []
        self.action_log: List[Dict] = []
        
        # Random seed for reproducibility
        self.random_seed: int = 12345
        self.rng = np.random.RandomState(self.random_seed)
    
    def add_neuron(self, neuron_id: str, model: str, params: Dict):
        """Register a neuron."""
        n = NeuronState(neuron_id, model)
        n.params = params
        self.neurons[neuron_id] = n
    
    def add_synapse(self, synapse_id: str, source_id: str, target_id: str,
                    weight: float, delay_ms: float, transmitter: str,
                    receptor: str):
        """Register a synapse."""
        s = Synapse(synapse_id, source_id, target_id)
        s.weight = weight
        s.delay_ms = max(0.1, delay_ms)  # Enforce minimum delay
        s.neurotransmitter = transmitter
        s.receptor_type = receptor
        
        self.synapses[synapse_id] = s
        
        # Link to neurons
        self.neurons[source_id].outgoing_synapses.append(s)
        self.neurons[target_id].incoming_synapses.append(s)
        
        # Initialize receptor open fraction
        self.neurons[target_id].receptor_open[synapse_id] = 0.0
```

---

## 2. TIMESTEP EXECUTION

### 2.1 Main Simulation Loop

```python
def simulate(network: NeuralNetwork, total_time_ms: float, 
             stimulus_fn: Callable, logging_tier: int = 2):
    """Main simulation driver.
    
    Args:
        network: NeuralNetwork object
        total_time_ms: Total simulation time
        stimulus_fn: Function(t) -> external input to sensory neurons
        logging_tier: 1=sparse, 2=moderate, 3=detailed
    """
    
    dt = network.dt
    num_steps = int(total_time_ms / dt)
    
    for step in range(num_steps):
        t = step * dt
        network.current_time = t
        
        # Single timestep execution
        execute_timestep(network, t, dt, stimulus_fn, logging_tier)
        
        # Progress indicator
        if step % 1000 == 0:
            print(f"  Step {step}/{num_steps} (t={t:.1f} ms)")
    
    print(f"Simulation complete. {len(network.spike_log)} spikes recorded.")
    return network


def execute_timestep(network: NeuralNetwork, t: float, dt: float,
                     stimulus_fn: Callable, logging_tier: int):
    """Execute one timestep of neural dynamics.
    
    ALGORITHM:
      1. Deliver queued events
      2. Aggregate synaptic currents
      3. Integrate neural ODEs
      4. Detect spikes
      5. Queue postsynaptic events
      6. Update neuromodulators
      7. Record state
    """
    
    # === STEP 1: Deliver Queued Events ===
    delivered_events = network.event_queue.pop_until(t + dt)
    
    for event in delivered_events:
        target = network.neurons[event.target_neuron]
        
        # Open postsynaptic receptors
        # (This updates dr/dt for AMPA, NMDA, etc.)
        # The actual current is computed in Step 2
        
        # Queue the event for processing (marker)
        # Receptor kinetics will be updated based on presence of event


    # === STEP 2: Aggregate Synaptic Currents ===
    for neuron in network.neurons.values():
        I_input = 0.0
        
        # Loop through all incoming synapses
        for synapse in neuron.incoming_synapses:
            r_open = neuron.receptor_open[synapse.synapse_id]
            
            source = network.neurons[synapse.source_neuron_id]
            g_eff = synapse.get_conductance(source, neuron)
            
            I_syn = g_eff * r_open * (neuron.V - synapse.reversal_potential)
            I_input += synapse.weight * I_syn
        
        # Add external stimulus
        I_stimulus = stimulus_fn(t, neuron.neuron_id)
        I_input += I_stimulus
        
        neuron.I_input = I_input


    # === STEP 3: Integrate Neural ODEs ===
    spike_events = []
    
    for neuron in network.neurons.values():
        # Check refractory period
        if neuron.is_refractory(t):
            # During refractory: voltage decays to E_rest
            E_rest = neuron.params.get("E_rest", -70.0)
            tau_decay = neuron.params.get("tau_decay_refr", 5.0)
            neuron.V = E_rest + (neuron.V - E_rest) * np.exp(-dt / tau_decay)
            neuron.refractory_until -= dt
            continue
        
        # Save previous voltage for spike detection
        neuron.V_prev = neuron.V
        
        # Integrate ODE based on firing model
        if neuron.firing_model == "HH":
            integrate_hodgkin_huxley(neuron, dt)
        
        elif neuron.firing_model == "LIF":
            integrate_lif(neuron, dt)
        
        elif neuron.firing_model == "LIF-mod":
            integrate_lif_modulated(neuron, dt)


    # === STEP 4: Spike Detection ===
    for neuron in network.neurons.values():
        V_thresh = neuron.params.get("V_thresh", -20.0)
        
        # Detect threshold crossing (from below)
        if neuron.V > V_thresh and neuron.V_prev <= V_thresh:
            spike_events.append((neuron.neuron_id, t))
            
            # Update spike tracking
            neuron.spike_count += 1
            neuron.last_spike_time = t
            neuron.refractory_until = t + neuron.params.get("tau_refr", 2.0)
            
            # Reset voltage
            E_reset = neuron.params.get("E_reset", -70.0)
            neuron.V = E_reset


    # === STEP 5: Queue Postsynaptic Events ===
    for source_id, spike_time in spike_events:
        source_neuron = network.neurons[source_id]
        
        # Find all synapses from this neuron
        for synapse in source_neuron.outgoing_synapses:
            target_id = synapse.target_neuron_id
            
            # CRITICAL: All events queued for FUTURE delivery
            delivery_time = spike_time + synapse.delay_ms
            
            event = SpikeEvent(
                delivery_time=delivery_time,
                source_neuron=source_id,
                target_neuron=target_id,
                synapse_id=synapse.synapse_id,
                neurotransmitter=synapse.neurotransmitter,
                receptor=synapse.receptor_type,
                weight=synapse.weight,
                amplitude=1.0
            )
            
            network.event_queue.push(event)
        
        # Log spike
        if logging_tier >= 1:
            network.spike_log.append({
                "time": t,
                "neuron_id": source_id,
                "spike_index": source_neuron.spike_count,
                "transmitted_synapses": [s.synapse_id for s in source_neuron.outgoing_synapses]
            })


    # === STEP 6: Update Receptor Kinetics ===
    for neuron in network.neurons.values():
        for synapse in neuron.incoming_synapses:
            r = neuron.receptor_open[synapse.synapse_id]
            
            # Determine if transmitter is present
            # (simplified: transmitter present if recent event or natural release)
            T_present = 1.0 if any(
                abs(t - e.delivery_time) < 2.0 
                for e in delivered_events 
                if e.target_neuron == neuron.neuron_id and e.synapse_id == synapse.synapse_id
            ) else 0.0
            
            # dr/dt = α * T * (1 - r) - β * r
            dr_dt = (synapse.alpha_rate * T_present * (1.0 - r) - 
                     synapse.beta_rate * r)
            
            # Update receptor open fraction
            r_new = r + dr_dt * dt
            neuron.receptor_open[synapse.synapse_id] = np.clip(r_new, 0.0, 1.0)


    # === STEP 7: Update Neuromodulators ===
    update_neuromodulators(network, spike_events, dt)


    # === STEP 8: Record State ===
    if logging_tier >= 2 and int(t * 100) % 10 == 0:  # Every 10 ms
        for neuron in network.neurons.values():
            network.neuron_log.append(neuron.get_snapshot(t))
```

---

## 3. ODE INTEGRATORS

### 3.1 Hodgkin-Huxley Integration (RK4)

```python
def integrate_hodgkin_huxley(neuron: NeuronState, dt: float):
    """RK4 integration of HH system.
    
    dV/dt = (1/Cm) * [
      -gNa*m³*h*(V-ENa) - gK*n⁴*(V-EK) - gL*(V-EL) + I_input
    ]
    dm/dt = αm(V)(1-m) - βm(V)m
    dh/dt = αh(V)(1-h) - βh(V)h
    dn/dt = αn(V)(1-n) - βn(V)n
    """
    
    # Extract parameters
    Cm = neuron.params.get("Cm", 1.0)
    gNa = neuron.params.get("g_Na", 120.0)
    gK = neuron.params.get("g_K", 36.0)
    gL = neuron.params.get("g_L", 0.3)
    ENa = neuron.params.get("E_Na", 50.0)
    EK = neuron.params.get("E_K", -77.0)
    EL = neuron.params.get("E_L", -54.0)
    
    # State
    V, m, h, n, I_in = neuron.V, neuron.m, neuron.h, neuron.n, neuron.I_input
    
    def dV_dt(V, m, h, n):
        return (1.0 / Cm) * (
            -gNa * m**3 * h * (V - ENa) -
            gK * n**4 * (V - EK) -
            gL * (V - EL) +
            I_in
        )
    
    def dm_dt(V, m):
        alpha = 0.1 * (V + 40.0) / (1.0 - np.exp(-(V + 40.0) / 10.0))
        beta = 4.0 * np.exp(-(V + 65.0) / 18.0)
        return alpha * (1.0 - m) - beta * m
    
    def dh_dt(V, h):
        alpha = 0.07 * np.exp(-(V + 65.0) / 20.0)
        beta = 1.0 / (1.0 + np.exp(-(V + 35.0) / 10.0))
        return alpha * (1.0 - h) - beta * h
    
    def dn_dt(V, n):
        alpha = 0.01 * (V + 55.0) / (1.0 - np.exp(-(V + 55.0) / 10.0))
        beta = 0.125 * np.exp(-(V + 65.0) / 80.0)
        return alpha * (1.0 - n) - beta * n
    
    # RK4 step
    k1_V = dV_dt(V, m, h, n)
    k1_m = dm_dt(V, m)
    k1_h = dh_dt(V, h)
    k1_n = dn_dt(V, n)
    
    k2_V = dV_dt(V + 0.5*dt*k1_V, m + 0.5*dt*k1_m, h + 0.5*dt*k1_h, n + 0.5*dt*k1_n)
    k2_m = dm_dt(V + 0.5*dt*k1_V, m + 0.5*dt*k1_m)
    k2_h = dh_dt(V + 0.5*dt*k1_V, h + 0.5*dt*k1_h)
    k2_n = dn_dt(V + 0.5*dt*k1_V, n + 0.5*dt*k1_n)
    
    k3_V = dV_dt(V + 0.5*dt*k2_V, m + 0.5*dt*k2_m, h + 0.5*dt*k2_h, n + 0.5*dt*k2_n)
    k3_m = dm_dt(V + 0.5*dt*k2_V, m + 0.5*dt*k2_m)
    k3_h = dh_dt(V + 0.5*dt*k2_V, h + 0.5*dt*k2_h)
    k3_n = dn_dt(V + 0.5*dt*k2_V, n + 0.5*dt*k2_n)
    
    k4_V = dV_dt(V + dt*k3_V, m + dt*k3_m, h + dt*k3_h, n + dt*k3_n)
    k4_m = dm_dt(V + dt*k3_V, m + dt*k3_m)
    k4_h = dh_dt(V + dt*k3_V, h + dt*k3_h)
    k4_n = dn_dt(V + dt*k3_V, n + dt*k3_n)
    
    # Update
    neuron.V += (dt / 6.0) * (k1_V + 2*k2_V + 2*k3_V + k4_V)
    neuron.m += (dt / 6.0) * (k1_m + 2*k2_m + 2*k3_m + k4_m)
    neuron.h += (dt / 6.0) * (k1_h + 2*k2_h + 2*k3_h + k4_h)
    neuron.n += (dt / 6.0) * (k1_n + 2*k2_n + 2*k3_n + k4_n)
    
    # Clip to valid ranges
    neuron.m = np.clip(neuron.m, 0.0, 1.0)
    neuron.h = np.clip(neuron.h, 0.0, 1.0)
    neuron.n = np.clip(neuron.n, 0.0, 1.0)
```

### 3.2 LIF Integration (Euler)

```python
def integrate_lif(neuron: NeuronState, dt: float):
    """Euler integration of LIF.
    
    dV/dt = -(V - E_rest) / τ_m + I_input / C_m
    """
    
    tau_m = neuron.params.get("tau_m", 20.0)
    E_rest = neuron.params.get("E_rest", -70.0)
    C_m = neuron.params.get("C_m", 1.0)
    
    dV_dt = -(neuron.V - E_rest) / tau_m + neuron.I_input / C_m
    
    neuron.V = neuron.V + dt * dV_dt
```

### 3.3 LIF with Modulation

```python
def integrate_lif_modulated(neuron: NeuronState, dt: float):
    """LIF with neuromodulation.
    
    τ_m_eff = τ_m * (1 + ω_D * D + ω_A * A)
    """
    
    tau_m_base = neuron.params.get("tau_m", 20.0)
    omega_D = neuron.params.get("omega_D", -0.1)  # Dopamine shortens
    omega_A = neuron.params.get("omega_A", 0.05)  # ACh lengthens
    
    tau_m_eff = tau_m_base * (1.0 + omega_D * neuron.dopamine + 
                               omega_A * neuron.acetylcholine)
    tau_m_eff = max(tau_m_eff, 1.0)  # Prevent blow-up
    
    E_rest = neuron.params.get("E_rest", -70.0)
    C_m = neuron.params.get("C_m", 1.0)
    
    dV_dt = -(neuron.V - E_rest) / tau_m_eff + neuron.I_input / C_m
    
    neuron.V = neuron.V + dt * dV_dt
```

---

## 4. NEUROMODULATOR UPDATES

```python
def update_neuromodulators(network: NeuralNetwork, spike_events: List,
                          dt: float):
    """Update global neuromodulator pools based on recent spikes."""
    
    # Dopamine release from VTA neurons
    dopamine_release = 0.0
    for neuron_id, spike_time in spike_events:
        neuron = network.neurons[neuron_id]
        if "VTA" in neuron.region or "dopamine_release" in neuron.params:
            release_per_spike = neuron.params.get("dopamine_per_spike", 0.01)
            dopamine_release += release_per_spike
    
    # Dopamine dynamics: dD/dt = -D/τ_D + release
    tau_D = 150.0  # ms
    dD_dt = -network.dopamine_global / tau_D + dopamine_release
    network.dopamine_global = max(0.0, network.dopamine_global + dt * dD_dt)
    
    # Similarly for other modulators...
    
    # Broadcast to all neurons
    for neuron in network.neurons.values():
        neuron.dopamine = network.dopamine_global
        neuron.acetylcholine = network.acetylcholine_global
        neuron.serotonin = network.serotonin_global
```

---

## 5. BEHAVIORAL OUTPUT COMPUTATION

```python
def compute_behavioral_output(network: NeuralNetwork, t: float,
                             window_ms: float = 50.0) -> Dict:
    """Compute motor output and action intensity.
    
    For each motor neuron: spike_rate -> action_intensity
    """
    
    behavioral_output = {
        "timestamp": t,
        "motor_commands": [],
        "cognitive_state": {}
    }
    
    # Motor cortex output
    for neuron_id, neuron in network.neurons.items():
        if "motor_cortex" not in neuron.region:
            continue
        
        # Count spikes in recent window
        recent_spikes = sum(
            1 for spike in network.spike_log
            if spike["neuron_id"] == neuron_id and
            spike["time"] > (t - window_ms)
        )
        
        spike_rate_hz = (recent_spikes / window_ms) * 1000.0
        
        # Map to action intensity
        if spike_rate_hz < 10.0:
            intensity = 0.0
        elif spike_rate_hz < 50.0:
            intensity = (spike_rate_hz - 10.0) / 40.0
        else:
            intensity = 1.0
        
        # Determine body part/action from neuron ID
        body_part = extract_body_part(neuron_id)
        
        behavioral_output["motor_commands"].append({
            "body_part": body_part,
            "intensity": intensity,
            "spike_rate_hz": spike_rate_hz,
            "source_neuron": neuron_id,
            "trace": list(neuron.incoming_synapses) if hasattr(neuron, 'incoming_synapses') else []
        })
    
    return behavioral_output
```

---

## 6. DETERMINISM & REPLAY

```python
def save_checkpoint(network: NeuralNetwork, filename: str):
    """Save complete neural state for replay."""
    
    checkpoint = {
        "current_time": network.current_time,
        "random_seed": network.random_seed,
        "neurons": {
            nid: {
                "V": n.V,
                "m": n.m,
                "h": n.h,
                "n": n.n,
                "dopamine": n.dopamine,
                "acetylcholine": n.acetylcholine,
                "receptor_open": dict(n.receptor_open),
            }
            for nid, n in network.neurons.items()
        },
        "event_queue": [
            {
                "delivery_time": e.delivery_time,
                "source": e.source_neuron,
                "target": e.target_neuron,
                "synapse_id": e.synapse_id,
            }
            for e in network.event_queue.events
        ],
        "global_modulators": {
            "dopamine": network.dopamine_global,
            "acetylcholine": network.acetylcholine_global,
            "serotonin": network.serotonin_global,
        }
    }
    
    import json
    with open(filename, "w") as f:
        json.dump(checkpoint, f, indent=2)


def load_checkpoint(network: NeuralNetwork, filename: str):
    """Restore neural state from checkpoint."""
    
    import json
    with open(filename, "r") as f:
        checkpoint = json.load(f)
    
    network.current_time = checkpoint["current_time"]
    
    for nid, state_dict in checkpoint["neurons"].items():
        n = network.neurons[nid]
        n.V = state_dict["V"]
        n.m = state_dict["m"]
        n.h = state_dict["h"]
        n.n = state_dict["n"]
        n.dopamine = state_dict["dopamine"]
        n.acetylcholine = state_dict["acetylcholine"]
        n.receptor_open = state_dict["receptor_open"]
    
    # Restore event queue...
    # (Note: Ordering must be deterministic via heap)
```

---

## 7. VERIFICATION & TESTING

```python
def verify_determinism(network1: NeuralNetwork, network2: NeuralNetwork,
                       total_time_ms: float, stimulus_fn: Callable) -> bool:
    """Verify two runs produce identical spikes."""
    
    # Run both networks
    simulate(network1, total_time_ms, stimulus_fn, logging_tier=1)
    simulate(network2, total_time_ms, stimulus_fn, logging_tier=1)
    
    # Compare spike logs
    spikes1 = [(s["time"], s["neuron_id"]) for s in network1.spike_log]
    spikes2 = [(s["time"], s["neuron_id"]) for s in network2.spike_log]
    
    if spikes1 == spikes2:
        print("✓ Determinism verified: identical spike sequences")
        return True
    else:
        print("✗ Determinism FAILED: spike sequences diverged")
        print(f"  First difference at: {min(len(spikes1), len(spikes2))}")
        return False


def test_recurrent_stability(network: NeuralNetwork, total_time_ms: float):
    """Verify recurrent circuits have bounded firing rates."""
    
    def stimulus_fn(t, neuron_id):
        # Small constant drive
        return 0.5 if "sensory" in neuron_id else 0.0
    
    simulate(network, total_time_ms, stimulus_fn, logging_tier=1)
    
    # Analyze spike rates
    for neuron_id in network.neurons:
        spikes = [s for s in network.spike_log if s["neuron_id"] == neuron_id]
        spike_rate = len(spikes) / (total_time_ms / 1000.0)
        
        if spike_rate > 500:  # Unrealistic firing rate
            print(f"✗ Neuron {neuron_id} firing at {spike_rate:.0f} Hz (unstable?)")
            return False
    
    print("✓ Recurrent stability verified: bounded firing rates")
    return True
```

