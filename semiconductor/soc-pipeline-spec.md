# SoC Pipeline Specification: System Architecture → Fabrication
*Full production-depth trace — 5nm-class FinFET representative assumptions*

All numerical values labeled: **[Measured]** / **[Published]** / **[Estimated]** / **[Hypothetical]**.  
Proprietary foundry parameters: *"Publicly unavailable; representative assumptions used."*

---

## 1. System Architecture

**Target Application:** High-performance edge AI inference SoC — vision/sensor fusion (autonomous systems, smart cameras, industrial). Primary: INT8/INT4 throughput, TOPS/W efficiency, deterministic latency. Secondary: FP16, functional safety.

**Performance Targets [Hypothetical]:**
- Peak INT8 throughput: 32–64 TOPS
- Efficiency: 4–8 TOPS/W (typical workload)
- Package power: 8–15 W
- Die size: 80–120 mm²
- Temperature range: −40°C to 125°C

**Compute Architecture (Heterogeneous):**
- 4× OoO 64-bit RISC-V application cores (4-wide issue, 128-entry ROB)
- 2× tightly-coupled AI matrix engines (16×16 systolic arrays, INT8/INT4, sparse support)
- Hardware accelerators: convolution sequencing, activation, quantization, reduction
- Shared coherent memory system with directory-based coherence

**Hierarchical Block Structure:**
```
SoC
├── Core Cluster
│   ├── Core 0–3 (OoO RV64, private L1I/L1D)
├── AI Cluster
│   ├── MatrixEngine 0 & 1 (systolic PE array + local SRAM)
├── Shared L2 Cache + Coherence Directory
├── NoC / Coherent Interconnect
├── Memory Controllers + PHY (LPDDR5 / HBM2e)
├── I/O Subsystem (PCIe Gen4/5, MIPI CSI/DSI, SerDes, GPIO, JTAG)
├── Security Island (RoT, crypto accelerators, secure boot)
├── Power Management Unit
└── Test & Debug Fabric (scan, BIST, trace)
```

**Clock Domains:** Core, AI, memory, I/O, always-on, analog/PLL. Per-domain DVFS. Synchronizers/async FIFOs at crossings.

**Power Domains:** Per-core, AI engines, SRAM banks, I/O, always-on, security island, analog. Isolation cells + level shifters at every boundary. Multi-voltage islands.

**Security:** Hardware root-of-trust, secure boot ROM, AES/SHA/public-key accelerators, memory encryption/isolation, side-channel countermeasures, secure debug authentication.

**Test/Debug:** Full scan, memory BIST, logic BIST, boundary scan, on-chip trace, performance counters, authenticated debug ports.

---

## 2. Custom ISA

**Base:** RISC-V RV64GC (Integer + M + A + F/D + C).

**Custom Extensions:**
- Matrix MAC (dense and sparse), vector load/store with post-increment and gather/scatter
- Quantization/activation helpers, prefetch and cache-control hints for AI streams
- Secure monitor call instructions for security island

**Encoding:** RISC-V custom-0/custom-1 opcode space. Fixed 32-bit with 16-bit compressed forms where beneficial.

**Privilege Levels:** U, S, H (Hypervisor, optional), M, + Secure Monitor mode.

**Memory Model:** RVWMO + acquire/release for AI engines. Atomic ops and LR/SC supported.

**Custom CSRs:** AI engine control/status, performance counters, power/clock control, key management, debug/trace control.

---

## 3. Verilog / SystemVerilog

**Primary HDL:** SystemVerilog (IEEE 1800).

**Coding Rules:**
- Synthesizable constructs only in production path
- Explicit clock and reset on every sequential block; no initial blocks in synthesizable code
- Parameterized modules (core count, cache size, AI array dimension)
- SystemVerilog interfaces + modports for major buses
- SVA assertions for protocol and pipeline correctness

**Packages:**
- `isa_pkg` — opcode definitions, CSR addresses, exception codes
- `types_pkg` — instruction, micro-op, cache-line types
- `params_pkg` — architectural parameters

---

## 4. ALU + Registers + Control

**ALU Operations:**
- ADD/SUB (with overflow/carry), AND/OR/XOR, shifts (logical/arithmetic)
- SLT/SLTU, MUL (high/low), DIV/REM (multi-cycle)

Critical path: 64-bit prefix adder (Kogge-Stone/Brent-Kung) + barrel shifter. Multiplier uses Booth encoding + Wallace tree reduction (2–4 pipeline stages at 5nm frequencies).

**Register File:**
- 32 architectural integer + 32 FP registers (x0 hard-wired zero)
- ~64–96 physical integer registers for renaming **[Estimated]**
- Multi-ported (4–8 read, 2–4 write) with bypass network

**Control Logic:** Combinational decode tables + sequential FSMs for pipeline control, flush/recovery, exception prioritization.

---

