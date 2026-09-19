# EDA Flow & Physical Design
*Phases 6–12*

---

## Phase 6: EDA Toolchain

### Open-Source Flow (OpenROAD)

RTL → Yosys (Synthesis) → OpenROAD (Floorplan → Placement → CTS → Routing → DRC/LVS) → KLayout (GDSII) → Netgen (LVS) → Magic (DRC) → OpenPhySyn (Parasitic Extraction) → OpenSTA (STA)

### Commercial Flow (Synopsys/Cadence)

RTL → VCS (Sim) → Synopsys DC (Synthesis) → Cadence Innovus (Floorplan → Placement → CTS → Routing) → Synopsys IC Validator (DRC/LVS) → StarRC (Parasitic) → PrimeTime (STA) → RedHawk (EM/IR)

### Tool Roles

| Phase                 | Open-Source              | Commercial               |
|-----------------------|--------------------------|--------------------------|
| Simulation            | Verilator, Icarus        | Synopsys VCS, Xcelium    |
| Synthesis             | Yosys                    | Synopsys DC, Genus       |
| Floorplanning         | OpenROAD                 | Cadence Innovus          |
| Placement             | OpenROAD (RePlAce)       | Cadence Innovus          |
| CTS                   | OpenROAD (TritonCTS)     | Cadence Innovus          |
| Routing               | OpenROAD (FastRoute)     | Cadence Innovus          |
| DRC/LVS               | Magic, KLayout           | Synopsys IC Validator    |
| Parasitic Extraction  | OpenPhySyn               | Synopsys StarRC          |
| STA                   | OpenSTA                  | Synopsys PrimeTime       |
| EM/IR Analysis        | —                        | Synopsys RedHawk         |

---

## Phase 7: Floorplan

### Die Dimensions

- **Total Die Area:** 100 mm² (10mm × 10mm)
- **Core Area:** 80 mm² (8mm × 10mm)
- **I/O Ring:** 20 mm² (perimeter)

### Macro Placement

| Macro               | Dimensions (mm) | Area (mm²) | Location      |
|---------------------|-----------------|------------|---------------|
| Systolic Array (×4) | 4.0 × 3.2       | 12.8 each  | Top-left      |
| Vector Unit (×2)    | 2.5 × 2.0       | 5.0 each   | Top-right     |
| Scalar Core         | 2.0 × 1.5       | 3.0        | Bottom-left   |
| SRAM Banks (×16)    | 1.0 × 1.0       | 1.0 each   | Center        |
| DMA Engines (×2)    | 1.5 × 1.0       | 1.5 each   | Bottom-right  |
| NoC Routers (8×8)   | 0.5 × 0.5       | 0.25 each  | Distributed   |

### Power Grid

- **VDD/GND Rails:** M8 (200μm pitch, 10μm strap width)
- **VDD_AI:** M7 (separate domain)
- **IR Drop Target:** < 5% of VDD (35mV for VDD_CORE = 0.7V)

### Clock Regions

H-tree for `clk_ai` rooted at die center, 3 levels. Buffer drive strengths: 1000×, 100×, 10×. Skew target: < 20ps.

### Routing Channels

- **Global:** M5–M8; **Local:** M1–M4
- **Keep-Out Zones:** Under SRAM arrays; around analog blocks (PLLs, ADCs)

---

## Phase 8: Placement

### Goals

| Metric      | Target       | Tool (OR)   | Tool (Commercial) |
|-------------|--------------|-------------|-------------------|
| Wire Length | < 500m total | RePlAce     | Innovus           |
| Congestion  | < 5%         | RePlAce     | Innovus           |
| Timing      | 0.4ns period | TritonCTS   | Innovus CTS       |
| Power       | < 12W        | OpenPhySyn  | Voltus            |

### Strategy

1. **Macro Placement:** Pre-place SRAM, DMA, NoC; legalize for no overlaps
2. **Global Placement:** Minimize wire length (quadratic cost function)
3. **Detailed Placement:** Legalize + timing-driven optimization
4. **Buffer Insertion:** For long nets on critical paths

### Congestion Analysis

| Region                    | Utilization | Fix?        |
|---------------------------|-------------|-------------|
| Systolic Array → SRAM     | 95%         | Add buffers |
| NoC Router                | 85%         | None        |
| CPU Subsystem             | 70%         | None        |

### Critical Paths

- `Systolic Array → Accumulator → SRAM Write`: 0.34ns
- `DMA → SRAM → Vector Unit`: 0.32ns
- `NoC Router → Scalar Core`: 0.28ns

---

## Phase 9: Clock-Tree Synthesis (CTS)

### Clock Tree Topology

| Domain    | Topology | Levels | Skew (ps) | Latency (ps) |
|-----------|----------|--------|-----------|--------------|
| `clk_ai`  | H-Tree   | 3      | < 20      | < 200        |
| `clk_cpu` | H-Tree   | 3      | < 30      | < 300        |
| `clk_io`  | Mesh     | 2      | < 50      | < 400        |

