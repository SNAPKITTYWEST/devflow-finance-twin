# Logic Design, Synthesis & Device Technology
*Phases 2–5*

---

## Phase 2: RTL Design

### RTL Hierarchy

```
chip_top
├── ai_subsystem
│   ├── systolic_array (4x)
│   │   ├── mac_unit (256x256)
│   │   ├── accumulator
│   │   └── pipeline_regs
│   ├── vector_unit (2x)
│   │   ├── simd_alu (512-bit)
│   │   └── vector_reg_file
│   └── noc_router (8x8 mesh)
├── cpu_subsystem
│   ├── scalar_core
│   │   ├── fetch_decode
│   │   ├── execute
│   │   └── writeback
│   └── l1_cache
├── memory_subsystem
│   ├── sram_arrays (16 banks)
│   └── dma_engine (2x)
└── io_subsystem
    ├── ddr5_phy
    ├── pcie_phy
    └── gpio
```

### Key RTL Modules (SystemVerilog)

#### MAC Unit
```verilog
module mac_unit #(
  parameter WIDTH = 16
) (
  input  logic [WIDTH-1:0] a, b,
  input  logic [2*WIDTH-1:0] acc_in,
  output logic [2*WIDTH-1:0] acc_out
);
  logic [2*WIDTH-1:0] product;
  assign product = $signed(a) * $signed(b);
  assign acc_out = acc_in + product;
endmodule
```

#### Vector ALU (512-bit SIMD)
```verilog
module vector_alu #(
  parameter DATA_WIDTH = 512,
  parameter LANES = 32
) (
  input  logic [DATA_WIDTH-1:0] a, b,
  input  logic [3:0] op,
  output logic [DATA_WIDTH-1:0] result
);
  always_comb begin
    for (int i = 0; i < LANES; i++) {
      case (op)
        4'd0: result[16*i +: 16] = a[16*i +: 16] + b[16*i +: 16];
        4'd1: result[16*i +: 16] = a[16*i +: 16] - b[16*i +: 16];
      endcase
    }
  end
endmodule
```

#### SRAM Bank
```verilog
module sram_bank #(
  parameter ADDR_WIDTH = 14,
  parameter DATA_WIDTH = 64
) (
  input  logic [ADDR_WIDTH-1:0] addr,
  input  logic [DATA_WIDTH-1:0] wdata,
  output logic [DATA_WIDTH-1:0] rdata,
  input  logic we, re,
  input  logic clk
);
  logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
  always_ff @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    if (re) rdata <= mem[addr];
  end
endmodule
```

### DFT (Design for Testability)

- **Scan Insertion:** All flip-flops replaced with scan FFs; 10,000 FFs per chain
- **Boundary Scan:** IEEE 1149.1 compliant

---

## Phase 3: Synthesis

### Synthesis Flow

RTL → Elaboration → Logic Optimization → Technology Mapping → Gate-Level Netlist → Timing Analysis → Area/Power Reports

### Toolchain

| Step                | Open-Source  | Commercial          |
|---------------------|--------------|---------------------|
| Elaboration         | Verilator    | Synopsys VCS        |
| Logic Optimization  | Yosys        | Synopsys DC         |
| Technology Mapping  | OpenROAD     | Synopsys DC         |
| Timing Analysis     | OpenSTA      | Synopsys PrimeTime  |

### Synthesis Constraints (SDC)

```sdc
create_clock -name clk_ai -period 0.4 -waveform {0 0.2} [get_ports clk_ai]
create_clock -name clk_cpu -period 0.666 [get_ports clk_cpu]

set_input_delay  0.1 -clock clk_ai [get_ports in_*]
set_output_delay 0.1 -clock clk_ai [get_ports out_*]

set_false_path -from [get_clocks clk_ai] -to [get_clocks clk_cpu]
```

### Post-Synthesis Metrics

| Metric           | Target      | Achieved (Est.) |
|------------------|-------------|-----------------|
| Clock Period     | 0.4ns       | 0.41ns          |
| Area             | < 50 mm²    | 48.2 mm²        |
| Dynamic Power    | < 10W       | 9.5W            |
| Leakage Power    | < 1W        | 0.8W            |
| Critical Path    | < 0.35ns    | 0.34ns          |