## 5. Pipeline

**Stages (4-wide OoO):**

| # | Stage           | Function                                         |
|---|-----------------|--------------------------------------------------|
| 1 | Fetch           | I-cache access, branch prediction, next-PC calc  |
| 2 | Decode          | Instruction → micro-ops, immediate extraction    |
| 3 | Rename          | Architectural → physical register mapping        |
| 4 | Dispatch/Issue  | Reservation stations, operand readiness          |
| 5 | Execute         | ALU / MUL / FPU / custom AI units                |
| 6 | Memory          | Address gen, TLB, cache access, alignment        |
| 7 | Writeback       | Results to physical register file / bypass       |
| 8 | Commit          | In-order retirement, exception check             |

**Branch Predictor:** Tournament or TAGE-style + BTB + RAS **[Estimated]**.  
**ROB Size:** 128 entries **[Estimated]**.  
**Hazard Handling:** Forwarding (data), prediction + recovery (control), arbitration (structural).

---

## 6. Cache / SRAM

| Cache         | Size    | Assoc | Line | Type          | Notes                    |
|---------------|---------|-------|------|---------------|--------------------------|
| L1I (per core)| 48 KB   | 8-way | 64B  | VIPT          | Parity/ECC               |
| L1D (per core)| 48 KB   | 8-way | 64B  | VIPT, WB/WA   | ECC                      |
| Shared L2     | 4 MB    | 16-way| 64B  | Inclusive, WB | Directory coherence, ECC |
| AI Scratchpad | Variable| Multi-bank | — | SW-managed   | 8T cells for low-V option|

**Bit Cells:** 6T high-density for main arrays; 8T/10T for multi-port or low-voltage AI buffers.  
**Coherence:** Directory-based MESI or MOESI variant.

---

## 7. Bus / NoC

**Topology:** Mesh (scalable) or hierarchical crossbar (simpler for small agent counts).

**Protocol:** ACE- or CHI-like coherent protocol. Separate request/response/data channels. Transaction IDs, coherence commands (ReadShared, ReadUnique, WriteBack, etc.).

**Features:**
- Virtual channels for deadlock avoidance
- QoS classes (real-time AI traffic prioritized over best-effort)
- Credit-based flow control; flit size matched to cache line

**Router Microarchitecture:** Input buffers, routing computation, VC allocation, switch allocation, crossbar.

**Memory Controller Interface:** NoC connects to controllers scheduling DRAM/HBM commands and managing refresh.

---

## 8. CPU Core

Each core contains: full 8-stage OoO pipeline, private L1I/L1D, local interrupt controller interface, FPU, performance counters, debug/trace port, power-gating/retention control.

**Physical Register File:** 128–160 physical registers to support renaming **[Estimated]**.

**Load/Store Unit:** Address generation, TLB, store buffer, load queue, memory ordering.

**FPU:** IEEE-754 single and double precision with FMA.

---

## 9. SoC Integration

**Top-Level Integration:** All cores, AI engines, L2, NoC, memory controllers, I/O, security island, PMU, and test fabric instantiated and connected.

**Address Map:** Unified physical space — DRAM, SRAM, MMIO, CSRs.

**Boot Sequence:** Secure boot ROM authenticates first-stage bootloader; subsequent stages verified before execution.

**Clock/Reset Distribution:** Global reset tree with synchronized de-assertion; per-domain clock trees balanced.

**Power Grid:** Multi-layer mesh. Isolation cells and retention registers at domain boundaries.

**PHY Integration:** Hard macros for SerDes, PCIe, MIPI, memory PHY placed and connected.

---

## 10. Synthesis

**Flow:**
1. RTL elaboration
2. High-level optimizations (constant propagation, DCE, retiming, resource sharing)
3. Technology mapping to standard-cell library
4. Gate-level netlist + timing/power reports

**Constraints:** Clock definitions + uncertainty, I/O delays, false/multi-cycle paths, max transition/capacitance, power intent (UPF/CPF).

**Quality Metrics:**
- Cell utilization, critical path slack, total negative slack
- Leakage and dynamic power estimates
- Fanout distribution

**Output:** Technology-mapped gate-level Verilog, SDC, power intent, area/timing/power reports.

---

## 11. Place & Route

**Floorplan:** Die dimensions → core area → macro placement (SRAM, PLL, PHY) → standard-cell rows → I/O ring → multi-layer power grid → clock regions → keep-outs.

**Placement:** Macro placement first; standard-cell placement optimizing timing/congestion/wire length/power. Critical paths, high-fanout nets, long interconnects identified and mitigated.

**CTS:** Balanced H-tree or mesh+tree hybrid. Buffer insertion for skew/transition. Skew target < 20–50ps depending on domain **[Estimated]**.

**Routing:** Multi-layer metal stack. Signal, clock, and power routing. Via insertion, antenna fixing, crosstalk/SI optimization.

