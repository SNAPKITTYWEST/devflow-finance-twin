# FILE REFERENCE — semiconductor/
## devflow-finance-twin · Semiconductor Design Dossier

**Generated:** 2026-09-19  
**Scope:** All files under `semiconductor/` — 13 files total  
**Technologies covered:** VHDL-2008, Python 3, MATLAB, Markdown/SystemVerilog (prose), Dafny (ALU spec cross-reference)  
**License:** FSL-1.1 / AGPL-3.0 + Sovereign Leviathan additional terms  

---

## Overview

The `semiconductor/` directory is an end-to-end SoC design dossier spanning from device physics through silicon packaging. It documents two distinct hardware targets:

**Target A — 3nm AI Accelerator SoC** (documented in `architecture.md`):  
- 10 TOPS at 15 W, 3nm FinFET, 100 mm² die  
- 256×256 systolic MAC array, 512-bit SIMD vector unit, RISC-V RV64IMAC scalar core  
- Custom AI ISA (VMAC.D16, VLD, VST) + scalar RISC-V base  
- 32 MB on-chip SRAM, 4 clock domains

**Target B — 5nm Edge AI SoC** (documented in `soc-pipeline-spec.md`):  
- 32–64 TOPS at 8–15 W, 80–120 mm² die  
- 4× OoO RV64 application cores (4-wide issue, 128-entry ROB)  
- 2× tightly-coupled AI matrix engines (16×16 systolic, INT8/INT4, sparse)  
- LPDDR5 / HBM2e memory, PCIe Gen 4/5, security island, power management unit

The directory also contains three synthesizable VHDL files implementing the transformer inference hardware, one Python bottom-up simulation from MOSFET to CPU, and one MATLAB fixed-point transformer forward pass.

---

## Directory Map

```
semiconductor/
├── README.md                  # Table of contents and design-point summary
├── architecture.md            # 3nm AI Accelerator SoC chip architecture spec
├── soc-pipeline-spec.md       # 5nm Edge AI SoC full pipeline trace
├── logic-design-synthesis.md  # RTL design, synthesis flow, standard cells
├── eda-physical-design.md     # EDA toolchain, floorplan, place, route, DRC/LVS
├── fabrication.md             # Wafer fabrication FEOL/BEOL, FinFET/GAA
├── packaging-validation.md    # Packaging, validation, yield, traceability
├── rtl-alu.md                 # SystemVerilog RV64 ALU spec
├── rtl-multipliers.md         # Booth + Wallace-tree multiplier spec
├── sk_transformer.vhd         # VHDL transformer (full, Q4.12 fixed-point)
├── sk_attention_matvec.vhd    # VHDL parameterized matvec + AXI4 attention
├── sk_logic_cells.vhd         # VHDL standard cell library + ASIC stubs
├── transformer_matlab.m       # MATLAB transformer forward pass (Weyl deformation)
└── mosfet_to_cpu.py           # Python: MOSFET → CMOS → ALU → CPU simulator
```

---

## FILE: semiconductor/README.md

**PURPOSE:** Index file for the semiconductor directory. Provides a concise table mapping each file to its description, names the two separate SoC design points and explains they are not conflicting specifications, and gives the command to run the Python MOSFET simulation. The README serves as the entry point for any engineer opening the directory.

**LANGUAGE:** Markdown  
**LOC:** ~37  
**RESPONSIBILITY:** Navigation and framing document; clarifies the two-target structure of the dossier.  
**INPUTS:** None  
**OUTPUTS:** Human-readable index  
**KEY FUNCTIONS/TYPES:**
- Design-point table distinguishing 3nm AI accelerator vs 5nm edge SoC
- File-to-description mapping table (12 files)
- `python semiconductor/mosfet_to_cpu.py` invocation example with expected output note

**DEPENDENCIES:** None  
**CALLERS:** Human engineers, CI documentation checks  
**CALLEES:** None  
**STATE:** None  
**PROOF OBLIGATIONS:** None  
**ERROR CONDITIONS:** None  
**RUNTIME ROLE:** Documentation  
**RELATED FILES:** `architecture.md`, `soc-pipeline-spec.md`, `mosfet_to_cpu.py`

---

## FILE: semiconductor/architecture.md

**PURPOSE:** Defines the chip architecture for the Phase 1 AI Accelerator SoC targeting 3nm FinFET process technology. Specifies performance targets (10 TOPS at 1.2V, <15W, 100mm²), the hybrid compute architecture (256×256 systolic MAC array, 512-bit SIMD vector unit, 4-wide superscalar scalar core), the custom AI ISA (VMAC.D16, VLD/VST, BRANCH/JUMP/CALL) plus RISC-V RV64IMAC scalar base, and a comprehensive memory hierarchy (L1 I/D caches per core, shared L2/L3, 32MB on-chip SRAM, external LPDDR5). Also documents clock domains, power domains, reset architecture, a thermal design (TDP < 15W, heatsink, thermal throttling), and the security subsystem (secure boot, TrustZone, OTP, AES-256/SHA-3 hardware accelerators). Provides a register map excerpt for the AI accelerator control registers and a brief RTL coding style guide.

**LANGUAGE:** Markdown  
**LOC:** ~200 (estimated)  
**RESPONSIBILITY:** Authoritative architectural specification for the 3nm AI accelerator SoC; the document from which RTL and physical design constraints are derived.  
**INPUTS:** None  
**OUTPUTS:** Human-readable specification  
**KEY FUNCTIONS/TYPES:**
- Performance targets table: 10 TOPS, 3 TOPS/W, 2.5 GHz, <15W, ~100mm²
- Compute architecture: systolic array (256×256), vector unit (512-bit SIMD), scalar core (4-wide superscalar)
- AI ISA encoding: VMAC.D16 (16-bit MACs), VLD/VST (vector memory), BRANCH/JUMP/CALL
- Memory hierarchy: L1 32KB I + 32KB D, L2 4MB shared, L3 optional, 32MB SRAM, LPDDR5
- Clock domains: `clk_ai` (2.5 GHz), `clk_cpu` (1.5 GHz), `clk_mem` (533 MHz)
- Power domains: always-on, AI cluster, CPU cluster, memory (DVFS)
- Thermal design: 15W TDP, 4-zone hotspot monitoring, clock throttle at 95°C
- Security: ARM TrustZone, secure boot via OTP, AES-256/SHA-3/ECC accelerators
- Register map: AI_CTRL (0x000), AI_STATUS (0x004), AI_MEM_BASE (0x008), AI_MEM_SIZE (0x00C)
- RTL style: synchronous reset, no latches, `always_ff`/`always_comb`, parameterized modules

