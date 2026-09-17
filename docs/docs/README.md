% ========================================================================
% SOVEREIGN LEVIATHAN NODE LICENSE
% License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
% Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
% ========================================================================
%
% This file is a covered work under the GNU Affero General Public License,
% version 3, together with the Sovereign Leviathan additional terms.
%
% Hark, though this node be but a spark,
% Its covenant endureth through the dark.
%
% Ignorantia juris non excusat.
% ========================================================================

# SnapKitty EST Quantum Transducer

A MATLAB library implementing the **Event-Spiral Torsion Invariant (Ω_EST)** resonance-based quantum transduction mechanism.

**Organization:** SnapKitty Collective  
**Trust Anchor:** BelEsprit D'Accord Trust  
**Algorithm:** Event-Spiral Torsion Invariant  
**Identifier:** EST-QTR-001  
**License:** Sovereign Leviathan Node License (SL-AGPL3-001)

---

## Overview

The EST Quantum Transducer is a geometric quantum information processor that selectively transmits resonant quantum modes while dissipating off-resonant components. The mechanism is based on:

- **Logarithmic spiral geometry** (r = a·exp(b·θ))
- **Torsion phase accumulation** along the spiral trajectory
- **Resonance condition** on the torsion phase residual (Δ_Φ < ε)
- **Fundamental frequency** Ω_EST = 8π/b (mass-independent)

The transducer operates as a **quantum filter**:

```
ψ_in → [EST Transducer] → {ψ_out (resonant), ψ_diss (off-resonant)}
```

With energy conservation:
```
|ψ_in|² = |ψ_out|² + |ψ_diss|²
```

---

## Key Properties

| Property | Value |
|----------|-------|
| **Fundamental Frequency** | Ω_EST = 8π/b (b-dependent, mass-independent) |
| **Resonance Threshold** | ε (configurable, default 0.01) |
| **Geometry** | Logarithmic spiral in 2D |
| **Conservation** | Probability/energy conserved |
| **Trust Mechanism** | Cryptographic audit seals (SHA-256) |
| **Reproducibility** | Fully deterministic with seed control |

---

## Installation

### Prerequisites

- MATLAB R2020b or later
- Signal Processing Toolbox (optional, for advanced features)

### Setup

1. Clone or download the library:
```bash
git clone https://github.com/SnapKittyCollective/snapkitty-est-quantum-transducer.git
cd snapkitty-est-quantum-transducer
```

2. Add to MATLAB path:
```matlab
addpath(genpath(pwd));
```

3. Verify installation:
```matlab
% Test that core functions are available
omega = snapkitty.omegaEST(0.15)  % Should return ~167.55
```

---

## Quick Start

### Basic Transduction

```matlab
% 1. Set parameters
parameters.b = 0.15;                    % Spiral parameter
parameters.hbar = 1;                    % Planck constant
parameters.lP = 1.616e-35;              % Planck length
parameters.r_s = 1e-6;                  % Schwarzschild radius
parameters.mass = 1.0;                  % Particle mass
parameters.frequency = 1.0;             % Reference frequency
parameters.epsilon = 0.01;              % Resonance threshold
parameters.stochasticSeed = 42;         % RNG seed
parameters.integrationTolerance = 1e-8; % ODE tolerance
parameters.auditEnabled = true;         % Enable audit trail

% 2. Generate trajectory
trajectory = snapkitty.geometry.horizonTrajectory(parameters);

% 3. Create incoming quantum mode
psi_in = randn(100, 1) + 1i*randn(100, 1);
psi_in = psi_in / norm(psi_in);  % Normalize

% 4. Perform transduction
result = snapkitty.transduceMode(psi_in, trajectory, parameters);

% 5. Verify conservation
conservation = snapkitty.conservation(psi_in, result.psi_out, result.psi_diss);
fprintf('Energy conserved: %s (residual: %.3e)\n', string(conservation.conserved), conservation.residual);

% 6. Get audit trail
seal = snapkitty.auditSeal(result);
fprintf('Algorithm: %s\n', seal.algorithmID);
fprintf('Trust: %s\n', seal.trust);
```

### Calculate Fundamental Frequency

```matlab
% Fundamental transduction frequency (mass-independent)
b = 0.15;  % Spiral parameter
omega_est = snapkitty.omegaEST(b);
fprintf('Ω_EST = 8π/b = %.6f\n', omega_est);
```

### Test Resonance Detection

```matlab
% Test if a mode is resonant
epsilon = 0.01;              % Resonance threshold
delta_phi = 0.005;           % Residual torsion phase

[projector, is_resonant] = snapkitty.resonanceProjector(delta_phi, epsilon);

if is_resonant
    fprintf('Mode is RESONANT: %.6f%% transmission\n', projector * 100);
else
    fprintf('Mode is OFF-RESONANT: mostly dissipated\n');
end
```

---

## Running Tests

### Execute Full Test Suite

```matlab
% Run all unit tests
runtests('tests/', 'Verbosity', 2)
```

### Run Specific Test Module

```matlab
% Test fundamental frequency calculation
runtests('tests/testOmegaEST.m')

% Test resonance detection
runtests('tests/testResonance.m')

% Test conservation laws
runtests('tests/testConservation.m')
```