**Signoff Loops:** Timing, congestion, DRV-driven repair (buffering, sizing, layer promotion).

**Parasitic Extraction:** RC extracted from routed layout; timing and power re-analyzed.

---

## 12. GDSII / OASIS

**Output:** Final placed-and-routed layout in GDSII or OASIS.

**Physical Verification:**
- DRC: geometry vs. manufacturing rule deck (zero violations or waived with justification)
- LVS: layout vs. gate-level netlist (device count, connectivity, parameters must match)
- ERC, antenna, density, metal-fill, IR-drop, EM, SI signoff

**Mask Data Preparation:**
- Optical Proximity Correction (OPC)
- Multiple-patterning decomposition (LELE, SADP, SAQP where needed)
- Reticle layout + alignment mark insertion
- Fracture for mask writer

---

## 13. Fabrication

### FEOL — Transistor Formation (FinFET representative)

1. **Wafer start:** Czochralski Si ingot → 300mm wafer slice → CMP → RCA clean
2. **Pad oxide + LPCVD nitride:** STI hard-mask
3. **Fin definition:** EUV or multi-patterned DUV lithography
4. **Fin etch:** Anisotropic RIE → vertical fins (height/width per process spec *[publicly unavailable]*)
5. **STI:** Oxide fill → CMP → nitride strip → oxide recess
6. **Well implants:** N-well (phosphorus), P-well (boron), Vt adjust implants
7. **Gate dielectric:** Interfacial oxide + ALD HfO₂ or equivalent high-k
8. **Metal gate:** Work-function metals + fill; gate-last (replacement) flow typical
9. **Spacers:** Dielectric spacers for S/D offset
10. **Epitaxial S/D:** Raised SiGe (PMOS) or Si:C/Si (NMOS) + doping
11. **Silicide/contacts:** Low-resistance contacts; W or Co fill with barrier

### MOL → BEOL — Interconnect Stack

12. **ILD deposition:** Low-k or ULK dielectrics
13. **Dual-damascene:** Via + trench lithography + etch
14. **Barrier/liner:** TaN/Ta or alternative
15. **Cu electroplate + CMP:** Repeat per metal layer; local layers tight pitch, upper layers thick for power/clock
16. **Passivation:** Final dielectric + nitride/oxide; bond-pad openings

### Process Notes

- **Lithography:** DUV 193nm immersion for many layers; EUV 13.5nm for critical layers. EUV wavelength ≠ gate length — resolution extended by multiple patterning + OPC + process integration.
- **Deposition:** ALD preferred for conformal films at high AR; CVD for dielectrics; PVD for barriers/metals; epitaxy for S/D.
- **Etch:** Anisotropic RIE; high selectivity, endpoint detection, sidewall profile control.
- **Doping:** Ion implantation → activation anneal; junction depth and Vt controlled per spec.
- **Yield:** Defect density monitoring, CD uniformity, overlay control, process-window centering. Variation exists wafer-to-wafer, die-to-die, and within-die.

---

## Full Traceability Chain

```
SPECIFICATION
    ↓ architecture validation, performance modeling
ARCHITECTURE (custom ISA, block diagram, interfaces)
    ↓ RTL coding, functional simulation, formal verification
RTL (SystemVerilog — ALU, registers, control, pipeline, cache, NoC, CPU, SoC)
    ↓ unit-level + system-level verification, emulation, FPGA prototype
SYNTHESIS (gate-level netlist, timing/area/power reports)
    ↓ standard-cell library characterization
PLACE & ROUTE (floorplan → placement → CTS → routing → physical verification)
    ↓ parasitic extraction, STA signoff, IR/EM signoff
GDSII / OASIS
    ↓ OPC + multiple-patterning decomposition + mask fracture
MASK / RETICLE DATA
    ↓ EUV + DUV lithography + process integration
WAFER FABRICATION (FEOL — transistors)
    ↓
BEOL (interconnect stack — M0 through upper metals)
    ↓ wafer probe/sort
DICED DIE → PACKAGING (flip-chip / 2.5D / chiplets)
    ↓ final test, qualification
TESTED & QUALIFIED SILICON
```

**At each transition:** input artifact, output artifact, primary tools, validation method, common failure modes, and governing physical/logical constraints are defined.

---

## Appendix: Transistor Density Estimates [Hypothetical]

1 cm² = 100 mm².

| Logic Density | Transistors on 100 mm² |
|---------------|------------------------|
| 100 MTr/mm²   | ~10 billion            |
| 150 MTr/mm²   | ~15 billion            |
| 200 MTr/mm²   | ~20 billion            |

SRAM density typically higher than random logic. Marketing node numbers ("5nm") are **not** equal to physical gate length or absolute density — they are scaling indicators.

---

*Source: Ahmad (ahmedparr93@gmail.com), Sep 18, 2026 — Full Production Build series*
