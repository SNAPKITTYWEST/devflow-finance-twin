# Chip Architecture
*AI Accelerator SoC — Phase 1*

## 1.1 Target Application

**AI Accelerator SoC for Edge Inference**
- **Use Case:** Real-time image segmentation (medical imaging, autonomous vehicles)
- **Performance Targets:**
  - 10 TOPS @ 1.2V, 3nm FinFET
  - Power: < 15W
  - Memory: 32MB on-chip SRAM

| Metric           | Target   | Source       |
|------------------|----------|--------------|
| Clock Frequency  | 2.5 GHz  | Hypothetical |
| Power Efficiency | 3 TOPS/W | Estimated    |
| Die Area         | ~100 mm² | Hypothetical |

## 1.2 Compute Architecture

**Hybrid Architecture:**
- **Systolic Array:** 256×256 MAC units for matrix operations
- **Vector Unit:** 512-bit SIMD for general-purpose compute
- **Scalar Core:** 4-wide superscalar for control tasks

## 1.3 ISA / Instruction Interface

- **Custom AI ISA:**
  - `VMAC.D16` — 16-bit multiply-accumulate
  - `VLD`/`VST` — vector load/store
  - `BRANCH`, `JUMP`, `CALL` — control
- **Scalar Base:** RISC-V RV64IMAC

## 1.4 Processing Elements

| Element             | Count | Role                | Clock Domain |
|---------------------|-------|---------------------|--------------|
| Systolic Array Core | 4     | Matrix operations   | `clk_ai`     |
| Vector Unit         | 2     | SIMD compute        | `clk_ai`     |
| Scalar Core         | 1     | Control/OS tasks    | `clk_cpu`    |
| DMA Engine          | 2     | Memory transfers    | `clk_io`     |

## 1.5 Memory Hierarchy

```
L0 (Register File): 64KB per core (1-cycle access)
L1 (Scratchpad): 128KB per core (3-cycle access)
L2 (Shared SRAM): 16MB (10-cycle access)
L3 (Off-Chip): DDR5-6400 (100ns latency)
```

**SRAM Architecture:**
- **Bitcell:** 6T FinFET (high-density, low-leakage)
- **Array:** 128 rows × 256 columns per bank
- **Banks:** 16 (interleaved for parallel access)

## 1.6 Interconnect Architecture

- **NoC Topology:** 8×8 Mesh (64 tiles)
- **Router:** 5-port (N/S/E/W/Local), wormhole routing, 256 GB/s per router
- **Global Wires:** M6–M8, repeat spacing 128λ

## 1.7 Clocking Strategy

| Domain    | Frequency | Source              | Skew Target |
|-----------|-----------|---------------------|-------------|
| `clk_ai`  | 2.5 GHz   | PLL (H-tree)        | < 20ps      |
| `clk_cpu` | 1.5 GHz   | Separate PLL        | < 30ps      |
| `clk_io`  | 1.0 GHz   | Gated from `clk_ai` | < 50ps      |

## 1.8 Power Domains

| Domain       | Voltage | Power Budget | Key Components           |
|--------------|---------|--------------|--------------------------|
| `VDD_CORE`   | 0.7V    | 10W          | Logic, SRAM              |
| `VDD_AI`     | 0.8V    | 12W          | Systolic Array, Vector   |
| `VDD_IO`     | 1.1V    | 2W           | I/O, PHY                 |
| `VDD_ANALOG` | 1.8V    | 1W           | PLLs, ADCs               |

**Power Gating:**
- Fine-grained: per-core
- Coarse-grained: domain-level (e.g., `VDD_AI` off during sleep)

## 1.9 I/O Interfaces

| Interface | Type     | Bandwidth  | Use Case            |
|-----------|----------|------------|---------------------|
| DDR5      | 64-bit   | 51.2 GB/s  | Off-chip memory     |
| PCIe 5.0  | x8 lanes | 32 GB/s    | Host communication  |
| Ethernet  | 10Gbps   | 1.25 GB/s  | Networking          |
| GPIO      | 32 pins  | —          | Debug/control       |

## 1.10 Security Architecture

- **Hardware Root of Trust:** RSA-2048 secure boot, AES-256 off-chip memory encryption
- **Side-Channel Mitigations:** Constant-time crypto, randomized clock jitter

## 1.11 Test/Debug Architecture

- **Scan Chains:** > 99% stuck-at fault coverage, at-speed testing
- **Debug Interfaces:** JTAG boundary scan, 1MB trace buffer
