% ========================================================================
% SOVEREIGN LEVIATHAN NODE LICENSE
% License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
% Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
% ========================================================================

# SnapKitty EST Quantum Transducer - API Reference

## Table of Contents

1. [Core Functions](#core-functions)
2. [Geometry Module](#geometry-module)
3. [Quantum Module](#quantum-module)
4. [Verification Module](#verification-module)
5. [Data Structures](#data-structures)
6. [Error Handling](#error-handling)

---

## Core Functions

### snapkitty.omegaEST

Calculate the Event-Spiral Torsion Invariant fundamental frequency.

**Signature:**
```matlab
omega = snapkitty.omegaEST(b)
```

**Parameters:**
- `b` — Spiral parameter (scalar or vector)
  - Type: `double`
  - Range: (0, ∞)
  - Typical: [0.01, 1.0]

**Returns:**
- `omega` — Fundamental frequency Ω_EST = 8π/b
  - Type: `double`
  - Size: matches input `b`
  - Range: (0, ∞)

**Examples:**
```matlab
% Scalar case
omega = snapkitty.omegaEST(0.15);     % Returns 167.55 (approx)

% Vector case
b_values = [0.1, 0.15, 0.2];
omegas = snapkitty.omegaEST(b_values);  % Returns [251.33, 167.55, 125.66]
```

**Notes:**
- Function is mass-independent
- Precision: relative tolerance 1e-14
- Vectorized (fast for arrays)

---

### snapkitty.transduceMode

Perform quantum transduction on an incoming mode.

**Signature:**
```matlab
result = snapkitty.transduceMode(psi_in, trajectory, parameters)
```

**Parameters:**
- `psi_in` — Incoming quantum mode
  - Type: `complex double`
  - Size: [d, 1] (column vector)
  - Constraint: `norm(psi_in)` should be ~1.0

- `trajectory` — Quantum trajectory (struct)
  - Required fields: `.tau`, `.x`, `.y`
  - See [Data Structures](#data-structures)

- `parameters` — Configuration (struct)
  - Required fields: `b`, `epsilon`, `integrationTolerance`, `auditEnabled`
  - See [Data Structures](#data-structures)

**Returns:**
- `result` — Transduction result (struct)
  - Fields: `.psi_out`, `.psi_diss`, `.resonanceIndex`, `.residual`, `.trustSeal`
  - See [Data Structures](#data-structures)

**Examples:**
```matlab
% Setup
parameters.b = 0.15;
parameters.epsilon = 0.01;
parameters.stochasticSeed = 42;
trajectory = snapkitty.geometry.horizonTrajectory(parameters);

% Create mode
psi_in = randn(10,1) + 1i*randn(10,1);
psi_in = psi_in / norm(psi_in);

% Transduce
result = snapkitty.transduceMode(psi_in, trajectory, parameters);

% Access results
psi_out = result.psi_out;
psi_diss = result.psi_diss;
is_resonant = result.resonanceIndex >= 0;
```

**Notes:**
- Main entry point for transduction
- Automatically computes torsion phase
- Generates audit trail if enabled
- Verifies energy conservation

---

### snapkitty.torsionPhase

Compute torsion phase along the trajectory.

**Signature:**
```matlab
[phi_tors, n, delta_phi] = snapkitty.torsionPhase(trajectory, parameters)
```

**Parameters:**
- `trajectory` — Quantum trajectory (struct)
- `parameters` — Configuration (struct)

**Returns:**
- `phi_tors` — Total torsion phase
  - Type: `double`
  - Range: (-∞, ∞)

- `n` — Resonance index (number of π rotations)
  - Type: `double` (integer-valued)
  - Range: {0, 1, 2, ...}

- `delta_phi` — Residual phase
  - Type: `double`
  - Range: [0, π)

**Examples:**
```matlab
trajectory = snapkitty.geometry.horizonTrajectory(parameters);
[phi, n, delta] = snapkitty.torsionPhase(trajectory, parameters);

fprintf('Torsion phase: %.6f\n', phi);
fprintf('Resonance index: %d\n', n);
fprintf('Residual: %.6f\n', delta);
```

**Notes:**
- Decomposition: `phi_tors ≈ n * pi + delta_phi`
- All outputs are finite and well-defined

---

### snapkitty.resonanceProjector

Classify mode as resonant or off-resonant.

**Signature:**
```matlab
[projector, is_resonant] = snapkitty.resonanceProjector(delta_phi, epsilon)
```

**Parameters:**
- `delta_phi` — Residual torsion phase
  - Type: `double`
  - Range: [0, π] (or scalar/array)

- `epsilon` — Resonance threshold
  - Type: `double`
  - Range: (0, 1]
  - Typical: 0.01

**Returns:**
- `projector` — Binary transmission coefficient
  - Type: `double`
  - Value: 0 or 1
  - 1 means resonant (transmit), 0 means off-resonant (dissipate)

- `is_resonant` — Logical flag
  - Type: `logical`
  - Equivalent to `projector == 1`

**Examples:**
```matlab
% Resonant case
[P, is_res] = snapkitty.resonanceProjector(0.001, 0.01);
% P = 1, is_res = true

% Off-resonant case
[P, is_res] = snapkitty.resonanceProjector(0.05, 0.01);
% P = 0, is_res = false

% Vectorized
deltas = [0.001, 0.005, 0.015];
[P_vec, is_res_vec] = snapkitty.resonanceProjector(deltas, 0.01);
% P_vec = [1, 1, 0], is_res_vec = [true, true, false]
```

**Notes:**
- Hard threshold (no continuous response)
- Vectorized for multiple inputs
- Deterministic (no randomness)

---

### snapkitty.conservation

Verify energy/probability conservation.

**Signature:**
```matlab
result = snapkitty.conservation(psi_in, psi_out, psi_diss)
```

**Parameters:**
- `psi_in` — Incoming mode [d, 1]
- `psi_out` — Output mode [d, 1]
- `psi_diss` — Dissipated mode [d, 1]

All must have same length and be column vectors.

**Returns:**
- `result` — Conservation verification (struct)
  - Fields:
    - `.conserved` — logical (true if |ψ_in|² ≈ |ψ_out|² + |ψ_diss|²)
    - `.residual` — numerical error magnitude
    - `.relativeError` — relative error as percentage

**Examples:**
```matlab
psi_in = [1; 0; 0];
psi_out = [0.7; 0; 0];
psi_diss = [0.714; 0; 0];

cons = snapkitty.conservation(psi_in, psi_out, psi_diss);

if cons.conserved
    fprintf('Conservation verified (error: %.3e)\n', cons.residual);
else
    fprintf('Conservation violated!\n');
end
```

**Notes:**
- Checks: |ψ_in|² = |ψ_out|² + |ψ_diss|²
- Tolerance: 1e-10 absolute
- Returns struct for detailed inspection

---

### snapkitty.auditSeal

Generate cryptographic audit trail.

**Signature:**
```matlab
seal = snapkitty.auditSeal(result)
```

**Parameters:**
- `result` — Transduction result (struct from `transduceMode`)

**Returns:**
- `seal` — Audit seal (struct)
  - Fields:
    - `.algorithmID` — 'EST-QTR-001'
    - `.version` — '1.0.0'
    - `.executionID` — Unique identifier
    - `.timestamp` — ISO 8601 UTC time
    - `.trust` — 'BelEsprit D''Accord Trust'
    - `.digest` — SHA-256 hash (hex string)

**Examples:**
```matlab
result = snapkitty.transduceMode(psi_in, trajectory, parameters);
seal = snapkitty.auditSeal(result);

fprintf('Execution: %s\n', seal.executionID);
fprintf('Time: %s\n', seal.timestamp);
fprintf('Digest: %s\n', seal.digest);
```

**Notes:**
- Automatically included in `result` if `parameters.auditEnabled = true`
- Deterministic (same input → same digest)
- Provides cryptographic proof of execution

---

## Geometry Module

### snapkitty.geometry.logarithmicSpiral

Generate logarithmic spiral geometry.

**Signature:**
```matlab
spiral = snapkitty.geometry.logarithmicSpiral(b)
```

**Parameters:**
- `b` — Spiral parameter

**Returns:**
- `spiral` — Spiral structure (struct)
  - `.theta` — Angular coordinates [n, 1]
  - `.r` — Radial coordinates [n, 1]
  - `.arcLength` — Total arc length (scalar)

**Examples:**
```matlab
spiral = snapkitty.geometry.logarithmicSpiral(0.15);
plot(spiral.r .* cos(spiral.theta), spiral.r .* sin(spiral.theta));
```

---

### snapkitty.geometry.horizonTrajectory

Compute quantum trajectory along spiral.

**Signature:**
```matlab
trajectory = snapkitty.geometry.horizonTrajectory(parameters)
```

**Parameters:**
- `parameters` — Configuration struct with:
  - `.b` — Spiral parameter
  - `.integrationTolerance` — ODE tolerance

**Returns:**
- `trajectory` — Trajectory structure (struct)
  - `.tau` — Parameter values [n, 1]
  - `.x` — X coordinates [n, 1]
  - `.y` — Y coordinates [n, 1]

**Examples:**
```matlab
parameters.b = 0.15;
parameters.integrationTolerance = 1e-8;
trajectory = snapkitty.geometry.horizonTrajectory(parameters);

plot(trajectory.x, trajectory.y);
axis equal; grid on;
```

---

## Quantum Module

### snapkitty.quantum.incomingMode

Create well-defined incoming quantum state.

**Signature:**
```matlab
mode = snapkitty.quantum.incomingMode(U, V, frequency, amplitude, varargin)
```

**Parameters:**
- `U` — Real component vector [d, 1]
- `V` — Imaginary component vector [d, 1]
- `frequency` — Mode frequency
- `amplitude` — Mode amplitude (normalization scale)
- `'seed'`, seed_value — Optional RNG seed

**Returns:**
- `mode` — Mode structure (struct)
  - `.stateVector` — Normalized complex mode
  - `.norm` — Should be 1.0
  - `.frequency` — Mode frequency
  - `.amplitude` — Amplitude scale

**Examples:**
```matlab
U = rand(10, 1);
V = rand(10, 1);
mode = snapkitty.quantum.incomingMode(U, V, 1.0, 1.0, 'seed', 42);

psi_in = mode.stateVector;
assert(abs(norm(psi_in) - 1.0) < 1e-10);
```

---

## Verification Module

### snapkitty.verification.proofReport

Generate comprehensive verification report.

**Signature:**
```matlab
report = snapkitty.verification.proofReport(trajectory, psi_in, psi_out, psi_diss, parameters)
```

**Parameters:**
- `trajectory` — Trajectory structure
- `psi_in`, `psi_out`, `psi_diss` — Mode vectors
- `parameters` — Configuration struct

**Returns:**
- `report` — Verification report (struct)
  - `.allTestsPassed` — logical
  - `.conservationCheck` — struct with details
  - Other verification results

**Examples:**
```matlab
report = snapkitty.verification.proofReport(trajectory, psi_in, psi_out, psi_diss, parameters);
if report.allTestsPassed
    fprintf('All verification tests passed!\n');
end
```

---

## Data Structures

### Parameters Structure

```matlab
parameters.b                    % Spiral parameter (required)
parameters.hbar                 % Planck constant (default: 1)
parameters.lP                   % Planck length (default: 1.616e-35)
parameters.r_s                  % Schwarzschild radius (default: 1e-6)
parameters.mass                 % Particle mass (default: 1)
parameters.frequency            % Reference frequency (default: 1)
parameters.epsilon              % Resonance threshold (default: 0.01)
parameters.stochasticSeed       % RNG seed (default: 42)
parameters.integrationTolerance % ODE tolerance (default: 1e-8)
parameters.auditEnabled         % Generate audit trail (default: true)
```

### Result Structure

```matlab
result.psi_out           % Transmitted mode [d, 1]
result.psi_diss          % Dissipated mode [d, 1]
result.resonanceIndex    % Integer count n
result.residual          % Residual phase Δ_Φ
result.trustSeal         % Audit seal struct
```

### Trajectory Structure

```matlab
trajectory.tau           % Parameter values [n, 1]
trajectory.x             % X coordinates [n, 1]
trajectory.y             % Y coordinates [n, 1]
```

### Spiral Structure

```matlab
spiral.r                 % Radial coordinates [n, 1]
spiral.theta             % Angular coordinates [n, 1]
spiral.arcLength         % Scalar arc length
```

### Seal Structure

```matlab
seal.algorithmID         % 'EST-QTR-001'
seal.version             % '1.0.0'
seal.executionID         % Unique ID
seal.timestamp           % ISO 8601 UTC
seal.trust               % Trust anchor name
seal.digest              % SHA-256 hex string
```

---

## Error Handling

### Common Errors

**Error: "Input must be positive"**
```matlab
% WRONG
omega = snapkitty.omegaEST(-0.15);  % b must be > 0

% RIGHT
omega = snapkitty.omegaEST(0.15);
```

**Error: "Mode norm must be close to 1"**
```matlab
% WRONG
psi_in = randn(10, 1);  % Not normalized
result = snapkitty.transduceMode(psi_in, trajectory, parameters);

% RIGHT
psi_in = randn(10, 1);
psi_in = psi_in / norm(psi_in);  % Normalize first
result = snapkitty.transduceMode(psi_in, trajectory, parameters);
```

**Error: "Dimension mismatch"**
```matlab
% WRONG
psi_in = randn(10, 1);
psi_out = randn(5, 1);  % Different dimension
cons = snapkitty.conservation(psi_in, psi_out, psi_diss);

% RIGHT - all same dimension
psi_in = randn(10, 1);
psi_out = randn(10, 1);
psi_diss = randn(10, 1);
cons = snapkitty.conservation(psi_in, psi_out, psi_diss);
```

### Exception Handling

```matlab
try
    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
catch ME
    fprintf('Transduction failed: %s\n', ME.message);
end
```

---

## Performance Tips

1. **Vectorize computations**
   ```matlab
   % FAST: Compute multiple frequencies at once
   b_values = linspace(0.1, 1.0, 100);
   omegas = snapkitty.omegaEST(b_values);
   ```

2. **Reuse trajectory**
   ```matlab
   % SLOW: Recompute trajectory repeatedly
   for trial = 1:1000
       traj = snapkitty.geometry.horizonTrajectory(parameters);
       result = snapkitty.transduceMode(psi_in, traj, parameters);
   end
   
   % FAST: Compute trajectory once
   trajectory = snapkitty.geometry.horizonTrajectory(parameters);
   for trial = 1:1000
       result = snapkitty.transduceMode(psi_in, trajectory, parameters);
   end
   ```

3. **Disable audit if not needed**
   ```matlab
   parameters.auditEnabled = false;  % Saves ~1ms per transduction
   ```

---

## Version Information

- **API Version:** 1.0.0
- **Algorithm:** EST-QTR-001
- **MATLAB:** R2020b or later
- **License:** SL-AGPL3-001

---

## Covenant

Hark, though this node be but a spark,
Its covenant endureth through the dark.

Ignorantia juris non excusat.