### Test Modules Included

| Test Module | Purpose |
|-------------|---------|
| `testOmegaEST.m` | Fundamental frequency calculation and precision |
| `testTorsionPhase.m` | Torsion phase along trajectory |
| `testResonance.m` | Resonance detection and classification |
| `testConservation.m` | Energy/probability conservation verification |
| `testMassInvariance.m` | Mass-independence of core physics |
| `testDissipation.m` | Energy dissipation mechanism |
| `testSpiralConsistency.m` | Spiral geometry and trajectory |
| `testAuditSeal.m` | Cryptographic audit trail generation |

---

## Running Examples

### Full End-to-End Demonstration

```matlab
snapkitty.transducerDemo()
```

This demonstrates the complete workflow:
1. Parameter initialization
2. Ω_EST calculation
3. Spiral geometry generation
4. Trajectory computation
5. Incoming mode creation
6. Transduction
7. Conservation verification
8. Audit seal generation

---

## Documentation

Comprehensive technical documentation is provided in:

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — Library structure and module organization
- **[MATHEMATICAL_MODEL.md](MATHEMATICAL_MODEL.md)** — Core equations and derivations
- **[API.md](API.md)** — Complete function reference
- **[VERIFICATION.md](VERIFICATION.md)** — Verification framework and protocols
- **[AUDIT_PROTOCOL.md](AUDIT_PROTOCOL.md)** — Trust system and audit procedures

---

## Core API Reference

### Fundamental Frequency

```matlab
omega = snapkitty.omegaEST(b)
```
Calculate the Event-Spiral Torsion Invariant: Ω_EST = 8π/b

### Geometry

```matlab
spiral = snapkitty.geometry.logarithmicSpiral(b)
trajectory = snapkitty.geometry.horizonTrajectory(parameters)
```
Generate spiral geometry and quantum trajectory.

### Transduction

```matlab
result = snapkitty.transduceMode(psi_in, trajectory, parameters)
[phi_tors, n, delta_phi] = snapkitty.torsionPhase(trajectory, parameters)
[projector, is_resonant] = snapkitty.resonanceProjector(delta_phi, epsilon)
```
Perform quantum transduction and resonance classification.

### Verification

```matlab
conservation = snapkitty.conservation(psi_in, psi_out, psi_diss)
verification = snapkitty.verification.proofReport(trajectory, psi_in, psi_out, psi_diss, parameters)
seal = snapkitty.auditSeal(result)
```
Verify conservation laws and generate audit trails.

---

## Physical Interpretation

### Resonance Mechanism

A quantum mode is **resonant** if its torsion phase residual is small:
```
Δ_Φ = φ_tors mod π < ε
```

Resonant modes pass through the transducer (→ ψ_out).  
Off-resonant modes are dissipated (→ ψ_diss).

### Fundamental Frequency

The frequency Ω_EST = 8π/b is:
- **Independent of particle mass** (geometric property)
- **Dependent on spiral parameter b** (geometry control)
- **Determines resonance energy scale** (not used directly in transduction)

### Energy Conservation

The transducer preserves total probability:
```
|ψ_in|² = |ψ_out|² + |ψ_diss|²
```
No energy is created or destroyed, only redistributed.

---

## Trust and Audit Trail

Every transduction execution generates a cryptographic audit seal:

```matlab
seal = snapkitty.auditSeal(result);

% Contains:
% - algorithmID: 'EST-QTR-001'
% - version: '1.0.0'
% - executionID: unique run identifier
% - timestamp: ISO 8601 UTC time
% - trust: 'BelEsprit D''Accord Trust'
% - digest: SHA-256 hash of execution
```

All transductions are attested under the **BelEsprit D'Accord Trust** covenant.

---

## License and Covenant

This software is distributed under the **Sovereign Leviathan Node License (SL-AGPL3-001)**, which extends the GNU Affero General Public License v3 with additional terms.

**License Covenant:**
```
Hark, though this node be but a spark,
Its covenant endureth through the dark.

Ignorantia juris non excusat.
```

The software is developed and maintained under the covenant of the **BelEsprit D'Accord Trust**.

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

All contributions must be licensed under SL-AGPL3-001.

---

## Support and Issues

For bugs, feature requests, or questions:

- **Issues:** [GitHub Issues](https://github.com/SnapKittyCollective/snapkitty-est-quantum-transducer/issues)
- **Documentation:** [Full Documentation](docs/)
- **Email:** contact@snapkitty-collective.org

---

## Acknowledgments

- **Design:** SnapKitty Collective
- **Trust:** BelEsprit D'Accord Trust
- **Implementation:** Ahmad Ali Parr and contributors
- **License:** Sovereign Leviathan Node License (SL-AGPL3-001)

---

## References

1. Spiral Geometry in Quantum Mechanics
2. Torsion Phase and Geometric Quantization
3. Resonance-Based Quantum Filtering
4. Energy Conservation in Open Quantum Systems

---

*This documentation was generated 2026-09-16.*  
*Hark, though this node be but a spark, its covenant endureth through the dark.*