- **Logic Depth:** 12 FO4 delays on critical paths
- **Fanout:** 80% ≤ 4, 15% 4–10, 5% > 10 (buffered)

---

## Phase 4: Standard-Cell Design (3nm FinFET)

### Standard Cell Library

| Cell Type      | Transistors | Drive (mA/μm) | Area (μm²) | Leakage (nA/μm) |
|----------------|-------------|----------------|------------|-----------------|
| INV            | 2           | 1.2            | 0.12       | 0.05            |
| NAND2          | 4           | 1.0            | 0.18       | 0.08            |
| NOR2           | 4           | 0.8            | 0.20       | 0.06            |
| DFF (Positive) | 8           | —              | 0.40       | 0.10            |
| MUX2           | 6           | 0.9            | 0.25       | 0.07            |
| AND2           | 6           | 0.7            | 0.22       | 0.09            |

### Key Cell Details

**CMOS Inverter:** NMOS W/L = 120nm/30nm, PMOS W/L = 240nm/30nm. Drive: 1.2 mA/μm @ 0.7V.

**6T SRAM Bitcell:**
- 2× access (NMOS), 2× pull-down (NMOS), 2× pull-up (PMOS)
- Cell area: 0.0105 μm² (150nm height × 70nm width)
- Read SNM > 150mV, Write Margin > 200mV

**D Flip-Flop:** Master-slave using transmission gates. Setup: 50ps, Hold: 30ps, Clk-to-Q: 80ps.

### Process Node Scaling

| Parameter           | 3nm (Est.) | 5nm (Published) | 7nm (Published) |
|---------------------|------------|-----------------|-----------------|
| Gate Length (Lg)    | 20nm       | 25nm            | 30nm            |
| Fin Pitch           | 42nm       | 48nm            | 54nm            |
| Metal Pitch (M1)    | 40nm       | 44nm            | 56nm            |
| SRAM Bitcell Area   | 0.0105 μm² | 0.012 μm²       | 0.015 μm²       |
| Logic Density       | ~150 MTr/mm² | ~120 MTr/mm² | ~100 MTr/mm²   |

> Marketing node names ("3nm") are scaling indicators, not physical gate lengths.

---

## Phase 5: Device Technology

### Transistor Architecture Comparison

#### Planar CMOS (28nm+)
- Flat silicon channel, poly/metal gate on one side
- Simple fabrication; poor short-channel control at scaled nodes

#### FinFET (22nm–3nm)
- 3D fin (height ~50nm, width ~5nm); gate wraps 3 sides
- Better electrostatic control, higher I_on, lower leakage
- Tradeoffs: fin width variability, fin-to-fin capacitance

#### GAA Nanosheets (2nm and below)
- Stacked Si sheets (~5nm thick); gate wraps all 4 sides
- Superior scalability and I_on/I_off vs. FinFET
- Tradeoffs: complex channel release step, sheet thickness control

### Architecture Comparison

| Architecture     | Channel   | Gate Control | Node Target  | Status           |
|------------------|-----------|--------------|--------------|------------------|
| FinFET           | Si        | 3-sided      | 3nm–22nm     | Production       |
| GAA Nanosheets   | Si        | 4-sided      | 2nm          | Production (2025)|
| Forksheet        | Si        | 4-sided      | < 2nm        | Research         |
| CFET             | Si/Ge/SiGe| Vertical     | < 2nm        | Research         |

### Electrostatic Control

| Parameter          | Planar CMOS | FinFET     | GAA Nanosheets |
|--------------------|-------------|------------|----------------|
| Gate Control       | 1-sided     | 3-sided    | 4-sided        |
| Vth Roll-Off       | Poor        | Good       | Excellent      |
| DIBL               | High        | Low        | Very Low       |
| Subthreshold Swing | ~70 mV/dec  | ~65 mV/dec | ~60 mV/dec     |
| I_on/I_off         | ~10³        | ~10⁴       | ~10⁵           |