### Clock Uncertainty

- **Jitter:** < 10ps; **Skew:** < 20ps; **Total Uncertainty:** 30ps (12% of 400ps period)
- **Effect on setup:** Effective period = 0.4ns − 0.03ns = 0.37ns

### Power

- Clock tree: ~20% of total power (~4W for `clk_ai`)
- **Optimizations:** Clock gating for idle blocks; low-swing clocks (0.5V) for non-critical domains

---

## Phase 10: Routing

### Interconnect Stack (3nm)

| Layer | Material | Pitch (nm) | Width (nm) | Use Case               |
|-------|----------|------------|------------|------------------------|
| M0    | Cobalt   | 40         | 20         | Local interconnect     |
| M1    | Cobalt   | 40         | 20         | Local interconnect     |
| M2    | Cobalt   | 44         | 22         | Local interconnect     |
| M3    | Copper   | 48         | 24         | Intermediate routing   |
| M4    | Copper   | 52         | 26         | Intermediate routing   |
| M5    | Copper   | 60         | 30         | Semi-global routing    |
| M6    | Copper   | 80         | 40         | Global routing         |
| M7    | Copper   | 120        | 60         | Power/clock            |
| M8    | Copper   | 200        | 100        | Power grid             |

### Parasitic Extraction

- **R(M1):** 0.2 Ω/μm; **R(M8):** 0.01 Ω/μm
- **C(M1):** 0.2 fF/μm; **C(M8):** 0.1 fF/μm
- **RC Delay formula:** `Delay = 0.5 × R × C × L²`
  - 1mm M1 wire: 0.5 × 0.2 × 0.2 × 10⁶ = **20ns** → use wider metals for long wires

### Signal Integrity

- **Crosstalk:** Shield critical nets with VDD/GND
- **Electromigration (EM):** Current density limit < 1 mA/μm² for Cu (M8)
- **IR Drop:** Target < 5% VDD

---

## Phase 11: Physical Verification

### DRC (Design Rule Check)

| Rule                | Value (nm) | Purpose               |
|---------------------|------------|-----------------------|
| Min Fin Width       | 5          | Lithography resolution|
| Min Fin Pitch       | 42         | Patterning density    |
| Min Gate Length     | 20         | Transistor scaling    |
| Min Metal Width (M1)| 20         | Current handling      |
| Min Metal Pitch (M1)| 40         | Routing density       |
| Min Via Size        | 20×20      | Contact resistance    |
| Min Spacing (M1-M1) | 20         | Crosstalk/shorts      |

**Tools:** Magic, KLayout (open-source); Synopsys IC Validator (commercial)

### LVS (Layout vs. Schematic)

Verify netlist match, device match, and connectivity. Tools: Netgen (open-source); Synopsys IC Validator (commercial).

### STA (Static Timing Analysis)

| Path                         | Required (ns) | Arrival (ns) | Slack (ps) |
|------------------------------|---------------|--------------|------------|
| `clk_ai → Systolic → SRAM`  | 0.400         | 0.340        | +60        |
| `clk_ai → Vector → DMA`     | 0.400         | 0.380        | +20        |
| `clk_cpu → Scalar Core`     | 0.666         | 0.600        | +66        |

**Tools:** OpenSTA (open-source); Synopsys PrimeTime (commercial)

### EM / IR Drop Analysis

- **EM Check:** `I < J_max × A`. M8 (100nm × 100nm): I_max = 10μA per strap.
- **IR Drop Check:** `ΔV = I × R < 5% VDD`. Example: 10A × 0.1Ω = 1V → FAIL; need wider/more straps.
- **Tools:** Synopsys RedHawk, Cadence Voltus

---

## Phase 12: Mask Data Preparation

### Layout to GDSII/OASIS

**GDSII:** Binary mask format. **OASIS:** Modern compressed alternative.  
**Tools:** KLayout, Magic (open-source); Cadence Virtuoso, Synopsys IC Compiler II (commercial)

### Optical Proximity Correction (OPC)

Compensates for lithography distortions by adding serifs, biasing line widths, and inserting sub-resolution assist features (SRAFs). Example: 40nm line → 42nm with serifs to print as 40nm.

### Multiple Patterning

- **LELE (Litho-Etch-Litho-Etch):** 2 masks → halves effective pitch
- **LELELE:** 3 masks → for pitches below ~40nm
- **Example:** DUV 193nm (native ~40nm resolution) + LELE → 20nm lines for 3nm M1

### Mask / Reticle

- **Reticle Size:** 6" × 6"
- **Magnification:** 4× (reticle features 4× larger than on-die)
- **Materials:** Quartz substrate + Chrome features + Pellicle (dust protection)