**DEPENDENCIES:** None  
**CALLERS:** `logic-design-synthesis.md` (references this for RTL hierarchy), `eda-physical-design.md` (references for floorplan)  
**CALLEES:** None  
**STATE:** None  
**PROOF OBLIGATIONS:** None  
**ERROR CONDITIONS:** None  
**RUNTIME ROLE:** Design reference  
**RELATED FILES:** `soc-pipeline-spec.md`, `logic-design-synthesis.md`, `sk_transformer.vhd`

---

## FILE: semiconductor/soc-pipeline-spec.md

**PURPOSE:** A full production-depth SoC pipeline trace for the 5nm Edge AI SoC, covering all 24 phases from system architecture through silicon validation. All numerical values are labeled as Measured, Published, Estimated, or Hypothetical, with proprietary foundry parameters explicitly marked unavailable. The document covers system architecture (heterogeneous RV64 + AI matrix engines), RTL design hierarchy, synthesis targets, floorplan strategy, clock tree design, power delivery network, test infrastructure, and packaging. It is the most detailed specification document in the directory.

**LANGUAGE:** Markdown  
**LOC:** ~400 (estimated)  
**RESPONSIBILITY:** Comprehensive pipeline trace for the 5nm target; the single source of truth for all 24 design phases.  
**INPUTS:** None  
**OUTPUTS:** Human-readable specification  
**KEY FUNCTIONS/TYPES:**
- System architecture: 32–64 TOPS INT8, 4–8 TOPS/W, 8–15W, 80–120mm²
- Core cluster: 4× OoO RV64 (4-wide issue, 128-entry ROB, private L1 I/D 32KB each)
- AI Cluster: 2× MatrixEngine (16×16 systolic PE, INT8/INT4, sparse support), local SRAM
- Coherence: directory-based, shared L2 cache + coherence directory
- NoC: coherent interconnect (torus or mesh topology)
- Memory: LPDDR5 / HBM2e controllers + PHY
- I/O: PCIe Gen4/5, MIPI CSI/DSI, SerDes, GPIO, JTAG
- Security island: root of trust (RoT), crypto accelerators, secure boot
- Power management unit: DVFS, power gating, on-chip regulators
- Test: scan chains, BIST, trace debug fabric
- Hierarchical block structure diagram (SoC → Core Cluster → AI Cluster → Shared L2 → NoC → Memory → I/O → Security → PMU → Test)
- Process: 5nm-class FinFET representative assumptions (TSMC N5/N4 or Samsung 5LPE proxy)
- Timing closure: 1.2–2.0 GHz main clock, 8–10 metal layers
- PDN targets: IR drop < 3% Vdd, electromigration margin > 10%
- DFT: scan coverage > 95%, ATPG fault coverage > 99%

**DEPENDENCIES:** None  
**CALLERS:** `eda-physical-design.md`, `fabrication.md`, `packaging-validation.md`  
**CALLEES:** None  
**STATE:** None  
**PROOF OBLIGATIONS:** None  
**ERROR CONDITIONS:** All estimates require validation against actual foundry PDK  
**RUNTIME ROLE:** Design reference  
**RELATED FILES:** `architecture.md`, `eda-physical-design.md`, `fabrication.md`

---

## FILE: semiconductor/logic-design-synthesis.md

**PURPOSE:** Documents RTL design philosophy, the complete chip-top RTL hierarchy, synthesis flow (Yosys/DC), standard-cell library selection, technology mapping, timing optimization, clock gating, and device physics for FinFET/GAA transistors. Covers the full RTL tree from `chip_top` down through `ai_subsystem` (systolic array, vector unit, NoC router), `cpu_subsystem` (scalar core with fetch/decode/execute/writeback, L1 cache), `memory_subsystem` (SRAM arrays, DMA), and `io_subsystem`. Includes synthesis constraints (SDC), power estimation, area breakdown, and quality-of-results metrics.

**LANGUAGE:** Markdown  
**LOC:** ~250 (estimated)  
**RESPONSIBILITY:** RTL design reference and synthesis methodology documentation.  
**INPUTS:** None  
**OUTPUTS:** Human-readable RTL and synthesis guide  
**KEY FUNCTIONS/TYPES:**
- RTL hierarchy tree: `chip_top` → `ai_subsystem` (4× systolic arrays, each 256×256 MACs, accumulator, pipeline regs; 2× vector units with 512-bit SIMD ALU and vector reg file; 8×8 mesh NoC) → `cpu_subsystem` (scalar core with 5-stage pipeline, L1 cache) → `memory_subsystem` (16-bank SRAM, 2× DMA) → `io_subsystem`
- Synthesis target: 2.5 GHz at TT/0.85V/25°C (typical), 2.0 GHz at SS/0.7V/125°C (worst-case)
- Standard cell library: SRAM compilers (64KB/256KB macros), I/O pads, standard cells (12T, 6T, FinFET 3nm)
- Technology mapping: Yosys `synth_generic` → `dfflibmap` → `abc` → foundry lib; DC `compile_ultra`
- Timing constraints: SDC with `create_clock`, `set_input_delay`, `set_output_delay`, multicycle paths for SRAM accesses
- Clock gating: fine-grain ICG cells on systolic array rows; estimated 30% dynamic power reduction
- Device physics: FinFET fin pitch ~5nm, gate length 12nm, EOT ~0.4nm, threshold voltage 250–350 mV
- Power: dynamic 8W AI cluster, 3W CPU cluster; static 1W total at typical
- Area: systolic array 40mm², vector unit 8mm², CPU 5mm², SRAM 30mm², I/O 10mm², misc 7mm²

**DEPENDENCIES:** None  
**CALLERS:** `eda-physical-design.md`  
**CALLEES:** None  
**STATE:** None  
**PROOF OBLIGATIONS:** None  
**ERROR CONDITIONS:** SDC constraints must be validated against actual timing analysis  
**RUNTIME ROLE:** Design reference  
**RELATED FILES:** `architecture.md`, `eda-physical-design.md`, `rtl-alu.md`

---

## FILE: semiconductor/eda-physical-design.md

