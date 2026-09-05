# verilog-a

**Analog/Mixed-Signal Circuits** — Continuous-time trigonometric processors, Riemann zeta zero unfolding, Chua's circuit integration, and cross-domain SPARK-to-Verilog-A mapping.

## Files

| File | Description |
|------|-------------|
| `trig_braid_processor.va` | Braid trigonometric processor (φ-weighted) |
| `trig_processor.va` | Simple trig processor (sin/cos) |
| `braid_trig_processor.va` | Minimal braid trig (metatron φ) |
| `SPARK_TO_VERILOG_A.md` | Cross-domain spec mapping |
| `CHUAS_CIRCUIT.md` | Chua's circuit equations, Python, Lyapunov |
| `RIEMANN_ZETA_VERILOG_A.md` | ζ zero unfolding via Verilog-A |
| `ZETA_UNFOLD_REVERSE_ENGINEERING.md` | Reverse engineering of zeta_unfold_node |
| `CHUA_INJECTION.md` | Chua's diode into zeta_unfold_node |
| `LYAPUNOV_VERIFICATION.md` | Lyapunov analysis (analytical failure, protocol) |
| `SPARK_TO_VERILOG_A.md` | SPARK contracts → Verilog-A mapping |

## Core Modules

### Trigonometric Processors

| Module | Purpose |
|--------|---------|
| `trig_braid_processor.va` | Full φ-weighted braid matrix ρ(σ₁) with bounds |
| `trig_processor.va` | Simple sin/cos with boundary checks |
| `braid_trig_processor.va` | Minimal metatron φ processor |

### Riemann Zeta Unfolding

```verilog
module zeta_unfold_node (in, out);
  // Logarithmic dispersion: ln(|V|/(2πe) + 1)
  // Nonlinear charge/flux integration
  // Berry-Keating H = xp via OTAs
  // Riemann-Siegel Z-function PLL
endmodule
```

### Chua's Circuit Integration

- Injects piecewise-linear Chua diode into zeta_unfold_node
- Breaks functoriality via time-dependent offset
- Proves topological rupture (Jacobian J ≠ 1)

### Lyapunov Verification

- Analytical: FAILED (log singularity, no smooth ODE)
- Numerical: Protocol defined (Benettin algorithm)
- Sealed: LYAPUNOV_STATUS with SEAL_LYAP

## Cross-Domain Mapping

| SPARK Contract | Verilog-A | Transistor Equivalent |
|----------------|-----------|----------------------|
| Bounded Integer | Voltage Rails | Supply clamping |
| State Invariant | Steady-state nodal balance | Collector/drain equilibrium |
| Matrix Multiplier | VCVS / Gilbert cell | Translinear loop |
| Hash Integrity | Non-linear mixing | Exponential mixer |

## Simulation

```bash
# Requires Verilog-AMS simulator (Spectre, Xyce, ngspice)
# For GPU acceleration: custom CUDA kernel pipeline
```

## Key Results

| Analysis | Status |
|----------|--------|
| Circuit extraction | PROVEN |
| Token map (9 tokens) | PROVEN |
| Operator map (4 operators) | PROVEN |
| Fibonacci test | FALSE |
| Functoriality | CONJECTURED |
| Lyapunov analytical | FAILED |
| Lyapunov numerical | PROTOCOL_DEFINED |
| Chua injection | TOPOLOGICAL_RUPTURE |