**PURPOSE:** Documents the complete EDA physical design flow across phases 6–12: toolchain selection (OpenROAD open-source flow and Synopsys/Cadence commercial flow), floorplanning, power planning, placement, clock tree synthesis (CTS), routing, physical verification (DRC/LVS), parasitic extraction, and static timing analysis (STA). Provides tool role tables comparing open-source and commercial tools for each phase. Specifies floorplan constraints (die size, I/O ring, macro placement), power grid topology (VDD/VSS stripes on metal 7–9, decap placement), CTS target (skew < 10 ps, insertion delay < 200 ps), routing rules (spacing/width by metal layer), and sign-off criteria.

**LANGUAGE:** Markdown  
**LOC:** ~300 (estimated)  
**RESPONSIBILITY:** Physical design methodology; the flow document that takes RTL to GDSII.  
**INPUTS:** None  
**OUTPUTS:** Human-readable EDA flow documentation  
**KEY FUNCTIONS/TYPES:**
- Open-source flow: RTL → Yosys → OpenROAD (floorplan → placement → TritonCTS → FastRoute → DRC/LVS) → KLayout → Netgen → Magic → OpenPhySyn → OpenSTA
- Commercial flow: RTL → VCS/Xcelium → Synopsys DC/Cadence Genus → Cadence Innovus (full PD) → Synopsys IC Validator → StarRC → PrimeTime → RedHawk (EM/IR)
- Tool role table: Simulation, Synthesis, Floorplanning, Placement, CTS, Routing, DRC/LVS, Parasitic Extraction, STA, EM/IR Analysis
- Floorplan: die 10mm × 10mm, I/O ring on all four edges, SRAM macros top-left quadrant, AI systolic arrays center, CPU bottom-right
- Power grid: M7/M8/M9 for VDD stripes (2µm width, 10µm pitch), M1–M6 for local distribution, decap cells every 20µm
- Placement: congestion-driven, utilization target 70–75%, timing-aware legalization
- CTS: H-tree topology for main clock, skew target < 10 ps, NDR routing for clock nets
- Routing: minimum metal rules per PDK (M1: 40nm min width, 50nm spacing; M9: 800nm width, 1µm spacing), DRC clean target
- Parasitic extraction: RC extraction for all nets, back-annotation to PrimeTime
- STA: setup/hold timing signoff at all PVT corners, OCV margins, CRPR

**DEPENDENCIES:** `logic-design-synthesis.md` (for netlist and SDC)  
**CALLERS:** `fabrication.md` (for GDSII handoff)  
**CALLEES:** None  
**STATE:** None  
**PROOF OBLIGATIONS:** None  
**ERROR CONDITIONS:** DRC violations require ECO iterations; IR drop > 3% requires PDN strengthening  
**RUNTIME ROLE:** Design reference  
**RELATED FILES:** `logic-design-synthesis.md`, `fabrication.md`, `packaging-validation.md`

---

## FILE: semiconductor/fabrication.md

**PURPOSE:** Covers wafer fabrication phases 13–19 for the 3nm FinFET process. The document provides a high-level process flow (Si ingot through passivation), then detailed step-by-step FEOL and BEOL descriptions. FEOL covers wafer preparation (Czochralski growth, 300mm, Ra < 0.5nm), STI (200nm trench, SiO2 fill, CMP), well formation (N-well phosphorus 1e13/cm², P-well boron 1e13/cm²), fin formation (FinFET pitch 5nm), gate stack (HKMG with HfO2 dielectric, TiN/TaN gate metal, W fill), and source/drain engineering. BEOL covers inter-layer dielectric (low-k SiOCH, k=2.7), Cu Damascene metallization for 8–12 metal layers, and passivation. Also documents lithography (EUV for < 7nm features, ArFi for larger features, SAQP for sub-10nm), doping techniques, and metrology.

**LANGUAGE:** Markdown  
**LOC:** ~280 (estimated)  
**RESPONSIBILITY:** Wafer fabrication process documentation; the interface between chip design and foundry.  
**INPUTS:** None  
**OUTPUTS:** Human-readable fabrication process specification  
**KEY FUNCTIONS/TYPES:**
- Wafer preparation: Czochralski CZ process, 300mm wafer, 0.7mm thickness, Ra < 0.5nm surface roughness
- STI: 200nm trench depth, SiO2 fill by CVD, CMP planarization
- Well formation: N-well (P+, 100 keV phosphorus, 1000°C anneal), P-well (P-, 50 keV boron, 900°C anneal)
- Fin formation: epitaxial Si fin growth, fin pitch ~5nm (SAQP), fin height ~30nm
- Gate stack: HfO2 EOT ~0.4nm (ALD), TiN work function metal (ALD), poly gate/W fill (CVD), CMP
- Source/drain: in-situ B-doped SiGe (PMOS) / As-doped Si (NMOS) epitaxial growth
- ILD: low-k SiOCH (k=2.7) by CVD, etch-stop SiCN
- Cu Damascene: trench/via etch, Ta/TaN barrier (ALD), Cu seed (PVD), Cu fill (ECD), CMP
- Metal layers: M1 at 20nm pitch, M2–M6 at 30–80nm pitch, M7–M10 at 100–800nm pitch
- Lithography: EUV (13.5nm, NA=0.33) for M1–M3 layers, ArFi (193nm immersion) for upper metals
- Metrology: CD-SEM, TEM cross-section, X-ray diffraction for film thickness, 4-point probe for sheet resistance
- Passivation: SiN/SiO2 bilayer, pad open for wire bonding / UBM for flip-chip
- Wafer sort: electrical testing at probe station before dicing

**DEPENDENCIES:** `eda-physical-design.md` (for GDSII input to mask making)  
**CALLERS:** `packaging-validation.md`  
**CALLEES:** None  
**STATE:** None  
**PROOF OBLIGATIONS:** None  
**ERROR CONDITIONS:** CMP non-uniformity causes dishing/erosion; EUV stochastic effects cause line-edge roughness at 3nm node  
**RUNTIME ROLE:** Process specification  
**RELATED FILES:** `eda-physical-design.md`, `packaging-validation.md`

---

## FILE: semiconductor/packaging-validation.md

**PURPOSE:** Documents packaging options, the chosen flip-chip packaging for the AI accelerator, 2.5D interposer/HBM packaging for the high-bandwidth target, silicon validation procedures, yield analysis, and the full traceability chain from wafer lot to deployed chip. Covers flip-chip bump specifications (150µm pitch, Cu pillar + SnAg solder), substrate design (6–8 metal layers, organic or ceramic), thermal interface materials (5–10 W/m·K), 2.5D interposer (passive Si or glass, through-silicon vias), HBM stacking, post-silicon bringup checklist, validation environments (socket, FIB analysis), yield estimation (negative binomial model), and traceability (lot ID, wafer ID, die coordinates, probe data, package ID linked through a database).

**LANGUAGE:** Markdown  
**LOC:** ~300 (estimated)  
**RESPONSIBILITY:** Packaging selection, silicon validation methodology, and yield/traceability documentation.  
**INPUTS:** None  
**OUTPUTS:** Human-readable packaging and validation specification  
**KEY FUNCTIONS/TYPES:**
- Packaging options table: Wire Bonding (low cost, limited I/O), Flip-Chip (high I/O, performance), 2.5D Interposer (heterogeneous), 3D Stacking (ultra-high density), Chiplets (modularity)
- Flip-chip spec: 150µm bump pitch, ~10,000 bumps, Cu pillar + SnAg solder, organic substrate 6–8 metal layers, copper lid TIM (5–10 W/m·K)
- 2.5D packaging: passive Si interposer with µ-bump pitch 40µm, TSV pitch 50µm, HBM2e stacks (8-Hi, 256GB/s per stack)
- Validation: power-on checklist, JTAG/scan chain verify, functional vector playback, thermal characterization (IR camera), frequency sweep
- Yield model: Y = exp(-AD) where A = die area, D = defect density (0.1–1 cm⁻² for mature process)
- Traceability: lot_id → wafer_id → die_xy → probe_result → package_id → test_result → ship_date
- Failure analysis: FIB cross-section, OBIRCH for hot-spot localization, liquid crystal hot-spot imaging
- Burn-in: 125°C, 1.3× Vdd, 168 hours for early life failure screening

**DEPENDENCIES:** `fabrication.md`  
**CALLERS:** None (terminal in the design flow)  
**CALLEES:** None  
**STATE:** None  
**PROOF OBLIGATIONS:** None  
**ERROR CONDITIONS:** Yield below threshold requires process optimization or design shrink  
**RUNTIME ROLE:** Manufacturing and validation reference  
**RELATED FILES:** `fabrication.md`, `eda-physical-design.md`

---

## FILE: semiconductor/rtl-alu.md

**PURPOSE:** A detailed SystemVerilog specification for a production-quality RV64 ALU. Defines an `alu_pkg` package with a 6-bit opcode enum (ALU_ADD through ALU_MULHU, 18 operations), the ALU module interface, and full submodule descriptions: an adder/subtractor (Brent-Kung parallel prefix, critical path 4 gate delays), a barrel shifter (log2(64) = 6 stages), a comparator (signed/unsigned SLT), a multiplier sub-module (Booth radix-4 + Wallace tree, 3-cycle latency), and a divider sub-module (non-restoring iterative, 64-cycle latency, `busy`/`done` handshake). Includes design style rules, reset values, synthesis pragmas, and a verification note pointing to the Dafny formal spec.

**LANGUAGE:** Markdown (with SystemVerilog code blocks)  
**LOC:** ~200 (estimated)  
**RESPONSIBILITY:** RV64 ALU RTL specification; the primary reference for implementing the scalar CPU execute stage.  
**INPUTS:** None  
**OUTPUTS:** Human-readable SystemVerilog specification  
**KEY FUNCTIONS/TYPES:**
- `alu_pkg` package with `alu_op_t` enum: ALU_ADD=0x00, ALU_SUB=0x01, ALU_AND=0x02, ALU_OR=0x03, ALU_XOR=0x04, ALU_SLL=0x05, ALU_SRL=0x06, ALU_SRA=0x07, ALU_SLT=0x08, ALU_SLTU=0x09, ALU_LUI=0x0A, ALU_AUIPC=0x0B, ALU_MUL=0x10, ALU_MULH=0x11, ALU_MULHSU=0x12, ALU_MULHU=0x13, ALU_DIV=0x18, ALU_DIVU=0x19, ALU_REM=0x1A, ALU_REMU=0x1B
- Module interface: inputs clk, rst_n, op (alu_op_t), a (64), b (64), start; outputs result (64), flags (z,n,c,v), busy, done
- Adder/subtractor: Brent-Kung parallel prefix tree, conditional sum for carry-select speedup
- Barrel shifter: 6-stage mux tree; arithmetic right shift sign-extends
- Comparator: SLT = (a - b)[63] XOR overflow; SLTU = borrow
- Multiplier: Booth radix-4 partial product generation (32 partial products for 64×64), Wallace tree compression to 2 addends, final carry-propagate adder; 3-cycle pipeline
- Divider: non-restoring SRT algorithm, 64 iterations, `busy` asserted during computation
- Style rules: no latches, synchronous active-low reset, `unique case` for opcode dispatch, no X-pessimism in simulation
- Link to `formal/tlm-jxcl/dafny/alu.dfy` for formal verification

**DEPENDENCIES:** None (spec document)  
**CALLERS:** CPU execute stage implementation  
**CALLEES:** `formal/tlm-jxcl/dafny/alu.dfy` (formal counterpart)  
**STATE:** ALU is combinational except multiplier (3 FF stages) and divider (sequential FSM with 64-cycle latency)  
**PROOF OBLIGATIONS:** Formally verified via `alu.dfy`; key lemmas: MulHiLoReconstruct, RolRorInverse, SubBorrow  
**ERROR CONDITIONS:** Division by zero: undefined behavior (caller must check); multiply overflow: MulH returns upper 64 bits  
**RUNTIME ROLE:** Execute stage of RV64 scalar core  
**RELATED FILES:** `formal/tlm-jxcl/dafny/alu.dfy`, `rtl-multipliers.md`, `logic-design-synthesis.md`

---

## FILE: semiconductor/rtl-multipliers.md

**PURPOSE:** A detailed RTL specification for multiplier implementations targeting the AI accelerator and RISC-V vector unit. Covers three multiplication algorithms and implementations: (1) Radix-2 Booth sequential multiplier in Chisel (examines overlapping 2-bit pairs, halves addition count, handles signed two's complement); (2) Radix-4 Booth with 3:2 compressors for higher throughput; (3) Wallace tree reduction network for multi-operand compression. Also includes a RISC-V vector unit multiplier specification for INT8 × INT8 → INT16 throughput of 256 multiplications per cycle. Provides Chisel, VHDL, and CUDA (for SW model) code examples.

**LANGUAGE:** Markdown (with Chisel Scala, VHDL, and CUDA code blocks)  
**LOC:** ~250 (estimated)  
**RESPONSIBILITY:** Multiplier algorithm selection and RTL specification for all compute-intensive units.  
**INPUTS:** None  
**OUTPUTS:** Human-readable multiplier RTL specification  
**KEY FUNCTIONS/TYPES:**
- Radix-2 Booth table: (00)→0, (01)→+multiplicand, (10)→−multiplicand, (11)→0
- Chisel `BoothMultiplier(width=64)`: sequential state machine, signed/unsigned output, `io.done` signal
- Radix-4 Booth: examines 3-bit overlapping windows, 16 partial products for 64×64, fewer adder stages
- Wallace tree: 3:2 compressors recursively reduce partial product count; final carry-propagate adder
- Compressor: full adder reused as 3:2 compressor (sum, carry); 6:2 compressor for higher compression ratios
- RISC-V vector INT8 multiplier: 256 INT8×INT8 multiplications per cycle (AVX-512 style, 256-wide SIMD)
- VHDL radix-4 Booth implementation with generic `N` parameter for arbitrary width
- CUDA INT8 GEMM kernel (reference model for hardware validation)
- Timing: Radix-4 Booth 64×64 → 7 adder stages → ~1.5 GHz at 3nm; Wallace tree → 6 stages → ~2 GHz

**DEPENDENCIES:** None  
**CALLERS:** `logic-design-synthesis.md`, `sk_transformer.vhd` (uses fixed-point multiplication)  
**CALLEES:** None  
**STATE:** Sequential multiplier state machine (start, computing, done)  
**PROOF OBLIGATIONS:** `MulHiLoReconstruct` in `formal/tlm-jxcl/dafny/alu.dfy` verifies hi×lo product reconstruction  
**ERROR CONDITIONS:** Radix-2 Booth requires one extra partial product for even-width operands; unsigned variant needs sign extension  
**RUNTIME ROLE:** AI systolic array PE and RISC-V vector unit multiply path  
**RELATED FILES:** `rtl-alu.md`, `formal/tlm-jxcl/dafny/alu.dfy`, `sk_transformer.vhd`

---

## FILE: semiconductor/sk_transformer.vhd

**PURPOSE:** A complete VHDL-2008 implementation of a fixed-point transformer model compiled to hardware. Configuration: embedding dimension D=8, 2 layers, 1 attention head, FFN width=16, sequence length=4, vocabulary size=16. Uses Q4.12 signed(15 downto 0) for activations and Q16.16 signed(31 downto 0) for accumulators. The file is self-contained and includes: the `sk_types_pkg` package (subtype declarations, array types, saturating arithmetic functions), an RMSNorm entity (layer normalization without mean subtraction), a matvec entity (parametric M×N matrix-vector multiply with accumulation), an attention entity (single-head causal attention with softmax approximation), an FFN entity (SwiGLU feed-forward network), a layer entity (attention + FFN + residuals), the top-level transformer entity (2 stacked layers + embedding lookup + head projection), and a VHDL testbench that feeds a token sequence and checks output. Also includes a Weyl deformation layer structure (`weyl_deform`) that applies a quantum-group-inspired operator to the query matrix.

**LANGUAGE:** VHDL-2008  
**LOC:** ~600 (estimated from structure; file not fully read)  
**RESPONSIBILITY:** Synthesizable VHDL reference implementation of the SK transformer for FPGA/ASIC targets; the primary VHDL artifact of the semiconductor directory.  
**INPUTS:** `clk`, `rst`, token sequence (SEQ_W=4 tokens, each VOCAB_W=16 bits), `start` signal  
**OUTPUTS:** Logits vector (VOCAB_W=16 elements, fx_t each), `done` signal  
**KEY FUNCTIONS/TYPES:**
- `sk_types_pkg` package body:
  - `fx_t` — Q4.12 signed 16-bit fixed-point
  - `fx_acc_t` — Q32.16 signed 32-bit accumulator
  - `fx_vec_d` — array(0 to D_W-1) of fx_t (D=8)
  - `fx_vec_ffn` — array(0 to FFN_W-1) of fx_t (FFN=16)
  - `fx_vec_voc` — array(0 to VOCAB_W-1) of fx_t (VOCAB=16)
  - `fx_mat_dd`, `fx_mat_dffn`, `fx_mat_ffnd`, `fx_mat_vocd` — matrix array types
  - `fx_vec_wq`, `fx_mat_wq` — Weyl deformation array types (WEYL_N = 2×QQ_W = 8)
  - `sat_fx` — saturating downshift from acc to fx_t
  - `fx_mul` — Q4.12 × Q4.12 → Q4.12 (with 12-bit right shift and saturation)
  - `fx_add`, `fx_sub` — saturating fixed-point add/subtract
- `sk_rms_norm` entity — RMSNorm: computes ||x||² / D, then x_i / sqrt(||x||²/D) in fixed-point
- `sk_matvec` entity — generic M×N matrix-vector multiply; accumulates into fx_acc_t, saturates to fx_t
- `sk_attention` entity — single-head causal self-attention: Q=x·Wq, K=x·Wk, V=x·Wv, scores=Q·K^T/sqrt(D), softmax(scores)·V
- `sk_ffn` entity — SwiGLU FFN: computes gate=sigmoid(x·W1_gate), up=x·W1_up, hidden=gate*up, output=hidden·W2
- `sk_layer` entity — one transformer layer: attention + add-residual + rms_norm + FFN + add-residual + rms_norm
- `sk_transformer` entity — top-level: embedding table lookup, 2 layers, final rms_norm, head projection to vocab
- `weyl_deform` entity — applies Weyl deformation operator U^k·V^m with QQ_W×QQ_W matrix to query
- Testbench: drives token_seq = [3, 7, 1, 5], checks `done`, reads logits

**DEPENDENCIES:** `ieee.std_logic_1164`, `ieee.numeric_std`, `ieee.math_real`, `sk_types_pkg`  
**CALLERS:** FPGA synthesis tool (Vivado, Quartus), ASIC flow (Cadence Genus), testbench  
**CALLEES:** `sk_types_pkg` functions (`sat_fx`, `fx_mul`, `fx_add`, `fx_sub`)  
**STATE:** Internal SRAM for weight storage; pipeline registers for multi-cycle computation  
**PROOF OBLIGATIONS:** Functional correctness verified by testbench; formal equivalence to MATLAB model via `transformer_matlab.m` (manual comparison)  
**ERROR CONDITIONS:** Integer overflow is handled by saturation in `sat_fx`; softmax overflow guarded by max subtraction (logsumexp trick); attention mask must be causal (lower triangular)  
**RUNTIME ROLE:** Synthesized to FPGA/ASIC for on-device transformer inference  
**RELATED FILES:** `sk_attention_matvec.vhd`, `sk_logic_cells.vhd`, `transformer_matlab.m`, `rtl-multipliers.md`

---

## FILE: semiconductor/sk_attention_matvec.vhd

**PURPOSE:** A parameterized, more general implementation of the matrix-vector engine and AXI4 single-head causal attention module, separated from the concrete-dimension transformer. Uses an unconstrained array form (`fx_vec` and `fx_acc_vec`) with generic parameters for dimensions M and N. The file includes an updated `sk_types_pkg` with unconstrained array types, a parameterized `sk_matvec_engine` entity (single-cycle accumulate loop, optional pipelining), and an `sk_attention_axi4` entity that fetches Q/K/V from an AXI4 master interface (causal K/V stored in external SRAM or HBM) and produces attention output. This is the production-grade attention module intended for larger sequence lengths where K/V caches must be stored off-chip.

**LANGUAGE:** VHDL-2008  
**LOC:** ~350 (estimated)  
**RESPONSIBILITY:** Parameterized matvec engine and AXI4-interfaced attention for large-sequence inference; owns the memory-efficient attention path.  
**INPUTS:** Generics M, N (matrix dimensions); AXI4 master signals for K/V fetch; query vector input  
**OUTPUTS:** Attention output vector; AXI4 read address/data signals  
**KEY FUNCTIONS/TYPES:**
- `sk_types_pkg` (updated version):
  - `fx_t` — signed(15 downto 0) Q4.12
  - `fx_acc_t` — signed(31 downto 0) Q16.16
  - `fx_vec` — unconstrained array (natural range <>) of fx_t
  - `fx_acc_vec` — unconstrained array (natural range <>) of fx_acc_t
  - `clog2(n)` — ceiling log base 2 (for address width calculation)
  - `sat_fx(x)` — saturating 32→16 bit downshift
  - `fx_mul(a,b)` — Q4.12 multiply with 12-bit right shift, saturation
  - `fx_add(a,b)`, `fx_sub(a,b)` — saturating add/subtract
  - `exp_lut(x)` — exponential approximation via lookup table (for softmax)
  - `rsqrt_lut(x)` — reciprocal square root LUT (for attention scaling)
- `sk_matvec_engine` entity:
  - Generic: M (output dim), N (input dim), PIPELINE_STAGES
  - Input: row-major weight matrix (M×N fx_t), input vector (N fx_t), `start`
  - Output: result vector (M fx_t), `valid`
  - Implementation: nested loop accumulation with fx_acc_t, final saturation
- `sk_attention_axi4` entity:
  - Handles causal attention with KV cache in external memory
  - AXI4 read channel: AR address (key/value base address), R data channel
  - Attention score computation: Q·K^T / sqrt(D) using `rsqrt_lut`
  - Softmax: uses `exp_lut` with log-sum-exp for numerical stability
  - Output: weighted sum V' = softmax(scores) · V

**DEPENDENCIES:** `ieee.std_logic_1164`, `ieee.numeric_std`, `sk_types_pkg`  
**CALLERS:** AXI4 interconnect, top-level SoC integration  
**CALLEES:** `sk_types_pkg` (`sat_fx`, `fx_mul`, `fx_add`, `exp_lut`, `rsqrt_lut`)  
**STATE:** State machine for AXI4 transaction management; shift register for partial sums  
**PROOF OBLIGATIONS:** Softmax normalization correctness; AXI4 handshake protocol compliance  
**ERROR CONDITIONS:** AXI4 BRESP != OKAY signals memory error; softmax overflow if query scale is too large  
**RUNTIME ROLE:** Used as the attention engine in large-sequence inference where K/V cache exceeds on-chip SRAM  
**RELATED FILES:** `sk_transformer.vhd`, `sk_logic_cells.vhd`, `architecture.md`

---

## FILE: semiconductor/sk_logic_cells.vhd

**PURPOSE:** A complete VHDL standard cell library implementing all primitive logic gates from first principles. The library defines the `sk_logic_pkg` package with: a `node_kind` enum (NK_CONST, NK_INPUT, NK_OUTPUT, NK_NOT, NK_NAND, NK_NOR, NK_AND, NK_OR, NK_XOR, NK_XNOR, NK_MUX, NK_DFF), a `logic_node` record for netlist representation, and function bodies for all primitive gates. ASIC binding entities are technology-independent stubs that map each function to the corresponding cell from the foundry PDK. Also implements recursive cell compositions (n-input AND from 2-input NAND chains, n-bit adder from full adders) and D flip-flop with synchronous reset.

**LANGUAGE:** VHDL-2008  
**LOC:** ~300 (estimated)  
**RESPONSIBILITY:** Owns the primitive gate library and cell-level netlist representation; the technology abstraction layer between RTL and ASIC.  
**INPUTS:** Logic signals (std_logic / bit1 subtype)  
**OUTPUTS:** Logic signals  
**KEY FUNCTIONS/TYPES:**
- `bit1` — subtype alias for `std_logic`
- `node_kind` — 12-constructor enum for netlist node types
- `logic_node` record — (kind, a, b, c: natural indices, v: bit1 for constants)
- `NODE_ZERO`, `NODE_ONE` — constant logic nodes
- `sk_not(a)` — NOT gate: `not a`
- `sk_nand(a,b)` — NAND: `not (a and b)`
- `sk_nor(a,b)` — NOR: `not (a or b)`
- `sk_and(a,b)` — AND: `a and b`
- `sk_or(a,b)` — OR: `a or b`
- `sk_xor(a,b)` — XOR: `a xor b`
- `sk_xnor(a,b)` — XNOR: `not (a xor b)`
- `sk_mux(s,a,b)` — 2:1 MUX: `(s and a) or (not s and b)` (using sk_and/sk_or)
- `sk_dff` entity — D flip-flop: synchronous reset, rising edge triggered
- `sk_ha` (half adder) — `sum = a xor b`, `carry = a and b`
- `sk_fa` (full adder) — uses two half adders: `sum = a xor b xor cin`, `cout` from carry-or logic
- `sk_rca_n` (n-bit ripple carry adder) — generic `N` parameter, chain of full adders
- ASIC binding stubs: `sk_inv_asic`, `sk_nand2_asic`, etc. — entity declarations mapping to PDK cells
- DFF binding: `sk_dff_asic` — maps to standard flip-flop cell with timing arc

**DEPENDENCIES:** `ieee.std_logic_1164`, `ieee.numeric_std`  
**CALLERS:** `sk_transformer.vhd`, `sk_attention_matvec.vhd`, ASIC synthesis flow  
**CALLEES:** IEEE library  
**STATE:** `sk_dff` maintains one bit of state (Q register)  
**PROOF OBLIGATIONS:** Boolean equivalence of gate implementations; verified by simulation testbench  
**ERROR CONDITIONS:** `std_logic` metavalues ('U', 'X', 'Z', 'W') propagate through logic; synthesis tools flatten to physical gates  
**RUNTIME ROLE:** Cell library used by synthesis tool for technology mapping; ASIC binding stubs replaced by foundry PDK cells during final synthesis  
**RELATED FILES:** `sk_transformer.vhd`, `sk_attention_matvec.vhd`, `rtl-alu.md`

---

## FILE: semiconductor/transformer_matlab.m

**PURPOSE:** A MATLAB reference implementation of a fixed-point transformer forward pass with a Weyl deformation layer. Configured for domain parameters D=768, q=32, p=3, vocabulary size=32000, sequence length=16. Implements the full transformer pipeline: Weyl clock-shift operators U and V (satisfying V·U = ω·U·V where ω = exp(2πi·p/q)), deformation matrix D_theta from normalized Weyl-basis coefficients, random weight initialization, embedding lookup, layer normalization, multi-head attention (Q·W_q, K·W_k, V·W_v, attention scores, softmax), SwiGLU MLP (gated linear unit), final RMS normalization, and vocabulary head projection. Two decoding modes: Mode A (greedy, argmax) and Mode B (phase-biased sampling using Weyl angles to skew the probability distribution). Serves as the golden reference for VHDL and CUDA implementations.

**LANGUAGE:** MATLAB  
**LOC:** ~250 (estimated)  
**RESPONSIBILITY:** Golden software reference model for the transformer forward pass; validates VHDL and quantized implementations.  
**INPUTS:** RNG seed 42 (for reproducibility), hardcoded domain parameters  
**OUTPUTS:** Generated token sequence (greedy or phase-biased), intermediate activations for comparison  
**KEY FUNCTIONS/TYPES:**
- `transformer_forward_fixed()` — main function (called with no arguments)
- Weyl operators: `U = diag(ω^0, ω^1, ..., ω^(q-1))`, `V` shift matrix; assertion `norm(V*U - ω*(U*V)) < 1e-10`
- `D_theta` — deformation matrix: `Σ_{k,m} C(k,m) · ω^(km) · U^k · V^m` where C is normalized random complex matrix
- Weight initialization: `W_emb` (vocab×D), `W_q`, `W_k`, `W_v`, `W_o` (D×D), `W_gate`, `W_down` (for SwiGLU), `W_head` (vocab×D), gamma vectors for RMS norm
- Embedding: `X = W_emb[tokens, :]` (seq_len × D)
- RMS normalization: `x / (||x||₂ / sqrt(D))` scaled by gamma
- Self-attention: `Q = X·W_q`, `K = X·W_k`, `V = X·W_v`; causal mask; attention scores `Q·K^T / sqrt(D)`; softmax; output `scores·V·W_o`
- Weyl deformation applied to Q: `Q_deformed = D_theta * Q` (with `init_deformation()` helper)
- SwiGLU MLP: `gate = sigmoid(X·W_gate_half)`, `up = X·W_gate_upper_half`, `h = gate .* up`, `output = h·W_down`
- Mode A decoding: `[~, token] = max(logits)` at each position
- Mode B decoding: computes Weyl angle `θ_i = (2π/q) * (i*p mod q) + θ_0 * γ^i`, adds bias to logits before softmax sampling
- `init_deformation()` — separate function initializing the Weyl basis matrix

**DEPENDENCIES:** MATLAB `math_real`, `rng`, matrix operations  
**CALLERS:** Manual comparison with `sk_transformer.vhd` and CUDA implementations  
**CALLEES:** MATLAB built-ins: `randn`, `diag`, `exp`, `norm`, `softmax` (custom inline), `max`  
**STATE:** All state is local to the function; RNG seeded at entry  
**PROOF OBLIGATIONS:** `assert(norm(V*U - ω*(U*V), 'fro') < 1e-10)` — algebraic constraint on Weyl operators  
**ERROR CONDITIONS:** Weyl operator construction: assertion failure if ω is not a primitive q-th root of unity; softmax numerical stability requires log-sum-exp (not implemented here — susceptible to overflow for large D)  
**RUNTIME ROLE:** Golden reference model; run on a workstation for expected-output generation before VHDL synthesis  
**RELATED FILES:** `sk_transformer.vhd` (VHDL implementation), `sk_attention_matvec.vhd`

---

## FILE: semiconductor/mosfet_to_cpu.py

**PURPOSE:** A bottom-up educational simulation of a complete computer from switch-level MOSFET physics up through CMOS gates, adders, an 8-bit ALU, a behavioral flip-flop, and finally an accumulator-style CPU with a program ROM. Organized as seven hierarchical levels, each building on the previous. Level 1 implements a MOSFET switch simulator with union-find merging of equipotential nodes and iterative charge propagation. Level 2 builds CMOS inverter, NAND2, NOR2, transmission gate, and MUX2 from MOSFET instances. Level 3 derives AND, OR, XOR, NAND, NOR, NOT from CMOS cells. Level 4 implements half adder, full adder, and N-bit ripple-carry adder. Level 5 implements an 8-bit ALU with 8 opcodes (ADD, SUB, AND, OR, XOR, NOT A, INC A, DEC A). Level 6 implements a behavioral D flip-flop (simulated posedge). Level 7 implements an accumulator CPU with a 256-byte program ROM, executing a test program and printing register states. The file runs end-to-end with `python3 mosfet_to_cpu.py` and prints "all levels verified" on success.

**LANGUAGE:** Python 3  
**LOC:** ~650 (estimated)  
**RESPONSIBILITY:** Pedagogical bottom-up CPU simulator; demonstrates that every component of a CPU can be derived from MOSFET physics. Also serves as a sanity check that the semiconductor design dossier is internally consistent.  
**INPUTS:** No inputs; self-contained with hardcoded test programs  
**OUTPUTS:** Console output: verification messages for each level, CPU register state trace  
**KEY FUNCTIONS/TYPES:**
- `L` enum (IntEnum): ZERO=0, ONE=1, Z=2 (high-impedance), X=3 (conflict)
- `Node` class: name, level (L), fixed (Bool) — represents a circuit node
- `Transistor` class: name, kind ('nmos'/'pmos'), gate, drain, source
- `Circuit` class: nodes dict, transistors list, `add_node`, `add_transistor`, `simulate()` — iterative propagation using union-find equivalence; handles VDD/GND driving, NMOS (gate=1 → on), PMOS (gate=0 → on), conflict detection
- `CMOS_INV`, `CMOS_NAND2`, `CMOS_NOR2`, `CMOS_TG`, `CMOS_MUX2` — gate factories returning `Circuit` instances
- `Gate` class (Level 3): wraps CMOS circuits with `compute(*inputs)` method
- `AND2`, `OR2`, `XOR2`, `NAND2`, `NOR2`, `NOT` — Gate instances
- `half_adder(a,b)` → (sum, carry), `full_adder(a,b,cin)` → (sum, cout)
- `ripple_adder_n(a_bits, b_bits, cin)` → (sum_bits, cout)
- `ALU8` class (Level 5): `compute(op, a, b)` where op ∈ {ADD, SUB, AND, OR, XOR, NOT_A, INC_A, DEC_A}; returns 8-bit result
- `ALU8.AluOp` IntEnum: 8 opcodes
- `DFF` class (Level 6): `posedge(d)` → Q; behavioral; no gate-level internals
- `CPU` class (Level 7): 256-byte ROM, 8-bit accumulator, program counter, `run(program, max_cycles=256)` → list of (pc, acc) snapshots
- `CPU.Opcode` enum: LOAD_IMM, ADD_IMM, SUB_IMM, AND_IMM, STORE_ACC, BRANCH_NZ, HALT
- Test program: `[LOAD_IMM 42, ADD_IMM 13, STORE_ACC 0, SUB_IMM 5, HALT]` → expects acc = 50 after step 2, acc = 45 after step 3
- `verify_all_levels()` — top-level function running all seven levels and asserting correctness

**DEPENDENCIES:** Python 3 `enum.IntEnum`, `collections.defaultdict`; no external packages  
**CALLERS:** `python3 semiconductor/mosfet_to_cpu.py` (direct execution)  
**CALLEES:** None (self-contained)  
**STATE:** `Circuit.nodes` dict (mutable during simulation); `CPU.acc`, `CPU.pc` (mutable registers); `DFF.Q` (mutable state)  
**PROOF OBLIGATIONS:** None formal; all correctness checked by assertion in `verify_all_levels()`  
**ERROR CONDITIONS:**
- `L.X` (conflict): two transistors driving opposite values → node level X; propagates through gates as X
- `L.Z` (floating): no driver → node remains high-impedance; may cause non-deterministic behavior
- Infinite loop: simulation iterates until no change; non-convergent circuits (oscillators) loop forever (max-iterations guard not shown)

**RUNTIME ROLE:** Educational/verification tool; run during development to check semiconductor understanding. Expected output: "Level 1-7: all verified."  
**RELATED FILES:** `architecture.md` (the hardware being simulated), `logic-design-synthesis.md`, `sk_logic_cells.vhd` (VHDL counterpart)

---

## Cross-Cutting Concerns

### Fixed-Point Arithmetic Conventions

All VHDL files use the same Q-format conventions:

| Type | Format | Range | MATLAB Equivalent |
|------|--------|-------|-------------------|
| `fx_t` | Q4.12, signed(15:0) | [-8, 8) | int16 / 4096 |
| `fx_acc_t` | Q16.16, signed(31:0) | [-32768, 32768) | int32 / 65536 |

The `fx_mul(a, b)` function performs: `p := a * b` (32-bit product), then `sat_fx(shift_right(p, 12))` to return to Q4.12 format. This loses 12 bits of fractional precision per multiply, which must be accounted for when cascading operations.

### Saturation Policy

`sat_fx(x: fx_acc_t)`: clips to [−32768, 32767] in Q4.12 units (i.e., [−8.0, 7.99975] in real-value terms). Clipping is always hard saturation — no rounding. For neural network inference this is acceptable since weights are typically normalized.

### Dependency Chain

```
mosfet_to_cpu.py         (L1: physics) →
sk_logic_cells.vhd       (cells) →
rtl-multipliers.md       (multiply) →
rtl-alu.md               (ALU) →
logic-design-synthesis.md →
sk_transformer.vhd / sk_attention_matvec.vhd →
transformer_matlab.m     (golden reference)
                    ↓
eda-physical-design.md →
fabrication.md →
packaging-validation.md
```

### Cross-References to Formal Verification

The `rtl-alu.md` document explicitly references `formal/tlm-jxcl/dafny/alu.dfy` as the formal counterpart. The Dafny ALU covers the same 64-bit arithmetic operations (Add, Sub, Mul, MulH, Div, Rem, And, Or, Xor, Not, Shl, Shr, Rol, Ror) with proven lemmas. The `sk_transformer.vhd` fixed-point multiply corresponds to `AluMul` in the Dafny spec, with the Q4.12 shift implementing the `>> 12` right shift that the Dafny spec represents as the lower 64 bits of a product.

### Process Technology Notes

All numerical process values are labeled according to the `soc-pipeline-spec.md` convention:
- `[Measured]` — from published silicon characterization
- `[Published]` — from foundry process design kit (PDK) documentation
- `[Estimated]` — derived from published papers or scaling rules
- `[Hypothetical]` — assumed for design study; requires validation against actual PDK

The 3nm FinFET parameters in `fabrication.md` (fin pitch 5nm, gate length 12nm, EOT 0.4nm) are representative of TSMC N3/N3E or Samsung SF3E class processes based on published literature as of 2024.
